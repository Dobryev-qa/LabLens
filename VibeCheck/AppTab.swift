import SwiftUI

enum AppTab: Int, CaseIterable {
    case history = 0
    case scan = 1
    case profile = 2

    var title: String {
        switch self {
        case .history: return "History"
        case .scan: return "Scan"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .history: return "clock.fill"
        case .scan: return "waveform.path.ecg"
        case .profile: return "person.fill"
        }
    }
}
