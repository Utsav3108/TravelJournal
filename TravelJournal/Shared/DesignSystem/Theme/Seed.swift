import Foundation

/// Deterministic randomness: FNV-1a 64 over a stable string key, then splitmix64.
/// Never use `hashValue` (randomised per launch). Freeze constants: changing them restyles every journey.
nonisolated enum Seed {
    static let version = 1

    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    /// splitmix64 (increment + finaliser).
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    /// Rotation in degrees in -limit...limit (limit clamped to 4), a pure function of `id`.
    static func rotation(id: String, limit: Double = 4) -> Double {
        var s = SeededStream(id, "rot")
        return s.range(-min(limit, 4), min(limit, 4))
    }
}

nonisolated struct SeededStream {
    private var state: UInt64

    init(_ id: String, _ salt: String) {
        state = Seed.mix(Seed.fnv1a(id + "|" + salt))
    }

    mutating func next() -> UInt64 {
        state = Seed.mix(state)
        return state
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }

    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }

    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
}
