import AppKit

/// A tiny Voyager for the menu bar (template image, adapts to light and dark
/// menu bars): the high-gain dish in three-quarter view — its concave face
/// half-transparent — over the bus, with the RTG boom to one side and the long
/// magnetometer boom to the other.
enum StatusGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ deg: CGFloat) -> CGPath {
                var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: deg * .pi / 180)
                return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
            }
            let c = CGPoint(x: 10.2, y: 9.6)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            // Bus under the dish.
            ctx.fill(CGRect(x: 8.6, y: 3.6, width: 3.4, height: 2.4))
            // RTG boom with the generator stack (left).
            ctx.setLineWidth(0.9)
            ctx.move(to: CGPoint(x: 8.8, y: 4.6)); ctx.addLine(to: CGPoint(x: 2.0, y: 2.2)); ctx.strokePath()
            ctx.setLineWidth(2.1); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 5.2, y: 3.3)); ctx.addLine(to: CGPoint(x: 2.1, y: 2.2)); ctx.strokePath()
            // Magnetometer boom (right), long and thin.
            ctx.setLineWidth(0.7); ctx.setLineCap(.butt)
            ctx.move(to: CGPoint(x: 11.8, y: 5.0)); ctx.addLine(to: CGPoint(x: 21.6, y: 1.0)); ctx.strokePath()
            // Dish: solid rim, translucent concave face, solid feed.
            ctx.addPath(ellipse(c, 7.0, 4.3, 16)); ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.addPath(ellipse(CGPoint(x: c.x + 0.25, y: c.y + 0.35), 5.7, 3.2, 16)); ctx.fillPath()
            ctx.setBlendMode(.normal)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
            ctx.addPath(ellipse(CGPoint(x: c.x + 0.25, y: c.y + 0.35), 5.7, 3.2, 16)); ctx.fillPath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(ellipse(CGPoint(x: c.x + 0.3, y: c.y + 0.4), 1.25, 0.95, 16)); ctx.fillPath()
            // Feed/subreflector mast pointing out of the dish.
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: c.x + 0.3, y: c.y + 0.4)); ctx.addLine(to: CGPoint(x: c.x - 0.6, y: c.y + 5.6)); ctx.strokePath()
            ctx.addPath(ellipse(CGPoint(x: c.x - 0.65, y: c.y + 5.6), 1.5, 0.75, 16)); ctx.fillPath()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Voyager Bar"
        return img
    }()
}
