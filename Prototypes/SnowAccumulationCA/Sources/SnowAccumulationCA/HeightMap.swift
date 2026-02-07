import CoreGraphics

/// Manages the snow pile height data with time-based growth.
/// Used with CAEmitterLayer where per-particle tracking isn't available.
struct HeightMap {
    let columnWidth: CGFloat = 4.0
    let screenWidth: CGFloat
    let maxHeight: CGFloat
    let baseRate: CGFloat
    let driftFactors: [CGFloat]
    var heights: [CGFloat]

    init(screenWidth: CGFloat, screenHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.maxHeight = 0.55 * screenHeight
        self.baseRate = maxHeight / 300.0 // 55% in 5 minutes

        let columnCount = Int(ceil(screenWidth / 4.0))
        self.heights = [CGFloat](repeating: 0, count: columnCount)

        // Scale-aware sine waves for natural unevenness
        var factors = [CGFloat](repeating: 0, count: columnCount)
        for i in 0..<columnCount {
            let normalizedX = CGFloat(i) / CGFloat(columnCount)
            factors[i] = 0.8
                + 0.2 * sin(normalizedX * .pi * 3)
                + 0.1 * sin(normalizedX * .pi * 7 + 2)
                + 0.1 * sin(normalizedX * .pi * 17 + 5)
        }
        self.driftFactors = factors
    }

    var averageHeight: CGFloat {
        heights.reduce(0, +) / CGFloat(max(heights.count, 1))
    }

    var isCapped: Bool {
        averageHeight >= maxHeight * 0.99
    }

    // MARK: - Update

    mutating func update(deltaTime dt: CGFloat) {
        guard !isCapped else { return }

        for i in 0..<heights.count {
            heights[i] += baseRate * dt * driftFactors[i]
            if heights[i] > maxHeight {
                heights[i] = maxHeight
            }
        }
    }

    // MARK: - Smoothing

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

    func heightAt(x: CGFloat) -> CGFloat {
        let column = x / columnWidth
        let i = Int(column)
        let fraction = column - CGFloat(i)

        guard i >= 0 else { return heights.first ?? 0 }
        guard i < heights.count - 1 else { return heights.last ?? 0 }

        return heights[i] + (heights[i + 1] - heights[i]) * fraction
    }
}
