//
//  AnimatedBottomBar.swift
//  Portado desde CustomBottomBar (Balaji Venkatesh).
//

import SwiftUI

enum AnimatedBottomBarCollapsedLayout {
    /// Campo + botón principal aparte (diseño original del ZIP).
    case splitMainAction
    /// Cápsula única estilo ChatGPT: + · texto · mic · botón azul.
    case inlineChatGPT
}

struct AnimatedBottomBar<LeadingAction: View, TrailingAction: View, MainAction: View>: View {
    var highlightWhenEmpty: Bool = true
    var hint: String
    var tint: Color = .green
    /// Si se define, la barra usa relleno opaco (p. ej. blanco) en lugar de `.bar`.
    var surfaceColor: Color? = nil
    var collapsedLayout: AnimatedBottomBarCollapsedLayout = .splitMainAction
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @ViewBuilder var leadingAction: () -> LeadingAction
    @ViewBuilder var trailingAction: () -> TrailingAction
    @ViewBuilder var mainAction: () -> MainAction
    @State private var isHighligting: Bool = false

    var body: some View {
        Group {
            if collapsedLayout == .inlineChatGPT {
                chatGPTAdaptiveBar
            } else {
                classicSplitBar
            }
        }
        .animation(.easeOut(duration: animationDuration), value: isFocused)
    }

    // MARK: - ChatGPT (un solo TextField: cerrado → abierto sin perder el teclado)

    private var chatGPTAdaptiveBar: some View {
        let shape = RoundedRectangle(cornerRadius: isFocused ? 25 : 26, style: .continuous)

        return VStack(alignment: .leading, spacing: isFocused ? 18 : 0) {
            HStack(alignment: isFocused ? .top : .center, spacing: 10) {
                if !isFocused {
                    Button {
                        isFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                TextField(hint, text: $text, axis: .vertical)
                    .lineLimit(isFocused ? 1...5 : 1...1)
                    .focused($isFocused)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.return)

                if !isFocused {
                    trailingAction()
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())

                    mainAction()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                }
            }

            if isFocused {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(subviews: leadingAction()) { subview in
                            subview
                                .frame(width: 35, height: 35)
                                .contentShape(.rect)
                        }
                    }

                    Spacer(minLength: 0)

                    trailingAction()
                        .frame(width: 35, height: 35)
                        .contentShape(.rect)
                }
            }
        }
        .padding(.leading, isFocused ? 15 : 14)
        .padding(.trailing, isFocused ? 15 : 8)
        .padding(.top, isFocused ? 18 : 8)
        .padding(.bottom, isFocused ? 10 : 8)
        .frame(minHeight: isFocused ? nil : 52)
        .background {
            shape
                .fill(surfaceColor ?? .white)
                .shadow(color: .black.opacity(0.08), radius: isFocused ? 14 : 10, y: 3)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .contentShape(shape)
    }

    // MARK: - Classic split (ZIP original)

    private var classicSplitBar: some View {
        let mainLayout = isFocused ? AnyLayout(ZStackLayout(alignment: .bottomTrailing)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 10))
        let shape = RoundedRectangle(cornerRadius: isFocused ? 25 : 30, style: .continuous)

        return ZStack {
            mainLayout {
                let subLayout = isFocused ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 20)) : AnyLayout(ZStackLayout(alignment: .trailing))

                subLayout {
                    TextField(hint, text: $text, axis: .vertical)
                        .lineLimit(isFocused ? 5 : 1)
                        .focused($isFocused)
                        .mask {
                            Rectangle()
                                .padding(.trailing, isFocused ? 0 : 40)
                        }

                    HStack(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(subviews: leadingAction()) { subview in
                                subview
                                    .frame(width: 35, height: 35)
                                    .contentShape(.rect)
                            }
                        }
                        .compositingGroup()
                        .allowsHitTesting(isFocused)
                        .blur(radius: isFocused ? 0 : 6)
                        .opacity(isFocused ? 1 : 0)

                        Spacer(minLength: 0)

                        trailingAction()
                            .frame(width: 35, height: 35)
                            .contentShape(.rect)
                    }
                }
                .frame(height: isFocused ? nil : 55)
                .padding(.leading, 15)
                .padding(.trailing, isFocused ? 15 : 10)
                .padding(.bottom, isFocused ? 10 : 0)
                .padding(.top, isFocused ? 20 : 0)
                .background {
                    ZStack {
                        HighlightingBackgroundView()

                        Group {
                            if let surfaceColor {
                                shape.fill(surfaceColor)
                            } else {
                                shape.fill(.bar)
                            }
                        }
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                        .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: -5)
                    }
                }

                mainAction()
                    .frame(width: 50, height: 50)
                    .clipShape(.circle)
                    .background {
                        Circle()
                            .fill(surfaceColor ?? Color(.systemBackground).opacity(0.92))
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                            .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: -5)
                    }
                    .visualEffect { [isFocused] content, proxy in
                        content
                            .offset(x: isFocused ? (proxy.size.width + 30) : 0)
                    }
            }
        }
        .geometryGroup()
    }

    @ViewBuilder
    private func HighlightingBackgroundView() -> some View {
        ZStack {
            let shape = RoundedRectangle(cornerRadius: isFocused ? 25 : 30, style: .continuous)

            if !isFocused && text.isEmpty && highlightWhenEmpty {
                shape
                    .stroke(
                        tint.gradient,
                        style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .mask {
                        let clearColors: [Color] = Array(repeating: .clear, count: 3)

                        shape
                            .fill(AngularGradient(
                                colors: clearColors + [Color.white] + clearColors,
                                center: .center,
                                angle: .init(degrees: isHighligting ? 360 : 0)
                            ))
                    }
                    .padding(-1.5)
                    .blur(radius: 1.5)
                    .onAppear {
                        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                            isHighligting = true
                        }
                    }
                    .onDisappear {
                        isHighligting = false
                    }
                    .transition(.blurReplace)
            }
        }
    }

    var animationDuration: CGFloat {
        if #available(iOS 26, *) {
            return 0.22
        } else {
            return 0.33
        }
    }
}
