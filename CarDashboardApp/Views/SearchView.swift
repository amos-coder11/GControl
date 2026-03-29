import SwiftUI

/// Buscador global (vehículos del concesionario).
struct SearchView: View {
    @EnvironmentObject var carsVM: CarsViewModel
    @Environment(\.dismiss) private var dismiss

    @Binding var query: String
    /// En pestaña con `role: .search`, el texto lo gestiona `.searchable` del `TabView`.
    var embeddedInTabView: Bool = false

    init(query: Binding<String>, embeddedInTabView: Bool = false) {
        _query = query
        self.embeddedInTabView = embeddedInTabView
    }

    private var filteredCars: [Car] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return carsVM.cars }
        return carsVM.cars.filter {
            $0.name.lowercased().contains(q)
                || $0.model.lowercased().contains(q)
                || $0.plate.lowercased().contains(q)
                || String($0.year).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !embeddedInTabView {
                    searchField
                }

                if filteredCars.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "magnifyingglass",
                        description: Text(query.isEmpty ? "Escribe matrícula, modelo o nombre." : "Prueba con otro término.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(filteredCars) { car in
                                CarRow(
                                    car: car,
                                    isSelected: carsVM.isSelected(car)
                                ) {
                                    carsVM.selectCar(car)
                                    dismiss()
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Buscador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embeddedInTabView {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PremiumAccent.ice)

            TextField("Buscar coches…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.7),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.65)
                }
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}

#Preview {
    SearchView(query: .constant(""), embeddedInTabView: true)
        .environmentObject(CarsViewModel())
        .environmentObject(AuthViewModel())
}
