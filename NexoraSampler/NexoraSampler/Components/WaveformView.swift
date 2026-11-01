import SwiftUI

/// Wellenform-Übersicht mit optionalen Start-/Endmarkern.
struct WaveformView: View {
    let peaks: [Float]
    var start: Double = 0
    var end: Double = 1
    var color: Color = Nexora.Colors.turquoise
    var dimColor: Color = Nexora.Colors.turquoise.opacity(0.25)
    var markerColor: Color = Nexora.Colors.pink
    var showsMarkers = true
    var reverse = false

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(dimColor), lineWidth: 1)
                return
            }
            let count = peaks.count
            let barWidth = size.width / CGFloat(count)
            let mid = size.height / 2
            for (i, p) in peaks.enumerated() {
                let x = CGFloat(i) * barWidth
                let pos = Double(i) / Double(count)
                let inside = pos >= start && pos <= end
                let h = max(1, CGFloat(min(p, 1)) * (size.height * 0.48))
                let rect = CGRect(x: x, y: mid - h, width: max(barWidth - 0.5, 0.6), height: h * 2)
                context.fill(Path(rect), with: .color(inside ? color : dimColor))
            }
            if showsMarkers {
                for (pos, isStart) in [(start, true), (end, false)] {
                    let x = CGFloat(pos) * size.width
                    var m = Path()
                    m.move(to: CGPoint(x: x, y: 0))
                    m.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(m, with: .color(markerColor), lineWidth: 1.5)
                    let flag = CGRect(x: isStart ? x : x - 6, y: 0, width: 6, height: 6)
                    context.fill(Path(flag), with: .color(markerColor))
                }
            }
            if reverse {
                context.draw(Text("◀ REV").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(markerColor),
                             at: CGPoint(x: size.width - 22, y: size.height - 7))
            }
        }
    }
}
