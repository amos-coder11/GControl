import SwiftUI
import WebKit
import AVFoundation

/// Objetivo de una llamada por softphone (número + nombre visible).
struct SoftphoneTarget: Identifiable, Equatable {
    let id = UUID()
    let number: String
    let name: String
    /// Si es true, se abre el teclado para marcar cualquier número (sin número prefijado).
    var isDialer: Bool = false
}

/// Softphone dentro de la app: el trabajador habla por el móvil (micro/altavoz) y el
/// cliente recibe una llamada normal mostrando el número de empresa como caller ID.
/// Reutiliza el mismo Twilio Voice (JS) que el CRM a través de una página del backend
/// cargada en un WebView. NO usa el número personal ni abre el marcador del teléfono.
struct SoftphoneCallView: View {
    let target: SoftphoneTarget
    let accessToken: String?
    let onClose: () -> Void

    private let backend = "https://drflowbackend.onrender.com"

    private enum Phase { case preparando, listo, error }
    @State private var phase: Phase = .preparando
    @State private var errorText: String?
    @State private var pageURL: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .preparando:
                VStack(spacing: 16) {
                    ProgressView().tint(.white)
                    Text("Conectando…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            case .error:
                VStack(spacing: 18) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(errorText ?? "No se pudo iniciar la llamada.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button("Cerrar") { close() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
            case .listo:
                if let url = pageURL {
                    SoftphoneWebView(urlString: url) { type, data in
                        if type == "hangup" { close() }
                        else if type == "loaderror" {
                            errorText = data.isEmpty ? "No se pudo cargar la llamada. ¿Está el servidor actualizado?" : data
                            phase = .error
                        }
                    }
                    .ignoresSafeArea()
                }
            }

            // Botón de cerrar siempre visible (por si la página tarda o falla).
            VStack {
                HStack {
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                }
                Spacer()
            }
        }
        .task { await prepare() }
        .onDisappear { deactivateAudio() }
    }

    private func close() {
        deactivateAudio()
        onClose()
    }

    private func prepare() async {
        await requestMicPermission()
        activateAudioSession()

        guard let token = accessToken, !token.isEmpty else {
            await fail("Sesión no válida. Vuelve a iniciar sesión.")
            return
        }
        guard let url = URL(string: "\(backend)/api/twilio/voice-token") else {
            await fail("URL no válida.")
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                await fail("No se pudo obtener el token de voz.")
                return
            }
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let voiceToken = obj?["token"] as? String, !voiceToken.isEmpty else {
                let msg = (obj?["credsError"] as? String) ?? "Token de voz vacío."
                await fail(msg)
                return
            }
            let dialFlag = target.isDialer ? "&dial=1" : ""
            let page = "\(backend)/api/twilio/softphone#to=\(enc(target.number))&token=\(enc(voiceToken))&name=\(enc(target.name))\(dialFlag)"
            await MainActor.run {
                self.pageURL = page
                self.phase = .listo
            }
        } catch {
            await fail(error.localizedDescription)
        }
    }

    @MainActor private func fail(_ msg: String) {
        errorText = msg
        phase = .error
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: - Audio

    private func requestMicPermission() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { _ in cont.resume() }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { _ in cont.resume() }
            }
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try? session.setActive(true)
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// WebView que aloja la página del softphone y concede el micrófono automáticamente.
private struct SoftphoneWebView: UIViewRepresentable {
    let urlString: String
    let onMessage: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "softphone")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "softphone")
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        let onMessage: (String, String) -> Void
        init(onMessage: @escaping (String, String) -> Void) { self.onMessage = onMessage }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            let type = body["type"] as? String ?? ""
            let data = body["data"] as? String ?? ""
            DispatchQueue.main.async { self.onMessage(type, data) }
        }

        // Si la página no carga (servidor sin actualizar, sin red…), avisamos.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // 102 = "frame load interrupted": lo provoca nuestro propio .cancel al
            // detectar un HTTP >=400; ya mostramos ese mensaje, no lo pisamos.
            if (error as NSError).code == 102 { return }
            DispatchQueue.main.async { self.onMessage("loaderror", error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onMessage("loaderror", error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
                DispatchQueue.main.async {
                    self.onMessage("loaderror", "El servidor respondió \(http.statusCode). Falta actualizar el backend.")
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Concede el permiso de micrófono dentro del WebView (iOS 15+).
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}
