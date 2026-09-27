import SwiftUI
import DGCharts

/// Brand colors mirrored as UIColor for DGCharts, which draws with UIKit types.
enum LineCheckChartColor {
    static let navy = UIColor(red: 0.03, green: 0.10, blue: 0.31, alpha: 1)
    static let blue = UIColor(red: 0.38, green: 0.20, blue: 0.95, alpha: 1)
    static let pink = UIColor(red: 1.0, green: 0.19, blue: 0.47, alpha: 1)
    static let purple = UIColor(red: 0.38, green: 0.20, blue: 0.95, alpha: 1)
    static let teal = UIColor(red: 0.02, green: 0.62, blue: 0.70, alpha: 1)
    static let amber = UIColor(red: 0.93, green: 0.63, blue: 0.13, alpha: 1)
    static let gridline = UIColor(red: 0.03, green: 0.10, blue: 0.31, alpha: 0.18)
    static let label = UIColor(red: 0.03, green: 0.10, blue: 0.31, alpha: 0.55)
}

/// One point for a DGCharts line/point series, with an optional explicit x-axis label
/// so labels always correspond to a real logged value - never an "automatic" tick that
/// lands somewhere no data exists.
struct ChartPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let label: String?
    let markerColor: UIColor?
    /// Richer, multi-line text for the press-and-hold callout (e.g. date + result), kept
    /// separate from `label` since the axis label needs to stay short.
    let markerText: String?

    init(x: Double, y: Double, label: String? = nil, markerColor: UIColor? = nil, markerText: String? = nil) {
        self.x = x
        self.y = y
        self.label = label
        self.markerColor = markerColor
        self.markerText = markerText ?? label
    }
}

/// A vertical reference line drawn across the whole chart at a given x
/// position - used to mark a date that matters biologically (ovulation, the
/// start/end of a fertile window) on top of a plain value-over-time line,
/// rather than leaving the reader to cross-reference the date themselves.
/// A reference value drawn across the chart (e.g. a BBT coverline).
struct ChartHorizontalMarker {
    let y: Double
    let label: String
    let color: UIColor
}

struct ChartVerticalMarker {
    let x: Double
    let label: String
    let color: UIColor
    var dashed: Bool = true
}

private func signature(of points: [ChartPoint]) -> Int {
    var hasher = Hasher()
    for point in points {
        hasher.combine(point.x)
        hasher.combine(point.y)
        hasher.combine(point.label)
    }
    return hasher.finalize()
}

/// A closure-backed AxisValueFormatter, since DGCharts wants a class conforming to the protocol.
final class ClosureValueFormatter: NSObject, AxisValueFormatter {
    let closure: (Double, AxisBase?) -> String
    init(_ closure: @escaping (Double, AxisBase?) -> String) { self.closure = closure }
    func stringForValue(_ value: Double, axis: AxisBase?) -> String { closure(value, axis) }
}

final class DaysValueFormatter: NSObject, ValueFormatter {
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        "\(Int(value.rounded()))"
    }
}

/// A press-and-hold callout showing the date (stashed in `ChartDataEntry.data`) for the
/// touched point - used on crowded trend charts instead of trying to fit every date along
/// the x-axis, which just overlaps into unreadable mush once there are more than a
/// handful of points.
final class ChartDateMarker: MarkerView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = LineCheckChartColor.navy.withAlphaComponent(0.92)
        layer.cornerRadius = 10
        label.font = .systemFont(ofSize: LineType.size(12), weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
        label.text = (entry.data as? String) ?? String(format: "%.2f", entry.y)
        let size = label.sizeThatFits(CGSize(width: 220, height: 44))
        self.bounds = CGRect(x: 0, y: 0, width: size.width + 20, height: size.height + 14)
        label.frame = bounds.insetBy(dx: 10, dy: 7)
    }

    override func offsetForDrawing(atPoint point: CGPoint) -> CGPoint {
        guard let chartView else { return CGPoint(x: -bounds.width / 2, y: -bounds.height - 12) }
        var x = -bounds.width / 2
        if point.x + x < 0 { x = -point.x }
        else if point.x + bounds.width + x > chartView.bounds.width { x = chartView.bounds.width - point.x - bounds.width }

        // Default to sitting above the touched point - but a point near the top of the chart
        // (e.g. a high temperature reading) leaves no headroom, so the bubble clips past the
        // chart's own top edge. Flip it below the point instead when that happens.
        var y = -bounds.height - 12
        if point.y + y < 0 { y = 12 }
        return CGPoint(x: x, y: y)
    }
}

