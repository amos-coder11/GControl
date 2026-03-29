import Foundation
import SwiftUI

enum CarStatus: String, CaseIterable {
    case connected = "Conectado"
    case disconnected = "Desconectado"
    case standby = "En espera"

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .red
        case .standby: return .orange
        }
    }

    var icon: String {
        switch self {
        case .connected: return "wifi"
        case .disconnected: return "wifi.slash"
        case .standby: return "moon.fill"
        }
    }
}
