#!/usr/bin/env swift
import AppKit
import CoreGraphics

let canvas = 1024.0

// ── Helpers ──────────────────────────────────────────────────────────────────

func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func radians(_ deg: CGFloat) -> CGFloat { deg * .pi / 180 }

// ── Context ───────────────────────────────────────────────────────────────────

let cs   = CGColorSpaceCreateDeviceRGB()
let ctx  = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// ── Background: rounded square ────────────────────────────────────────────────

let r: CGFloat = 224          // corner radius (macOS icon style ~22%)
let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: canvas, height: canvas),
                cornerWidth: r, cornerHeight: r, transform: nil)

// Gradient: deep navy → indigo/violet
let gradColors = [
    cgColor(0.07, 0.08, 0.18),   // deep navy (bottom)
    cgColor(0.18, 0.12, 0.38),   // indigo (top)
] as CFArray

let locs: [CGFloat] = [0, 1]
let gradient = CGGradient(colorsSpace: cs, colors: gradColors, locations: locs)!

ctx.saveGState()
ctx.addPath(bg)
ctx.clip()
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: canvas / 2, y: 0),
                       end:   CGPoint(x: canvas / 2, y: canvas),
                       options: [])
ctx.restoreGState()

// ── Viewfinder frame ──────────────────────────────────────────────────────────
// Four L-shaped corner brackets drawn in white

let fw: CGFloat = 480          // frame width/height
let fx: CGFloat = (canvas - fw) / 2
let fy: CGFloat = (canvas - fw) / 2
let arm: CGFloat = 110         // length of each bracket arm
let thick: CGFloat = 36        // line thickness
let cr: CGFloat = 18           // inner corner radius of brackets

ctx.setStrokeColor(cgColor(1, 1, 1, 0.92))
ctx.setLineWidth(thick)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Corner positions: (startX, startY, armDirX, armDirY)
let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (fx,        fy + fw,   1,  -1),   // top-left     → right, down (flipped Y)
    (fx + fw,   fy + fw,  -1,  -1),   // top-right    → left, down
    (fx,        fy,        1,   1),   // bottom-left  → right, up
    (fx + fw,   fy,       -1,   1),   // bottom-right → left, up
]

for (cx2, cy2, dx, dy) in corners {
    ctx.move(to: CGPoint(x: cx2 + dx * arm, y: cy2))
    ctx.addLine(to: CGPoint(x: cx2, y: cy2))
    ctx.addLine(to: CGPoint(x: cx2, y: cy2 + dy * arm))
}
ctx.strokePath()

// ── Centre crosshair dot ──────────────────────────────────────────────────────

let dotR: CGFloat = 18
ctx.setFillColor(cgColor(1, 1, 1, 0.7))
ctx.fillEllipse(in: CGRect(x: canvas/2 - dotR, y: canvas/2 - dotR,
                            width: dotR*2, height: dotR*2))

// ── Floating card (bottom-right) ──────────────────────────────────────────────
// Represents the floating preview thumbnail

let cardW: CGFloat = 210
let cardH: CGFloat = 152
let cardX: CGFloat = canvas - cardW - 60
let cardY: CGFloat = 58

// Card shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 28,
              color: cgColor(0, 0, 0, 0.55))
let cardPath = CGPath(roundedRect: CGRect(x: cardX, y: cardY, width: cardW, height: cardH),
                      cornerWidth: 18, cornerHeight: 18, transform: nil)
ctx.setFillColor(cgColor(1, 1, 1, 0.13))
ctx.addPath(cardPath)
ctx.fillPath()
ctx.restoreGState()

// Card fill (frosted glass look)
ctx.setFillColor(cgColor(0.95, 0.95, 1.0, 0.18))
ctx.addPath(cardPath)
ctx.fillPath()

// Card border
ctx.setStrokeColor(cgColor(1, 1, 1, 0.35))
ctx.setLineWidth(3)
ctx.addPath(cardPath)
ctx.strokePath()

// Simulated image lines inside the card (screenshot content hint)
ctx.setFillColor(cgColor(1, 1, 1, 0.22))
let lineH: CGFloat = 10
let lineX = cardX + 18
let lineW = cardW - 36
for i in 0..<3 {
    let lineY = cardY + 24 + CGFloat(i) * (lineH + 9)
    let w = i == 2 ? lineW * 0.6 : lineW
    ctx.fill(CGRect(x: lineX, y: lineY, width: w, height: lineH).insetBy(dx: 0, dy: 0)
             .applying(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)))
    let path2 = CGPath(roundedRect: CGRect(x: lineX, y: lineY, width: w, height: lineH),
                       cornerWidth: 3, cornerHeight: 3, transform: nil)
    ctx.addPath(path2)
    ctx.fillPath()
}

// ── Export PNG ────────────────────────────────────────────────────────────────

let cgImage = ctx.makeImage()!
let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: canvas, height: canvas))
let tiff    = nsImage.tiffRepresentation!
let rep     = NSBitmapImageRep(data: tiff)!
let png     = rep.representation(using: .png, properties: [:])!

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/SnapFloat_icon_1024.png"

try! png.write(to: URL(fileURLWithPath: outPath))
print("Icon written to \(outPath)")
