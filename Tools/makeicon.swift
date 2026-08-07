import AppKit
import CoreGraphics
import Foundation

// Renders the Melon Tap app icon: a watermelon slice, flat edge down.
// One 1024pt master; Xcode derives every other size from it.

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

func color(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

let W = CGFloat(size)

// Background: warm off-white, so the slice reads on both a black watch face
// and a light home screen.
ctx.setFillColor(color(250, 246, 236))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))

// The slice is a semicircle standing on its flat edge. watchOS masks icons to
// a circle, so the whole slice — including its bottom corners, which sit
// furthest from centre — has to fit inside that circle's safe area. With this
// radius the corners land ~0.39W from centre, comfortably inside the mask.
let cx = W / 2
let cy = W * 0.304
let rSkin: CGFloat = W * 0.392
let rRind: CGFloat = rSkin * 0.945
let rFlesh: CGFloat = rSkin * 0.875

func semicircle(radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx - radius, y: cy))
    p.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
             startAngle: .pi, endAngle: 0, clockwise: true)
    p.closeSubpath()
    return p
}

// Dark green skin
ctx.addPath(semicircle(radius: rSkin))
ctx.setFillColor(color(31, 106, 51))
ctx.fillPath()

// Pale rind
ctx.addPath(semicircle(radius: rRind))
ctx.setFillColor(color(226, 240, 205))
ctx.fillPath()

// Red flesh
ctx.addPath(semicircle(radius: rFlesh))
ctx.setFillColor(color(226, 58, 62))
ctx.fillPath()

// Seeds, placed by polar coordinates so they follow the flesh rather than
// sitting on a grid. Each is an ellipse tilted along its own radius.
let seeds: [(CGFloat, CGFloat)] = [   // (angle in degrees, fraction of flesh radius)
    (28, 0.72), (58, 0.80), (90, 0.78), (122, 0.80), (152, 0.72),
    (44, 0.47), (74, 0.52), (106, 0.52), (136, 0.47),
    (90, 0.24)
]

ctx.setFillColor(color(28, 24, 22))
for (deg, frac) in seeds {
    let a = deg * .pi / 180
    let r = rFlesh * frac
    let x = cx + cos(a) * r
    let y = cy + sin(a) * r
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: a - .pi / 2)
    let sw = W * 0.036
    let sh = W * 0.056
    ctx.addEllipse(in: CGRect(x: -sw/2, y: -sh/2, width: sw, height: sh))
    ctx.fillPath()
    ctx.restoreGState()
}

guard let image = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
