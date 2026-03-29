import SwiftUI

struct CarsView: View {
    @EnvironmentObject var carsVM: CarsViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Header
                SectionHeader(
                    title: "Mis Coches",
                    subtitle: "\(carsVM.cars.count) vehículos registrados"
                )

                // Active car highlight
                if let activeCar = carsVM.selectedCar {
                    activeCarCard(activeCar)
                }

                // Car list
                VStack(spacing: 12) {
                    ForEach(carsVM.cars) { car in
                        CarRow(
                            car: car,
                            isSelected: carsVM.isSelected(car)
                        ) {
                            carsVM.selectCar(car)
                        }
                    }
                }

                // Add car button
                addCarButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Active Car Card
    private func activeCarCard(_ car: Car) -> some View {
        GlassCard(cornerRadius: 26, padding: 20) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vehículo activo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .textCase(.uppercase)
                            .tracking(1.2)

                        Text(car.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(.cyan.opacity(0.15))
                            .frame(width: 60, height: 60)

                        Image(systemName: car.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                }

                Divider()
                    .overlay(Color.primary.opacity(0.12))

                HStack(spacing: 20) {
                    infoChip(icon: "car.fill", label: car.model)
                    infoChip(icon: "calendar", label: String(car.year))
                    infoChip(icon: "rectangle.fill", label: car.plate)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.cyan.opacity(0.2), lineWidth: 1)
        }
    }

    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Add Car Button
    private var addCarButton: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Añadir vehículo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))

                    Text("Conecta un nuevo coche")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        CarsView()
            .environmentObject(CarsViewModel())
    }
}
