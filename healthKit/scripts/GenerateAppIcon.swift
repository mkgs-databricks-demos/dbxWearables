#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Generates a simple app icon with a gradient background and SF Symbol
/// Run this script, then drag the generated images into Assets.xcassets/AppIcon

func generateAppIcon() {
    let sizes: [(size: Int, scale: Int, name: String)] = [
        (20, 2, "Icon-20@2x"),
        (20, 3, "Icon-20@3x"),
        (29, 2, "Icon-29@2x"),
        (29, 3, "Icon-29@3x"),
        (40, 2, "Icon-40@2x"),
        (40, 3, "Icon-40@3x"),
        (60, 2, "Icon-60@2x"),
        (60, 3, "Icon-60@3x"),
        (1024, 1, "Icon-1024") // App Store icon
    ]
    
    let outputDir = FileManager.default.currentDirectoryPath + "/AppIcons"
    try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    
    for icon in sizes {
        let pixelSize = icon.size * icon.scale
        if let image = createIcon(size: pixelSize) {
            let url = URL(fileURLWithPath: "\(outputDir)/\(icon.name).png")
            saveImage(image, to: url)
            print("✅ Generated: \(icon.name).png (\(pixelSize)x\(pixelSize))")
        }
    }
    
    print("\n✨ App icons generated in: \(outputDir)")
    print("📝 Drag these images into Assets.xcassets/AppIcon in Xcode")
}

func createIcon(size: Int) -> CGImage? {
    let width = size
    let height = size
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return nil
    }
    
    // Gradient background (health-themed: pink to red)
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1.0),  // Pink
            CGColor(red: 1.0, green: 0.2, blue: 0.4, alpha: 1.0)   // Red
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
        options: []
    )
    
    // Add rounded corners (iOS style)
    let cornerRadius = CGFloat(size) * 0.2237 // Apple's app icon corner radius ratio
    let path = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    context.addPath(path)
    context.clip()
    
    // Draw a simple sync icon (circular arrows)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(CGFloat(size) * 0.08)
    context.setLineCap(.round)
    
    let center = CGFloat(size) / 2
    let radius = CGFloat(size) * 0.3
    
    // Draw circular arrow
    context.addArc(
        center: CGPoint(x: center, y: center),
        radius: radius,
        startAngle: .pi / 4,
        endAngle: .pi * 2 - .pi / 4,
        clockwise: false
    )
    context.strokePath()
    
    // Draw arrow head
    let arrowSize = CGFloat(size) * 0.12
    let arrowX = center + radius * cos(.pi / 4)
    let arrowY = center - radius * sin(.pi / 4)
    
    context.move(to: CGPoint(x: arrowX, y: arrowY))
    context.addLine(to: CGPoint(x: arrowX + arrowSize, y: arrowY - arrowSize * 0.5))
    context.move(to: CGPoint(x: arrowX, y: arrowY))
    context.addLine(to: CGPoint(x: arrowX + arrowSize * 0.5, y: arrowY + arrowSize))
    context.strokePath()
    
    // Draw heart symbol in center
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    let heartSize = CGFloat(size) * 0.15
    let heartX = center - heartSize / 2
    let heartY = center - heartSize / 2
    
    // Simple heart shape using bezier curve
    context.move(to: CGPoint(x: center, y: heartY + heartSize))
    context.addCurve(
        to: CGPoint(x: heartX, y: heartY + heartSize * 0.3),
        control1: CGPoint(x: center, y: heartY + heartSize * 0.7),
        control2: CGPoint(x: heartX, y: heartY + heartSize * 0.5)
    )
    context.addArc(
        center: CGPoint(x: heartX + heartSize * 0.25, y: heartY + heartSize * 0.25),
        radius: heartSize * 0.25,
        startAngle: .pi,
        endAngle: 0,
        clockwise: true
    )
    context.addArc(
        center: CGPoint(x: heartX + heartSize * 0.75, y: heartY + heartSize * 0.25),
        radius: heartSize * 0.25,
        startAngle: .pi,
        endAngle: 0,
        clockwise: true
    )
    context.addCurve(
        to: CGPoint(x: center, y: heartY + heartSize),
        control1: CGPoint(x: heartX + heartSize, y: heartY + heartSize * 0.5),
        control2: CGPoint(x: center, y: heartY + heartSize * 0.7)
    )
    context.fillPath()
    
    return context.makeImage()
}

func saveImage(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// Run the generator
generateAppIcon()