/// Tracks the last-applied data signature so `updateUIView` (called by SwiftUI on any
/// ancestor re-render, not just real data changes) can skip re-assigning chart data and
/// re-triggering its entrance animation - without this, charts visibly flicker while the
/// surrounding scroll view or card animates.
final class ChartUpdateCoordinator {
    var lastSignature: Int?
    /// The custom hand-drawn intro stroke and point dots currently animating in, if any -
    /// tracked so a new data update can remove a still-running one instead of leaving it
    /// stacked underneath, or a stale completion handler restoring state that's no longer current.
    var introLayer: CAShapeLayer?
    var introDotLayers: [CALayer] = []
}

/// A smooth Catmull-Rom-style curve through a series of points, in the same spirit as
/// DGCharts' own `.cubicBezier` line mode - used to draw a temporary overlay stroke that
/// looks like the finished chart line, so the real line can be hidden and this one animated
/// with a true continuous `strokeEnd` reveal instead of DGCharts' native reveal, which shows
/// one whole point (and its connecting segment) at a time rather than tracing the path.
private func smoothedPath(through points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 1 else { return path }
    for i in 0..<(points.count - 1) {
        let p0 = points[max(0, i - 1)]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = points[min(points.count - 1, i + 2)]
        let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: control1, control2: control2)
    }
    return path
}

@MainActor
private func styledAxes(_ chart: BarLineChartViewBase, yFormatter: ((Double) -> String)?, yGranularity: Double?, xLabels: [Double: String], xValues: [Double]) {
    chart.rightAxis.enabled = false
    chart.leftAxis.gridColor = LineCheckChartColor.gridline
    chart.leftAxis.gridLineDashLengths = [4, 4]
    chart.leftAxis.labelTextColor = LineCheckChartColor.label
    chart.leftAxis.labelFont = .systemFont(ofSize: LineType.size(12), weight: .semibold)
    chart.leftAxis.axisLineColor = .clear
    if let yFormatter {
        chart.leftAxis.valueFormatter = ClosureValueFormatter { value, _ in yFormatter(value) }
    }
    if let yGranularity {
        chart.leftAxis.granularityEnabled = true
        chart.leftAxis.granularity = yGranularity
    } else {
        chart.leftAxis.granularityEnabled = false
    }

    chart.xAxis.labelPosition = .bottom
    chart.xAxis.drawGridLinesEnabled = false
    chart.xAxis.axisLineColor = LineCheckChartColor.gridline
    chart.xAxis.labelTextColor = LineCheckChartColor.label
    chart.xAxis.labelFont = .systemFont(ofSize: LineType.size(12), weight: .semibold)
    chart.xAxis.granularity = 1
    chart.xAxis.granularityEnabled = true
    chart.xAxis.valueFormatter = ClosureValueFormatter { value, _ in xLabels[value] ?? "" }

    // The first/last axis label is centered on its tick, so its other half overflows past
    // the plot's data range - pad the range itself (not just the view margin) so that
    // overflow lands in blank space instead of getting clipped by the chart's own edge. Kept
    // small and capped, since with only a couple of points a whole extra index-width of
    // padding on each side reads as a huge empty gutter around the line.
    if let lo = xValues.min(), let hi = xValues.max() {
        let padding = min(0.5, max(0.2, (hi - lo) * 0.06))
        chart.xAxis.axisMinimum = lo - padding
        chart.xAxis.axisMaximum = hi + padding
    }

    chart.legend.enabled = false
    chart.dragEnabled = true
    chart.pinchZoomEnabled = false
    chart.scaleXEnabled = false
    chart.scaleYEnabled = false
    chart.doubleTapToZoomEnabled = false
    chart.noDataText = ""
    // Circle/bar marks sitting exactly at an axis min/max, or at the first/last x position,
    // need real headroom on every side, or their far edge renders flush against - and gets
    // visually clipped by - the view's own bounds.
    chart.extraTopOffset = 20
    chart.extraBottomOffset = 16
    chart.extraLeftOffset = 10
    chart.extraRightOffset = 10
}

