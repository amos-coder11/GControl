import ImageIO
import SwiftUI
import UIKit
import WebKit

/// Reproduce un GIF del bundle con `UIImageView` (SwiftUI `Image` no anima GIF del catálogo).
struct GIFAnimatedView: UIViewRepresentable {
    var resourceName: String = "AIAssistantOrb"
    var bundle: Bundle = .main

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.backgroundColor = .clear
        load(into: v)
        return v
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        load(into: uiView)
    }

    private func load(into imageView: UIImageView) {
        guard let url = bundle.url(forResource: resourceName, withExtension: "gif"),
              let data = try? Data(contentsOf: url)
        else {
            imageView.image = nil
            imageView.stopAnimating()
            return
        }
        if let animated = Self.animatedUIImage(from: data) {
            imageView.image = animated
            imageView.startAnimating()
        } else if let still = UIImage(data: data) {
            imageView.image = still
            imageView.stopAnimating()
        } else {
            imageView.image = nil
        }
    }

    private static func animatedUIImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        if count == 1 {
            guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return UIImage(cgImage: cg)
        }
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for i in 0 ..< count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay =
                (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval)
                ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? TimeInterval)
                ?? 0.1
            duration += max(delay, 0.02)
            images.append(UIImage(cgImage: cg))
        }
        guard !images.isEmpty else { return nil }
        // `duration` en UIImage es el tiempo por fotograma, no el total del GIF.
        let perFrame = max(duration / Double(images.count), 0.02)
        return UIImage.animatedImage(with: images, duration: perFrame)
    }
}

// MARK: - Animated SVG (SMIL)

