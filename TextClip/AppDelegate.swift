import Cocoa
import SwiftUI
import CoreGraphics
import Accessibility
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var hasShownAccessibilityAlert = false
    private var mainWindowController: NSWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()
        requestAccessibilityPermission()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "TextClip")
            button.action = #selector(menuBarButtonClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        
        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture Text", action: #selector(captureText), keyEquivalent: "2")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem(title: "Open TextClip", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit TextClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    private func requestAccessibilityPermission() {
        os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Checking Accessibility permission")
        
        guard !hasShownAccessibilityAlert else {
            os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Accessibility alert already shown, skipping")
            return
        }
        
        let accessibilityEnabled = AXIsProcessTrusted()
        if !accessibilityEnabled {
            os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Prompting for Accessibility permission")
            hasShownAccessibilityAlert = true
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "TextClip needs Accessibility permission to enable the global Cmd+Shift+2 shortcut. Please enable it in System Settings > Privacy & Security > Accessibility and relaunch TextClip."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
                    alert.beginSheetModal(for: window) { response in
                        if response == .alertFirstButtonReturn {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } else {
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        } else {
            hasShownAccessibilityAlert = true
        }
    }
    
    private func setupGlobalHotkey() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
            guard let refcon else { return Unmanaged.passRetained(event) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            if type == .keyDown {
                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 19 {
                    os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Cmd+Shift+2 triggered")
                    DispatchQueue.main.async { appDelegate.captureText() }
                    return nil
                }
            }
            return Unmanaged.passRetained(event)
        }
        
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask), callback: eventTapCallback, userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        if let eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Global event tap enabled for Cmd+Shift+2")
        } else {
            os_log(.error, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Failed to create event tap")
        }
    }
    
    @MainActor @objc func menuBarButtonClicked(sender: AnyObject) {
        if let event = NSApp.currentEvent, event.type == .rightMouseDown {
            statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else {
            captureText()
        }
    }
    
    @MainActor @objc func captureText() {
        os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Initiating text capture")
        ScreenTextRecognizer.shared.captureScreenAreaAndRecognizeText { recognizedString in
            if let text = recognizedString, !text.isEmpty {
                os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Recognized Text: %{public}@", text)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let success = pasteboard.setString(text, forType: .string)
                os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Clipboard update: %d", success)
            } else {
                os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "No text recognized")
            }
        }
    }
    
    @MainActor @objc func openMainWindow() {
        // If the window already exists, just bring it to the front.
        if let windowController = mainWindowController, windowController.window?.isVisible == true {
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Otherwise, create a new window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "TextClip"
        window.contentView = NSHostingView(rootView: ContentView())
        
        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        self.mainWindowController = windowController
        
        NSApp.activate(ignoringOtherApps: true)
    }
}