/// A smooth filled line chart - used for temperature, hormone-ratio, and progression trends.
struct DGLineChart: UIViewRepresentable {
    let points: [ChartPoint]
    var color: UIColor = LineCheckChartColor.purple
    var yAxisMin: Double?
    var yAxisMax: Double?
    var yGranularity: Double?
    var yFormatter: ((Double) -> String)?
    var showArea: Bool = true
    var zeroLine: Bool = false
    /// Reference dates drawn as vertical lines across the chart (e.g.
    /// estimated ovulation, fertile-window bounds) so a value-over-time line
    /// reads against the cycle context it actually happened in.
    var verticalMarkers: [ChartVerticalMarker] = []
    var horizontalMarkers: [ChartHorizontalMarker] = []
    /// When there are too many points to label every one along the x-axis without them
    /// overlapping into mush, show a zoomed-in, pannable/pinchable window over the most
    /// recent points instead, with a press-and-hold callout for the exact date.
    var isZoomable: Bool = false

    func makeUIView(context: Context) -> LineChartView {
        LineChartView()
    }

    func makeCoordinator() -> ChartUpdateCoordinator { ChartUpdateCoordinator() }

    func updateUIView(_ chart: LineChartView, context: Context) {
        var sig = signature(of: points) &+ color.hashValue &+ (yAxisMin?.hashValue ?? 0) &+ (yAxisMax?.hashValue ?? 0)
        for marker in verticalMarkers { sig = sig &+ marker.x.hashValue &+ marker.label.hashValue }
        for marker in horizontalMarkers { sig = sig &+ marker.y.hashValue &+ marker.label.hashValue }
        guard context.coordinator.lastSignature != sig else { return }
        context.coordinator.lastSignature = sig
        let dataSet = configure(chart)
        beginIntroAnimation(chart: chart, dataSet: dataSet, coordinator: context.coordinator)
    }

    /// Renders this chart's current data to a static image without any of
    /// updateUIView's coordinator/signature bookkeeping or intro animation -
    /// used for PDF export, where the chart is built fresh off-screen for a
    /// single snapshot rather than kept alive as a live, animating view.
    /// DGCharts draws via Core Graphics rather than pure SwiftUI, so
    /// SwiftUI's ImageRenderer can't snapshot a live chart view directly -
    /// getChartImage() is DGCharts' own export path and renders correctly
    /// regardless (2026-08-27, confirmed after ImageRenderer produced a
    /// "content unavailable" placeholder image for these charts).
    @MainActor
    func renderedImage(size: CGSize) -> UIImage? {
        let chart = LineChartView(frame: CGRect(origin: .zero, size: size))
        chart.backgroundColor = .white
        _ = configure(chart)
        chart.layoutIfNeeded()
        return chart.getChartImage(transparent: false)
    }