/// Renderiza SVG con animaciones SMIL (p. ej. iconos de Lordicon) vía WKWebView.
struct AnimatedSVGIconView: UIViewRepresentable {
    var resourceName: String
    var size: CGFloat = 20
    var tintHex: String = "#8E8E93"
    /// Cambia para reiniciar animaciones one-shot (p. ej. tab bar).
    var replayToken: UUID = UUID()
    /// `false` muestra el frame final estático entre reproducciones.
    var isPlaying: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        let html = htmlDocument
        context.coordinator.loadedKey = cacheKey
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let key = cacheKey
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        uiView.loadHTMLString(htmlDocument, baseURL: nil)
    }

    private var cacheKey: String {
        let playback = isPlaying ? replayToken.uuidString : "idle"
        return "\(resourceName)|\(tintHex)|\(playback)"
    }

    private var htmlDocument: String {
        Self.htmlDocument(
            svg: isPlaying ? Self.loadSVG(named: resourceName) : Self.loadIdleSVG(named: resourceName),
            tintHex: tintHex
        )
    }

    static func htmlDocument(svg: String, tintHex: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
            width: 100%;
            height: 100%;
        }
        svg {
            width: 100%;
            height: 100%;
            display: block;
            color: \(tintHex);
        }
        </style>
        </head>
        <body><div id="svg-root">\(svg)</div></body>
        </html>
        """
    }

    final class Coordinator {
        var loadedKey: String?
    }

    static func loadSVG(named name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return normalizeSVG(text)
        }
        if name == "HomePatientsCloudIcon" {
            return patientsCloudSVG
        }
        if name == "HomeCitasCalendarIcon" {
            return citasCalendarSVG
        }
        if name == "TabBarChatIcon" {
            return tabBarChatSVG
        }
        if name == "HomeWeekDayIconUnselected" {
            return homeWeekDayIconUnselectedSVG
        }
        if name == "HomeWeekDayIconSelected" {
            return homeWeekDayIconSelectedSVG
        }
        if name == "HomeWorkdayJornadaIcon" {
            return homeWorkdayJornadaSVG
        }
        return ""
    }

    static func loadIdleSVG(named name: String) -> String {
        if name == "TabBarChatIcon" {
            return tabBarChatIdleSVG
        }
        if name == "HomeWeekDayIconUnselected" {
            return homeWeekDayIconUnselectedIdleSVG
        }
        if name == "HomeWeekDayIconSelected" {
            return homeWeekDayIconSelectedIdleSVG
        }
        if name == "HomeCitasCalendarIcon" {
            return citasCalendarIdleSVG
        }
        if name == "HomePatientsCloudIcon" {
            return patientsCloudIdleSVG
        }
        if name == "HomeWorkdayJornadaIcon" {
            return homeWorkdayJornadaIdleSVG
        }
        return loadSVG(named: name)
    }

    private static func normalizeSVG(_ text: String) -> String {
        text.replacingOccurrences(of: "film=\"currentColor\"", with: "fill=\"currentColor\"")
    }

    /// Respaldo embebido por si el recurso no está en el bundle.
    private static let patientsCloudSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <defs>
    <mask id="SVGhNeVEbZD">
    <g fill="#fff">
    <path fill-opacity="0" stroke="#fff" stroke-dasharray="60" stroke-dashoffset="60" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 19h11c2.21 0 4 -1.79 4 -4c0 -2.21 -1.79 -4 -4 -4h-1v-1c0 -2.76 -2.24 -5 -5 -5c-2.42 0 -4.44 1.72 -4.9 4h-0.1c-2.76 0 -5 2.24 -5 5c0 2.76 2.24 5 5 5Z">
    <animate fill="freeze" attributeName="stroke-dashoffset" dur="0.6s" values="60;0" />
    <animate fill="freeze" attributeName="fill-opacity" begin="0.23s" dur="0.15s" to="0.3" />
    </path>
    <path d="M6 11h12v0h-12Z">
    <animate fill="freeze" attributeName="d" begin="0.33s" dur="0.3s" values="M6 11h12v0h-12Z;M6 11h12v11h-12Z" />
    </path>
    </g>
    <path d="M8 13h8v0h-8Z">
    <animate fill="freeze" attributeName="d" begin="0.4s" dur="0.23s" values="M8 13h8v0h-8Z;M8 13h8v7h-8Z" />
    </path>
    </mask>
    </defs>
    <g fill="currentColor">
    <path d="M0 0h24v24H0z" mask="url(#SVGhNeVEbZD)" />
    <path d="M9 12h6v1h-6ZM9 12h6v1h-6ZM9 12h6v1h-6ZM9 12h6v1h-6Z" opacity="0">
    <animate fill="freeze" attributeName="opacity" begin="0.4s" dur="0.1s" to="1" />
    <animate fill="freeze" attributeName="d" begin="0.4s" dur="0.45s" values="M9 12h6v1h-6ZM9 12h6v1h-6ZM9 12h6v1h-6ZM9 12h6v1h-6Z;M9 14h6v1h-6ZM9 16h6v1h-6ZM9 18h6v1h-6ZM9 20h6v1h-6Z" />
    </path>
    </g>
    </svg>
    """

    private static let citasCalendarSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <g fill="currentColor">
    <path fill-opacity="0" stroke="currentColor" stroke-dasharray="66" stroke-dashoffset="66" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4h7c0.55 0 1 0.45 1 1v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1Z">
    <animate fill="freeze" attributeName="stroke-dashoffset" dur="0.6s" values="66;0" />
    <animate fill="freeze" attributeName="fill-opacity" begin="0.38s" dur="0.15s" to="0.3" />
    </path>
    <path d="M5 5h14v0h-14Z">
    <animate fill="freeze" attributeName="d" begin="0.23s" dur="0.15s" values="M5 5h14v0h-14Z;M5 5h14v3h-14Z" />
    </path>
    </g>
    <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
    <path stroke-dasharray="4" stroke-dashoffset="4" d="M7 4v-2M17 4v-2">
    <animate fill="freeze" attributeName="stroke-dashoffset" begin="0.31s" dur="0.15s" to="0" />
    </path>
    <path stroke-dasharray="12" stroke-dashoffset="12" d="M7 11h10">
    <animate fill="freeze" attributeName="stroke-dashoffset" begin="0.38s" dur="0.15s" to="0" />
    </path>
    <path stroke-dasharray="10" stroke-dashoffset="10" d="M7 15h7">
    <animate fill="freeze" attributeName="stroke-dashoffset" begin="0.45s" dur="0.15s" to="0" />
    </path>
    </g>
    </svg>
    """

    private static let citasCalendarIdleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <g fill="currentColor">
    <path fill-opacity="0.25" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4h7c0.55 0 1 0.45 1 1v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1Z" />
    <path d="M5 5h14v3h-14Z" />
    </g>
    <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
    <path d="M7 4v-2M17 4v-2" />
    <path d="M7 11h10" />
    <path d="M7 15h7" />
    </g>
    </svg>
    """

    private static let patientsCloudIdleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <g fill="currentColor">
    <path fill-opacity="0.25" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 19h11c2.21 0 4 -1.79 4 -4c0 -2.21 -1.79 -4 -4 -4h-1v-1c0 -2.76 -2.24 -5 -5 -5c-2.42 0 -4.44 1.72 -4.9 4h-0.1c-2.76 0 -5 2.24 -5 5c0 2.76 2.24 5 5 5Z" />
    <path d="M9 12h6v1h-6ZM9 14h6v1h-6ZM9 16h6v1h-6Z" opacity="0.55" />
    </g>
    </svg>
    """

    private static let tabBarChatSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 32 32">
    <path d="M0 0h32v32H0z" fill="none" />
    <path fill="currentColor" d="M2 13.5C2 7.701 6.701 3 12.5 3S23 7.701 23 13.5S18.3 24 12.5 24c-1.686 0-3.281-.398-4.695-1.106L3.89 23.943a1.5 1.5 0 0 1-1.837-1.837l1.05-3.918A10.4 10.4 0 0 1 2 13.5m10.5 12q1-.001 1.955-.158A8.46 8.46 0 0 0 19.5 27c1.486 0 2.88-.38 4.094-1.049a1 1 0 0 1 .741-.09l3.456.926l-.926-3.458a1 1 0 0 1 .09-.74A8.46 8.46 0 0 0 28 18.5a8.49 8.49 0 0 0-3.665-6.991a12 12 0 0 0-.787-2.7A10.5 10.5 0 0 1 30 18.5a10.5 10.5 0 0 1-1.102 4.688l1.05 3.918a1.5 1.5 0 0 1-1.838 1.837l-3.915-1.049A10.46 10.46 0 0 1 19.5 29c-3.124 0-5.93-1.364-7.853-3.53q.423.03.853.03" />
    </svg>
    """

    private static let tabBarChatIdleSVG = tabBarChatSVG

    private static let homeWeekDayIconUnselectedSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <g stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
    <path fill="currentColor" fill-opacity=".3" d="M20 5v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1Z">
    <animate fill="freeze" attributeName="d" dur="0.4s" values="M22 3v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1Z;M20 5v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1Z" />
    </path>
    <path fill="none" d="M8 8h8M8 12h8M8 16h5M4 5v14c0 0.55 0.45 1 1 1h14">
    <animate fill="freeze" attributeName="d" dur="0.4s" values="M10 6h8M10 10h8M10 14h5M2 6v15c0 0.55 0.45 1 1 1h15;M8 8h8M8 12h8M8 16h5M4 5v14c0 0.55 0.45 1 1 1h14" />
    </path>
    </g>
    </svg>
    """

    private static let homeWeekDayIconUnselectedIdleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <g stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
    <path fill="currentColor" fill-opacity=".3" d="M20 5v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1Z" />
    <path fill="none" d="M8 8h8M8 12h8M8 16h5M4 5v14c0 0.55 0.45 1 1 1h14" />
    </g>
    </svg>
    """

    private static let homeWeekDayIconSelectedSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M22 3v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1ZM10 6h8M10 10h8M10 14h5M2 6v15c0 0.55 0.45 1 1 1h15">
    <animate fill="freeze" attributeName="d" dur="0.4s" values="M20 5v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1ZM8 8h8M8 12h8M8 16h5M4 5v14c0 0.55 0.45 1 1 1h14;M22 3v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1ZM10 6h8M10 10h8M10 14h5M2 6v15c0 0.55 0.45 1 1 1h15" />
    </path>
    </svg>
    """

    private static let homeWeekDayIconSelectedIdleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M22 3v14c0 0.55 -0.45 1 -1 1h-14c-0.55 0 -1 -0.45 -1 -1v-14c0 -0.55 0.45 -1 1 -1h14c0.55 0 1 0.45 1 1ZM10 6h8M10 10h8M10 14h5M2 6v15c0 0.55 0.45 1 1 1h15" />
    </svg>
    """

    private static let homeWorkdayJornadaSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <path fill="currentColor" fill-opacity="0" d="M6 4h4v2h4v-2h4v16h-12v-16Z">
    <animate fill="freeze" attributeName="fill-opacity" begin="1.1s" dur="0.15s" to=".3" />
    </path>
    <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <path stroke-dasharray="66" stroke-width="2" d="M12 3h7v18h-14v-18h7Z">
    <animate fill="freeze" attributeName="stroke-dashoffset" dur="0.6s" values="66;0" />
    </path>
    <path stroke-dasharray="14" stroke-dashoffset="14" d="M14.5 3.5v3h-5v-3">
    <animate fill="freeze" attributeName="stroke-dashoffset" begin="0.7s" dur="0.2s" to="0" />
    </path>
    <path stroke-dasharray="12" stroke-dashoffset="12" stroke-width="2" d="M9 13l2 2l4 -4">
    <animate fill="freeze" attributeName="stroke-dashoffset" begin="0.9s" dur="0.2s" to="0" />
    </path>
    </g>
    </svg>
    """

    private static let homeWorkdayJornadaIdleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
    <path d="M0 0h24v24H0z" fill="none" />
    <path fill="currentColor" fill-opacity="0.3" d="M6 4h4v2h4v-2h4v16h-12v-16Z" />
    <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <path stroke-width="2" d="M12 3h7v18h-14v-18h7Z" />
    <path d="M14.5 3.5v3h-5v-3" />
    <path stroke-width="2" d="M9 13l2 2l4 -4" />
    </g>
    </svg>
    """
}

