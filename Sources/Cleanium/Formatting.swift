import Foundation
import CleaniumCore

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

extension Risk {
    var label: String {
        switch self {
        case .safe: return "Safe — regenerated automatically"
        case .rebuildable: return "Rebuildable — one command restores"
        case .redownload: return "Re-downloadable"
        case .userData: return "User data — verify first"
        case .unknown: return "Unknown"
        }
    }
    var badge: String {
        switch self {
        case .safe: return "A"
        case .rebuildable: return "B"
        case .redownload: return "C"
        case .userData: return "D"
        case .unknown: return "?"
        }
    }
}

extension Provenance {
    var label: String {
        switch self {
        case .bundled: return "built-in rule"
        case .learned: return "learned rule"
        case .llm(let p): return "AI (\(p))"
        }
    }
}
