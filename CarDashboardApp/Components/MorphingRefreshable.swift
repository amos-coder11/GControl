//
//  MorphingRefreshable.swift
//  GooeyRefreshable (Balaji) — integrado en Groo
//  Metaball via Canvas (alphaThreshold + blur), sin Metal toolchain.
//

import SwiftUI

extension View {
    /// Pull-to-refresh gooey (Dynamic Island). Usar en `List` / `ScrollView`.
    /// - Parameter pullOffset: desplaza headers sticky al tirar / refrescar.
    /// - Parameter scrollProgress: progreso 0…1 para pintar el indicador fuera (por encima del blur).
    /// - Parameter embedOverlay: si es `false`, no dibuja la gota aquí (úsalo con `MorphingRefreshIndicator`).
    @ViewBuilder
    func morphingRefreshable(
        pullOffset: Binding<CGFloat> = .constant(0),
        scrollProgress: Binding<CGFloat> = .constant(0),
        embedOverlay: Bool = true,
        onRefresh: @escaping () async -> Void
    ) -> some View {
        modifier(
            MorphingRefreshableModifier(
                pullOffset: pullOffset,
                scrollProgress: scrollProgress,
                embedOverlay: embedOverlay,
                onRefresh: onRefresh
            )
        )
    }
}

/// Indicador gooey para colocar **por encima** del blur blanco fijo.
struct MorphingRefreshIndicator: View {
    var scrollProgress: CGFloat
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            ZStack {
                if safeArea.top < 70, scrollProgress != 0 {
                    MorphingView(
                        safeArea: safeArea,
                        scrollProgress: scrollProgress,
                        sceneActive: scenePhase == .active
                    )
                }
            }
            .ignoresSafeArea()
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }
}

private struct MorphingRefreshableModifier: ViewModifier {
    @Binding var pullOffset: CGFloat
    @Binding var scrollProgress: CGFloat
    var embedOverlay: Bool
    var onRefresh: () async -> Void

    @State private var actualProgress: CGFloat = 0
    @State private var isRefreshing: Bool = false
    @State private var isAnimating: Bool = false
    @State private var tintColor: Color = .gray
    @State private var isTintUpdateAvailable: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    /// Espacio mínimo que baja el header mientras carga (para ver la gota completa).
    private let refreshingHeaderOffset: CGFloat = 72

    func body(content: Content) -> some View {
        content
            .background(RefreshControlTintUpdater(color: $tintColor) {
                isTintUpdateAvailable = $0
            })
            .compositingGroup()
            .overlay(alignment: .top) {
                if embedOverlay {
                    GeometryReader {
                        let safeArea = $0.safeAreaInsets

                        ZStack {
                            if safeArea.top < 70 && scrollProgress != 0 && isTintUpdateAvailable {
                                MorphingView(
                                    safeArea: safeArea,
                                    scrollProgress: scrollProgress,
                                    sceneActive: scenePhase == .active
                                )
                            }
                        }
                        .ignoresSafeArea()
                    }
                    .frame(height: 1)
                    .allowsHitTesting(false)
                }
            }
            .mask {
                Rectangle()
                    .ignoresSafeArea()
            }
            .refreshable {
                isRefreshing = true
                publishPullOffset(rawPull: max(0, actualProgress * 60))
                await onRefresh()

                if actualProgress == 0 {
                    isAnimating = true
                    withAnimation(.easeInOut(duration: 0.2), completionCriteria: .logicallyComplete) {
                        scrollProgress = 0.01
                        pullOffset = 0
                    } completion: {
                        scrollProgress = 0
                        isAnimating = false
                    }
                } else {
                    pullOffset = 0
                    if !isAnimating {
                        scrollProgress = 0
                    }
                }

                isRefreshing = false
            }
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { _, newValue in
                let progress = max(min(-newValue / 60, 1), 0)
                actualProgress = progress

                if !isAnimating {
                    let nextProgress = isRefreshing ? 1 : progress
                    if abs(nextProgress - scrollProgress) > 0.001 {
                        scrollProgress = nextProgress
                    }
                }

                publishPullOffset(rawPull: max(0, -newValue))
            }
            .onGeometryChange(for: EdgeInsets.self) {
                $0.safeAreaInsets
            } action: { newValue in
                if newValue.top < 70 {
                    tintColor = .clear
                } else {
                    tintColor = .gray
                }
            }
    }

