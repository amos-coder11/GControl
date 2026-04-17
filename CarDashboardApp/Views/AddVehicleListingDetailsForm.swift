import SwiftUI

/// Estado extra del alta (stock, fiscalidad, dueño, portales) — se serializa en `listing_extra` + columnas escalares.
struct AddVehicleListingExtendedState {
    var acquisitionCategory: String = "compras"
    var purchasePriceText: String = ""
    var marketPriceText: String = ""
    /// `yes` · `no` · `half` (50 %)
    var vatDeductible: String = "no"
    var singleOwner: Bool = true
    var serviceBook: Bool = true
    var officialServiceBook: Bool = true
    var nationalVehicle: Bool = true
    var dgtLabelText: String = ""
    var colorText: String = ""
    var lastServiceKmText: String = ""
    var lastServiceYearText: String = ""
    var vinText: String = ""
    var storeLocationText: String = ""
    var ownerNameText: String = ""
    var ownerPhoneText: String = ""
    var ownerEmailText: String = ""
    var ownerZoneText: String = ""
    var ownerCanVisitOffice: Bool = true
    var listingDescriptionText: String = ""
    var publishAll: Bool = true
    var publishAutoScout: Bool = true
    var publishCochesNet: Bool = true
    var publishWallapop: Bool = true
    var publishWeb: Bool = true
}

/// Formulario alineado con el flujo Dealcar / stock interno (capturas de referencia).
struct AddVehicleListingDetailsForm: View {
    @Binding var xf: AddVehicleListingExtendedState
    @Binding var equipmentCodes: Set<String>
    @Binding var salePriceText: String
    /// Hechos actuales del alta (marca, modelo, toggles, etc.) para enviar al modelo.
    let listingFactsSnapshot: () -> String
    @Binding var formErrorMessage: String?

    @State private var isGeneratingListingDescription = false

    private let acquisitionOptions: [(id: String, title: String, icon: String)] = [
        ("compras", "Compras", "cart.fill"),
        ("gv_con", "GV CON", "doc.text.fill"),
        ("gv_sin", "GV SIN", "doc.plaintext.fill"),
        ("gv_fotos", "GV FOTOS", "photo.on.rectangle.angled"),
        ("empenos", "Empeños", "hand.raised.fill"),
        ("alquilados", "Alquilados", "key.fill"),
    ]