    @discardableResult
    @MainActor
    private func configure(_ chart: LineChartView) -> LineChartDataSet {
        // Multiple points can legitimately share an x (e.g. two scans logged the same
        // cycle day), so this must tolerate duplicate keys rather than crash on them.
        let xLabels = Dictionary(
            points.compactMap { point -> (Double, String)? in
                guard let label = point.label else { return nil }
                return (point.x, label)
            },
            uniquingKeysWith: { first, _ in first }
        )
        styledAxes(chart, yFormatter: yFormatter, yGranularity: yGranularity, xLabels: xLabels, xValues: points.map(\.x))

        if let yAxisMin { chart.leftAxis.axisMinimum = yAxisMin } else { chart.leftAxis.resetCustomAxisMin() }
        if let yAxisMax { chart.leftAxis.axisMaximum = yAxisMax } else { chart.leftAxis.resetCustomAxisMax() }

        chart.leftAxis.removeAllLimitLines()
        if zeroLine {
            let limitLine = ChartLimitLine(limit: 0)
            limitLine.lineColor = LineCheckChartColor.navy.withAlphaComponent(0.18)
            limitLine.lineWidth = 1
            chart.leftAxis.addLimitLine(limitLine)
        }

        for marker in horizontalMarkers {
            let limitLine = ChartLimitLine(limit: marker.y, label: marker.label)
            limitLine.lineColor = marker.color
            limitLine.lineWidth = 1.2
            limitLine.lineDashLengths = [4, 3]
            limitLine.valueTextColor = marker.color
            limitLine.valueFont = .systemFont(ofSize: LineType.size(10), weight: .bold)
            limitLine.labelPosition = .leftTop
            chart.leftAxis.addLimitLine(limitLine)
        }
        chart.leftAxis.drawLimitLinesBehindDataEnabled = true

        chart.xAxis.removeAllLimitLines()
        for marker in verticalMarkers {
            let limitLine = ChartLimitLine(limit: marker.x, label: marker.label)
            limitLine.lineColor = marker.color
            limitLine.lineWidth = 1.4
            if marker.dashed { limitLine.lineDashLengths = [5, 4] }
            limitLine.valueTextColor = marker.color
            limitLine.valueFont = .systemFont(ofSize: LineType.size(10), weight: .bold)
            limitLine.labelPosition = .rightTop
            limitLine.xOffset = 4
            limitLine.yOffset = 4
            chart.xAxis.addLimitLine(limitLine)
        }

        let entries = points.map { point -> ChartDataEntry in
            let entry = ChartDataEntry(x: point.x, y: point.y)
            entry.data = point.markerText
            return entry
        }
        let dataSet = LineChartDataSet(entries: entries)
        dataSet.colors = [color]
        dataSet.lineWidth = 3
        dataSet.mode = .cubicBezier
        dataSet.drawCirclesEnabled = true
        dataSet.circleRadius = 4
        dataSet.circleColors = points.map { $0.markerColor ?? color }
        dataSet.drawCircleHoleEnabled = true
        dataSet.circleHoleColor = .white
        dataSet.drawValuesEnabled = false
        dataSet.highlightEnabled = isZoomable
        // Our own ChartDateMarker bubble already shows the tapped value, so DGCharts' built-in
        // crosshair (a vertical + horizontal line through the tapped point) would just be
        // redundant clutter on top of it - suppress it, keeping only the marker bubble.
        dataSet.drawVerticalHighlightIndicatorEnabled = false
        dataSet.drawHorizontalHighlightIndicatorEnabled = false
        dataSet.drawFilledEnabled = showArea
        if showArea {
            dataSet.fillAlpha = 0.18
            dataSet.fill = LinearGradientFill(
                gradient: CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [color.withAlphaComponent(0.32).cgColor, color.withAlphaComponent(0.02).cgColor] as CFArray,
                    locations: [0, 1]
                )!,
                angle: 90
            )
        }

        chart.data = LineChartData(dataSet: dataSet)

        if isZoomable {
            chart.scaleXEnabled = true
            chart.pinchZoomEnabled = true
            chart.doubleTapToZoomEnabled = true
            chart.highlightPerTapEnabled = true
            chart.highlightPerDragEnabled = false
            // Full dates for every point overlap into unreadable mush once there are more
            // than a handful, so only a window of recent points is visible at once (panned/
            // zoomed via setVisibleXRangeMaximum below) - the target label count must match
            // that window size, or DGCharts spreads fewer labels across more points than are
            // visible, leaving some circles with no label under them at all.
            let visibleCount = Double(min(max(points.count, 1), 5))
            chart.xAxis.drawLabelsEnabled = true
            chart.xAxis.setLabelCount(Int(visibleCount), force: false)
            let marker = ChartDateMarker(frame: .zero)
            marker.chartView = chart
            chart.marker = marker
            chart.setVisibleXRangeMaximum(visibleCount)
            if let lastX = points.last?.x {
                chart.moveViewToX(lastX)
            }
        } else {
            chart.scaleXEnabled = false
            chart.pinchZoomEnabled = false
            chart.doubleTapToZoomEnabled = false
            chart.xAxis.drawLabelsEnabled = true
            chart.marker = nil
            chart.fitScreen()
        }

