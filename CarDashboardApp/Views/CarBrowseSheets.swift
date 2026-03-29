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

// MARK: - Filtros (pantalla completa)

struct CarsFilterSheet: View {
    @Binding var filters: CarListFilters
    let sourceCars: [Car]
    let resultCount: Int
    var onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        filterHintBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 12)

                        FilterAccordionRow(title: "Tipo de coche", systemImage: "sparkles.car") {
                            multiPickSection(options: bodyOptions, selection: $filters.bodyTypes)
                        }

                        FilterAccordionRow(title: "Marca y modelo", systemImage: "car.side") {
                            multiPickSection(options: brandOptions, selection: $filters.brands)
                        }

                        FilterAccordionRow(title: "Precio", systemImage: "tag") {
                            priceSection
                        }

                        FilterAccordionRow(title: "Servicios online", systemImage: "cart") {
                            Toggle("Solo con servicios online", isOn: $filters.onlineServicesOnly)
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.vertical, 4)
                        }

                        FilterAccordionRow(title: "Ubicación", systemImage: "mappin.and.ellipse") {
                            multiPickSection(options: locationOptions, selection: $filters.locations)
                        }

                        FilterAccordionRow(title: "Vendedores", systemImage: "checkmark.shield") {
                            multiPickSection(options: sellerOptions, selection: $filters.sellerKinds)
                        }

                        FilterAccordionRow(title: "Año de fabricación", systemImage: "calendar") {
                            yearSection
                        }

                        FilterAccordionRow(title: "Kilometraje", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                            kmSection
                        }

                        FilterAccordionRow(title: "Motor / combustible", systemImage: "engine.combustion") {
                            multiPickSection(options: fuelOptions, selection: $filters.fuelTypes)
                            Toggle("Solo eléctricos e híbridos enchufables", isOn: $filters.electricOnly)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 10)
                        }

                        FilterAccordionRow(title: "Etiqueta DGT", systemImage: "leaf") {
                            multiPickSection(options: dgtOptions, selection: $filters.dgtLabels)
                        }

                        FilterAccordionRow(title: "Equipamiento", systemImage: "wrench.and.screwdriver") {
                            TextField("Palabras clave (GPS, techo, cuero…)", text: $filters.equipmentQuery)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 15, weight: .medium))
                        }

                        FilterAccordionRow(title: "Color", systemImage: "paintpalette") {
                            multiPickSection(options: colorOptions, selection: $filters.colors)
                        }
                    }
                    .padding(.bottom, 120)
                }

                footerBar
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Limpiar filtros") {
                        filters = CarListFilters()
                        onClear()
                    }
                    .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }

    private var filterHintBanner: some View {
        Text("Combina filtros para acotar el listado. El recuento se actualiza al cerrar esta pantalla.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.28))
            )
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                dismiss()
            } label: {
                Text("Mostrar \(formatIntES(resultCount))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.06, green: 0.09, blue: 0.22))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var brandOptions: [String] {
        uniqueSorted(sourceCars.map(\.brandForFilter).filter { !$0.isEmpty })
    }

    private var bodyOptions: [String] {
        uniqueSorted(sourceCars.compactMap(\.bodyType).filter { !$0.isEmpty })
    }

    private var fuelOptions: [String] {
        uniqueSorted(sourceCars.compactMap(\.fuelType).filter { !$0.isEmpty })
    }

    private var sellerOptions: [String] {
        uniqueSorted(sourceCars.compactMap(\.sellerKind).filter { !$0.isEmpty })
    }

    private var dgtOptions: [String] {
        uniqueSorted(sourceCars.compactMap(\.dgtLabel).filter { !$0.isEmpty })
    }

    private var colorOptions: [String] {
        uniqueSorted(sourceCars.map(\.colorForFilter).filter { !$0.isEmpty })
    }

    private var locationOptions: [String] {
        uniqueSorted(sourceCars.compactMap(\.locationText).filter { !$0.isEmpty })
    }

    private func uniqueSorted(_ arr: [String]) -> [String] {
        Array(Set(arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func multiPickSection(options: [String], selection: Binding<Set<String>>) -> some View {
        Group {
            if options.isEmpty {
                Text("No hay valores en los anuncios cargados. Añade columnas en la base de datos o más vehículos.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { opt in
                        Button {
                            if selection.wrappedValue.contains(opt) {
                                selection.wrappedValue.remove(opt)
                            } else {
                                selection.wrappedValue.insert(opt)
                            }
                        } label: {
                            HStack {
                                Text(opt)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selection.wrappedValue.contains(opt) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(selection.wrappedValue.contains(opt) ? Color.accentColor : Color.primary.opacity(0.28))
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mín. €")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("0", text: priceMinBinding)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Máx. €")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Sin límite", text: priceMaxBinding)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var priceMinBinding: Binding<String> {
        Binding(
            get: {
                if let v = filters.minPriceEUR { return String(format: "%.0f", v) }
                return ""
            },
            set: { newVal in
                var f = filters
                let cleaned = newVal.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
                f.minPriceEUR = cleaned.isEmpty ? nil : Double(cleaned)
                filters = f
            }
        )
    }

    private var priceMaxBinding: Binding<String> {
        Binding(
            get: {
                if let v = filters.maxPriceEUR { return String(format: "%.0f", v) }
                return ""
            },
            set: { newVal in
                var f = filters
                let cleaned = newVal.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
                f.maxPriceEUR = cleaned.isEmpty ? nil : Double(cleaned)
                filters = f
            }
        )
    }

    private var yearSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Desde")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Año", text: yearMinBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hasta")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Año", text: yearMaxBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var yearMinBinding: Binding<String> {
        Binding(
            get: { filters.minYear.map(String.init) ?? "" },
            set: { newVal in
                var f = filters
                let t = newVal.filter { $0.isNumber }
                f.minYear = t.isEmpty ? nil : Int(t)
                filters = f
            }
        )
    }

    private var yearMaxBinding: Binding<String> {
        Binding(
            get: { filters.maxYear.map(String.init) ?? "" },
            set: { newVal in
                var f = filters
                let t = newVal.filter { $0.isNumber }
                f.maxYear = t.isEmpty ? nil : Int(t)
                filters = f
            }
        )
    }

    private var kmSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mín. km")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("0", text: kmMinBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Máx. km")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Sin límite", text: kmMaxBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var kmMinBinding: Binding<String> {
        Binding(
            get: { filters.minKm.map(String.init) ?? "" },
            set: { newVal in
                var f = filters
                let t = newVal.filter { $0.isNumber }
                f.minKm = t.isEmpty ? nil : Int(t)
                filters = f
            }
        )
    }

    private var kmMaxBinding: Binding<String> {
        Binding(
            get: { filters.maxKm.map(String.init) ?? "" },
            set: { newVal in
                var f = filters
                let t = newVal.filter { $0.isNumber }
                f.maxKm = t.isEmpty ? nil : Int(t)
                filters = f
            }
        )
    }

    private func formatIntES(_ v: Int) -> String {
        v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }
}

// MARK: - Accordion fila

private struct FilterAccordionRow<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28)

                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Divider().padding(.leading, 16)
        }
    }
}
