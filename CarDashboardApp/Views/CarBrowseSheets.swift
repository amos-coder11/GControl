import SwiftUI

// MARK: - Ordenar (bottom sheet)

struct CarsSortSheet: View {
    @Binding var sort: CarSortOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ordenar anuncios")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text("Se ordenan automáticamente al seleccionar una opción")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CarSortOption.allCases) { option in
                        Button {
                            sort = option
                            dismiss()
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: sort == option ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(sort == option ? .primary : .tertiary)

                                Text(option.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option != CarSortOption.allCases.last {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }
}
