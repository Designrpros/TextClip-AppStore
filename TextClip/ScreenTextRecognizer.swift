import Foundation
import AppKit
import Vision
import ScreenCaptureKit
import OSLog
import CoreImage

private let logger = OSLog(subsystem: "com.Alcatelz.TextClip", category: "ScreenCapture")

@MainActor
class ScreenTextRecognizer: NSObject, Sendable {
    static let shared = ScreenTextRecognizer()
    
    private var activeCaptureScreen: NSScreen?
    private var originalFrontmostApp: NSRunningApplication?
    private var completionHandler: ((String?) -> Void)?
    private var hasShownPermissionAlert = false
    private var captureTasks: [UUID: Task<Void, Never>] = [:]
    private let maxConcurrentCaptures = 3
    private var selectionWindow: ScreenSelectionWindow?
    private var shareableContent: SCShareableContent?
    private var hasScreenRecordingPermission: Bool?
    private let ciContext = CIContext()
    private var preFetchTask: Task<Void, Never>?
    private var lastKnownMouseScreen: NSScreen? // New property to track mouse screen
    private var mouseMonitor: Any? // To store the event monitor
    
    private override init() {
        super.init()
        // Register for display change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func displayConfigurationChanged() {
        os_log(.info, log: logger, "Display configuration changed, invalidating shareable content and selection window")
        shareableContent = nil
        selectionWindow = nil // Force reinitialization on next capture
    }
    
    func setPreFetchTask(_ task: Task<Void, Never>) {
        preFetchTask = task
    }
    
    func setInitialPermission(_ isAuthorized: Bool) {
        hasScreenRecordingPermission = isAuthorized
        os_log(.info, log: logger, "Cached initial permission: %d", isAuthorized)
    }
    
    func preInitializeSelectionWindow(for screen: NSScreen) {
        if selectionWindow == nil || selectionWindow?.screen != screen {
            selectionWindow = ScreenSelectionWindow(screen: screen)
            os_log(.info, log: logger, "Pre-initialized ScreenSelectionWindow for screen: %{public}@", NSStringFromRect(screen.frame))
        }
    }
    
    func fetchShareableContent() async {
        await withCheckedContinuation { continuation in
            SCShareableContent.getWithCompletionHandler { content, error in
                Task { @MainActor in
                    if let error {
                        os_log(.error, log: logger, "Failed to fetch shareable content: %{public}@", error.localizedDescription)
                        self.shareableContent = nil
                    } else if let content {
                        os_log(.info, log: logger, "Successfully fetched shareable content")
                        self.shareableContent = content
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    func captureScreenAreaAndRecognizeText(completion: @escaping (String?) -> Void) {
        os_log(.info, log: logger, "Requesting capture, active tasks: %d", captureTasks.count)
        guard captureTasks.count < maxConcurrentCaptures else {
            os_log(.info, log: logger, "Capture rejected: too many concurrent captures")
            _ = ToastView(message: "Too many captures, please wait.", duration: 1.5, screen: nil)
            completion(nil)
            return
        }
        self.completionHandler = completion
        let taskId = UUID()
        let setupStart = DispatchTime.now()
        let task = Task { @MainActor in
            defer { captureTasks.removeValue(forKey: taskId) }
            self.originalFrontmostApp = NSWorkspace.shared.frontmostApplication // Store before capture
            if let preFetchTask = preFetchTask {
                os_log(.info, log: logger, "Awaiting pre-fetch completion for first capture")
                await preFetchTask.value
                self.preFetchTask = nil
            }
            let mouseLocation = NSEvent.mouseLocation
            let activeScreen = lastKnownMouseScreen ??
                               NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ??
                               NSScreen.main
            guard let activeScreen else {
                os_log(.error, log: logger, "No screen found for mouse location: %{public}@", NSStringFromPoint(mouseLocation))
                _ = ToastView(message: "No active screen found.", duration: 1.5, screen: nil)
                completion(nil)
                return
            }
            self.activeCaptureScreen = activeScreen // Store the screen
            os_log(.info, log: logger, "Found active screen: %{public}@", NSStringFromRect(activeScreen.frame))
            requestScreenRecordingPermission { [weak self] granted in
                guard let self else {
                    os_log(.error, log: logger, "Self deallocated in permission callback")
                    completion(nil)
                    return
                }
                if granted {
                    self.hasShownPermissionAlert = false
                    let setupDuration = Double(DispatchTime.now().uptimeNanoseconds - setupStart.uptimeNanoseconds) / 1_000_000
                    os_log(.info, log: logger, "Setup completed in %.2f ms", setupDuration)
                    self.showSelectionWindow(for: activeScreen)
                } else {
                    os_log(.error, log: logger, "Screen recording permission denied")
                    _ = ToastView(message: "Screen recording permission required.", duration: 1.5, screen: nil)
                    completion(nil)
                }
            }
        }
        captureTasks[taskId] = task
    }
    
    private func requestScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        if let hasPermission = hasScreenRecordingPermission {
            os_log(.info, log: logger, "Using cached permission: %d", hasPermission)
            completion(hasPermission)
            return
        }
        let isAuthorized = CGPreflightScreenCaptureAccess()
        hasScreenRecordingPermission = isAuthorized
        os_log(.info, log: logger, "Initial permission check: %d", isAuthorized)
        if isAuthorized {
            completion(true)
        } else {
            if #available(macOS 13.0, *) { CGRequestScreenCaptureAccess() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
                os_log(.info, log: logger, "Post-request permission: %d", self.hasScreenRecordingPermission ?? false)
                completion(self.hasScreenRecordingPermission ?? false)
                if !(self.hasScreenRecordingPermission ?? false) && !self.hasShownPermissionAlert {
                    self.hasShownPermissionAlert = true
                    self.showScreenRecordingPermissionAlert(completion: completion)
                }
            }
        }
    }
    
    private func showScreenRecordingPermissionAlert(completion: @escaping (Bool) -> Void) {
        os_log(.info, log: logger, "Showing screen recording permission alert")
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "TextClip needs screen recording permission to capture text. Please enable it in System Settings > Privacy & Security > Screen Recording, then relaunch TextClip."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            os_log(.info, log: logger, "User opened System Settings")
            if #available(macOS 13.0, *) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacyPane?PrivacyId=ScreenRecording") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            completion(false)
        } else if response == .alertSecondButtonReturn {
            os_log(.info, log: logger, "User chose to relaunch")
            let url = URL(fileURLWithPath: Bundle.main.executablePath!)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    os_log(.error, log: logger, "Failed to relaunch: %{public}@", error.localizedDescription)
                }
                NSApp.terminate(nil)
            }
            completion(false)
        } else {
            os_log(.info, log: logger, "User cancelled permission alert")
            completion(false)
        }
    }
    