    static let equipmentList: [(code: String, title: String)] = [
        ("nav", "Navegador"), ("leather", "Asientos de cuero"), ("sunroof", "Techo solar"),
        ("cam360", "Cámara 360"), ("led", "Faros LED"), ("bluetooth", "Bluetooth"),
        ("cruise", "Control de crucero"), ("parking", "Sensores aparcamiento"),
        ("accruise", "Crucero adaptativo"), ("climate2", "Climatizador bizona"),
        ("carplay", "CarPlay / Android Auto"), ("climate3", "Climatizador trizona"),
        ("alloy", "Llantas aleación"), ("keyless", "Keyless / arranque"),
        ("heated_seats", "Asientos calefactables"), ("vent_seats", "Asientos ventilados"),
        ("heated_wheel", "Volante calefactable"), ("premium_sound", "Sonido premium"),
        ("tailgate", "Portón eléctrico"), ("hud", "Head-Up Display"),
        ("fold_mirrors", "Retrovisores eléctricos"), ("lane", "Asistente de carril"),
        ("aeb", "Frenada emergencia"), ("limiter", "Limitador velocidad"),
        ("blind", "Ángulo muerto"), ("hill", "Control de descensos"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            formSectionTitle("Origen del vehículo")
            acquisitionGrid

            formSectionTitle("Precios (€)")
            fieldLabel("Precio de compra *")
            darkField(TextField("", text: $xf.purchasePriceText, prompt: Text("Ej: 18.500").foregroundStyle(.white.opacity(0.5))))
            fieldLabel("Precio de mercado (opcional)")
            darkField(TextField("", text: $xf.marketPriceText, prompt: Text("Opcional").foregroundStyle(.white.opacity(0.5))))
            fieldLabel("Precio de venta *")
            darkField(TextField("", text: $salePriceText, prompt: Text("PVP al contado").foregroundStyle(.white.opacity(0.5))))
            financedHint
            fieldLabel("IVA deducible")
            vatRow

            formSectionTitle("Historial y datos")
            toggleRow(title: "Único propietario", on: $xf.singleOwner)
            toggleRow(title: "Libro de revisiones", on: $xf.serviceBook)
            toggleRow(title: "Libro en casa oficial", on: $xf.officialServiceBook)
            HStack(spacing: 10) {
                originChip(title: "Nacional", selected: xf.nationalVehicle) { xf.nationalVehicle = true }
                originChip(title: "Importado", selected: !xf.nationalVehicle) { xf.nationalVehicle = false }
            }

            fieldLabel("Etiqueta ambiental (DGT)")
            darkField(TextField("", text: $xf.dgtLabelText, prompt: Text("Vacío = sin pastilla · 0 emisiones, C o B (ECO no se muestra en tarjeta)").foregroundStyle(.white.opacity(0.5))))
            fieldLabel("Color *")
            darkField(TextField("", text: $xf.colorText, prompt: Text("Ej: Negro").foregroundStyle(.white.opacity(0.5))))
            fieldLabel("Última revisión (km) opcional")
            darkField(TextField("", text: $xf.lastServiceKmText, prompt: Text("Ej: 85.000").foregroundStyle(.white.opacity(0.5)))
                .keyboardType(.numberPad))
            fieldLabel("Última revisión (año) opcional")
            darkField(TextField("", text: $xf.lastServiceYearText, prompt: Text("Ej: 2023").foregroundStyle(.white.opacity(0.5)))
                .keyboardType(.numberPad))

            formSectionTitle("Identificación extendida")
            fieldLabel("Nº bastidor (VIN) opcional")
            darkField(TextField("", text: $xf.vinText, prompt: Text("Ej: WBA…").foregroundStyle(.white.opacity(0.5))))
            fieldLabel("Ubicación / tienda")
            darkField(TextField("", text: $xf.storeLocationText, prompt: Text("Ej: Las Rozas, Pinto…").foregroundStyle(.white.opacity(0.5))))

            formSectionTitle("Equipamiento destacado (opcional)")
            equipmentGrid

            formSectionTitle("Datos del dueño (uso interno)")
            fieldLabel("Nombre del dueño")
            darkField(TextField("", text: $xf.ownerNameText, prompt: Text("Ej: Juan Pérez").foregroundStyle(.white.opacity(0.5))))
            fieldLabel("Teléfono")
            darkField(TextField("", text: $xf.ownerPhoneText, prompt: Text("Ej: 600 123 456").foregroundStyle(.white.opacity(0.5)))
                .keyboardType(.phonePad))
            fieldLabel("Email opcional")
            darkField(TextField("", text: $xf.ownerEmailText, prompt: Text("Opcional").foregroundStyle(.white.opacity(0.5)))
                .keyboardType(.emailAddress))
            fieldLabel("Zona España opcional")
            darkField(TextField("", text: $xf.ownerZoneText, prompt: Text("Ej: Madrid").foregroundStyle(.white.opacity(0.5))))
            toggleRow(title: "Puede desplazarse a oficinas", on: $xf.ownerCanVisitOffice)

            HStack(alignment: .firstTextBaseline) {
                formSectionTitle("Descripción del anuncio")
                Spacer(minLength: 8)
                Button {
                    Task { await generateListingDescriptionWithAI() }
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingListingDescription {
                            ProgressView()
                                .scaleEffect(0.78)
                                .tint(PremiumAccent.ice)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("Generar con IA")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(PremiumAccent.ice.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule(style: .continuous)
                            .strokeBorder(PremiumAccent.ice.opacity(0.45), lineWidth: 1)
                            .background {
                                Capsule(style: .continuous).fill(Color.white.opacity(0.06))
                            }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingListingDescription || !OpenAIChatClient.isConfigured)
                .opacity(OpenAIChatClient.isConfigured ? 1 : 0.42)
            }

            Text("Genera un borrador con los datos del formulario y la foto (si ya rellenaste con IA) o escribe a mano.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if !OpenAIChatClient.isConfigured {
                Text("Configura OPENAI_API_KEY en DeveloperSettings.local.xcconfig para usar «Generar con IA».")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            }

            ZStack(alignment: .topLeading) {
                if xf.listingDescriptionText.isEmpty {
                    Text("Describe el vehículo (visible en el anuncio) o pulsa «Generar con IA»…")
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }
                TextEditor(text: $xf.listingDescriptionText)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .medium))
                    .frame(minHeight: 120)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background {
                LiquidGlassFormFieldBackground(cornerRadius: 16)
            }

            formSectionTitle("Publicación en portales")
            toggleRow(title: "Publicar en todas las plataformas", on: $xf.publishAll)
            if !xf.publishAll {
                toggleRow(title: "AutoScout24", on: $xf.publishAutoScout)
                toggleRow(title: "Coches.net", on: $xf.publishCochesNet)
                toggleRow(title: "Wallapop", on: $xf.publishWallapop)
                toggleRow(title: "Web propia", on: $xf.publishWeb)
            }

            Text("Wallapop / Coches.net y otros dependen de integraciones activas en tu cuenta. Los datos se guardan en Supabase para uso interno y exportaciones.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 4)
        }
    }

    private var acquisitionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(acquisitionOptions, id: \.id) { opt in
                Button {
                    xf.acquisitionCategory = opt.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: opt.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(opt.title)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(xf.acquisitionCategory == opt.id ? .white : .white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(xf.acquisitionCategory == opt.id
                                  ? PremiumAccent.tabActive.opacity(0.95)
                                  : Color.white.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(xf.acquisitionCategory == opt.id ? 0.35 : 0.14), lineWidth: 0.75)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var vatRow: some View {
        HStack(spacing: 10) {
            vatChip("Sí", id: "yes")
            vatChip("No", id: "no")
            vatChip("50%", id: "half")
        }
    }

    private func vatChip(_ title: String, id: String) -> some View {
        Button {
            xf.vatDeductible = id
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white.opacity(0.92))
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(xf.vatDeductible == id ? PremiumAccent.ice.opacity(0.35) : Color.white.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.65)
                }
        }
        .buttonStyle(.plain)
    }

    private var financedHint: some View {
        Group {
            if let sale = Self.parseEUR(salePriceText), sale > 0 {
                let approx = (sale * 0.9).rounded()
                Text("Precio financiado orientativo: \(Self.formatIntES(Int(approx))) € (10 % menos que al contado)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PremiumAccent.ice.opacity(0.88))
                    .padding(.top, 2)
            }
        }
    }

    private var equipmentGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Self.equipmentList, id: \.code) { item in
                let on = equipmentCodes.contains(item.code)
                Button {
                    if on { equipmentCodes.remove(item.code) } else { equipmentCodes.insert(item.code) }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(on ? PremiumAccent.ice : .white.opacity(0.4))
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(on ? 0.1 : 0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.65)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formSectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, 6)
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(.white.opacity(0.62))
    }

    private func darkField(_ content: some View) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background { LiquidGlassFormFieldBackground() }
    }

    private func toggleRow(title: String, on: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Toggle("", isOn: on)
                .labelsHidden()
                .tint(PremiumAccent.tabActive)
        }
        .padding(.vertical, 4)
    }

    private func originChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? PremiumAccent.tabActive.opacity(0.85) : Color.white.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.65)
                }
        }
        .buttonStyle(.plain)
    }

    private static func parseEUR(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let v = Double(t.replacingOccurrences(of: ",", with: ".")) { return v }
        let filtered = t.filter { $0.isNumber || $0 == "." || $0 == "," }
        return Double(String(filtered).replacingOccurrences(of: ",", with: "."))
    }

    private static func formatIntES(_ v: Int) -> String {
        v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    @MainActor
    private func generateListingDescriptionWithAI() async {
        guard OpenAIChatClient.isConfigured else {
            formErrorMessage = "Falta OPENAI_API_KEY en la configuración local."
            return
        }
        formErrorMessage = nil
        isGeneratingListingDescription = true
        defer { isGeneratingListingDescription = false }

        let facts = listingFactsSnapshot()
        do {
            let text = try await OpenAIChatClient.generateVehicleListingDescription(factsBlock: facts)
            xf.listingDescriptionText = text
        } catch {
            formErrorMessage = error.localizedDescription
        }
    }
}
