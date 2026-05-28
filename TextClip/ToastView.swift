import AppKit
import OSLog

// Custom NSWindow subclass to control key window behavior
class ToastWindow: NSWindow {
    override var canBecomeKey: Bool {
        return false
    }
}

class ToastView {
    private let window: ToastWindow
    private let textField: NSTextField
    private static let logger = OSLog(subsystem: "Alcatelz.TextClip", category: "ToastView")
    
    init(message: String, duration: TimeInterval = 1.0, screen: NSScreen? = nil) {
        let toastWidth: CGFloat = 300
        let toastHeight: CGFloat = 50
        let screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let toastFrame = NSRect(
            x: screenFrame.midX - toastWidth / 2,
            y: screenFrame.maxY - toastHeight - 20,
            width: toastWidth,
            height: toastHeight
        )
        
        window = ToastWindow(
            contentRect: toastFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10.0
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        window.contentView = contentView
        
        textField = NSTextField(frame: NSRect(x: 10, y: 10, width: toastWidth - 20, height: toastHeight - 20))
        textField.isEditable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.textColor = .white
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.stringValue = message
        textField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textField)
        
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textField.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -20),
            textField.heightAnchor.constraint(equalTo: contentView.heightAnchor, constant: -20)
        ])
        
        window.alphaValue = 0.0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.dismiss()
        }
        
        os_log(.debug, log: Self.logger, "Displayed toast: %s on screen: %{public}@", message, NSStringFromRect(screenFrame))
    }
    
    private func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.window.animator().alphaValue = 0.0
        } completionHandler: {
            self.window.orderOut(nil)
            os_log(.debug, log: Self.logger, "Dismissed toast")
        }
    }
}