    private func showSelectionWindow(for screen: NSScreen) {
        os_log(.info, log: logger, "Showing selection window for screen: %{public}@", NSStringFromRect(screen.frame))
        if selectionWindow?.isVisible == true {
            selectionWindow?.orderOut(nil)
        }
        selectionWindow = ScreenSelectionWindow(screen: screen)
        
        selectionWindow?.completion = { [weak self] selectedRect in
            guard let self else {
                os_log(.error, log: logger, "Self deallocated")
                return
            }
            defer {
                self.selectionWindow?.orderOut(nil)
                self.selectionWindow = nil
                self.lastKnownMouseScreen = nil
                self.activeCaptureScreen = nil
                // Restore original app focus
                if let originalApp = self.originalFrontmostApp {
                    originalApp.activate(options: [])
                    self.originalFrontmostApp = nil
                }
                os_log(.info, log: logger, "Selection window hidden, nulled, screens reset, and original app focus restored")
            }
            
            guard let rect = selectedRect else {
                os_log(.info, log: logger, "No region selected")
                _ = ToastView(message: "Capture cancelled.", duration: 1.5, screen: self.activeCaptureScreen)
                self.completionHandler?(nil)
                return
            }
            os_log(.info, log: logger, "Selected region: %{public}@", NSStringFromRect(rect))
            _ = ToastView(message: "Capturing...", duration: 1.5, screen: self.activeCaptureScreen)
            
            let startTime = DispatchTime.now()
            self.captureScreenshot(region: rect, startTime: startTime) { cgImage in
                os_log(.info, log: logger, "Capture screenshot completion, cgImage: %{public}@", cgImage != nil ? "valid" : "nil")
                if let cgImage {
                    self.recognizeText(from: cgImage, regionSize: rect.size, startTime: startTime)
                } else {
                    os_log(.error, log: logger, "No CGImage received")
                    DispatchQueue.main.async {
                        self.completionHandler?(nil)
                        _ = ToastView(message: "Failed to capture screenshot.", duration: 1.5, screen: self.activeCaptureScreen)
                    }
                }
            }
        }
        
        selectionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        os_log(.info, log: logger, "Selection window displayed with autofocus")
    }
    
