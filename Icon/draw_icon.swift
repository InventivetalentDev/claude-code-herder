// Draws the app icon: Claude's spark caught in a lasso. Usage: swift draw_icon.swift <out.png>
import AppKit
import SwiftUI

func color(_ hex: UInt32) -> Color {
    Color(
        red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255)
}

let clay = color(0xD97757)
let ropeDark = color(0x8A6A45)
let ropeLight = color(0xC9A06A)

struct Spark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(clay)
                    .frame(width: size * 0.085, height: size * (i.isMultiple(of: 2) ? 0.5 : 0.4))
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The loop around the spark, plus the tail sweeping down and out of the frame.
struct Rope: Shape {
    static let knot = CGPoint(x: 764, y: 402)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 222, y: 292, width: 580, height: 420))
        p.move(to: Self.knot)
        p.addCurve(
            to: CGPoint(x: 1000, y: 884), control1: CGPoint(x: 900, y: 424),
            control2: CGPoint(x: 820, y: 744))
        return p
    }
}

/// Draws a path as rope: dark edge, tan body, and a highlight for roundness.
struct RopeStroke<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            shape.stroke(ropeDark, style: StrokeStyle(lineWidth: 30, lineCap: .round))
            shape.stroke(ropeLight, style: StrokeStyle(lineWidth: 23, lineCap: .round))
            shape.stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .offset(x: -2, y: -5)
        }
    }
}

struct Icon: View {
    let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)

    var body: some View {
        ZStack {
            squircle
                .fill(LinearGradient(
                    colors: [color(0xFCFBF8), color(0xEDEAE0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            Spark(size: 330)
                .offset(x: 6, y: 6)
                .compositingGroup()  // one shadow for the whole spark, not one per ray
                .shadow(color: color(0x9E3B2C).opacity(0.25), radius: 6, y: 4)
            ZStack {
                RopeStroke(shape: Rope())
                // The honda: the small eye the loop runs through.
                RopeStroke(shape: Circle())
                    .frame(width: 44, height: 44)
                    .position(Rope.knot)
            }
            .frame(width: 1024, height: 1024)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
            .rotationEffect(.degrees(14))
            .mask(squircle.frame(width: 824, height: 824))
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
        let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else {
        fatalError("rendering the icon failed")
    }
    do {
        try png.write(to: out)
    } catch {
        fatalError("writing \(out.path) failed: \(error)")
    }
}
