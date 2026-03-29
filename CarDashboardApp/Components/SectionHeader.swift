import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    /// Texto claro sobre fondo Revolut / oscuro.
    var lightOnDark: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(lightOnDark ? Color.white : Color.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(lightOnDark ? Color.white.opacity(0.55) : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        SectionHeader(title: "Dashboard", subtitle: "Datos en tiempo real")
            .padding()
    }
}