    private func publishPullOffset(rawPull: CGFloat) {
        let next: CGFloat
        if isRefreshing {
            next = max(rawPull, refreshingHeaderOffset * scrollProgress)
        } else if isAnimating {
            next = pullOffset
        } else {
            next = rawPull
        }
        if abs(next - pullOffset) > 0.5 {
            pullOffset = next
        }
    }
}

private struct MorphingView: View {
    var safeArea: EdgeInsets
    var scrollProgress: CGFloat
    var sceneActive: Bool

    var body: some View {
        let hasDynamicIsland = safeArea.top >= 59
        let extraScrollOffset: CGFloat = hasDynamicIsland ? 0 : 15
        let baseOffset: CGFloat = safeArea.top < 35 ? (safeArea.top + 50) : (safeArea.top + extraScrollOffset)
        let scrollOffset = baseOffset * scrollProgress
        let blurRadius: CGFloat = 25 - (25 * scrollProgress)
        let indicatorProgress: CGFloat = scrollProgress > 0.2 ? (scrollProgress - 0.2) / 0.8 : 0
        let indicatorSize: CGFloat = 30 + (indicatorProgress * 10)
        let spinnerOpacity: CGFloat = scrollProgress > 0.8 ? (scrollProgress - 0.8) / 0.2 : 0
        let spinnerSize: CGFloat = 30 + (scrollProgress * 10)
        let islandY: CGFloat = hasDynamicIsland ? (safeArea.top - 33) / 2 : 0

        Rectangle()
            .fill(.clear)
            .frame(height: safeArea.top)
            .overlay(alignment: .top) {
                Canvas { context, size in
                    context.addFilter(.alphaThreshold(min: 0.5))
                    context.addFilter(.blur(radius: max(blurRadius, 0.01)))

                    context.drawLayer { layer in
                        if let island = context.resolveSymbol(id: 0) {
                            let rect = CGRect(
                                x: (size.width - 100) / 2,
                                y: islandY,
                                width: 100,
                                height: 33
                            )
                            layer.draw(island, in: rect)
                        }
                        if let drop = context.resolveSymbol(id: 1) {
                            let rect = CGRect(
                                x: (size.width - indicatorSize) / 2,
                                y: islandY + 33 + scrollOffset - indicatorSize / 2,
                                width: indicatorSize,
                                height: indicatorSize
                            )
                            layer.draw(drop, in: rect)
                        }
                    }
                } symbols: {
                    Capsule()
                        .fill(.black)
                        .frame(width: 100, height: 33)
                        .opacity(sceneActive ? 1 : 0)
                        .mask {
                            Capsule()
                                .padding(.top, 5)
                        }
                        .tag(0)
                        .id(0)

                    Circle()
                        .fill(.black)
                        .frame(width: indicatorSize, height: indicatorSize)
                        .tag(1)
                        .id(1)
                }
                .frame(height: safeArea.top + scrollOffset + indicatorSize)
                .overlay(alignment: .top) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                        .opacity(spinnerOpacity)
                        .frame(width: spinnerSize, height: spinnerSize)
                        .offset(
                            y: islandY + 33 + scrollOffset - spinnerSize / 2
                        )
                }
                .offset(y: safeArea.top < 35 ? -35 : 0)
            }
    }
}

private struct RefreshControlTintUpdater: UIViewRepresentable {
    @Binding var color: Color
    var result: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        updateTint(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        updateTint(uiView)
    }

    private func updateTint(_ view: UIView) {
        DispatchQueue.main.async {
            if let compositingGroup = view.superview?.superview,
               let scrollview = compositingGroup.subviews.last?.subviews.last as? UIScrollView {
                scrollview.refreshControl?.tintColor = UIColor(color)
                result(true)
            } else {
                result(false)
            }
        }
    }
}
