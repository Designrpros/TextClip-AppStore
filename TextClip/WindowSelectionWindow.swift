//
//  WindowSelectionWindow.swift
//  TextClip
//
//  Created by Vegar Berentsen on 26/05/2025.
//

import AppKit
import OSLog

class WindowSelectionWindow: NSPanel {
    private var overlayView: WindowSelectionOverlayView
    private var currentWindowRect: NSRect?
    var completion: ((NSRect?, Int32?) -> Void)? // Returns window rect and ID
    static let logger = OSLog(subsystem: "Alcatelz.TextClip", category: "WindowSelection")
    
    init(screen: NSScreen) {
        os_log(.debug, log: Self.logger, "Initializing WindowSelectionWindow for screen: %{public}@", NSStringFromRect(screen.frame))
        self.overlayView = WindowSelectionOverlayView(frame: screen.frame)
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setFrame(screen.frame, display: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        isFloatingPanel = true
        
        contentView = overlayView
        
        NSCursor.crosshair.push() // Use crosshair for simplicity; consider custom camera cursor
        os_log(.info, log: Self.logger, "Pushed crosshair cursor")
        
        // Track mouse movements to update highlight
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateWindowHighlight(at: event.locationInWindow)
            return event
        }
    }
    
    deinit {
        NSCursor.pop()
        os_log(.info, log: Self.logger, "Popped cursor stack")
        os_log(.debug, log: Self.logger, "Deinitializing WindowSelectionWindow")
    }
    
    private func updateWindowHighlight(at point: NSPoint) {
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            currentWindowRect = nil
            overlayView.windowRect = nil
            overlayView.needsDisplay = true
            return
        }
        
        let globalPoint = convertPoint(toScreen: point)
        for info in windowInfo {
            guard let bounds = info[kCGWindowBounds as String] as? [String: Int],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  let windowID = info[kCGWindowNumber as String] as? Int32 else { continue }
            let rect = NSRect(x: x, y: y, width: width, height: height)
            if NSPointInRect(globalPoint, rect) {
                currentWindowRect = rect
                overlayView.windowRect = rect
                overlayView.windowID = windowID
                overlayView.needsDisplay = true
                os_log(.debug, log: Self.logger, "Highlighted window at rect: %{public}@", NSStringFromRect(rect))
                return
            }
        }
        
        currentWindowRect = nil
        overlayView.windowRect = nil
        overlayView.windowID = nil
        overlayView.needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        os_log(.debug, log: Self.logger, "Mouse up at location: %{public}@", NSStringFromPoint(event.locationInWindow))
        if let rect = currentWindowRect, let windowID = overlayView.windowID {
            os_log(.info, log: Self.logger, "Selected window at rect: %{public}@, ID: %d", NSStringFromRect(rect), windowID)
            completion?(rect, windowID)
        } else {
            os_log(.info, log: Self.logger, "No window selected")
            completion?(nil, nil)
        }
        acceptsMouseMovedEvents = false
        ignoresMouseEvents = true
        os_log(.debug, log: Self.logger, "Disabled event handling after mouseUp")
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            os_log(.info, log: Self.logger, "Selection cancelled via Escape")
            completion?(nil, nil)
            acceptsMouseMovedEvents = false
            ignoresMouseEvents = true
            os_log(.debug, log: Self.logger, "Disabled event handling after keyDown")
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        os_log(.debug, log: Self.logger, "Mouse moved to: %{public}@", NSStringFromPoint(event.locationInWindow))
        NSCursor.crosshair.set()
    }
}

class WindowSelectionOverlayView: NSView {
    var windowRect: NSRect?
    var windowID: Int32?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        windowRect = nil
        windowID = nil
        os_log(.debug, log: WindowSelectionWindow.logger, "Initialized WindowSelectionOverlayView")
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        windowRect = nil
        windowID = nil
        os_log(.debug, log: WindowSelectionWindow.logger, "Initialized WindowSelectionOverlayView (coder)")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        os_log(.debug, log: WindowSelectionWindow.logger, "Drawing overlay: windowRect = %{public}@",
               windowRect.map { NSStringFromRect($0) } ?? "nil")
        
        // Dim the entire screen slightly
        NSColor.black.withAlphaComponent(0.3).setFill()
        NSBezierPath(rect: bounds).fill()
        
        if let rect = windowRect, !rect.isEmpty {
            // Clear the window's interior
            NSColor.clear.setFill()
            NSBezierPath(rect: rect).fill()
            
            // Draw a blue highlight border
            NSColor.blue.withAlphaComponent(0.5).setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 4.0
            borderPath.stroke()
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
}
