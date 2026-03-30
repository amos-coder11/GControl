import SwiftUI

struct CarsView: View {
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showSortSheet = false
    @State private var showFilterSheet = false
    @FocusState private var browseSearchFieldFocused: Bool

    private var displayedCars: [Car] {
        carsVM.displayedBrowseCars()
    }

    private var resultCountText: String {
        displayedCars.count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    private var browseContextEmpty: Bool {
        carsVM.browseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !carsVM.browseFilters.hasActiveFilters
    }

    private var carsEmptyFootnote: String {
        if carsVM.lastFetchHadZeroRowsFromBackend, browseContextEmpty {
            return "Prueba a limpiar filtros o cambiar la búsqueda.\n\nEl servidor devolvió 0 filas: en Supabase revisa RLS de «vehicles». Para el mismo catálogo en todas las cuentas, permite SELECT a «anon» y «authenticated». Ejemplo en el repo: supabase/migrations/20260330130000_vehicles_marketplace_read_all.sql"
        }
        return "Prueba a limpiar filtros o cambiar la búsqueda."
    }

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                stickyBrowseChrome

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        Text("\(resultCountText) resultados")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)

                        if carsVM.isLoadingVehicles && carsVM.cars.isEmpty {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 32)
                        }

                        if let err = carsVM.vehiclesError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }

                        if !carsVM.isLoadingVehicles || !carsVM.cars.isEmpty {
                            if displayedCars.isEmpty {
                                ContentUnavailableView(
                                    "Sin resultados",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text(carsEmptyFootnote)
                                )
                                .foregroundStyle(.white)
                                .symbolRenderingMode(.hierarchical)
                                .tint(.white.opacity(0.85))
                                .padding(.vertical, 24)
                                .padding(.horizontal, 16)
                            } else {
                                LazyVStack(spacing: 14) {
                                    ForEach(Array(displayedCars.enumerated()), id: \.element.id) { idx, car in
                                        CarListingCard(
                                            car: car,
                                            isSelected: carsVM.isSelected(car)
                                        ) {
                                            carsVM.selectCar(car)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .onAppear {
                                            // Prefetch: precarga imágenes de coches cercanos al viewport
                                            CarUIImageLoader.prefetch(
                                                cars: displayedCars,
                                                around: idx,
                                                auth: auth,
                                                window: 4
                                            )
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            if carsVM.isLoadingMoreVehicles {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white.opacity(0.7))
                                    Text("Cargando más vehículos…")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.vertical, 12)
                            }
                        }

                        addCarButton
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 28)
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .refreshable {
                    await carsVM.loadVehicles()
                }
            }
            .frame(maxWidth: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    LiquidGlassKeyboardAccessoryBar {
                        browseSearchFieldFocused = false
                    }
                }
            }
            .sheet(isPresented: $showSortSheet) {
                CarsSortSheet(sort: $carsVM.browseSort)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFilterSheet) {
                CarsFilterSheet(
                    filters: $carsVM.browseFilters,
                    sourceCars: carsVM.cars,
                    resultCount: carsVM.displayedBrowseCars().count,
                    onClear: {}
                )
            }
            .task {
                if carsVM.cars.isEmpty && !carsVM.isLoadingVehicles {
                    await carsVM.loadVehicles()
                }
            }
        }
    }

    private var stickyBrowseChrome: some View {
        CarsBrowseHeaderBar(
            initials: auth.userInitials,
            profileImage: auth.profileAvatarImage,
            searchText: $carsVM.browseSearchText,
            hasActiveFilters: carsVM.browseFilters.hasActiveFilters,
            searchFieldFocused: $browseSearchFieldFocused,
            onSort: { showSortSheet = true },
            onFilter: { showFilterSheet = true }
        )
        .appChromeHeaderOuterPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addCarButton: some View {
        GlassCard(cornerRadius: 20, padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Añadir vehículo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Conecta un nuevo coche")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

#Preview {
    NavigationStack {
        CarsView()
            .environmentObject(CarsViewModel())
            .environmentObject(AuthViewModel())
    }
}

