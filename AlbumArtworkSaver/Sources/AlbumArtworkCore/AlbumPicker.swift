import Foundation

enum AlbumPicker {
    /// Shuffled pool, repeated cyclically (each round reshuffled) when it is
    /// smaller than `count`. Empty pool gives an empty result.
    static func initialFill(count: Int, pool: [AlbumID], using rng: inout SplitMix64) -> [AlbumID] {
        guard !pool.isEmpty, count > 0 else { return [] }
        var result: [AlbumID] = []
        result.reserveCapacity(count)
        while result.count < count {
            result.append(contentsOf: pool.shuffled(using: &rng).prefix(count - result.count))
        }
        return result
    }

    /// Ready and invisible, else ready and not `avoiding`, else any ready, else nil.
    static func replacement(
        pool: [AlbumID],
        isReady: (AlbumID) -> Bool,
        visible: Set<AlbumID>,
        avoiding: AlbumID?,
        using rng: inout SplitMix64
    ) -> AlbumID? {
        let ready = pool.filter(isReady)
        if let pick = ready.filter({ !visible.contains($0) }).randomElement(using: &rng) { return pick }
        if let pick = ready.filter({ $0 != avoiding }).randomElement(using: &rng) { return pick }
        return ready.randomElement(using: &rng)
    }

    /// Up to `count` distinct invisible albums, topped up with visible ones.
    static func prefetchCandidates(
        pool: [AlbumID], visible: Set<AlbumID>, count: Int, using rng: inout SplitMix64
    ) -> [AlbumID] {
        let hidden = pool.filter { !visible.contains($0) }.shuffled(using: &rng)
        var result = Array(hidden.prefix(max(0, count)))
        if result.count < count {
            let shown = pool.filter { visible.contains($0) }.shuffled(using: &rng)
            result.append(contentsOf: shown.prefix(count - result.count))
        }
        return result
    }
}
