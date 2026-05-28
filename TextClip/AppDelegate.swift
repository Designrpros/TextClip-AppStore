import Cocoa
import SwiftUI
import OSLog
import HotKey // 1. Import the newly added library

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem?
    private var mainWindowController: NSWindowController?
    
    // 2. Keep a strong reference to the HotKey instance so it doesn't get deallocated
    private var globalHotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()
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
    
    private func setupGlobalHotkey() {
        // 3. Initialize the hotkey for Cmd + Shift + 2
        globalHotKey = HotKey(key: .two, modifiers: [.command, .shift])
        
        // 4. Set up what happens when the key combination is pressed
        globalHotKey?.keyDownHandler = { [weak self] in
            os_log(.info, log: OSLog(subsystem: "com.Alcatelz.textclip", category: "AppDelegate"), "Cmd+Shift+2 triggered via HotKey framework")
            
            // 5. Resolves the MainActor isolation error safely
            Task { @MainActor in
                self?.captureText()
            }
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
        if let windowController = mainWindowController, windowController.window?.isVisible == true {
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
