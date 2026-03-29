import SwiftUI

/// Coches / Buscador: misma fila que Inicio (avatar + pastilla + 2 círculos). Ordenar + filtros sustituyen a gráfico/campana con el **mismo** ancho útil para el buscador.
struct CarsBrowseHeaderBar: View {
    let initials: String
    @Binding var searchText: String
    var hasActiveFilters: Bool
    @FocusState.Binding var searchFieldFocused: Bool
    var onSort: () -> Void
    var onFilter: () -> Void

    var body: some View {
        AppChromeHeaderRow(
            initials: initials,
            searchText: $searchText,
            prompt: Text("¿Qué estás buscando?")
                .foregroundStyle(.white),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFieldFocused
        ) {
            HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                AppChromeHeaderCircleIconButton(
                    systemName: "arrow.up.arrow.down",
                    accessibilityLabel: "Ordenar",
                    action: onSort
                )

                ZStack(alignment: .topTrailing) {
                    AppChromeHeaderCircleIconButton(
                        systemName: "slider.horizontal.3",
                        accessibilityLabel: "Filtros",
                        action: onFilter
                    )
                    if hasActiveFilters {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                    }
                }
            }
        }
    }
}

private struct CarsBrowseHeaderBarPreviewHost: View {
    @FocusState private var focused: Bool
    var body: some View {
        CarsBrowseHeaderBar(
            initials: "J",
            searchText: .constant(""),
            hasActiveFilters: true,
            searchFieldFocused: $focused,
            onSort: {},
            onFilter: {}
        )
        .padding()
        .background(Color.black)
    }
}

#Preview {
    CarsBrowseHeaderBarPreviewHost()
}