        return dataSet
    }

    // DGCharts' own phase-based reveal isn't used for the intro at all - it shows one
    // whole point (and its connecting segment) at a time rather than continuously tracing
    // the path, and its timing can't be reliably interleaved with a separate custom
    // animation (chaining into it here previously caused a premature full-reveal redraw
    // before the phase animation had even been (re)started). Instead the real line and
    // circles are hidden for the intro, and a fully self-driven overlay - one smooth hand
    // -drawn stroke plus a small "pop" dot per point, all timed off the same clock - draws
    // in their place, then the real interactive chart swaps in underneath once it's done.
    @MainActor
    private func beginIntroAnimation(chart: LineChartView, dataSet: LineChartDataSet, coordinator: ChartUpdateCoordinator) {
        let introDuration = 1.1
        coordinator.introLayer?.removeFromSuperlayer()
        coordinator.introLayer = nil
        coordinator.introDotLayers.forEach { $0.removeFromSuperlayer() }
        coordinator.introDotLayers = []

        let restoreLineWidth = dataSet.lineWidth
        let visibleEntryPoints: [ChartPoint] = isZoomable ? Array(points.suffix(Int(min(max(points.count, 1), 5)))) : points

        // On the very first `updateUIView` call after `makeUIView`, SwiftUI can still be mid
        // layout - `chart.bounds` may still be zero-sized here, which would make
        // `pixelForValues` compute a garbage/degenerate path. Retry on the next run loop turn
        // (by which point layout has settled) rather than silently drawing a broken overlay.
        func startIntroAnimation(attemptsLeft: Int) {
            chart.layoutIfNeeded()
            guard chart.bounds.width > 1, chart.bounds.height > 1 else {
                guard attemptsLeft > 0 else { return }
                DispatchQueue.main.async { startIntroAnimation(attemptsLeft: attemptsLeft - 1) }
                return
            }

            let pixelPoints = visibleEntryPoints.map { chart.pixelForValues(x: $0.x, y: $0.y, axis: .left) }
            guard pixelPoints.count > 1 else { return }

            // Hide the real line and circles entirely until the hand-drawn intro finishes -
            // nothing about their timing is driven by DGCharts' own animator any more.
            dataSet.lineWidth = 0
            dataSet.drawCirclesEnabled = false
            chart.notifyDataSetChanged()

            let strokeLayer = CAShapeLayer()
            strokeLayer.path = smoothedPath(through: pixelPoints)
            strokeLayer.strokeColor = color.cgColor
            strokeLayer.fillColor = UIColor.clear.cgColor
            strokeLayer.lineWidth = restoreLineWidth
            strokeLayer.lineCap = .round
            strokeLayer.lineJoin = .round
            strokeLayer.strokeEnd = 0
            chart.layer.addSublayer(strokeLayer)
            coordinator.introLayer = strokeLayer

            let strokeAnimation = CABasicAnimation(keyPath: "strokeEnd")
            strokeAnimation.fromValue = 0
            strokeAnimation.toValue = 1
            strokeAnimation.duration = introDuration
            strokeAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            strokeAnimation.fillMode = .forwards
            strokeAnimation.isRemovedOnCompletion = false
            strokeLayer.add(strokeAnimation, forKey: "draw")

            // Each dot pops in once the stroke reaches it - evenly spaced by point order,
            // which tracks the hand-drawn stroke closely enough to read as one continuous motion.
            let dotDiameter = CGFloat(dataSet.circleRadius) * 2
            var dotLayers: [CALayer] = []
            for (index, point) in pixelPoints.enumerated() {
                let dot = CALayer()
                dot.frame = CGRect(x: point.x - dotDiameter / 2, y: point.y - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
                dot.cornerRadius = dotDiameter / 2
                dot.backgroundColor = (visibleEntryPoints[index].markerColor ?? color).cgColor
                dot.opacity = 0
                let holeDiameter = dotDiameter * 0.5
                let hole = CALayer()
                hole.frame = CGRect(x: (dotDiameter - holeDiameter) / 2, y: (dotDiameter - holeDiameter) / 2, width: holeDiameter, height: holeDiameter)
                hole.cornerRadius = holeDiameter / 2
                hole.backgroundColor = UIColor.white.cgColor
                dot.addSublayer(hole)
                chart.layer.addSublayer(dot)
                dotLayers.append(dot)

                let delay = pixelPoints.count > 1 ? introDuration * Double(index) / Double(pixelPoints.count - 1) : 0
                let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                pop.values = [0, 1.3, 1]
                pop.keyTimes = [0, 0.6, 1]
                pop.duration = 0.3
                pop.beginTime = CACurrentMediaTime() + delay
                pop.fillMode = .backwards
                pop.isRemovedOnCompletion = false
                dot.add(pop, forKey: "pop")

                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0
                fadeIn.toValue = 1
                fadeIn.duration = 0.001
                fadeIn.beginTime = CACurrentMediaTime() + delay
                fadeIn.fillMode = .forwards
                fadeIn.isRemovedOnCompletion = false
                dot.add(fadeIn, forKey: "fadeIn")
            }
            coordinator.introDotLayers = dotLayers

            DispatchQueue.main.asyncAfter(deadline: .now() + introDuration + 0.3) { [weak chart] in
                guard let chart, coordinator.introLayer === strokeLayer else { return }
                strokeLayer.removeFromSuperlayer()
                dotLayers.forEach { $0.removeFromSuperlayer() }
                coordinator.introLayer = nil
                coordinator.introDotLayers = []
                dataSet.lineWidth = restoreLineWidth
                dataSet.drawCirclesEnabled = true
                chart.notifyDataSetChanged()
            }
        }
        startIntroAnimation(attemptsLeft: 5)
    }
}

