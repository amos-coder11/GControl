import SwiftUI
import UIKit

/// Coches / Buscador: misma fila que Inicio (avatar + pastilla + ordenar).
struct CarsBrowseHeaderBar: View {
    let initials: String
    var profileImage: UIImage? = nil
    @Binding var searchText: String
    @FocusState.Binding var searchFieldFocused: Bool
    var onSort: () -> Void

    var body: some View {
        AppChromeHeaderRow(
            initials: initials,
            profileImage: profileImage,
            searchText: $searchText,
            prompt: Text("¿Qué estás buscando?")
                .foregroundStyle(.white),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFieldFocused
        ) {
            AppChromeHeaderCircleIconButton(
                systemName: "arrow.up.arrow.down",
                accessibilityLabel: "Ordenar",
                action: onSort
            )
        }
    }
}

private struct CarsBrowseHeaderBarPreviewHost: View {
    @FocusState private var focused: Bool
    var body: some View {
        CarsBrowseHeaderBar(
            initials: "J",
            searchText: .constant(""),
            searchFieldFocused: $focused,
            onSort: {}
        )
        .padding()
        .background(Color.black)
    }
}

#Preview {
    CarsBrowseHeaderBarPreviewHost()
}