    private func captureScreenshot(region: CGRect, startTime: DispatchTime, completion: @escaping (CGImage?) -> Void) {
        os_log(.info, log: logger, "Capturing screenshot for region: %{public}@", NSStringFromRect(region))
        let screenshotStart = DispatchTime.now()
        let minSize: CGFloat = 10.0
        let validatedRegion = CGRect(
            x: region.origin.x,
            y: region.origin.y,
            width: max(region.width, minSize),
            height: max(region.height, minSize)
        )
        
        let fetchShareableContent = { [weak self] (completion: @escaping (SCShareableContent?, Error?) -> Void) in
            guard let self else {
                os_log(.error, log: logger, "Self deallocated during shareable content fetch")
                completion(nil, nil)
                return
            }
            os_log(.info, log: logger, "Fetching fresh shareable content")
            SCShareableContent.getWithCompletionHandler { content, error in
                if let content {
                    Task { @MainActor in
                        self.shareableContent = content
                    }
                }
                completion(content, error)
            }
        }
        
        fetchShareableContent { content, error in
            if let error {
                os_log(.error, log: logger, "Failed to get shareable content: %{public}@", error.localizedDescription)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let content else {
                os_log(.error, log: logger, "Shareable content not available")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Get the screen containing the region's origin
            let regionPoint = NSPoint(x: validatedRegion.origin.x, y: validatedRegion.origin.y)
            os_log(.debug, log: logger, "Region point: %{public}@", NSStringFromPoint(regionPoint))
            guard let targetScreen = NSScreen.screens.first(where: { screen in
                let contains = NSPointInRect(regionPoint, screen.frame)
                os_log(.debug, log: logger, "Checking screen %{public}@: contains=%d", NSStringFromRect(screen.frame), contains)
                return contains
            }) ?? NSScreen.screens.first,
                  let screenDisplayID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                os_log(.error, log: logger, "No screen found for region: %{public}@", NSStringFromRect(validatedRegion))
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let targetDisplay = content.displays.first(where: { $0.displayID == screenDisplayID }) else {
                os_log(.error, log: logger, "No display found for screen display ID: %d", screenDisplayID)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            os_log(.info, log: logger, "Capturing from display ID: %d, frame: %{public}@", targetDisplay.displayID, NSStringFromRect(targetDisplay.frame))
            
            let contentFilter = SCContentFilter(display: targetDisplay, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(validatedRegion.width)
            configuration.height = Int(validatedRegion.height)
            // Convert global coordinates to display-local coordinates
            let sourceRect = CGRect(
                x: validatedRegion.origin.x - targetDisplay.frame.origin.x,
                y: validatedRegion.origin.y - targetDisplay.frame.origin.y,
                width: validatedRegion.width,
                height: validatedRegion.height
            )
            // Validate sourceRect bounds
            let displayBounds = CGRect(x: 0, y: 0, width: targetDisplay.frame.width, height: targetDisplay.frame.height)
            guard sourceRect.minX >= 0, sourceRect.minY >= 0,
                  sourceRect.maxX <= displayBounds.width, sourceRect.maxY <= displayBounds.height else {
                os_log(.error, log: logger, "Invalid sourceRect: %{public}@, display bounds: %{public}@", NSStringFromRect(sourceRect), NSStringFromRect(displayBounds))
                DispatchQueue.main.async { completion(nil) }
                return
            }
            configuration.sourceRect = sourceRect
            os_log(.debug, log: logger, "Capture sourceRect: %{public}@", NSStringFromRect(configuration.sourceRect))
            configuration.capturesAudio = false
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { cgImage, error in
                if let error {
                    os_log(.error, log: logger, "Failed to capture screenshot: %{public}@", error.localizedDescription)
                    DispatchQueue.main.async { completion(nil) }
                }
                guard let cgImage else {
                    os_log(.error, log: logger, "No CGImage received")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let duration = Double(DispatchTime.now().uptimeNanoseconds - screenshotStart.uptimeNanoseconds) / 1_000_000
                os_log(.info, log: logger, "Screenshot captured successfully in %.2f ms", duration)
                DispatchQueue.main.async { completion(cgImage) }
            }
        }
    }
    
    private func preprocessImage(_ cgImage: CGImage) -> CGImage? {
        let preprocessStart = DispatchTime.now()
        let ciImage = CIImage(cgImage: cgImage)
        // Downscale image to reduce processing time
        let scale = min(1.0, 800.0 / max(CGFloat(cgImage.width), CGFloat(cgImage.height)))
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(scaledImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(1.3, forKey: kCIInputContrastKey)
        contrastFilter?.setValue(0.2, forKey: kCIInputBrightnessKey)
        guard let outputImage = contrastFilter?.outputImage,
              let enhancedCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            os_log(.error, log: logger, "Failed to apply contrast filter")
            return cgImage
        }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - preprocessStart.uptimeNanoseconds) / 1_000_000
        os_log(.info, log: logger, "Preprocessing completed in %.2f ms", duration)
        return enhancedCGImage
    }
    
    private func recognizeText(from cgImage: CGImage, regionSize: CGSize, startTime: DispatchTime) {
        os_log(.info, log: logger, "Entering recognizeText with QR code support")
        _ = DispatchTime.now()

        // First, check for QR Codes
        let barcodeRequest = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            if let error = error {
                os_log(.error, log: logger, "QR Code detection error: %{public}@", error.localizedDescription)
                // Don't call completion, fall through to text recognition
                return
            }
            
            let qrObservations = request.results as? [VNBarcodeObservation] ?? []
            let qrStrings = qrObservations.compactMap { $0.payloadStringValue }
            
            if !qrStrings.isEmpty {
                // QR Code found, prioritize it
                let combinedPayload = qrStrings.joined(separator: "\n")
                os_log(.info, log: logger, "Found QR Code with payload: %{public}@", combinedPayload)
                
                DispatchQueue.main.async {
                    self.completionHandler?(combinedPayload)
                    _ = ToastView(message: "QR Code Copied!", duration: 1.5, screen: self.activeCaptureScreen)
                }
            } else {
                // No QR Code found, proceed to text recognition
                os_log(.info, log: logger, "No QR codes found, proceeding with text recognition.")
                self.performTextRecognition(from: cgImage, regionSize: regionSize, startTime: startTime)
            }
        }
        barcodeRequest.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([barcodeRequest])
        } catch {
            os_log(.error, log: logger, "Failed to perform barcode request: %{public}@", error.localizedDescription)
            // Fallback to text recognition on failure
            performTextRecognition(from: cgImage, regionSize: regionSize, startTime: startTime)
        }
    }

    private func performTextRecognition(from cgImage: CGImage, regionSize: CGSize, startTime: DispatchTime) {
        os_log(.info, log: logger, "Performing text recognition")
        let ocrStart = DispatchTime.now()
        
        guard let processedImage = preprocessImage(cgImage) else {
            os_log(.error, log: logger, "Image preprocessing failed")
            DispatchQueue.main.async {
                self.completionHandler?(nil)
                _ = ToastView(message: "Image processing failed.", duration: 1.5, screen: self.activeCaptureScreen)
            }
            return
        }
        
        guard processedImage.width > 10, processedImage.height > 10,
              processedImage.colorSpace != nil,
              processedImage.bitsPerPixel == 32,
              processedImage.bitsPerComponent == 8 else {
            os_log(.error, log: logger, "Invalid CGImage format for text recognition: width=%d, height=%d, bitsPerPixel=%d",
                   processedImage.width, processedImage.height, processedImage.bitsPerPixel)
            DispatchQueue.main.async {
                self.completionHandler?(nil)
                _ = ToastView(message: "Invalid image format.", duration: 1.5, screen: self.activeCaptureScreen)
            }
            return
        }
        
        let capturedCompletion = self.completionHandler
        
        DispatchQueue.global(qos: .userInteractive).async {
            let request = VNRecognizeTextRequest { request, error in
                let fullDuration = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                
                if let error = error {
                    os_log(.error, log: logger, "Text recognition error: %{public}@", error.localizedDescription)
                    DispatchQueue.main.async {
                        capturedCompletion?(nil)
                        _ = ToastView(message: "Text recognition failed.", duration: 1.5, screen: self.activeCaptureScreen)
                    }
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    os_log(.info, log: logger, "No text recognized after %.2f ms.", fullDuration)
                    DispatchQueue.main.async {
                        capturedCompletion?(nil)
                        _ = ToastView(message: "No text recognized.", duration: 1.5, screen: self.activeCaptureScreen)
                    }
                    return
                }

                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                var output = recognizedStrings.joined(separator: "\n")
                output = output.replacingOccurrences(of: "ClContext", with: "CIContext")
                
                os_log(.info, log: logger, "Recognized text: %{public}@", output)
                DispatchQueue.main.async {
                    capturedCompletion?(output.isEmpty ? nil : output)
                    _ = ToastView(message: "Text Copied!", duration: 1.5, screen: self.activeCaptureScreen)
                    let ocrDuration = Double(DispatchTime.now().uptimeNanoseconds - ocrStart.uptimeNanoseconds) / 1_000_000
                    os_log(.info, log: logger, "Full capture completed in %.2f ms (OCR took %.2f ms)", fullDuration, ocrDuration)
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let area = regionSize.width * regionSize.height
            request.minimumTextHeight = area > 400000 ? 0.02 : 0.025
            os_log(.info, log: logger, "Using minimumTextHeight: %.3f for region area: %.0f", request.minimumTextHeight, area)
            
            let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                os_log(.error, log: logger, "Failed to perform text recognition request: %{public}@", error.localizedDescription)
                DispatchQueue.main.async {
                    capturedCompletion?(nil)
                    _ = ToastView(message: "Text recognition failed.", duration: 1.5, screen: self.activeCaptureScreen)
                }
            }
        }
    }
}