/// A bar chart for discrete per-day values (OPK ratio, flow intensity, cycle length).
struct DGBarChart: UIViewRepresentable {
    let points: [ChartPoint]
    var color: UIColor = LineCheckChartColor.purple
    var barColors: [UIColor]?
    /// Forces the y-axis minimum. Defaults to 0 (bars always grow up from a
    /// floor), but deviation-from-baseline data needs bars that can go
    /// negative - pass nil to let the axis size itself to the data instead.
    var yAxisMin: Double? = 0
    var yAxisMax: Double?
    var yGranularity: Double?
    var yFormatter: ((Double) -> String)?
    var showValueLabels: Bool = false
    var valueLabelsInsideBars: Bool = false
    /// Draws a dashed reference line at the mean of the plotted values, labeled "Avg" -
    /// context for whether recent bars are running above or below the user's own recent
    /// normal, derived from their own chart rather than a fixed threshold.
    var averageLine: Bool = false
    /// Draws a plain reference line at zero - for deviation-from-baseline
    /// data, where zero (not the mean) is the meaningful reference point.
    var zeroLine: Bool = false
    /// Reference dates drawn as vertical lines across the chart (e.g.
    /// estimated ovulation, fertile-window bounds).
    var verticalMarkers: [ChartVerticalMarker] = []
    var horizontalMarkers: [ChartHorizontalMarker] = []
    /// When there are too many bars to label every one along the x-axis without them
    /// overlapping into mush, show a zoomed-in, pannable/pinchable window over the most
    /// recent bars instead, with a press-and-hold callout for the exact date.
    var isZoomable: Bool = false

    func makeUIView(context: Context) -> BarChartView {
        BarChartView()
    }

    func makeCoordinator() -> ChartUpdateCoordinator { ChartUpdateCoordinator() }

