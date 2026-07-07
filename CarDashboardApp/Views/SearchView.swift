import SwiftUI

/// Pestaña Buscador: mismo criterio que Coches (`browseSearchText` y orden).
struct SearchView: View {
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showSortSheet = false
    @FocusState private var browseSearchFieldFocused: Bool

    private var displayedCars: [Car] {
        carsVM.displayedBrowseCars()
    }

    private var resultCountText: String {
        displayedCars.count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    private var searchEmptyFootnote: String {
        let qEmpty = carsVM.browseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if qEmpty, carsVM.lastFetchHadZeroRowsFromBackend {
            return "Si esperabas anuncios aquí también, el listado llega vacío desde Supabase (tabla «vehicles» / RLS). Escribe para buscar."
        }
        return carsVM.browseSearchText.isEmpty
            ? "Escribe en el buscador."
            : "Prueba con otro término."
    }

    var body: some View {
        NavigationStack {
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

                            if !carsVM.isLoadingVehicles || !carsVM.cars.isEmpty {
                                if displayedCars.isEmpty {
                                    ContentUnavailableView(
                                        "Sin resultados",
                                        systemImage: "magnifyingglass",
                                        description: Text(searchEmptyFootnote)
                                    )
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                                    .tint(.white.opacity(0.85))
                                    .padding(.vertical, 24)
                                    .padding(.horizontal, 16)
                                } else {
                                    // Lista perezosa: solo renderiza las tarjetas visibles (scroll fluido
                                    // aunque haya cientos de coches).
                                    LazyVStack(spacing: 20) {
                                        ForEach(displayedCars) { car in
                                            CarListingCard(
                                                car: car,
                                                isSelected: carsVM.isSelected(car)
                                            ) {
                                                carsVM.selectCar(car)
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.bottom, 28)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    .refreshable {
                        await carsVM.loadVehicles(companyId: auth.companyId)
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
            }
        }
    }

    private var stickyBrowseChrome: some View {
        CarsBrowseHeaderBar(
            initials: auth.userInitials,
            profileImage: auth.profileAvatarImage,
            searchText: $carsVM.browseSearchText,
            searchFieldFocused: $browseSearchFieldFocused,
            onSort: { showSortSheet = true }
        )
        .appChromeHeaderOuterPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SearchView()
        .environmentObject(CarsViewModel())
        .environmentObject(AuthViewModel())
        .environmentObject(MainTabRouter())
}
