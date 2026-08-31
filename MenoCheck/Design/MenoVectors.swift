import SwiftUI

/// Drawn rather than photographed, so these adapt to dark mode, scale without blurring,
/// and can point at exactly the thing being described.

// MARK: - Identity

/// The app mark: a cassette window with its two lines, the test line highlighted.
struct MenoMark: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let frame = CGRect(x: unit * 0.08, y: unit * 0.2,
                               width: unit * 0.84, height: unit * 0.6)
            let shell = Path(roundedRect: frame, cornerRadius: unit * 0.14)
            context.stroke(shell, with: .color(MenoColor.primary), lineWidth: unit * 0.08)

            let barWidth = unit * 0.1
            for (index, fraction) in [0.34, 0.66].enumerated() {
                let x = frame.minX + frame.width * fraction - barWidth / 2
                let bar = Path(roundedRect: CGRect(x: x, y: frame.minY + frame.height * 0.22,
                                                   width: barWidth, height: frame.height * 0.56),
                               cornerRadius: barWidth / 2)
                context.fill(bar, with: .color(index == 1 ? MenoColor.primary
                                                          : MenoColor.primary.opacity(0.35)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Camera guide

/// Corner brackets, as on a camera frame — an alignment guide rather than a border.
struct RegistrationMarks: Shape {
    var armLength: CGFloat = 30
    var cornerRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = min(armLength, min(rect.width, rect.height) / 3)
        let radius = min(cornerRadius, arm)

        func corner(_ pivot: CGPoint, _ dx: CGFloat, _ dy: CGFloat) {
            path.move(to: CGPoint(x: pivot.x, y: pivot.y + dy * arm))
            path.addLine(to: CGPoint(x: pivot.x, y: pivot.y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: pivot.x + dx * radius, y: pivot.y),
                              control: pivot)
            path.addLine(to: CGPoint(x: pivot.x + dx * arm, y: pivot.y))
        }

        corner(CGPoint(x: rect.minX, y: rect.minY), 1, 1)
        corner(CGPoint(x: rect.maxX, y: rect.minY), -1, 1)
        corner(CGPoint(x: rect.maxX, y: rect.maxY), -1, -1)
        corner(CGPoint(x: rect.minX, y: rect.maxY), 1, -1)
        return path
    }
}

// MARK: - Series progress

/// Progress through a fixed-length test series: filled for saved readings, outlined for
/// what is still to come, and a ring on the one that is due next.
struct SeriesProgress: View {
    let completed: Int
    let total: Int

    private var strong: Color { MenoColor.primary }
    private var faint: Color { MenoColor.primary.opacity(0.25) }

    var body: some View {
        Canvas { context, size in
            let stationCount = max(total, 1)
            let diameter = min(size.height, 22.0)
            let step = size.width / CGFloat(stationCount)
            let centreY = size.height / 2

            // Connecting track, drawn behind the stations.
            var track = Path()
            track.move(to: CGPoint(x: step * 0.5, y: centreY))
            track.addLine(to: CGPoint(x: size.width - step * 0.5, y: centreY))
            context.stroke(track, with: .color(faint), lineWidth: 2)

            for index in 0..<stationCount {
                let centre = CGPoint(x: step * (CGFloat(index) + 0.5), y: centreY)
                let dot = CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                                 width: diameter, height: diameter)

                if index < completed {
                    context.fill(Path(ellipseIn: dot), with: .color(strong))
                    var tick = Path()
                    tick.move(to: CGPoint(x: centre.x - diameter * 0.2, y: centre.y))
                    tick.addLine(to: CGPoint(x: centre.x - diameter * 0.05, y: centre.y + diameter * 0.15))
                    tick.addLine(to: CGPoint(x: centre.x + diameter * 0.22, y: centre.y - diameter * 0.18))
                    context.stroke(tick, with: .color(MenoColor.onPrimary),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else if index == completed {
                    // The reading that is due next.
                    context.fill(Path(ellipseIn: dot), with: .color(MenoColor.surface))
                    context.stroke(Path(ellipseIn: dot.insetBy(dx: 1, dy: 1)),
                                   with: .color(strong), lineWidth: 2)
                } else {
                    context.stroke(Path(ellipseIn: dot.insetBy(dx: 4, dy: 4)),
                                   with: .color(faint), lineWidth: 2)
                }
            }
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Test series progress")
        .accessibilityValue("\(completed) of \(total) readings saved")
    }
}

// MARK: - Test strip

/// A schematic of the lateral flow cassette. This replaces the photograph, whose red
/// annotation box was baked into the image and could not be restyled or explained.
struct TestStripDiagram: View {
    /// 0 = no line visible, 1 = fully developed.
    var controlLine: Double = 1
    var testLine: Double = 0.72

    var body: some View {
        Canvas { context, size in
            let body = CGRect(x: 1, y: size.height * 0.34,
                              width: size.width - 2, height: size.height * 0.60)
            let shell = Path(roundedRect: body, cornerRadius: 8)
            context.fill(shell, with: .color(MenoColor.surfaceAlt))
            context.stroke(shell, with: .color(MenoColor.rule), lineWidth: 1.5)

            // Sample well.
            let wellRadius = body.height * 0.24
            let wellCentre = CGPoint(x: body.minX + body.width * 0.11, y: body.midY)
            context.stroke(Path(ellipseIn: CGRect(x: wellCentre.x - wellRadius,
                                                  y: wellCentre.y - wellRadius,
                                                  width: wellRadius * 2, height: wellRadius * 2)),
                           with: .color(MenoColor.inkTertiary), lineWidth: 1.5)

            // Result window.
            let window = CGRect(x: body.minX + body.width * 0.32, y: body.minY + body.height * 0.18,
                                width: body.width * 0.50, height: body.height * 0.64)
            let windowPath = Path(roundedRect: window, cornerRadius: 3)
            context.fill(windowPath, with: .color(MenoColor.surface))
            context.stroke(windowPath, with: .color(MenoColor.rule), lineWidth: 1.5)

            let stations: [(String, String, Double, CGFloat)] = [
                ("C", "Control", controlLine, 0.30),
                ("T", "Test", testLine, 0.68),
            ]
            for (letter, name, strength, fraction) in stations {
                let x = window.minX + window.width * fraction
                let barWidth = window.width * 0.08
                let bar = Path(roundedRect: CGRect(x: x - barWidth / 2, y: window.minY + 4,
                                                   width: barWidth, height: window.height - 8),
                               cornerRadius: barWidth / 2)
                if strength > 0.02 {
                    context.fill(bar, with: .color(MenoColor.primary.opacity(0.3 + 0.7 * strength)))
                } else {
                    context.stroke(bar, with: .color(MenoColor.inkTertiary.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                // Leader up to a named callout, so the letters are not a private code.
                var leader = Path()
                leader.move(to: CGPoint(x: x, y: window.minY - 3))
                leader.addLine(to: CGPoint(x: x, y: size.height * 0.22))
                context.stroke(leader, with: .color(MenoColor.inkTertiary.opacity(0.7)), lineWidth: 1)

                let callout = context.resolve(
                    Text("\(letter) · \(name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MenoColor.inkSecondary)
                )
                context.draw(callout, at: CGPoint(x: x, y: size.height * 0.11), anchor: .center)
            }
        }
        .frame(height: 124)
    }
}

// MARK: - Trend

/// The series trend as a smooth trace with a node per reading, most recent emphasised.
struct TracePlot: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let inset: CGFloat = 8
            let plot = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2, height: size.height - inset * 2)

            // Scaled across the range rather than from zero, with headroom at both ends.
            // Three readings a few points apart otherwise draw as a flat line that says
            // nothing about the rise the caption is describing.
            let span = max(high - low, 0.0001)
            func point(_ index: Int) -> CGPoint {
                let fraction = 0.15 + 0.7 * (values[index] - low) / span
                return CGPoint(x: plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1),
                               y: plot.maxY - plot.height * CGFloat(fraction))
            }

            var trace = Path()
            trace.move(to: point(0))
            for index in 1..<values.count { trace.addLine(to: point(index)) }

            // Soft fill under the trace, then the trace itself.
            var area = trace
            area.addLine(to: CGPoint(x: point(values.count - 1).x, y: plot.maxY))
            area.addLine(to: CGPoint(x: point(0).x, y: plot.maxY))
            area.closeSubpath()
            context.fill(area, with: .color(MenoColor.primary.opacity(0.08)))
            context.stroke(trace, with: .color(MenoColor.primary),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            for index in values.indices {
                let centre = point(index)
                let radius: CGFloat = index == values.count - 1 ? 6 : 4
                let dot = CGRect(x: centre.x - radius, y: centre.y - radius,
                                 width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(MenoColor.surface))
                context.stroke(Path(ellipseIn: dot), with: .color(MenoColor.primary), lineWidth: 2.5)
            }
        }
        .accessibilityHidden(true)
    }
}
