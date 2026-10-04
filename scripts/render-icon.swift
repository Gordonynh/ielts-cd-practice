// 绘制 App 图标（1024×1024 PNG）：渐变背景上的机考窗口——Highlight 标出的文字、带光标的答题框、
// 底部题号（其中一题用 Review 圆形标记），右下角是完成的对勾。
//
// 用法:
//   xcrun swift scripts/render-icon.swift [输出路径，默认 IELTSCDPractice/Assets.xcassets/AppIcon.appiconset/AppIcon.png]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "IELTSCDPractice/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// App Store 要求图标不透明：画布不带 alpha 通道
let cg = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 左上角为原点
cg.translateBy(x: 0, y: size)
cg.scaleBy(x: 1, y: -1)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ path: CGPath, _ fillColor: CGColor) {
    cg.addPath(path)
    cg.setFillColor(fillColor)
    cg.fillPath()
}

func stroke(_ path: CGPath, _ strokeColor: CGColor, width: CGFloat) {
    cg.addPath(path)
    cg.setStrokeColor(strokeColor)
    cg.setLineWidth(width)
    cg.strokePath()
}

// 背景：与 App 首页相同的靛蓝 → 蓝色渐变
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0x5445EB), color(0x1F85F7)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])

// 机考窗口
let card = CGRect(x: 164, y: 188, width: 696, height: 620)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: 22), blur: 48, color: color(0x101040, 0.35))
fill(rounded(card, 64), color(0xFFFFFF))
cg.restoreGState()

// 页眉
cg.saveGState()
cg.addPath(rounded(card, 64))
cg.clip()
fill(CGPath(rect: CGRect(x: card.minX, y: card.minY, width: card.width, height: 92), transform: nil), color(0xECEFF8))
cg.restoreGState()
fill(rounded(CGRect(x: 224, y: 222, width: 108, height: 26), 13), color(0x2A2F45))
fill(rounded(CGRect(x: 692, y: 222, width: 108, height: 26), 13), color(0xB9BFD3))

// 文字行：第二行用黄色 Highlight 标出
let line = color(0xCDD2E0)
fill(rounded(CGRect(x: 224, y: 334, width: 576, height: 28), 14), line)
fill(rounded(CGRect(x: 210, y: 384, width: 352, height: 64), 14), color(0xFFD23F))
fill(rounded(CGRect(x: 224, y: 402, width: 496, height: 28), 14), color(0x9A8A3A, 0.55))
fill(rounded(CGRect(x: 562, y: 402, width: 158, height: 28), 14), line)
fill(rounded(CGRect(x: 224, y: 470, width: 536, height: 28), 14), line)

// 答题框与光标
stroke(rounded(CGRect(x: 224, y: 540, width: 316, height: 84), 16), color(0x3D5AFE), width: 8)
fill(rounded(CGRect(x: 254, y: 560, width: 8, height: 44), 4), color(0x3D5AFE))

// 底部题号：当前题实心，第四题为 Review 圆形
let navY: CGFloat = 690
for index in 0..<5 {
    let rect = CGRect(x: 224 + CGFloat(index) * 72, y: navY, width: 52, height: 52)
    switch index {
    case 0: fill(rounded(rect, 10), color(0x3D5AFE))
    case 3: stroke(CGPath(ellipseIn: rect.insetBy(dx: 3, dy: 3), transform: nil), color(0xF5A524), width: 7)
    default: stroke(rounded(rect.insetBy(dx: 3, dy: 3), 9), color(0xB9BFD3), width: 6)
    }
}

// 右下角对勾
let badge = CGPoint(x: 806, y: 770)
fill(CGPath(ellipseIn: CGRect(x: badge.x - 132, y: badge.y - 132, width: 264, height: 264), transform: nil), color(0xFFFFFF))
fill(CGPath(ellipseIn: CGRect(x: badge.x - 112, y: badge.y - 112, width: 224, height: 224), transform: nil), color(0x22C55E))
let check = CGMutablePath()
check.move(to: CGPoint(x: badge.x - 54, y: badge.y + 2))
check.addLine(to: CGPoint(x: badge.x - 16, y: badge.y + 40))
check.addLine(to: CGPoint(x: badge.x + 58, y: badge.y - 40))
cg.addPath(check)
cg.setStrokeColor(color(0xFFFFFF))
cg.setLineWidth(38)
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.strokePath()

let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, cg.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("无法写入 \(output)") }
print("已生成 \(output)")
