import AppKit

enum StatusBarIcon {
    static func image() -> NSImage {
        if let url = Bundle.main.url(forResource: "OpenLessStatusIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }
        return fallbackImage()
    }

    private static func fallbackImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let dark = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.12, alpha: 1)
        let blue = NSColor(calibratedRed: 0.18, green: 0.50, blue: 1.0, alpha: 1)
        let plate = NSBezierPath(roundedRect: NSRect(x: 1.7, y: 1.7, width: 14.6, height: 14.6), xRadius: 4.3, yRadius: 4.3)
        NSColor.white.withAlphaComponent(0.92).setFill()
        plate.fill()
        dark.withAlphaComponent(0.10).setStroke()
        plate.lineWidth = 0.45
        plate.stroke()

        let ring = NSBezierPath()
        ring.lineWidth = 2.2
        ring.lineCapStyle = .round
        ring.appendArc(
            withCenter: NSPoint(x: 8.5, y: 9),
            radius: 6.1,
            startAngle: 42,
            endAngle: 330,
            clockwise: false
        )
        dark.setStroke()
        ring.stroke()

        let dash = NSBezierPath()
        dash.lineWidth = 2.1
        dash.lineCapStyle = .round
        dash.move(to: NSPoint(x: 12.4, y: 9))
        dash.line(to: NSPoint(x: 16.1, y: 9))
        blue.setStroke()
        dash.stroke()

        image.isTemplate = false
        return image
    }
}