// MARK: - Tab bar SVG → UIImage (UITabBar no renderiza WKWebView en el label)

// MARK: - Tab bar Chat icon (UIImage para UITabBar)

enum TabBarChatIconMetrics {
    /// Mismo tamaño que el avatar de la pestaña 「Tú」 y SF Symbols del tab bar.
    static let side: CGFloat = 26
}

enum TabBarChatIconRenderer {
    private static var cache: [String: UIImage] = [:]

    @MainActor
    static func staticIcon(selected: Bool) -> UIImage {
        let key = selected ? "sel" : "idle"
        if let cached = cache[key] { return cached }
        return provisionalIcon(selected: selected)
    }

    @MainActor
    private static func provisionalIcon(selected: Bool) -> UIImage {
        let side = TabBarChatIconMetrics.side
        let swiftUIColor = selected ? GrooBrand.primary : Color(red: 0.55, green: 0.55, blue: 0.58)
        let renderer = ImageRenderer(
            content: Image("TabBarChatIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(swiftUIColor)
                .frame(width: side, height: side)
        )
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal) ?? UIImage()
    }

    @MainActor
    static func preloadFromSVG() async {
        cache.removeAll()
        let side = TabBarChatIconMetrics.side
        let variants: [(String, String)] = [("idle", "#8E8E93"), ("sel", "#598AFA")]
        for (key, tintHex) in variants {
            if let image = await SVGTabIconRenderer.shared.idleChatIcon(tintHex: tintHex, side: side) {
                cache[key] = image
            }
        }
    }
}

