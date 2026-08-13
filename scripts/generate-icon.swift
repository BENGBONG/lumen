#!/usr/bin/env swift
//
// Lumen app icon generator.
// Draws the icon with Core Graphics, exports all PNG sizes for an .iconset
// directory.  Run:
//
//   swift scripts/generate-icon.swift
//
// Produces:  build/Lumen.iconset/icon_*.png
// Then run:  iconutil -c icns build/Lumen.iconset -o build/AppIcon.icns
//

import Cocoa
import CoreGraphics

// MARK: - Icon drawing

func drawIcon(size: CGFloat) -> Data {
    let width  = Int(size)
    let height = Int(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    // ── Squircle background with deep-blue → cyan gradient ──────────────
    let cornerRadius = size * 0.2237   // Apple's standard icon curvature
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(roundedRect: bgRect,
                        cornerWidth: cornerRadius,
                        cornerHeight: cornerRadius,
                        transform: nil)

    context.saveGState()
    context.addPath(bgPath)
    context.clip()

    // Indigo (top) → sky-blue (bottom)
    let topColor    = CGColor(red: 0.18, green: 0.27, blue: 0.92, alpha: 1.0)
    let bottomColor = CGColor(red: 0.42, green: 0.71, blue: 1.00, alpha: 1.0)
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [topColor, bottomColor] as CFArray,
                              locations: [0.0, 1.0])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),     // top
                               end:   CGPoint(x: 0, y: 0),        // bottom
                               options: [])

    // ── Subtle radial highlight in upper-left for depth ─────────────────
    let highlight = CGGradient(colorsSpace: colorSpace,
                               colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
                                        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
                               locations: [0.0, 1.0])!
    context.drawRadialGradient(highlight,
                               startCenter: CGPoint(x: size * 0.3, y: size * 0.75),
                               startRadius: 0,
                               endCenter:   CGPoint(x: size * 0.3, y: size * 0.75),
                               endRadius:   size * 0.55,
                               options: [])

    context.restoreGState()

    // ── Two stacked cards (representing the dual panes) ─────────────────
    let cardW = size * 0.42
    let cardH = size * 0.52
    let cardCorner = size * 0.07

    let centerX = size / 2
    let centerY = size / 2 - size * 0.02

    // Back card — slightly rotated left, semi-transparent
    drawCard(in: context,
             center: CGPoint(x: centerX - cardW * 0.18,
                             y: centerY - cardH * 0.06),
             width: cardW, height: cardH,
             corner: cardCorner,
             rotation: -10 * .pi / 180,
             fill: CGColor(red: 1, green: 1, blue: 1, alpha: 0.70),
             stroke: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
             strokeWidth: size * 0.005)

    // Front card — upright, opaque
    drawCard(in: context,
             center: CGPoint(x: centerX + cardW * 0.12,
                             y: centerY - cardH * 0.02),
             width: cardW, height: cardH,
             corner: cardCorner,
             rotation: 6 * .pi / 180,
             fill: CGColor(red: 1, green: 1, blue: 1, alpha: 0.97),
             stroke: nil,
             strokeWidth: 0)

    // Three tiny "row" stripes on the front card to suggest a file list
    let frontCenter = CGPoint(x: centerX + cardW * 0.12, y: centerY - cardH * 0.02)
    context.saveGState()
    context.translateBy(x: frontCenter.x, y: frontCenter.y)
    context.rotate(by: 6 * .pi / 180)
    let stripeColor = CGColor(red: 0.55, green: 0.62, blue: 0.78, alpha: 0.55)
    context.setFillColor(stripeColor)
    let stripeW = cardW * 0.62
    let stripeH = size * 0.018
    let stripeStartY = cardH * 0.18
    for i in 0..<3 {
        let y = stripeStartY - CGFloat(i) * stripeH * 3.0
        let r = CGRect(x: -stripeW / 2, y: y, width: stripeW, height: stripeH)
        let p = CGPath(roundedRect: r, cornerWidth: stripeH / 2,
                       cornerHeight: stripeH / 2, transform: nil)
        context.addPath(p)
        context.fillPath()
    }
    context.restoreGState()

    // ── Sparkle (AI indicator) ──────────────────────────────────────────
    let sparkleCenter = CGPoint(x: size * 0.79, y: size * 0.79)
    let sparkleSize   = size * 0.13
    drawSparkle(in: context, center: sparkleCenter, size: sparkleSize)

    // ── Render to PNG ───────────────────────────────────────────────────
    let cgImage = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Helpers

