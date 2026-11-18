// Draws the 1024px app icon. Regenerate the asset catalog with scripts/make-icon.sh.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }

// macOS icon grid: 824pt body centred, continuous-corner radius ~185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: c(0, 0, 0, 0.35))
ctx.addPath(shape); ctx.setFillColor(c(20, 24, 34)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [c(44, 52, 70), c(18, 21, 30)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// faint panel inset
let panel = CGPath(roundedRect: body.insetBy(dx: 70, dy: 70), cornerWidth: 110, cornerHeight: 110, transform: nil)
ctx.addPath(panel); ctx.setFillColor(c(255, 255, 255, 0.035)); ctx.fillPath()
ctx.addPath(panel); ctx.setStrokeColor(c(255, 255, 255, 0.08)); ctx.setLineWidth(3); ctx.strokePath()

// 3x3 jacks
let xs: [CGFloat] = [312, 512, 712], ys: [CGFloat] = [712, 512, 312]
func jack(_ p: CGPoint, lit: Bool) {
    if lit {
        let glow = CGGradient(colorsSpace: cs, colors: [c(255, 184, 76, 0.55), c(255, 184, 76, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: p, startRadius: 0, endCenter: p, endRadius: 110, options: [])
    }
    ctx.setFillColor(lit ? c(255, 196, 92) : c(78, 88, 110))
    ctx.fillEllipse(in: CGRect(x: p.x - 46, y: p.y - 46, width: 92, height: 92))
    ctx.setFillColor(lit ? c(120, 62, 10) : c(14, 16, 23))
    ctx.fillEllipse(in: CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44))
}
let a = CGPoint(x: xs[0], y: ys[0]), b = CGPoint(x: xs[2], y: ys[1])
for y in ys { for x in xs { let p = CGPoint(x: x, y: y); jack(p, lit: p == a || p == b) } }

// patch cable a -> b, sagging
let cable = CGMutablePath()
cable.move(to: a)
cable.addCurve(to: b, control1: CGPoint(x: 330, y: 560), control2: CGPoint(x: 640, y: 590))
ctx.setLineCap(.round)
ctx.addPath(cable); ctx.setStrokeColor(c(0, 0, 0, 0.35)); ctx.setLineWidth(46); ctx.strokePath()
ctx.addPath(cable); ctx.setStrokeColor(c(255, 168, 56)); ctx.setLineWidth(34); ctx.strokePath()
ctx.addPath(cable); ctx.setStrokeColor(c(255, 226, 160, 0.6)); ctx.setLineWidth(8); ctx.strokePath()
// plugs
for p in [a, b] {
    ctx.setFillColor(c(255, 214, 130)); ctx.fillEllipse(in: CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60))
    ctx.setFillColor(c(200, 120, 30)); ctx.fillEllipse(in: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28))
}
// top sheen
let sheen = CGGradient(colorsSpace: cs, colors: [c(255, 255, 255, 0.10), c(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
