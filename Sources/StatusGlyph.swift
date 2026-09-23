import AppKit

/// A tiny Voyager silhouette for the menu bar (template image, adapts to light
/// and dark menu bars): high-gain dish with feed, bus, RTG boom and the long
/// magnetometer boom.
enum StatusGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            // Dish: a shallow bowl opening upwards, seen slightly from above.
            let dish = NSBezierPath()
            dish.move(to: NSPoint(x: 4.2, y: 11.2))
            dish.curve(to: NSPoint(x: 15.8, y: 11.2), controlPoint1: NSPoint(x: 5.6, y: 6.9), controlPoint2: NSPoint(x: 14.4, y: 6.9))
            dish.curve(to: NSPoint(x: 4.2, y: 11.2), controlPoint1: NSPoint(x: 13.6, y: 12.6), controlPoint2: NSPoint(x: 6.4, y: 12.6))
            dish.close()
            dish.fill()
            // Feed and subreflector.
            let feed = NSBezierPath()
            feed.move(to: NSPoint(x: 10, y: 10.6)); feed.line(to: NSPoint(x: 10, y: 14.2))
            feed.lineWidth = 1.1
            feed.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.9, y: 13.7, width: 2.2, height: 1.3)).fill()
            // Bus.
            NSBezierPath(roundedRect: NSRect(x: 8.2, y: 6.2, width: 3.6, height: 2.2), xRadius: 0.4, yRadius: 0.4).fill()
            // RTG boom with the generators.
            let rtg = NSBezierPath()
            rtg.move(to: NSPoint(x: 8.4, y: 6.9)); rtg.line(to: NSPoint(x: 3.2, y: 4.2))
            rtg.lineWidth = 0.9
            rtg.stroke()
            let gen = NSBezierPath()
            gen.move(to: NSPoint(x: 5.6, y: 5.6)); gen.line(to: NSPoint(x: 2.6, y: 4.0))
            gen.lineWidth = 2.1
            gen.lineCapStyle = .round
            gen.stroke()
            // Magnetometer boom, long and thin.
            let mag = NSBezierPath()
            mag.move(to: NSPoint(x: 11.6, y: 6.8)); mag.line(to: NSPoint(x: 19.2, y: 1.2))
            mag.lineWidth = 0.75
            mag.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Voyager Bar"
        return img
    }()
}