@MainActor
final class SVGTabIconRenderer: NSObject, WKNavigationDelegate {
    static let shared = SVGTabIconRenderer()

    private var loadContinuation: CheckedContinuation<Void, Never>?

    func playChatAnimation(
        tintHex: String,
        side: CGFloat,
        onFrame: @escaping @MainActor (UIImage) -> Void
    ) async {
        let webView = makeWebView(side: side)
        webView.navigationDelegate = self
        attachOffscreen(webView)
        defer {
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }

        let html = AnimatedSVGIconView.htmlDocument(
            svg: AnimatedSVGIconView.loadSVG(named: "TabBarChatIcon"),
            tintHex: tintHex
        )
        webView.loadHTMLString(html, baseURL: nil)
        await waitForLoad()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let frameDelaysMs: [UInt64] = [0, 80, 150, 250, 400, 600, 800, 1000, 1200]
        for (index, delayMs) in frameDelaysMs.enumerated() {
            if index > 0 {
                let previous = frameDelaysMs[index - 1]
                try? await Task.sleep(nanoseconds: (delayMs - previous) * 1_000_000)
            }
            if let raw = await takeSnapshot(from: webView, side: side) {
                onFrame(Self.normalizeTabIcon(raw, side: side))
            }
        }
    }

    func idleChatIcon(tintHex: String, side: CGFloat) async -> UIImage? {
        await snapshot(
            svg: AnimatedSVGIconView.loadIdleSVG(named: "TabBarChatIcon"),
            tintHex: tintHex,
            side: side
        )
    }

