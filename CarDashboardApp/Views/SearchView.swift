import SwiftUI

/// Pestaña Buscador: mismo criterio que Coches (`browseSearchText`, filtros y orden).
struct SearchView: View {
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
                                        description: Text(
                                            carsVM.browseSearchText.isEmpty
                                                ? "Escribe en el buscador o ajusta filtros."
                                                : "Prueba con otro término o limpia filtros."
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                                    .tint(.white.opacity(0.85))
                                    .padding(.vertical, 24)
                                    .padding(.horizontal, 16)
                                } else {
                                    VStack(spacing: 20) {
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
}

#Preview {
    SearchView()
        .environmentObject(CarsViewModel())
        .environmentObject(AuthViewModel())
}
