import CoreGraphics

/// Manages the snow pile height data and generates paths for rendering.
/// Height grows only when snow is deposited via `depositSnow(atX:)`.
struct HeightMap {
    let columnWidth: CGFloat = 4.0
    let screenWidth: CGFloat
    let maxHeight: CGFloat
    var heights: [CGFloat]

    /// Per-column color deposit tracking for multi-session blending
    var colorDeposits: [ColorDeposit]

    /// Cumulative area swept away by the cursor (in square points)
    private(set) var totalSweptArea: CGFloat = 0

    /// Cosine splat radius in points — each deposit spreads across this range
    private let splatRadius: CGFloat = 100.0
    private let splatColumns: Int

    /// Peak height added at the center of each deposit.
    private let peakDeposit: CGFloat = 4.0

    init(screenWidth: CGFloat, screenHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.maxHeight = 0.25 * screenHeight

        let columnCount = Int(ceil(screenWidth / 4.0))
        self.heights = [CGFloat](repeating: 0, count: columnCount)
        self.colorDeposits = [ColorDeposit](repeating: ColorDeposit(), count: columnCount)
        self.splatColumns = Int(splatRadius / 4.0)
    }

    var averageHeight: CGFloat {
        heights.reduce(0, +) / CGFloat(max(heights.count, 1))
    }

    var isCapped: Bool {
        heights.contains { $0 >= maxHeight }
    }

    // MARK: - Snow Deposit

    /// Deposit snow at a landing position, spreading height via cosine falloff
    mutating func depositSnow(atX x: CGFloat) {
        depositSnow(atX: x, session: nil)
    }

    /// Deposit snow at a landing position with session tracking for color blending.
    mutating func depositSnow(atX x: CGFloat, session: Int?) {
        guard !isCapped else { return }

        let centerColumn = Int(x / columnWidth)

        let start = max(0, centerColumn - splatColumns)
        let end = min(heights.count - 1, centerColumn + splatColumns)
        guard start <= end else { return }

        for i in start...end {
            let distance = abs(CGFloat(i - centerColumn)) * columnWidth
            let factor = cos(distance / splatRadius * .pi / 2)
            if factor > 0 {
                let deposit = peakDeposit * factor
                heights[i] = min(heights[i] + deposit, maxHeight)
                if let s = session {
                    colorDeposits[i].sessionHeights[s, default: 0] += deposit
                }
            }
        }
    }

    // MARK: - Sweep (cursor interaction)

    /// Lower the pile around a point, simulating the cursor sweeping snow away.
    /// Tracks cumulative swept area for threshold detection.
    mutating func sweepSnow(atX x: CGFloat, radius: CGFloat, amount: CGFloat) {
        let centerColumn = Int(x / columnWidth)
        let radiusColumns = Int(radius / columnWidth)

        let start = max(0, centerColumn - radiusColumns)
        let end = min(heights.count - 1, centerColumn + radiusColumns)
        guard start <= end else { return }

        for i in start...end {
            let distance = abs(CGFloat(i - centerColumn)) * columnWidth
            let factor = cos(distance / radius * .pi / 2)
            if factor > 0 {
                let before = heights[i]
                heights[i] = max(heights[i] - amount * factor, 0)
                let removed = before - heights[i]
                totalSweptArea += removed * columnWidth
            }
        }
    }

    // MARK: - Melt

    /// Decay all heights by a factor (0..1). Returns true when fully melted.
    mutating func melt(factor: CGFloat) -> Bool {
        var allMelted = true
        for i in 0..<heights.count {
            heights[i] *= factor
            colorDeposits[i].melt(factor: factor)
            if heights[i] < 0.5 {
                heights[i] = 0
            } else {
                allMelted = false
            }
        }
        return allMelted
    }

    // MARK: - Smoothing

    /// 3-tap moving average to blend deposits into natural contours
    mutating func smooth() {
        var smoothed = heights
        for i in 0..<heights.count {
            let prev = i > 0 ? heights[i - 1] : heights[i]
            let next = i < heights.count - 1 ? heights[i + 1] : heights[i]
            smoothed[i] = (prev + 2 * heights[i] + next) / 4
        }
        heights = smoothed
    }

    // MARK: - Path Generation

    /// Closed path for the pile fill (bottom edge included)
    func buildPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))

        for i in 0..<heights.count {
            let x = CGFloat(i) * columnWidth
            path.addLine(to: CGPoint(x: x, y: heights[i]))
        }

        path.addLine(to: CGPoint(x: screenWidth, y: 0))
        path.closeSubpath()
        return path
    }

    /// Open path tracing only the top surface (for glow node)
    func buildSurfacePath() -> CGPath {
        let path = CGMutablePath()
        guard !heights.isEmpty else { return path }
        path.move(to: CGPoint(x: 0, y: heights[0]))

        for i in 1..<heights.count {
            let x = CGFloat(i) * columnWidth
            path.addLine(to: CGPoint(x: x, y: heights[i]))
        }

        return path
    }

    /// Interpolated height at a given x position
    func heightAt(x: CGFloat) -> CGFloat {
        let column = x / columnWidth
        let i = Int(column)
        let fraction = column - CGFloat(i)

        guard i >= 0 else { return heights.first ?? 0 }
        guard i < heights.count - 1 else { return heights.last ?? 0 }

        return heights[i] + (heights[i + 1] - heights[i]) * fraction
    }
}