    private func snapshot(svg: String, tintHex: String, side: CGFloat) async -> UIImage? {
        let webView = makeWebView(side: side)
        webView.navigationDelegate = self
        attachOffscreen(webView)
        defer {
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }

        webView.loadHTMLString(
            AnimatedSVGIconView.htmlDocument(svg: svg, tintHex: tintHex),
            baseURL: nil
        )
        await waitForLoad()
        try? await Task.sleep(nanoseconds: 50_000_000)
        return await takeSnapshot(from: webView, side: side).map { Self.normalizeTabIcon($0, side: side) }
    }

    private static func normalizeTabIcon(_ image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func waitForLoad() async {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    private func attachOffscreen(_ webView: WKWebView) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return }
        webView.isHidden = true
        webView.frame = CGRect(x: -200, y: -200, width: webView.bounds.width, height: webView.bounds.height)
        window.addSubview(webView)
    }

    private func makeWebView(side: CGFloat) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: side, height: side),
            configuration: config
        )
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    private func takeSnapshot(from webView: WKWebView, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: Double(side * UIScreen.main.scale))
            webView.takeSnapshot(with: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

struct TabBarChatAnimatedIcon: View {
    var replayToken: UUID

    @State private var bounceToken = 0

    private var side: CGFloat { TabBarChatIconMetrics.side }

    var body: some View {
        Image("TabBarChatIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .keyframeAnimator(
                initialValue: TabBarChatBounceValues(),
                trigger: bounceToken
            ) { content, values in
                content
                    .scaleEffect(values.scale)
                    .rotationEffect(.degrees(values.degrees))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1.0, duration: 0)
                    SpringKeyframe(1.24, duration: 0.16, spring: .bouncy)
                    SpringKeyframe(0.92, duration: 0.10, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.14, spring: .bouncy)
                }
                KeyframeTrack(\.degrees) {
                    LinearKeyframe(0, duration: 0)
                    SpringKeyframe(-7, duration: 0.08, spring: .bouncy)
                    SpringKeyframe(5, duration: 0.08, spring: .bouncy)
                    SpringKeyframe(0, duration: 0.10, spring: .bouncy)
                }
            }
            .onChange(of: replayToken) { _, _ in
                bounceToken += 1
            }
            .accessibilityHidden(true)
    }
}

private struct TabBarChatBounceValues: Equatable {
    var scale: CGFloat = 1
    var degrees: Double = 0
}

