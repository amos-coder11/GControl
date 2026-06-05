import SwiftUI

/// Texto del EULA / términos de tolerancia cero para contenido generado por usuarios.
enum UGCTermsText {
    static let title = "Términos de uso y comunidad"

    static let body = """
    Bienvenido a CarHub365. Al usar el chat, el directorio de equipo y otras funciones con contenido generado por usuarios, aceptas lo siguiente:

    1. Tolerancia cero
    No se permite contenido objetable ni conducta abusiva. Esto incluye, entre otros: acoso, amenazas, incitación al odio, contenido sexual explícito, violencia gráfica, spam y suplantación de identidad.

    2. Tu responsabilidad
    Eres responsable del contenido que publicas o envías. CarHub puede eliminar contenido y suspender o expulsar cuentas que infrinjan estas normas.

    3. Denuncias
    Puedes denunciar mensajes o usuarios desde cualquier conversación. Nuestro equipo revisa cada informe y actúa en un plazo máximo de 24 horas, eliminando el contenido y expulsando al usuario infractor cuando corresponda.

    4. Bloqueo
    Puedes bloquear a cualquier usuario abusivo. Al bloquear, dejarás de ver su contenido de inmediato y se notificará automáticamente al equipo de CarHub para revisión.

    5. Filtrado
    La aplicación filtra automáticamente lenguaje objetable en los mensajes enviados y mostrados.

    6. Contacto
    Para consultas sobre moderación: soporte@carhub365.com

    Versión de términos: \(ContentModerationFilter.currentTermsVersion)
    """
}

/// Pantalla completa de términos (desde ajustes o enlace en registro).
struct UGCTermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(UGCTermsText.body)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(UGCTermsText.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

/// Hoja de aceptación obligatoria antes de registrarse o iniciar sesión.
struct UGCTermsAcceptanceSheet: View {
    @Binding var isPresented: Bool
    var onAccepted: () -> Void

    @State private var didReadTerms = false
    @State private var showFullTerms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(UGCTermsText.title)
                        .font(.system(size: 22, weight: .bold))

                    Text(UGCTermsText.body)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Button("Leer términos completos") {
                        showFullTerms = true
                    }
                    .font(.system(size: 14, weight: .semibold))

                    Toggle(isOn: $didReadTerms) {
                        Text("He leído y acepto los Términos de uso. Entiendo que no hay tolerancia para contenido objetable ni usuarios abusivos.")
                            .font(.system(size: 14))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.35, green: 0.55, blue: 1.0)))

                    Button {
                        onAccepted()
                        isPresented = false
                    } label: {
                        Text("Aceptar y continuar")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(didReadTerms ? Color.accentColor : Color.gray.opacity(0.35))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(!didReadTerms)
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { isPresented = false }
                }
            }
            .sheet(isPresented: $showFullTerms) {
                UGCTermsView()
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    UGCTermsView()
}
