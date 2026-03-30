import Foundation

/// Cliente para la API Messages de Anthropic (Claude).
/// Clave: `ANTHROPIC_API_KEY` vía xcconfig / Info. Modelo opcional: `ANTHROPIC_MODEL` (p. ej. `claude-sonnet-4-5-20250929`).
enum AnthropicContractClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    /// IDs antiguos tipo `claude-3-5-sonnet-20241022` devuelven 404; usar familia Claude 4.x (docs.anthropic.com).
    private static let defaultModel = "claude-sonnet-4-20250514"

    private static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static var model: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_MODEL") as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return defaultModel
    }

    static var isConfigured: Bool { apiKey != nil }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int, String?)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Falta la clave de Anthropic. Configura ANTHROPIC_API_KEY (DeveloperSettings.local.xcconfig)."
            case .invalidResponse:
                return "Respuesta inválida del servidor."
            case let .httpStatus(code, msg):
                if let msg, !msg.isEmpty { return "Error \(code): \(msg)" }
                return "Error del servicio (\(code))."
            case .decodingFailed:
                return "No se pudo leer la respuesta de Claude."
            }
        }
    }

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentBlock]
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let type: String?
            let message: String
        }

        let error: APIError?
    }

    // MARK: - Prompts por tipo (edita aquí el “estilo” de cada documento)

    /// CarHub vende al cliente: compraventa clásica con entrega y tráfico.
    private static let systemPromptVenta = """
    ROL: Redactor de borradores de CONTRATO DE VENTA / COMPRAVENTA en España. EL VENDEDOR es el concesionario \
    «CarHub» (persona jurídica). EL COMPRADOR es el particular cuyos datos se facilitan.

    AVISO LEGAL (primer bloque, 2–4 frases): BORRADOR, no es asesoramiento jurídico, revisión profesional previa a firmar.

    TONO: español de España, formal, cláusulas en tercera persona. Sin markdown ni emojis.

    ESTRUCTURA:
    1) Lugar y fecha larga.
    2) REUNIDOS — EL VENDEDOR CarHub [CIF], [domicilio social]; EL COMPRADOR (datos facilitados o [marcadores]).
    3) EXPONEN — I–III: voluntad de compraventa; titularidad del Vendedor sobre el vehículo (sin afirmar hechos no dados).
    4) CLÁUSULAS PRIMERA a OCTAVA mínimo:
       PRIMERA objeto del vehículo (marca/modelo; [matrícula], [bastidor], [km], [año] si no hay datos).
       SEGUNDA precio en EUR del dato; IVA [según normativa] si aplica.
       TERCERA forma de pago [a concretar] si falta.
       CUARTA entrega, documentación, plazo [Plazo entrega].
       QUINTA estado revisado por comprador, entrega en estado actual, sin garantías extra no indicadas.
       SEXTA cargas, transferencia DGT, colaboración mutua.
       SÉPTIMA RGPD/LOPDGDD breve.
       OCTAVA ley española, tribunales, ejemplares.
    5) Cierre firmas.

    REGLAS: no inventar CIF, matrícula, bastidor, km, año. Si el usuario adjunta «TEXTO EXTRAÍDO DEL PDF MODELO», \
    prioriza su estructura y epígrafes frente a esta lista genérica. Solo cuerpo del documento.
    """

    /// CarHub compra al particular: el cliente es el vendedor del vehículo.
    private static let systemPromptCompra = """
    ROL: Redactor de borradores de CONTRATO DE COMPRA DE VEHÍCULO USADO en España. EL COMPRADOR es el concesionario \
    «CarHub». EL VENDEDOR del vehículo es el particular (datos del cliente en el formulario).

    AVISO LEGAL (primer bloque): BORRADOR, no asesoramiento jurídico, revisión profesional obligatoria antes de firmar.

    TONO: español de España, formal. Sin markdown.

    ESTRUCTURA distinta a la venta al público:
    1) Lugar y fecha.
    2) REUNIDOS — EL COMPRADOR CarHub [CIF], [domicilio]; EL VENDEDOR particular (nombre, DNI, domicilio del formulario).
    3) EXPONEN — el Vendedor declara ser titular o tener legitimación para enajenar; voluntad de venta; CarHub compra para su actividad.
    4) CLÁUSULAS PRIMERA a OCTAVA:
       PRIMERA objeto: vehículo marca/modelo; identificación [matrícula], [bastidor], [km], [año] con marcadores si faltan.
       SEGUNDA precio de adquisición en EUR (importe acordado a pagar al Vendedor).
       TERCERA forma y plazo de pago al Vendedor [a concretar].
       CUARTA entrega del vehículo, llaves, documentación (permiso, ITV, etc.) y plazo.
       QUINTA estado del vehículo “tal cual”, inspección previa del Comprador, sin garantías del Vendedor salvo las legalmente imperativas.
       SEXTA ausencia de cargas o obligación del Vendedor de levantarlas antes del pago / plazos [marcadores].
       SÉPTIMA transferencia a nombre de CarHub o gestión en tráfico, colaboración del Vendedor.
       OCTAVA RGPD breve, ley española, tribunales, ejemplares.
    5) Firmas.

    REGLAS: no inventar datos. No confundir roles: el particular VENDE, CarHub COMPRA. Si hay texto del PDF modelo en \
    el mensaje del usuario, prioriza su estructura frente a esta plantilla genérica.
    """

    /// Documento de garantía del vehículo (GV), no es compraventa.
    private static let systemPromptGV = """
    ROL: Redactor de borradores de DOCUMENTO DE GARANTÍA DEL VEHÍCULO (GV) en España, emitido en el marco comercial \
    del concesionario «CarHub». No es un contrato de compraventa: es condiciones de garantía para el BENEFICIARIO \
    (el cliente identificado en los datos).

    AVISO (inicio): BORRADOR informativo; la garantía comercial real depende de la póliza/contrato firmado; revisión profesional.

    TONO: claro y formal, español de España. Sin markdown.

    ESTRUCTURA propia de garantía:
    1) Título: DOCUMENTO DE GARANTÍA DEL VEHÍCULO (GV) — CarHub.
    2) Fecha y lugar.
    3) BENEFICIARIO DE LA GARANTÍA: datos del cliente (nombre, DNI, dirección).
    4) VEHÍCULO GARANTIZADO: marca, modelo; [matrícula], [bastidor], [fecha primera matriculación] si no constan.
    5) REFERENCIA DE OPERACIÓN: precio indicado en EUR solo como referencia del contexto comercial, sin redactar como contrato de compra.
    6) ALCANCE: qué cubre la garantía en términos genéricos (defectos de fabricación o mecánica según plan) usando [Duración en meses], \
    [Límite kilométrico], [Tipo de garantía: legal/comercial ampliada] como marcadores si no hay datos.
    7) EXCLUSIONES: desgaste natural, accidentes, mantenimiento incumplido, manipulación no autorizada, competición, etc. (lista prudente).
    8) PROCEDIMIENTO DE RECLAMACIÓN: plazo para comunicar avería [marcador], talleres autorizados [marcador], documentación.
    9) PROTECCIÓN DE DATOS breve.
    10) Ley aplicable y contacto CarHub [marcador].

    REGLAS: no prometer plazos ni coberturas concretas sin datos; usar [marcadores]. No redactar compraventa sustitutiva. \
    Si el usuario incluye el PDF modelo, replica su formato de garantía en primer lugar.
    """

    private static func systemPrompt(for kind: AIContractDocumentKind) -> String {
        switch kind {
        case .venta: return systemPromptVenta
        case .compra: return systemPromptCompra
        case .gv: return systemPromptGV
        }
    }

    static func generateContract(
        kind: AIContractDocumentKind,
        clientName: String,
        clientID: String,
        clientAddress: String,
        vehicleBrand: String,
        vehicleModel: String,
        priceEUR: String
    ) async throws -> String {
        guard let key = apiKey else { throw ClientError.missingAPIKey }

        let templateExcerpt = ContractTemplateLoader.plainText(for: kind)
        let userPrompt = contractUserPrompt(
            kind: kind,
            clientName: clientName,
            clientID: clientID,
            clientAddress: clientAddress,
            vehicleBrand: vehicleBrand,
            vehicleModel: vehicleModel,
            priceEUR: priceEUR,
            templateExcerpt: templateExcerpt
        )

        let system = systemPrompt(for: kind)

        let body = RequestBody(
            model: model,
            max_tokens: 8192,
            system: system,
            messages: [.init(role: "user", content: userPrompt)]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        guard (200 ... 299).contains(http.statusCode) else {
            if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data), let e = env.error {
                throw ClientError.httpStatus(http.statusCode, e.message)
            }
            let snippet = String(data: data, encoding: .utf8)
            throw ClientError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        let text = decoded.content.compactMap { block -> String? in
            guard block.type == "text", let t = block.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
                return nil
            }
            return t
        }.joined(separator: "\n\n")

        if text.isEmpty { throw ClientError.decodingFailed }
        return text
    }

    private static func contractUserPrompt(
        kind: AIContractDocumentKind,
        clientName: String,
        clientID: String,
        clientAddress: String,
        vehicleBrand: String,
        vehicleModel: String,
        priceEUR: String,
        templateExcerpt: String?
    ) -> String {
        let tipo: String
        let roles: String
        switch kind {
        case .venta:
            tipo = "CONTRATO DE VENTA (CarHub vende al cliente)."
            roles = "VENDEDOR: CarHub. COMPRADOR: el cliente con los datos siguientes."
        case .compra:
            tipo = "CONTRATO DE COMPRA (CarHub compra el coche al particular)."
            roles = "COMPRADOR: CarHub. VENDEDOR del vehículo: el particular con los datos siguientes."
        case .gv:
            tipo = "DOCUMENTO GV — GARANTÍA DEL VEHÍCULO (no compraventa)."
            roles = "BENEFICIARIO de la garantía: el cliente con los datos siguientes. Emisor: CarHub."
        }

        var prompt = """
        \(tipo)

        \(roles)

        Datos (usa [marcadores] solo si vinieron vacíos del formulario):

        Nombre: \(clientName)
        DNI/NIE/NIF: \(clientID)
        Dirección: \(clientAddress)
        Vehículo — marca: \(vehicleBrand)
        Vehículo — modelo: \(vehicleModel)
        Importe en EUR (precio operación / referencia): \(priceEUR)

        Fecha del documento: hoy en español, formato largo (ej. «31 de marzo de 2026»).
        """

        if let tpl = templateExcerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !tpl.isEmpty {
            prompt += """

            --- TEXTO EXTRAÍDO DEL PDF MODELO OFICIAL DE LA EMPRESA ---
            Prioridad: reproduce la MISMA estructura (epígrafes, orden de bloques, estilo de numeración de cláusulas) \
            y el mismo registro jurídico que este texto. Sustituye todos los datos variables por los del formulario de arriba. \
            No copies datos personales, matrículas o importes que aparezcan en el modelo si son solo ejemplos de plantilla.

            \(tpl)
            --- FIN DEL MODELO PDF ---
            """
        }

        return prompt
    }
}