    func updateUIView(_ chart: BarChartView, context: Context) {
        var sig = signature(of: points) &+ color.hashValue &+ (yAxisMax?.hashValue ?? 0) &+ (yAxisMin?.hashValue ?? 0)
        for marker in verticalMarkers { sig = sig &+ marker.x.hashValue &+ marker.label.hashValue }
        for marker in horizontalMarkers { sig = sig &+ marker.y.hashValue &+ marker.label.hashValue }
        guard context.coordinator.lastSignature != sig else { return }
        context.coordinator.lastSignature = sig
        configure(chart)
        chart.animate(yAxisDuration: 0.5, easingOption: .easeOutCubic)
    }

    /// See DGLineChart.renderedImage - same rationale (DGCharts draws via
    /// Core Graphics, so SwiftUI's ImageRenderer can't snapshot a live
    /// chart view; getChartImage() is DGCharts' own working export path).
    @MainActor
    func renderedImage(size: CGSize) -> UIImage? {
        let chart = BarChartView(frame: CGRect(origin: .zero, size: size))
        chart.backgroundColor = .white
        configure(chart)
        chart.layoutIfNeeded()
        return chart.getChartImage(transparent: false)
    }

    @MainActor
    private func configure(_ chart: BarChartView) {
        // Multiple points can legitimately share an x (e.g. two scans logged the same
        // cycle day), so this must tolerate duplicate keys rather than crash on them.
        let xLabels = Dictionary(
            points.compactMap { point -> (Double, String)? in
                guard let label = point.label else { return nil }
                return (point.x, label)
            },
            uniquingKeysWith: { first, _ in first }
        )
        styledAxes(chart, yFormatter: yFormatter, yGranularity: yGranularity, xLabels: xLabels, xValues: points.map(\.x))
        if let yAxisMin { chart.leftAxis.axisMinimum = yAxisMin } else { chart.leftAxis.resetCustomAxisMin() }
        if let yAxisMax { chart.leftAxis.axisMaximum = yAxisMax } else { chart.leftAxis.resetCustomAxisMax() }

        chart.leftAxis.removeAllLimitLines()
        if averageLine, !points.isEmpty {
            let average = points.map(\.y).reduce(0, +) / Double(points.count)
            let limitLine = ChartLimitLine(limit: average)
            limitLine.lineColor = color.withAlphaComponent(0.55)
            limitLine.lineWidth = 1.2
            limitLine.lineDashLengths = [5, 4]
            chart.leftAxis.addLimitLine(limitLine)
        }
        if zeroLine {
            let limitLine = ChartLimitLine(limit: 0)
            limitLine.lineColor = LineCheckChartColor.navy.withAlphaComponent(0.25)
            limitLine.lineWidth = 1
            chart.leftAxis.addLimitLine(limitLine)
        }

        for marker in horizontalMarkers {
            let limitLine = ChartLimitLine(limit: marker.y, label: marker.label)
            limitLine.lineColor = marker.color
            limitLine.lineWidth = 1.2
            limitLine.lineDashLengths = [4, 3]
            limitLine.valueTextColor = marker.color
            limitLine.valueFont = .systemFont(ofSize: LineType.size(10), weight: .bold)
            limitLine.labelPosition = .leftTop
            chart.leftAxis.addLimitLine(limitLine)
        }
        chart.leftAxis.drawLimitLinesBehindDataEnabled = true

        chart.xAxis.removeAllLimitLines()
        for marker in verticalMarkers {
            let limitLine = ChartLimitLine(limit: marker.x, label: marker.label)
            limitLine.lineColor = marker.color
            limitLine.lineWidth = 1.4
            if marker.dashed { limitLine.lineDashLengths = [5, 4] }
            limitLine.valueTextColor = marker.color
            limitLine.valueFont = .systemFont(ofSize: LineType.size(10), weight: .bold)
            limitLine.labelPosition = .rightTop
            limitLine.xOffset = 4
            limitLine.yOffset = 4
            chart.xAxis.addLimitLine(limitLine)
        }

        let entries = points.map { BarChartDataEntry(x: $0.x, y: $0.y) }
        let dataSet = BarChartDataSet(entries: entries)
        dataSet.colors = barColors ?? points.map { $0.markerColor ?? color }
        dataSet.drawValuesEnabled = showValueLabels
        dataSet.valueFont = .systemFont(ofSize: LineType.size(11), weight: .bold)
        dataSet.valueTextColor = valueLabelsInsideBars ? .white : LineCheckChartColor.navy
        if valueLabelsInsideBars { dataSet.valueFormatter = DaysValueFormatter() }
        chart.drawValueAboveBarEnabled = !valueLabelsInsideBars
        // The value is already shown permanently above each bar when showValueLabels is on,
        // so a tap-to-reveal marker on top would just be a second, overlapping copy of the
        // same number, colliding with the value label and the average line's own label.
        dataSet.highlightEnabled = isZoomable && !showValueLabels

        let data = BarChartData(dataSet: dataSet)
        data.barWidth = 0.42
        chart.data = data
        if averageLine, !points.isEmpty {
            addAverageBarLabel(to: chart, points: points)
        } else {
            chart.viewWithTag(9417)?.removeFromSuperview()
        }

        if isZoomable {
            chart.scaleXEnabled = true
            chart.pinchZoomEnabled = true
            chart.doubleTapToZoomEnabled = true
            chart.highlightPerTapEnabled = !showValueLabels
            chart.highlightPerDragEnabled = false
            chart.xAxis.drawLabelsEnabled = true
            let visibleCount = Double(min(max(points.count, 1), 4))
            chart.xAxis.setLabelCount(Int(visibleCount), force: false)
            if showValueLabels {
                chart.marker = nil
            } else {
                let marker = ChartDateMarker(frame: .zero)
                marker.chartView = chart
                chart.marker = marker
            }
            chart.setVisibleXRangeMaximum(visibleCount)
            if let lastX = points.last?.x {
                chart.moveViewToX(lastX)
            }
        } else {
            chart.scaleXEnabled = false
            chart.pinchZoomEnabled = false
            chart.doubleTapToZoomEnabled = false
            chart.xAxis.drawLabelsEnabled = true
            chart.marker = nil
            chart.fitScreen()
        }
    }

