import AppKit
import OSLog

class ScreenSelectionWindow: NSPanel {
    private var selectionRect: NSRect?
    private var startPoint: NSPoint?
    private var overlayView: SelectionOverlayView
    private var dimensionLabel: NSTextField
    var completion: ((NSRect?) -> Void)?
    static let logger = OSLog(subsystem: "Alcatelz.TextClip", category: "ScreenSelection")
    
    init(screen: NSScreen) {
        os_log(.debug, log: Self.logger, "Initializing ScreenSelectionWindow for screen: %{public}@", NSStringFromRect(screen.frame))
        self.overlayView = SelectionOverlayView(frame: screen.frame)
        self.dimensionLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        
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
        // Ensure window stays in current space
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle] // Removed .stationary for better focus behavior
        isFloatingPanel = true
        
        dimensionLabel.isEditable = false
        dimensionLabel.isBezeled = false
        dimensionLabel.drawsBackground = true
        dimensionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        dimensionLabel.textColor = .white
        dimensionLabel.alignment = .center
        dimensionLabel.font = NSFont.systemFont(ofSize: 12)
        dimensionLabel.stringValue = ""
        dimensionLabel.isHidden = true
        overlayView.addSubview(dimensionLabel)
        
        contentView = overlayView
        
        NSCursor.crosshair.push()
        os_log(.info, log: Self.logger, "Pushed crosshair cursor")
    }
    
    deinit {
        NSCursor.pop()
        os_log(.info, log: Self.logger, "Popped cursor stack")
        os_log(.debug, log: Self.logger, "Deinitializing ScreenSelectionWindow")
    }
    
    func reset() {
        os_log(.debug, log: Self.logger, "Resetting ScreenSelectionWindow")
        selectionRect = nil
        startPoint = nil
        dimensionLabel.stringValue = ""
        dimensionLabel.isHidden = true
        overlayView.selectionRect = nil
        overlayView.needsDisplay = true
        NSCursor.crosshair.push()
    }
    
    override var canBecomeKey: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        os_log(.debug, log: Self.logger, "Mouse down at location: %{public}@", NSStringFromPoint(event.locationInWindow))
        startPoint = event.locationInWindow
        selectionRect = NSRect(origin: startPoint!, size: .zero)
        overlayView.selectionRect = selectionRect
        overlayView.needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let currentPoint = event.locationInWindow
        let origin = NSPoint(
            x: min(start.x, currentPoint.x),
            y: min(start.y, currentPoint.y)
        )
        let size = NSSize(
            width: abs(currentPoint.x - start.x),
            height: abs(currentPoint.y - start.y)
        )
        let minSize: CGFloat = 10.0
        selectionRect = NSRect(
            origin: origin,
            size: NSSize(
                width: max(size.width, minSize),
                height: max(size.height, minSize)
            )
        )
        overlayView.selectionRect = selectionRect
        overlayView.needsDisplay = true
        
        if let rect = selectionRect {
            let width = Int(rect.width)
            let height = Int(rect.height)
            dimensionLabel.stringValue = "\(width) x \(height)"
            dimensionLabel.isHidden = false
            let labelX = rect.maxX + 5
            let labelY = rect.minY - 25
            dimensionLabel.frame = NSRect(x: labelX, y: labelY, width: 100, height: 20)
            os_log(.debug, log: Self.logger, "Updated selection rect: %{public}@", NSStringFromRect(rect))
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        os_log(.debug, log: Self.logger, "Mouse up at location: %{public}@", NSStringFromPoint(event.locationInWindow))
        dimensionLabel.isHidden = true
        if let rect = selectionRect, !rect.isEmpty {
            let screenRect = convertToScreenCoordinates(rect)
            os_log(.info, log: Self.logger, "Selected screen region: %{public}@", NSStringFromRect(screenRect))
            os_log(.debug, log: Self.logger, "Invoking completion with region: %{public}@", NSStringFromRect(screenRect))
            completion?(screenRect)
        } else {
            os_log(.info, log: Self.logger, "No region selected")
            os_log(.debug, log: Self.logger, "Invoking completion with nil")
            completion?(nil)
        }
        // Disable event handling to prevent lingering interactions
        acceptsMouseMovedEvents = false
        ignoresMouseEvents = true
        os_log(.debug, log: Self.logger, "Disabled event handling after mouseUp")
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            os_log(.info, log: Self.logger, "Selection cancelled via Escape")
            dimensionLabel.isHidden = true
            os_log(.debug, log: Self.logger, "Invoking completion with nil due to Escape")
            completion?(nil)
            // Disable event handling
            acceptsMouseMovedEvents = false
            ignoresMouseEvents = true
            os_log(.debug, log: Self.logger, "Disabled event handling after keyDown")
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        os_log(.debug, log: Self.logger, "Mouse entered window")
        NSCursor.crosshair.set()
    }
    
    override func mouseMoved(with event: NSEvent) {
        os_log(.debug, log: Self.logger, "Mouse moved to: %{public}@", NSStringFromPoint(event.locationInWindow))
        NSCursor.crosshair.set()
    }
    
    private func convertToScreenCoordinates(_ rect: NSRect) -> NSRect {
        guard let screen else {
            os_log(.error, log: Self.logger, "No screen available for coordinate conversion")
            return rect
        }
        let screenFrame = screen.frame
        let globalOrigin = NSPoint(
            x: rect.origin.x + screenFrame.origin.x,
            y: screenFrame.maxY - rect.origin.y - rect.height
        )
        let screenRect = NSRect(origin: globalOrigin, size: rect.size)
        os_log(.debug, log: Self.logger, "Converted to global coordinates: %{public}@", NSStringFromRect(screenRect))
        // Check if the origin is within the screen frame
        if !NSPointInRect(screenRect.origin, screenFrame) {
            os_log(.error, log: Self.logger, "Converted origin %{public}@ is not within screen frame %{public}@", NSStringFromPoint(screenRect.origin), NSStringFromRect(screenFrame))
        }
        return screenRect
    }
}

class SelectionOverlayView: NSView {
    var selectionRect: NSRect?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        selectionRect = nil
        os_log(.debug, log: ScreenSelectionWindow.logger, "Initialized SelectionOverlayView with cleared selectionRect")
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        selectionRect = nil
        os_log(.debug, log: ScreenSelectionWindow.logger, "Initialized SelectionOverlayView with cleared selectionRect (coder)")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        os_log(.debug, log: ScreenSelectionWindow.logger, "Drawing overlay: selectionRect = %{public}@",
               selectionRect.map { NSStringFromRect($0) } ?? "nil")
        
        if let rect = selectionRect, !rect.isEmpty {
            NSColor.black.withAlphaComponent(0.3).setFill()
            let path = NSBezierPath(rect: bounds)
            let selectionPath = NSBezierPath(rect: rect)
            path.append(selectionPath)
            path.setClip()
            path.fill()
            
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 1.0
            borderPath.stroke()
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
}