func drawCard(in ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat,
              corner: CGFloat, rotation: CGFloat,
              fill: CGColor, stroke: CGColor?, strokeWidth: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: corner,
                      cornerHeight: corner, transform: nil)

    // Soft drop shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.025),
                  blur: height * 0.06,
                  color: CGColor(red: 0, green: 0, blue: 0.15, alpha: 0.35))

    ctx.setFillColor(fill)
    ctx.addPath(path)
    ctx.fillPath()

    if let s = stroke {
        ctx.setStrokeColor(s)
        ctx.setLineWidth(strokeWidth)
        ctx.addPath(path)
        ctx.strokePath()
    }

    ctx.restoreGState()
}

/// 4-point sparkle (✦) — vertical & horizontal diamond.
func drawSparkle(in ctx: CGContext, center: CGPoint, size: CGFloat) {
    let r = size / 2

    // Glow halo behind the sparkle
    let halo = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1, green: 1, blue: 0.85, alpha: 0.65),
            CGColor(red: 1, green: 1, blue: 0.85, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(halo,
                           startCenter: center, startRadius: 0,
                           endCenter:   center, endRadius: size * 1.0,
                           options: [])

    // Sparkle 4-point star: long vertical & horizontal lens shapes
    let starColor = CGColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1.0)
    ctx.setFillColor(starColor)

    let path = CGMutablePath()
    let waist = r * 0.18
    // Vertical lens
    path.move(to:    CGPoint(x: center.x,         y: center.y + r))
    path.addCurve(to: CGPoint(x: center.x + waist, y: center.y),
                  control1: CGPoint(x: center.x + waist * 0.6, y: center.y + r * 0.6),
                  control2: CGPoint(x: center.x + waist,        y: center.y + r * 0.3))
    path.addCurve(to: CGPoint(x: center.x,         y: center.y - r),
                  control1: CGPoint(x: center.x + waist,        y: center.y - r * 0.3),
                  control2: CGPoint(x: center.x + waist * 0.6, y: center.y - r * 0.6))
    path.addCurve(to: CGPoint(x: center.x - waist, y: center.y),
                  control1: CGPoint(x: center.x - waist * 0.6, y: center.y - r * 0.6),
                  control2: CGPoint(x: center.x - waist,        y: center.y - r * 0.3))
    path.addCurve(to: CGPoint(x: center.x,         y: center.y + r),
                  control1: CGPoint(x: center.x - waist,        y: center.y + r * 0.3),
                  control2: CGPoint(x: center.x - waist * 0.6, y: center.y + r * 0.6))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()

    // Horizontal lens (90° rotated)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: .pi / 2)
    ctx.translateBy(x: -center.x, y: -center.y)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()

    // Bright center dot
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let dotR = r * 0.12
    ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR,
                               width: dotR * 2, height: dotR * 2))
}

// MARK: - Main

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",        16),
    ("icon_16x16@2x",     32),
    ("icon_32x32",        32),
    ("icon_32x32@2x",     64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x", 1024),
]

let here = FileManager.default.currentDirectoryPath
let iconset = "\(here)/build/Lumen.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let png = drawIcon(size: CGFloat(px))
    let url = URL(fileURLWithPath: "\(iconset)/\(name).png")
    try png.write(to: url)
    print("  ✓ \(name).png  (\(px)×\(px))")
}

print("\nIconset written to: \(iconset)")
print("Run: iconutil -c icns \(iconset) -o build/AppIcon.icns")