    private func addAverageBarLabel(to chart: BarChartView, points: [ChartPoint]) {
        chart.viewWithTag(9417)?.removeFromSuperview()
        guard !points.isEmpty else { return }
        let average = points.map(\.y).reduce(0, +) / Double(points.count)

        let label = UILabel()
        label.tag = 9417
        // Rounded half-up, like every other average on Trends (28.5 -> 29).
        label.text = "AVG \(Int(average.rounded()))"
        label.textColor = .white
        label.font = .systemFont(ofSize: LineType.size(11), weight: .bold)
        label.textAlignment = .center
        label.backgroundColor = color.withAlphaComponent(0.82)
        label.layer.cornerRadius = 7
        label.layer.masksToBounds = true
        chart.addSubview(label)

        // Positioned on the next runloop turn, not here: SwiftUI sets this
        // chart's final frame *after* the representable's update pass, so a
        // frame computed now is measured against a stale (often near-empty)
        // viewport and the badge ends up stranded in a corner of the card.
        DispatchQueue.main.async { [weak chart, weak label] in
            guard let chart, let label, label.superview === chart else { return }
            let content = chart.viewPortHandler.contentRect
            guard content.width > 1, content.height > 1 else { return }

            let text = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            let size = CGSize(width: ceil(text.width) + 16, height: ceil(text.height) + 8)

            // Centred across the plot area rather than pinned to one end, and
            // sitting just above the dashed average line it labels - clamped
            // so a line near the top or bottom of the range can't push the
            // badge outside the plot.
            let y = chart.getTransformer(forAxis: .left).pixelForValues(x: 0, y: average).y
            let top = y.isFinite ? y - size.height - 4 : content.minY
            label.frame = CGRect(
                x: content.midX - size.width / 2,
                y: min(max(top, content.minY + 2), content.maxY - size.height - 2),
                width: size.width,
                height: size.height
            )
        }
    }
}
