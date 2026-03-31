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
    ROL: Generador de cuerpo de CONTRATO DE VENTA en España. EL VENDEDOR es «CarHub». EL COMPRADOR es el particular.

    IMPORTANTE: La aplicación genera AUTOMÁTICAMENTE el encabezado (logo, título, fecha), REUNIDOS, tabla de datos del vehículo \
    y líneas de firma. Tú SOLO debes generar el TEXTO DEL CONTRATO a partir de la sección «EXPONEN:» hasta el final.

    TONO: español formal, tercera persona, sin markdown ni emojis.

    ESTRUCTURA (SOLO desde EXPONEN):
    1) "EXPONEN:" — ambas partes acuerdan formalizar la venta, características del vehículo (rellenadas por tabla)
    2) Punto 2: Vendedor declara vehículo en buen estado, km reales, sin daños estructurales, sin defectos ocultos, toda documentación, \
    libre de cargas (si no, se considera fraude)
    3) Punto 3: ITV revisada con resultado FAVORABLE, próxima ITV antes de [marcador fecha]
    4) Punto 4: ambas partes tienen capacidad legal, Vendedor aportará documentación para transferencia de titularidad
    5) Punto 5: precio acordado en #[precio]€#, forma de pago: [precio]€ MEDIANTE TRANSFERENCIA BANCARIA A CUENTA [marcador]
    6) Punto 6: jurisdicción juzgados de Madrid
    7) Luego: ANEXOS CLÁUSULA EN ACUERDOS O CONTRATOS SUSCRITOS CON CLIENTES (RGPD completo, ley UE 2016/679, Ley Orgánica 3/2018 \
    con toda la normativa sobre derechos, confidencialidad, etc.)

    REGLAS: no inventar matrícula, bastidor, km. NO incluyas encabezado, fecha, REUNIDOS ni tabla de vehículo. Solo texto desde EXPONEN.
    """

    /// CarHub compra al particular: el cliente es el vendedor del vehículo.
    private static let systemPromptCompra = """
    ROL: Generador de cuerpo de CONTRATO DE COMPRA DE VEHÍCULO USADO en España. EL COMPRADOR es «CarHub». \
    EL VENDEDOR es el particular.

    IMPORTANTE: La aplicación genera AUTOMÁTICAMENTE el encabezado (logo, título, fecha), REUNIDOS, tabla de datos del vehículo \
    y líneas de firma. Tú SOLO debes generar el TEXTO DEL CONTRATO a partir de «EXPONEN» hasta el final.

    TONO: español formal, sin markdown, sin emojis.

    ESTRUCTURA (SOLO desde EXPONEN):
    1) “EXPONEN” — ambas partes acuerdan formalizar la compraventa
    2) “Si presenta desperfectos de pintura, especificar las piezas a continuación:” [línea de marcador]
    3) Encabezado “CONDICIONES”
    4) Cláusulas PRIMERA a SÉPTIMA:
       PRIMERA: Vendedor declara ser titular del vehículo, en buen estado, aportará documentación
       SEGUNDA: km reales, vehículo libre de cargas y deudas
       TERCERA: Vendedor aportará documentación y firmará para transferencia de titularidad
       CUARTA: Sin daños estructurales ni defectos ocultos; si se encuentran, Vendedor reembolsa cantidad adelantada + gastos + \
       mitad comisión
       QUINTA: ITV favorable, próxima ITV antes de [marcador fecha]
       SEXTA: Inicialmente anticipo de [precio]€, resto en venta según precio final
       SÉPTIMA: Jurisdicción juzgados Madrid / Alcalá de Henares
    5) Párrafo de pago: “El pago del precio se realiza por el comprador al vendedor del siguiente modo: [precio]€”
    6) Checklist de documentación: Ficha técnica: SI, Permiso de circulación: SI, Número de llaves: 2, Libro de revisiones: DIGITAL
    7) “CONDICIONES DE LA GESTIÓN DE VENTA DEL VEHICULO:” con su propio EXPONEN
    8) Puntos 1º a 12º: precio inicial, comisión, cuota mensual (100€), autorización cambio titularidad, condiciones rescisión, \
    consulta oferta, aceptación irrevocable, objetos personales, seguros, exclusividad, pago tras venta, autorización inspección
    9) Cierre: ambas partes reconocen capacidad legal, jurisdicción juzgados Madrid

    REGLAS: No inventar datos. NO incluyas encabezado, fecha, REUNIDOS ni tabla de vehículo. Solo texto desde EXPONEN.
    """

    /// Documento de garantía del vehículo (GV), no es compraventa.
    private static let systemPromptGV = """
    ROL: Generador de cuerpo de DOCUMENTO DE GARANTÍA DEL VEHÍCULO (GV) en España, emitido por «CarHub». \
    No es contrato de compraventa: son condiciones de garantía.

    IMPORTANTE: La aplicación genera AUTOMÁTICAMENTE el encabezado (logo, título, fecha), REUNIDOS, tabla de datos del vehículo \
    y líneas de firma. Tú SOLO debes generar el TEXTO DEL CONTRATO a partir de «EXPONEN» hasta el final.

    TONO: formal, español de España. Sin markdown.

    ESTRUCTURA (SOLO desde EXPONEN):
    1) "EXPONEN" — encabezado
    2) Puntos I–VI:
       I: ambas partes acuerdan formalizar la venta y garantía legal
       II: estado vehículo, elementos, componentes, antigüedad, km en anexo
       III: comprador ha examinado y probado el vehículo, acepta condiciones
       IV: ITV revisada FAVORABLE, próxima ITV antes de [marcador fecha]
       V: AC CAR certifica vehículo entregado libre de cargas
       VI: ambas partes tienen capacidad legal
    3) "ESTIPULACIONES" — encabezado
    4) Cláusulas PRIMERA–DÉCIMA:
       PRIMERA: precio acordado #[precio]€#, pago por transferencia
       SEGUNDA: entrega vehículo, comprador responsable desde esta fecha
       TERCERA: período garantía legal 12 meses
       CUARTA: derechos consumidor per ley protección consumidor
       QUINTA: derecho reparación en caso no-conformidad
       SEXTA: comprador debe reportar no-conformidad dentro 2 semanas
       SÉPTIMA: vendedor determina método reparación y taller, puede usar piezas recondicionadas
       OCTAVA: lista exclusiones (desgaste normal, mal uso, reparaciones no autorizadas, etc.)
       DÉCIMA: procedimiento reclamaciones (notificación 24h, AC CAR decide taller)
    5) "EXCLUSIONES" — encabezado con lista detallada:
       - Elementos desgaste normal (correas, neumáticos, frenos, batería, etc.)
       - Componentes interiores (asientos, salpicadero, etc.)
       - Operaciones mantenimiento preventivo
       - Consumibles (bujías, filtros, limpiaparabrisas, fluidos, etc.)
       - Partes carrocería y accesorios
       - Reparaciones inadecuadas o negligencia
       - Reparaciones temporales asistencia carretera
       - Cuentakilómetros manipulados
       - Defectos fabricación (cubiertos por fabricante)
       - Combustible incorrecto
       - Costos verificación/desmontaje
       - Trabajo taller no autorizado
       - Ajustes desgaste normal/holgura
       - Piezas no homologadas
       - Condiciones alteradas impidiendo verificación causa
       - Declaraciones falsas
       - Reparaciones previas malas
       - Responsabilidad civil
       - Mantenimiento desgaste antigüedad/km normal
    6) ANEXOS CLÁUSULA EN ACUERDOS O CONTRATOS SUSCRITOS CON CLIENTES (RGPD: Reglamento UE 2016/679, \
    Ley Orgánica 3/2018 con toda cláusula normativa sobre derechos, confidencialidad, etc.)

    REGLAS: No inventar datos. NO incluyas encabezado, fecha, REUNIDOS ni tabla de vehículo. Solo texto desde EXPONEN.
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

        Genera SOLO el cuerpo del contrato desde la sección EXPONEN en adelante. NO incluyas encabezado, título, \
        fecha, REUNIDOS, tabla de datos del vehículo ni líneas de firma, ya que esos elementos se generan \
        automáticamente por la aplicación.
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
