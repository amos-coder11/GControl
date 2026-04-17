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

// MARK: - OpenAI (pestaña IA · Chat Completions)

/// Chat Viera vía OpenAI. Claves: `OPENAI_API_KEY`, opcional `OPENAI_MODEL` en Info (xcconfig).
enum OpenAIChatClient {
    private static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static var openAIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static var openAIModel: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "OPENAI_MODEL") as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "gpt-4o-mini"
    }

    static var isConfigured: Bool { openAIKey != nil }

    enum OpenAIError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int, String?)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Falta OPENAI_API_KEY. Configúrala en DeveloperSettings.local.xcconfig."
            case .invalidResponse:
                return "Respuesta inválida del servidor."
            case let .httpStatus(code, msg):
                if let msg, !msg.isEmpty { return "Error \(code): \(msg)" }
                return "Error del servicio (\(code))."
            case .decodingFailed:
                return "No se pudo leer la respuesta de OpenAI."
            }
        }
    }

    private struct OpenAIChatMessageDTO: Encodable {
        let role: String
        let content: String
    }

    private struct OpenAINonStreamRequestBody: Encodable {
        let model: String
        let messages: [OpenAIChatMessageDTO]
    }

    private struct OpenAIStreamRequestBody: Encodable {
        let model: String
        let messages: [OpenAIChatMessageDTO]
        let stream: Bool
    }

    private struct OpenAIStreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        let choices: [Choice]?
    }

    private struct OpenAIStreamErrorEnvelope: Decodable {
        struct Err: Decodable {
            let message: String?
        }

        let error: Err?
    }

    private static let vieraSystemPrompt = """
    Eres Viera, asistente de IA de la app CarHub (concesionario / gestión de vehículos en España). \
    Hablas en español con tono claro, profesional y elegante, como en una app de chat de primera calidad: fluido, directo y agradable de leer.

    FORMATO DE SALIDA (obligatorio): la app muestra texto plano, sin motor Markdown. \
    NUNCA uses sintaxis Markdown ni caracteres que la interfaz no interprete: \
    no asteriscos para negrita o cursiva (** * __ _), no almohadillas (#), no guiones de lista tipo "- item" en bloques densos, \
    no tablas, no bloques de código con cercos. Si quieres destacar algo, hazlo con la redacción (orden de palabras, una frase corta al inicio), no con símbolos.

    Prioriza párrafos continuos con buen ritmo; separa ideas con una línea en blanco entre párrafos. \
    Evita listas largas con muchos puntos numerados salvo que el usuario pida explícitamente una enumeración; \
    aun así, mantén cada ítem en una o dos frases simples, sin etiquetas entre asteriscos. \
    Cuando el usuario pida "punto por punto", responde con claridad pero sin aspecto de documento técnico: frases completas, tono natural.

    Puedes ayudar con: coches y stock, ventas, documentación básica, mensajes para clientes, resúmenes. \
    No inventes datos legales ni financieros concretos; indica contrastar con el equipo si hace falta.

    Emojis con mucha moderación (como mucho uno cada varias frases); nunca sustituyas información clave solo con iconos.
    """

    /// Si el bloque de datos de la app va vacío, no añadimos esta parte (el modelo no tendría UUID reales).
    private static let vieraStructuredCardsInstruction = """
    Cuando el usuario pida enviar una tarea al equipo comercial, asignar compañeros, avisar a ventas, o cuando cites \
    vehículos concretos del inventario que aparecen en los datos de referencia, al terminar tu respuesta en texto plano \
    para el usuario añade ÚNICAMENTE al final (sin texto después) este bloque literal para que la app muestre fotos:

    <<<VIERA_CARDS
    {"team":["uuid-en-minúsculas",...],"cars":["uuid-en-minúsculas",...]}
    >>>

    Reglas: "team" y "cars" son arrays opcionales de strings UUID exactamente como en la lista de referencia (minúsculas). \
    Omite una clave si no aplica. Si no corresponde mostrar fichas, no escribas el bloque. No expliques el bloque al usuario.

    Siempre que hables de vehículos concretos de la lista de inventario (por matrícula, marca y modelo o nombre), \
    incluye sus id en "cars" para que la app muestre la tarjeta con foto.

    Si el usuario quiere enviar una oferta, resumen comercial o que un compañero gestione el cliente, \
    incluye en "team" el UUID del comercial indicado en COMERCIAL_DEL_EQUIPO_SUGERIDO o el que el usuario nombre del listado EQUIPO, \
    y en "cars" los vehículos implicados. Si nombra a una persona concreta del listado EQUIPO, incluye solo su user_id en "team". \
    Si habla de «todo el equipo» o similar, puedes omitir "team" o listar varios: la app mostrará a todo el equipo y el usuario elegirá destinatario y coche. \
    En la app se rellena el horario si lo dijo en el chat; el comercial recibe tarea por pasos con foto del vehículo.
    """

    private struct OpenAIChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable {
                let content: String?
            }

            let message: Msg?
        }

        let choices: [Choice]?
    }

    private struct OpenAIAPIErrorEnvelope: Decodable {
        struct APIErr: Decodable {
            let message: String?
        }

        let error: APIErr?
    }

    private static func openAIMessages(
        for conversation: [(isUser: Bool, text: String)],
        dataContextSupplement: String?
    ) -> [OpenAIChatMessageDTO] {
        var systemContent = vieraSystemPrompt
        if let raw = dataContextSupplement?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            systemContent += """

            ---
            \(raw)

            \(vieraStructuredCardsInstruction)
            """
        }
        var messages: [OpenAIChatMessageDTO] = [
            OpenAIChatMessageDTO(role: "system", content: systemContent),
        ]
        for turn in conversation {
            messages.append(
                OpenAIChatMessageDTO(role: turn.isUser ? "user" : "assistant", content: turn.text)
            )
        }
        return messages
    }

    /// Respuesta en streaming (SSE). `onChunk` se llama por cada trozo de texto en el orden correcto.
    /// `dataContextSupplement`: listado equipo + coches; si es nil o vacío, no se pide el bloque de tarjetas.
    static func streamVieraChatReply(
        conversation: [(isUser: Bool, text: String)],
        dataContextSupplement: String?,
        onChunk: @escaping (String) async -> Void
    ) async throws {
        guard let key = openAIKey else { throw OpenAIError.missingAPIKey }

        let messages = openAIMessages(for: conversation, dataContextSupplement: dataContextSupplement)
        let body = OpenAIStreamRequestBody(model: openAIModel, messages: messages, stream: true)
        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        if !(200 ... 299).contains(http.statusCode) {
            var err = Data()
            err.reserveCapacity(4096)
            for try await b in bytes {
                err.append(b)
                if err.count >= 8192 { break }
            }
            let snippet = String(data: err, encoding: .utf8)
            if let d = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: err),
               let m = d.error?.message, !m.isEmpty {
                throw OpenAIError.httpStatus(http.statusCode, m)
            }
            throw OpenAIError.httpStatus(http.statusCode, snippet)
        }

        try await readOpenAISSEStream(bytes) { piece in
            await onChunk(piece)
        }
    }

    private static func readOpenAISSEStream(
        _ bytes: URLSession.AsyncBytes,
        onDelta: @escaping (String) async -> Void
    ) async throws {
        var lineBytes: [UInt8] = []
        lineBytes.reserveCapacity(256)

        for try await byte in bytes {
            if byte == 10 {
                guard !lineBytes.isEmpty else { continue }
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)

                guard line.hasPrefix("data:") else { continue }
                let rest = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if rest == "[DONE]" { return }
                guard let data = rest.data(using: .utf8) else { continue }

                if let env = try? JSONDecoder().decode(OpenAIStreamErrorEnvelope.self, from: data),
                   let msg = env.error?.message, !msg.isEmpty {
                    throw OpenAIError.httpStatus(0, msg)
                }

                guard let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                      let piece = chunk.choices?.first?.delta?.content,
                      !piece.isEmpty
                else { continue }

                await onDelta(piece)
            } else if byte != 13 {
                lineBytes.append(byte)
            }
        }
    }

    static func vieraChatReply(conversation: [(isUser: Bool, text: String)]) async throws -> String {
        guard let key = openAIKey else { throw OpenAIError.missingAPIKey }

        let messages = openAIMessages(for: conversation, dataContextSupplement: nil)
        let body = OpenAINonStreamRequestBody(model: openAIModel, messages: messages)
        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        guard (200 ... 299).contains(http.statusCode) else {
            if let env = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data),
               let m = env.error?.message, !m.isEmpty {
                throw OpenAIError.httpStatus(http.statusCode, m)
            }
            let snippet = String(data: data, encoding: .utf8)
            throw OpenAIError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let text = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if text.isEmpty { throw OpenAIError.decodingFailed }
        return text
    }

    private static let vehicleListingSystemPrompt = """
    Eres redactor de anuncios de vehículos de ocasión para concesionarios en España.
    Redactas en español, tono profesional, cercano y claro, sin exagerar ni prometer garantías no indicadas en los datos.

    FORMATO DE SALIDA (obligatorio): texto plano únicamente. La app no interpreta Markdown.
    No uses asteriscos, almohadillas, tablas, ni listas densas con guiones. Separa ideas con párrafos y una línea en blanco entre ellos.
    Entre 2 y 5 párrafos según la cantidad de datos útiles.

    REGLAS:
    - Solo afirma hechos que consten explícitamente en el bloque de datos. Si falta algo relevante, no lo inventes.
    - No incluyas en el anuncio datos personales del dueño (nombre, teléfono, email) ni precios de compra.
    - Puedes mencionar el precio de venta al contado solo si aparece en los datos como «precio venta» o similar.
    - Menciona equipamiento destacado solo si aparece listado en los datos.
    - Si el bloque está muy vacío, redacta un párrafo breve invitando a contactar para más información, sin inventar especificaciones.
    """

    /// Borrador de descripción de anuncio a partir de hechos estructurados (texto plano).
    static func generateVehicleListingDescription(factsBlock: String) async throws -> String {
        guard let key = openAIKey else { throw OpenAIError.missingAPIKey }

        let trimmed = factsBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        let userContent: String
        if trimmed.isEmpty {
            userContent = "No hay datos estructurados. Escribe un párrafo muy breve genérico invitando a solicitar información del vehículo en el concesionario, sin inventar marca ni modelo."
        } else {
            userContent = """
            Datos del vehículo y del formulario (usa solo lo que consta; ignora líneas vacías o «no indicado»):

            \(trimmed)
            """
        }

        let messages = [
            OpenAIChatMessageDTO(role: "system", content: vehicleListingSystemPrompt),
            OpenAIChatMessageDTO(role: "user", content: userContent),
        ]
        let body = OpenAINonStreamRequestBody(model: openAIModel, messages: messages)
        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        guard (200 ... 299).contains(http.statusCode) else {
            if let env = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data),
               let m = env.error?.message, !m.isEmpty {
                throw OpenAIError.httpStatus(http.statusCode, m)
            }
            let snippet = String(data: data, encoding: .utf8)
            throw OpenAIError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let text = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if text.isEmpty { throw OpenAIError.decodingFailed }
        return text
    }
}
