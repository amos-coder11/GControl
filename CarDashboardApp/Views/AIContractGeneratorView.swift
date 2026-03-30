import PDFKit
import SwiftUI
import UIKit

enum AIContractState {
    case typeSelection
    case form
    case generating
    case result
}

struct AIContractGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentState: AIContractState = .typeSelection
    @State private var selectedDocumentKind: AIContractDocumentKind = .venta
    
    // Client Details
    @State private var clientName = ""
    @State private var clientID = ""
    @State private var clientAddress = ""
    
    // Vehicle Details
    @State private var vehicleBrand = ""
    @State private var vehicleModel = ""
    @State private var price = ""
    
    @State private var isAnimatingAI = false
    @State private var generatedContractText = ""
    @State private var contractPDFData: Data?
    @State private var generationErrorMessage: String?
    @State private var showGenerationError = false
    @State private var showPDFPreview = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var pdfActionErrorMessage: String?
    @State private var showPDFActionError = false
    
    @FocusState private var focusedField: String?

    private var pricePlaceholder: String {
        switch selectedDocumentKind {
        case .venta: return "Precio de venta (€)"
        case .compra: return "Precio de compra al particular (€)"
        case .gv: return "Importe referencia / operación (€)"
        }
    }
    
    var body: some View {
        ZStack {
            // Background pitch black for OLED
            Color.black.ignoresSafeArea()
            
            // Subtle Top Ambient Glow
            GeometryReader { proxy in
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: proxy.size.width)
                    .blur(radius: 80)
                    .offset(y: -proxy.size.width / 2)
            }
            .ignoresSafeArea()
                
            VStack(spacing: 0) {
                customTopBar
                
                switch currentState {
                case .typeSelection:
                    typeSelectionView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .form:
                    formView
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .generating:
                    generatingView
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                case .result:
                    resultView
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("No se pudo generar el contrato", isPresented: $showGenerationError, actions: {
            Button("Entendido", role: .cancel) {}
        }, message: {
            Text(generationErrorMessage ?? "Error desconocido.")
        })
        .alert("PDF", isPresented: $showPDFActionError, actions: {
            Button("Entendido", role: .cancel) {}
        }, message: {
            Text(pdfActionErrorMessage ?? "No se pudo preparar el PDF.")
        })
        .sheet(isPresented: $showPDFPreview) {
            Group {
                if let data = contractPDFData {
                    NavigationStack {
                        ContractPDFKitView(data: data)
                            .ignoresSafeArea(edges: .bottom)
                            .navigationTitle("Vista previa")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cerrar") { showPDFPreview = false }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Compartir") {
                                        showPDFPreview = false
                                        presentShareForCurrentPDF()
                                    }
                                }
                            }
                    }
                } else {
                    ProgressView("Preparando PDF…")
                        .padding()
                        .onAppear { refreshContractPDFDataIfNeeded() }
                }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            shareURL = nil
        }) {
            if let url = shareURL {
                ContractShareSheet(activityItems: [url])
            }
        }
    }
    
    // MARK: - Navigation Bar
    private var customTopBar: some View {
        HStack {
            Spacer()
            
            Text("Contrato Inteligente")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Type Selection View
    private var typeSelectionView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 70, height: 70)
                        .blur(radius: 20)
                        .opacity(0.6)
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 8)
                
                Text("¿Qué deseas redactar?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Selecciona el tipo de contrato para cargar las cláusulas legales correspondientes.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            
            VStack(spacing: 16) {
                ForEach(AIContractDocumentKind.allCases) { kind in
                    contractTypeButton(
                        title: kind.title,
                        description: kind.shortHint,
                        icon: iconForDocumentKind(kind),
                        kind: kind
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            Spacer()
        }
    }
    
    private func iconForDocumentKind(_ kind: AIContractDocumentKind) -> String {
        switch kind {
        case .venta: return "car.side.front.open.fill"
        case .compra: return "arrow.down.circle.fill"
        case .gv: return "shield.checkered"
        }
    }

    private func contractTypeButton(title: String, description: String, icon: String, kind: AIContractDocumentKind) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                selectedDocumentKind = kind
                currentState = .form
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.cyan)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(20)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Form View
    private var formView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Intro Hero
                VStack(spacing: 12) {
                    ZStack {
                        // Icon Glow
                        Circle()
                            .fill(LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                            .blur(radius: 20)
                            .opacity(0.6)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, .cyan.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            )
                    }
                    .padding(.bottom, 8)
                    
                    Text("Asistente Legal IA")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Redacta un contrato perfecto y sin errores al instante introduciendo los datos clave.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .lineSpacing(4)
                }
                .padding(.top, 24)

                HStack {
                    Text(selectedDocumentKind.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            currentState = .typeSelection
                        }
                    } label: {
                        Text("Cambiar tipo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 22)
                
                VStack(spacing: 28) {
                    // Client Section
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "Datos del Cliente", icon: "person.fill")
                        
                        VStack(spacing: 12) {
                            customTextField(placeholder: "Nombre completo", text: $clientName, id: "name")
                            customTextField(placeholder: "DNI / NIE / NIF", text: $clientID, id: "dni")
                            customTextField(placeholder: "Dirección completa", text: $clientAddress, id: "address")
                        }
                    }
                    
                    // Operation Section
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "Datos de la Operación", icon: "car.fill")
                        
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                customTextField(placeholder: "Marca", text: $vehicleBrand, id: "brand")
                                customTextField(placeholder: "Modelo", text: $vehicleModel, id: "model")
                            }
                            customTextField(placeholder: pricePlaceholder, text: $price, id: "price")
                                .keyboardType(.decimalPad)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Generate Button
                Button {
                    startAIGeneration()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 18, weight: .bold))
                        Text("Generar Contrato Inteligente")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [.indigo, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .cyan.opacity(0.3), radius: 20, x: 0, y: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: - Generating View
    private var generatingView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            ZStack {
                // Background aura
                Circle()
                    .fill(Color.indigo.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)
                    .scaleEffect(isAnimatingAI ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimatingAI)
                
                // Outer rotating dashed ring
                Circle()
                    .stroke(
                        LinearGradient(colors: [.cyan, .clear, .indigo, .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, dash: [40, 15, 10, 15])
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(Angle(degrees: isAnimatingAI ? 360 : 0))
                    .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: isAnimatingAI)
                
                // Inner rotating solid ring
                Circle()
                    .stroke(
                        LinearGradient(colors: [.purple.opacity(0.8), .cyan.opacity(0.8)], startPoint: .bottom, endPoint: .top),
                        lineWidth: 2
                    )
                    .frame(width: 90, height: 90)
                    .rotationEffect(Angle(degrees: isAnimatingAI ? -360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: isAnimatingAI)
                
                Image(systemName: "cpu.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, value: isAnimatingAI)
            }
            
            VStack(spacing: 12) {
                Text("Redactando contrato")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Analizando marco legal, aplicando normativas\ny personalizando cláusulas.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimatingAI = true
        }
        .onDisappear {
            isAnimatingAI = false
        }
    }
    
    // MARK: - Result View
    private var resultView: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(
                                LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .font(.system(size: 24))
                        Text("Contrato Generado")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 8)
                    
                    Text(generatedContractText)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(8)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding()
            }
            
            // Actions
            VStack(spacing: 16) {
                Button {
                    refreshContractPDFDataIfNeeded()
                    showPDFPreview = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Ver PDF")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(white: 0.14))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                
                Button {
                    presentShareForCurrentPDF()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Exportar PDF")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        contractPDFData = nil
                        generatedContractText = ""
                        currentState = .typeSelection
                    }
                } label: {
                    Text("Crear otro contrato")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .background(
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .bottom, endPoint: .top)
                    .frame(height: 140)
                    .offset(y: -40)
                    .allowsHitTesting(false)
            )
        }
    }
    
    // MARK: - Helper Components
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .padding(.leading, 4)
    }
    
    private func customTextField(placeholder: String, text: Binding<String>, id: String) -> some View {
        let isFocused = focusedField == id
        
        return TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
            .focused($focusedField, equals: id)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .font(.system(size: 16, weight: .medium))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isFocused ? Color.cyan.opacity(0.6) : Color.white.opacity(0.06), lineWidth: isFocused ? 1.5 : 1)
            )
            .autocorrectionDisabled()
            .shadow(color: isFocused ? .cyan.opacity(0.15) : .clear, radius: 10, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
    
    // MARK: - Logic
    
    private func refreshContractPDFDataIfNeeded() {
        guard !generatedContractText.isEmpty else { return }
        if contractPDFData == nil {
            contractPDFData = ContractPDFExporter.makePDFData(
                body: generatedContractText,
                documentSubtitle: selectedDocumentKind.title
            )
        }
    }
    
    private func presentShareForCurrentPDF() {
        refreshContractPDFDataIfNeeded()
        guard let data = contractPDFData else {
            pdfActionErrorMessage = "No hay datos de PDF para compartir."
            showPDFActionError = true
            return
        }
        do {
            shareURL = try ContractPDFExporter.writeTemporaryPDF(data: data)
            showShareSheet = true
        } catch {
            pdfActionErrorMessage = error.localizedDescription
            showPDFActionError = true
        }
    }
    
    private func startAIGeneration() {
        focusedField = nil
        generationErrorMessage = nil

        guard AnthropicContractClient.isConfigured else {
            generationErrorMessage = AnthropicContractClient.ClientError.missingAPIKey.localizedDescription
            showGenerationError = true
            return
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            currentState = .generating
        }

        let name = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = clientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = vehicleBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let priceStr = price.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let text = try await AnthropicContractClient.generateContract(
                    kind: selectedDocumentKind,
                    clientName: name.isEmpty ? "[completar nombre]" : name,
                    clientID: id.isEmpty ? "[completar DNI/NIE/NIF]" : id,
                    clientAddress: addr.isEmpty ? "[completar dirección]" : addr,
                    vehicleBrand: brand.isEmpty ? "[completar marca]" : brand,
                    vehicleModel: model.isEmpty ? "[completar modelo]" : model,
                    priceEUR: priceStr.isEmpty ? "[completar precio]" : priceStr
                )
                await MainActor.run {
                    generatedContractText = text
                    contractPDFData = ContractPDFExporter.makePDFData(
                        body: text,
                        documentSubtitle: selectedDocumentKind.title
                    )
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        currentState = .result
                    }
                }
            } catch {
                await MainActor.run {
                    generationErrorMessage = error.localizedDescription
                    showGenerationError = true
                    withAnimation(.easeInOut(duration: 0.35)) {
                        currentState = .form
                    }
                }
            }
        }
    }
}

// MARK: - PDF vista previa y compartir (mismo archivo = siempre incluido en el target)

private struct ContractPDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(white: 0.12, alpha: 1)
        if let doc = PDFDocument(data: data) {
            v.document = doc
        }
        return v
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(data: data)
    }
}

private struct ContractShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        configurePopover(for: controller)
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        configurePopover(for: controller)
    }

    private func configurePopover(for controller: UIActivityViewController) {
        guard let popover = controller.popoverPresentationController else { return }
        let source = controller.view ?? UIView()
        popover.sourceView = source
        let b = source.bounds
        popover.sourceRect = b.isEmpty
            ? CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 1, height: 1)
            : CGRect(x: b.midX, y: b.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
    }
}

#Preview {
    AIContractGeneratorView()
}
