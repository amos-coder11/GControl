import PhotosUI
import SwiftUI

struct GrooSmileStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var mode: StudioMode = .aiSmile
    @State private var sourceImage: UIImage?
    @State private var resultImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var comparePosition: CGFloat = 0.5
    @State private var designOptions = GeminiSmileClient.SmileDesignOptions()
    @State private var dentalParams = GrooDentalArchParams()
    @State private var showShareSheet = false
    @State private var showSendToChat = false
    @State private var sendChatCaption = "Esta sería tu sonrisa mejorada."
    @State private var didSendToChat = false

    private enum StudioMode: String, CaseIterable, Identifiable {
        case aiSmile
        case model3D

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aiSmile: return "Sonrisa IA"
            case .model3D: return "Modelo 3D"
            }
        }

        var icon: String {
            switch self {
            case .aiSmile: return "sparkles"
            case .model3D: return "cube.transparent"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modo", selection: $mode) {
                    ForEach(StudioMode.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 16) {
                        switch mode {
                        case .aiSmile:
                            aiSmileSection
                        case .model3D:
                            model3DSection
                        }

                        disclaimer
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(GrooClinicDesign.ScreenBackground())
            .navigationTitle("Estudio de sonrisa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                GrooCameraImagePicker { image in
                    showCamera = false
                    if let image {
                        applySourceImage(image)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run { applySourceImage(image) }
                    }
                    await MainActor.run { selectedPhoto = nil }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let resultImage {
                    GrooImageActivityShareSheet(image: resultImage)
                }
            }
            .sheet(isPresented: $showSendToChat) {
                if let resultImage {
                    GrooSmileSendToChatSheet(
                        image: resultImage,
                        caption: $sendChatCaption,
                        sessions: groo.sessions.sorted(by: { $0.updatedAt > $1.updatedAt }),
                        onCreateNew: {
                            let id = groo.startNewSession()
                            sendSmile(to: id, image: resultImage)
                        },
                        onSelect: { session in
                            sendSmile(to: session.id, image: resultImage)
                        }
                    )
                    .environmentObject(groo)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Enviado al chat", isPresented: $didSendToChat) {
                Button("Ver chat") {
                    dismiss()
                    tabRouter.openChat()
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("La imagen se envió con el mensaje «\(sendChatCaption)».")
            }
        }
    }

    // MARK: - IA

    private var aiSmileSection: some View {
        VStack(spacing: 16) {
            captureActions

            if let sourceImage {
                if let resultImage {
                    beforeAfterCompare(original: sourceImage, enhanced: resultImage)
                } else {
                    imagePreview(sourceImage, label: "Tu foto")
                }
            } else {
                emptyPhotoPlaceholder
            }

            designControls

            generateButton
        }
    }

    private var captureActions: some View {
        HStack(spacing: 10) {
            Button {
                showCamera = true
            } label: {
                Label("Cámara", systemImage: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(GrooBrand.primary)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Galería", systemImage: "photo.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(GrooBrand.primary)
        }
    }

    private var emptyPhotoPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "face.smiling")
                .font(.system(size: 44))
                .foregroundStyle(GrooBrand.primary.opacity(0.6))
            Text("Foto del paciente + Gemini")
                .font(.system(size: 15, weight: .semibold))
            Text("La IA mejora solo los dientes y coloca un fondo negro de estudio. El rostro se mantiene igual.")
                .font(.system(size: 13))
                .foregroundStyle(DrflowTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(studioCard)
    }

    private var designControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tipo de sonrisa")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)

            Text("Elige la forma antes de generar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GeminiSmileClient.SmileType.allCases) { type in
                        smileTypeChip(type)
                    }
                }
                .padding(.vertical, 2)
            }

            Text(designOptions.smileType.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GrooBrand.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 2)

            Text("Diseño a medida")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)

            sliderRow("Blancura", value: $designOptions.whitenLevel, icon: "sun.max.fill")
            sliderRow("Alineación", value: $designOptions.alignmentLevel, icon: "align.horizontal.center")
            sliderRow("Naturalidad", value: $designOptions.naturalLook, icon: "leaf.fill")

            TextField("Notas del paciente (opcional)", text: $designOptions.notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .background(studioCard)
        .onChange(of: designOptions.whitenLevel) { _, v in dentalParams.whiteness = v }
        .onChange(of: designOptions.alignmentLevel) { _, v in dentalParams.alignment = v }
    }

    private func smileTypeChip(_ type: GeminiSmileClient.SmileType) -> some View {
        let selected = designOptions.smileType == type
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                designOptions.smileType = type
                resultImage = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : GrooBrand.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(selected ? Color.white.opacity(0.22) : GrooBrand.primarySoft)
                    )

                Text(type.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? .white : Color.black.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 128, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? GrooBrand.primary : Color(red: 0.97, green: 0.98, blue: 1.0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GrooBrand.primary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(GrooBrand.primary)
            }
            Slider(value: value, in: 0.2...1)
                .tint(GrooBrand.primary)
        }
    }

    private var generateButton: some View {
        Button {
            Task { await generateSmile() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isGenerating ? "Gemini creando \(designOptions.smileType.title)…" : "Crear sonrisa (\(designOptions.smileType.title))")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(GrooBrand.primary)
        .disabled(sourceImage == nil || isGenerating || !GeminiSmileClient.isConfigured)
        .overlay(alignment: .bottom) {
            if !GeminiSmileClient.isConfigured {
                Text("Configura GEMINI_API_KEY / GEMINI_IMAGE_API_KEY en DeveloperSettings.local.xcconfig")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 52)
            }
        }
    }

    // MARK: - 3D

    private var model3DSection: some View {
        VStack(spacing: 16) {
            Text("Modela el arco dental en 3D")
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            GrooDentalArch3DView(params: dentalParams)
                .frame(height: 280)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.94, green: 0.97, blue: 1), Color.white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 14) {
                sliderRow("Blancura dental", value: $dentalParams.whiteness, icon: "sparkle")
                sliderRow("Alineación", value: $dentalParams.alignment, icon: "arrow.left.and.right")
                sliderRow("Ancho de arco", value: $dentalParams.archWidth, icon: "arrow.up.left.and.arrow.down.right")
                Toggle("Mostrar arco inferior", isOn: $dentalParams.showLowerArch)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(14)
            .background(studioCard)

            if let resultImage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resultado IA de referencia")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DrflowTheme.textTertiary)
                    imagePreview(resultImage, label: "Sonrisa diseñada")
                }
            }
        }
    }

    // MARK: - Helpers

    private func imagePreview(_ image: UIImage, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .padding(14)
        .background(studioCard)
    }

    private func beforeAfterCompare(original: UIImage, enhanced: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Antes / Después")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Image(uiImage: enhanced)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: geo.size.height)
                        .clipped()

                    Image(uiImage: original)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: geo.size.height)
                        .clipped()
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: width * comparePosition)
                        }

                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: width * comparePosition - 1)
                        .shadow(color: .black.opacity(0.2), radius: 2)

                    HStack {
                        Text("Antes")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        Spacer()
                        Text("Después")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding(10)
                    .frame(width: width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            comparePosition = min(max(value.location.x / width, 0.05), 0.95)
                        }
                )
            }
            .frame(height: 320)

            Slider(value: $comparePosition, in: 0.05...0.95)
                .tint(GrooBrand.primary)

            Button {
                showShareSheet = true
            } label: {
                Label("Compartir resultado", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(GrooBrand.primary)

            Button {
                showSendToChat = true
            } label: {
                Label("Enviar al chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(GrooBrand.primary)
        }
        .padding(14)
        .background(studioCard)
    }

    private var disclaimer: some View {
        Text(GrooImageProcessing.smileAIPreviewDisclaimerEN)
            .font(.system(size: 11))
            .foregroundStyle(DrflowTheme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private var studioCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func applySourceImage(_ image: UIImage) {
        sourceImage = GrooImageProcessing.resize(image)
        resultImage = nil
        comparePosition = 0.5
    }

    @MainActor
    private func generateSmile() async {
        guard let sourceImage else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            resultImage = try await GeminiSmileClient.transformSmile(
                image: sourceImage,
                options: designOptions
            )
            dentalParams.whiteness = designOptions.whitenLevel
            dentalParams.alignment = designOptions.alignmentLevel
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendSmile(to sessionId: UUID, image: UIImage) {
        let caption = sendChatCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = caption.isEmpty ? "Esta sería tu sonrisa mejorada." : caption
        sendChatCaption = finalCaption
        guard groo.sendSmilePreviewToChat(sessionId: sessionId, image: image, caption: finalCaption) else {
            errorMessage = "No se pudo enviar al chat."
            return
        }
        showSendToChat = false
        didSendToChat = true
    }
}

private struct GrooImageActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct GrooSmileSendToChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @Binding var caption: String
    let sessions: [GrooChatSession]
    var onCreateNew: () -> Void
    var onSelect: (GrooChatSession) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mensaje")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("Esta sería tu sonrisa mejorada.", text: $caption, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Conversaciones") {
                    Button {
                        onCreateNew()
                    } label: {
                        Label("Nueva conversación", systemImage: "plus.bubble.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    if sessions.isEmpty {
                        Text("No hay chats todavía. Crea uno nuevo.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                onSelect(session)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(GrooBrand.primarySoft)
                                        Image(systemName: "bubble.left.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(GrooBrand.primary)
                                    }
                                    .frame(width: 40, height: 40)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.black.opacity(0.88))
                                            .lineLimit(1)
                                        Text(session.preview)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.45))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(GrooBrand.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Enviar al chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

struct GrooCameraImagePicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = ["public.image"]
        if picker.sourceType == .camera {
            picker.cameraDevice = .front
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            onPick(image)
        }
    }
}
