import SwiftUI

/// Tarjetas tipo Revolut bajo las acciones rápidas: solo coches del listado que ya tienen imagen.
struct DashboardHomeNotificationsSection: View {
    let cars: [Car]

    private struct Template {
        let title: String
        let subtitlePrefix: String
        let actionTitle: String
    }

    private static let templates: [Template] = [
        Template(
            title: "Coche captado",
            subtitlePrefix: "Ya está en tu inventario:",
            actionTitle: "Ver detalles"
        ),
        Template(
            title: "Coche vendido",
            subtitlePrefix: "Operación cerrada:",
            actionTitle: "Gestionar"
        ),
        Template(
            title: "Listado actualizado",
            subtitlePrefix: "Visible para compradores:",
            actionTitle: "Ver anuncio"
        ),
    ]

    private var feedCars: [Car] {
        Array(cars.filter(\.hasImagePayload).prefix(Self.templates.count))
    }

    private struct Row: Identifiable {
        let id: UUID
        let template: Template
        let car: Car
    }

    private var rows: [Row] {
        zip(Self.templates, feedCars).map { tpl, car in
            Row(id: car.id, template: tpl, car: car)
        }
    }

    var body: some View {
        Group {
            if !rows.isEmpty {
                VStack(spacing: 14) {
                    ForEach(rows) { row in
                        DashboardHomeNotificationCard(
                            title: row.template.title,
                            subtitle: "\(row.template.subtitlePrefix) \(Self.carLine(row.car)).",
                            actionTitle: row.template.actionTitle,
                            car: row.car
                        )
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func carLine(_ car: Car) -> String {
        if let brand = car.brandName?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            return "\(brand) \(car.model)"
        }
        return car.name
    }
}

// MARK: - Tarjeta

private struct DashboardHomeNotificationCard: View {
    @EnvironmentObject private var auth: AuthViewModel

    let title: String
    let subtitle: String
    let actionTitle: String
    let car: Car

    private let corner: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CarThumbnailView(car: car, size: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: {}) {
                Text(actionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background {
            DashboardChromeCardBackground(cornerRadius: corner)
        }
    }
}

#Preview {
    ScrollView {
        DashboardHomeNotificationsSection(cars: MockData.cars)
            .environmentObject(AuthViewModel())
            .padding()
    }
    .background(Color.black)
}
