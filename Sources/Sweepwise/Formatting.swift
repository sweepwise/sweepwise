import Foundation
import SwiftUI
import SweepwiseCore

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

extension Risk {
    var label: String {
        switch self {
        case .safe: return "Safe to delete — comes back by itself"
        case .rebuildable: return "Safe to delete — one command rebuilds it"
        case .redownload: return "Deletable — can be downloaded again"
        case .userData: return "Careful — your own files, check first"
        case .unknown: return "Unknown — check before deleting"
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
    var color: Color {
        switch self {
        case .safe: return .green
        case .rebuildable: return .teal
        case .redownload: return .blue
        case .userData: return .red
        case .unknown: return .orange
        }
    }
}

extension Provenance {
    var label: String {
        switch self {
        case .bundled: return "Sweepwise's built-in knowledge"
        case .learned: return "a rule you approved earlier"
        case .llm(let p): return "AI (\(p))"
        }
    }
}
