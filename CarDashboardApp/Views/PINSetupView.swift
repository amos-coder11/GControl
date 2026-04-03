import SwiftUI

/// Tras iniciar sesión por primera vez (sin PIN en Keychain): crear PIN de 6 dígitos dos veces.
struct PINSetupView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var auth: AuthViewModel

    @State private var phase: Phase = .enterFirst
    @State private var firstPIN = ""
    @State private var currentEntry = ""
    @State private var mismatch = false

    private enum Phase {
        case enterFirst
        case confirm
    }

    var body: some View {
        ZStack {
            Image("ChatBackdropBase")
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                Text(phase == .enterFirst ? "Crea tu PIN" : "Confirma tu PIN")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("6 dígitos para desbloquear la app. Face ID seguirá disponible.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                pinDotsRow
                    .padding(.top, 32)

                if mismatch {
                    Text("Los PIN no coinciden. Inténtalo de nuevo.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)

                setupKeypad

                Spacer(minLength: 40)
            }
        }
        .onChange(of: currentEntry) { _, new in
            guard new.count == 6 else { return }
            switch phase {
            case .enterFirst:
                firstPIN = new
                currentEntry = ""
                phase = .confirm
                mismatch = false
            case .confirm:
                if new == firstPIN {
                    if let uid = auth.session?.user.id {
                        appLock.savePINAndUnlock(new, userId: uid)
                    } else {
                        mismatch = true
                        currentEntry = ""
                    }
                } else {
                    mismatch = true
                    currentEntry = ""
                }
            }
        }
    }

    private var pinDotsRow: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 6, id: \.self) { i in
                Circle()
                    .fill(i < currentEntry.count ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var setupKeypad: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { key in
                Button {
                    guard currentEntry.count < 6 else { return }
                    currentEntry.append(key)
                } label: {
                    Text(key)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Color.clear.frame(height: 72)
            Button {
                guard currentEntry.count < 6 else { return }
                currentEntry.append("0")
            } label: {
                Text("0")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            Button {
                if !currentEntry.isEmpty {
                    currentEntry.removeLast()
                }
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    PINSetupView()
        .environmentObject(AppLockManager())
        .environmentObject(AuthViewModel())
}
