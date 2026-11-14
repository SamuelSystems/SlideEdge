public enum LevelMath {
    /// Applies a slide delta to a 0...1 level and snaps the result to the delta's step grid,
    /// so slides starting from an arbitrary level land on the same 16 (or 64) positions as the keys.
    public static func apply(_ delta: Double, to level: Double) -> Double {
        let step = isMultiple(delta, of: GestureConfig.coarseStep) ? GestureConfig.coarseStep : GestureConfig.fineStep
        let snapped = ((level + delta) / step).rounded() * step
        return min(max(snapped, 0), 1)
    }

    static func isMultiple(_ value: Double, of step: Double) -> Bool {
        let ratio = value / step
        return abs(ratio - ratio.rounded()) < 1e-9
    }
}
