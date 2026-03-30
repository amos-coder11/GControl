import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var auth: AuthViewModel

    @State private var pinEntry = ""

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
                Spacer(minLength: 24)

                profileBlock

                Text(timeGreeting + ", " + auth.shortGreetingName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                pinDotsRow
                    .padding(.top, 36)

                Spacer(minLength: 20)

                pinKeypad

                if let err = appLock.authError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }

                Button {
                    Task {
                        await auth.signOut()
                    }
                } label: {
                    Text("¿Has olvidado tu clave de acceso?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
        }
        .onAppear {
            pinEntry = ""
            appLock.authenticateWithBiometry()
        }
        .onChange(of: appLock.authError) { _, new in
            if new != nil {
                pinEntry = ""
            }
        }
        .onChange(of: appLock.isUnlocked) { _, unlocked in
            if unlocked {
                pinEntry = ""
            }
        }
    }

    private var profileBlock: some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Text(auth.userInitials)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
        }
    }

    private var pinDotsRow: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 6, id: \.self) { i in
                Circle()
                    .fill(i < pinEntry.count ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var pinKeypad: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { key in
                keypadDigitButton(key)
            }
            keypadBiometryButton
            keypadDigitButton("0")
            keypadDeleteButton
        }
        .padding(.horizontal, 40)
    }

    private func keypadDigitButton(_ digit: String) -> some View {
        Button {
            guard pinEntry.count < 6 else { return }
            pinEntry.append(digit)
            if pinEntry.count == 6 {
                appLock.submitPIN(pinEntry)
            }
        } label: {
            Text(digit)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(appLock.isAuthenticating)
    }

    private var keypadBiometryButton: some View {
        Button {
            appLock.authenticateWithBiometry()
        } label: {
            Image(systemName: biometrySymbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(appLock.isAuthenticating)
    }

    private var keypadDeleteButton: some View {
        Button {
            if !pinEntry.isEmpty {
                pinEntry.removeLast()
                appLock.authError = nil
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

    private var biometrySymbol: String {
        switch appLock.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        @unknown default: return "lock.fill"
        }
    }

    private var timeGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5 ..< 12: return "Buenos días"
        case 12 ..< 20: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }
}

#Preview {
    LockScreenView()
        .environmentObject(AppLockManager())
        .environmentObject(AuthViewModel())
}