enum TabBarProfileIconRenderer {
    static func image(image: UIImage?, initial: String, side: CGFloat = 26) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: rect).addClip()

            if let image {
                let scale = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
                let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let origin = CGPoint(
                    x: (side - drawSize.width) / 2,
                    y: (side - drawSize.height) / 2
                )
                image.draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                UIColor(red: 0.35, green: 0.55, blue: 0.98, alpha: 1).setFill()
                ctx.cgContext.fill(rect)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: side * 0.42, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                let text = NSString(string: initial)
                let textSize = text.size(withAttributes: attrs)
                text.draw(
                    at: CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2),
                    withAttributes: attrs
                )
            }
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}

struct TabBarProfileAnimatedIcon: View {
    var image: UIImage?
    var initial: String
    var replayToken: UUID

    @State private var bounceToken = 0

    private let side: CGFloat = 26

    var body: some View {
        Image(uiImage: TabBarProfileIconRenderer.image(image: image, initial: initial, side: side))
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(Circle())
            .keyframeAnimator(
                initialValue: TabBarChatBounceValues(),
                trigger: bounceToken
            ) { content, values in
                content
                    .scaleEffect(values.scale)
                    .rotationEffect(.degrees(values.degrees))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1.0, duration: 0)
                    SpringKeyframe(1.18, duration: 0.16, spring: .bouncy)
                    SpringKeyframe(0.94, duration: 0.10, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.14, spring: .bouncy)
                }
                KeyframeTrack(\.degrees) {
                    LinearKeyframe(0, duration: 0)
                    SpringKeyframe(12, duration: 0.12, spring: .bouncy)
                    SpringKeyframe(0, duration: 0.14, spring: .bouncy)
                }
            }
            .onChange(of: replayToken) { _, _ in
                bounceToken += 1
            }
            .accessibilityHidden(true)
    }
}

struct HomeWorkdayAnimatedIcon: View {
    var size: CGFloat = 32
    var replayToken: UUID = UUID()
    var isPlaying: Bool = true
    var tintHex: String = "#598AFA"

    var body: some View {
        AnimatedSVGIconView(
            resourceName: "HomeWorkdayJornadaIcon",
            size: size,
            tintHex: tintHex,
            replayToken: replayToken,
            isPlaying: isPlaying
        )
        .frame(width: size, height: size)
    }
}

struct HomeAppointmentsAnimatedIcon: View {
    var size: CGFloat = 18
    var replayToken: UUID = UUID()
    var isPlaying: Bool = true

    var body: some View {
        AnimatedSVGIconView(
            resourceName: "HomeCitasCalendarIcon",
            size: size,
            tintHex: "#8E8E93",
            replayToken: replayToken,
            isPlaying: isPlaying
        )
        .frame(width: size, height: size)
    }
}

struct HomePatientsAnimatedIcon: View {
    var size: CGFloat = 18
    var replayToken: UUID = UUID()
    var isPlaying: Bool = true

    var body: some View {
        AnimatedSVGIconView(
            resourceName: "HomePatientsCloudIcon",
            size: size,
            tintHex: "#8E8E93",
            replayToken: replayToken,
            isPlaying: isPlaying
        )
        .frame(width: size, height: size)
    }
}

/// Ícono de documento bajo cada día en la franja semanal del inicio.
struct HomeWeekDayDocumentIcon: View {
    var isSelected: Bool
    var replayToken: UUID
    var isPlaying: Bool
    var size: CGFloat = 18

    private var resourceName: String {
        isSelected ? "HomeWeekDayIconSelected" : "HomeWeekDayIconUnselected"
    }

    private var tintHex: String {
        isSelected ? "#598AFA" : "#D1D1D6"
    }

    var body: some View {
        AnimatedSVGIconView(
            resourceName: resourceName,
            size: size,
            tintHex: tintHex,
            replayToken: replayToken,
            isPlaying: isPlaying
        )
        .frame(width: size, height: size)
    }
}
