import Foundation
import UIKit

/// Campos que el formulario «Añadir vehículo» guarda (todos opcionales salvo lo que el usuario complete).
struct VehicleVisionFill: Sendable {
    var brand: String?
    var model: String?
    var year: Int?
    var licensePlate: String?
    var priceEUR: Double?
    var mileageKm: Int?
    var fuelType: String?
    var transmission: String?
}

/// Visión OpenAI: misma `OPENAI_API_KEY` / `OPENAI_MODEL` que Viera (xcconfig + Info).
enum OpenAIVehicleVisionClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static func resolvedAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            let t = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !t.hasPrefix("$(") { return t }
        }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.hasPrefix("$(") { return nil }
        return t
    }

    private static var visionModel: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "OPENAI_MODEL") as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !t.hasPrefix("$(") { return t }
        }
        return "gpt-4o-mini"
    }

    static var isConfigured: Bool { resolvedAPIKey() != nil }

    enum VisionError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int, String?)
        case decodingFailed
        case emptyModelReply

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Falta OPENAI_API_KEY. Añádela en DeveloperSettings.local.xcconfig (como para Viera) y recompila."
            case .invalidResponse:
                return "Respuesta inválida del servidor."
            case let .httpStatus(code, msg):
                if let msg, !msg.isEmpty { return "OpenAI (\(code)): \(msg)" }
                return "Error del servicio (\(code))."
            case .decodingFailed:
                return "No se pudo interpretar el JSON del modelo. Revisa la foto o inténtalo de nuevo."
            case .emptyModelReply:
                return "El modelo no devolvió texto. Prueba con otra foto más clara del vehículo."
            }
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct E: Decodable { let message: String? }
        let error: E?
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg?
        }
        let choices: [Choice]?
    }

    private struct VisionRequestBody: Encodable {
        struct RF: Encodable { let type: String }
        struct Msg: Encodable {
            let role: String
            let content: MsgContent
        }

        enum MsgContent: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let s):
                    var c = encoder.singleValueContainer()
                    try c.encode(s)
                case .parts(let arr):
                    var c = encoder.unkeyedContainer()
                    for p in arr {
                        try c.encode(p)
                    }
                }
            }
        }

        struct ContentPart: Encodable {
            let type: String
            let text: String?
            let image_url: ImageURLWrapper?

            struct ImageURLWrapper: Encodable {
                let url: String
            }

            static func text(_ s: String) -> ContentPart {
                ContentPart(type: "text", text: s, image_url: nil)
            }

            static func imageDataURL(_ base64JPEG: String) -> ContentPart {
                ContentPart(
                    type: "image_url",
                    text: nil,
                    image_url: .init(url: "data:image/jpeg;base64,\(base64JPEG)")
                )
            }
        }

        let model: String
        let messages: [Msg]
        let response_format: RF
    }

    static func jpegPayloadForVision(from originalJPEG: Data) -> Data? {
        guard let img = UIImage(data: originalJPEG) else { return nil }
        let maxSide: CGFloat = 1280
        let w = img.size.width
        let h = img.size.height
        let longest = max(w, h)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: max(w * scale, 1), height: max(h * scale, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let drawn = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
        return drawn.jpegData(compressionQuality: 0.78)
    }

    static func inferVehicleFields(fromJPEG jpegData: Data) async throws -> VehicleVisionFill {
        guard let key = resolvedAPIKey() else { throw VisionError.missingAPIKey }
        guard let visionJPEG = jpegPayloadForVision(from: jpegData) else {
            throw VisionError.invalidResponse
        }
        let b64 = visionJPEG.base64EncodedString()

        let systemText = """
        Eres un experto en identificación de automóviles para inventario de concesionario en España. \
        Analizas UNA foto del vehículo. Responde SOLO con JSON válido (sin markdown). \
        Campos que pueden ir null si no es fiable: \
        brand, model, year, license_plate, price_eur, mileage_km, fuel_type, transmission. \
        No inventes matrícula ni precio salvo que se lean claramente. \
        Año entero 1950–2035 si lo estimas por generación. \
        Combustible y transmisión en español corto (Gasolina, Diesel, Eléctrico, Manual, Automático).
        """

        let userText = "Identifica el coche y rellena solo ese JSON."

        let body = VisionRequestBody(
            model: visionModel,
            messages: [
                .init(role: "system", content: .text(systemText)),
                .init(
                    role: "user",
                    content: .parts([
                        .text(userText),
                        .imageDataURL(b64),
                    ])
                ),
            ],
            response_format: .init(type: "json_object")
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VisionError.invalidResponse }

        if !(200 ... 299).contains(http.statusCode) {
            if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
               let m = env.error?.message, !m.isEmpty {
                throw VisionError.httpStatus(http.statusCode, m)
            }
            let snippet = String(data: data, encoding: .utf8)
            throw VisionError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let raw = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw VisionError.emptyModelReply
        }

        guard let jsonData = extractJSONObjectData(from: raw) else {
            throw VisionError.decodingFailed
        }

        return try parseVisionFill(from: jsonData)
    }

    private static func extractJSONObjectData(from text: String) -> Data? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") {
            return String(t[start ... end]).data(using: .utf8)
        }
        return t.data(using: .utf8)
    }

    private static func parseVisionFill(from jsonData: Data) throws -> VehicleVisionFill {
        guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw VisionError.decodingFailed
        }

        func trimmedString(_ key: String) -> String? {
            guard let v = obj[key] else { return nil }
            if v is NSNull { return nil }
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            let t = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        func intValue(_ key: String) -> Int? {
            guard let v = obj[key], !(v is NSNull) else { return nil }
            if let i = v as? Int { return i }
            if let d = v as? Double { return Int(d) }
            if let s = v as? String {
                let digits = s.filter { $0.isNumber }
                if digits.isEmpty { return nil }
                return Int(digits)
            }
            return nil
        }

        func doubleValue(_ key: String) -> Double? {
            guard let v = obj[key], !(v is NSNull) else { return nil }
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String {
                let normalized = s
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                    .filter { "0123456789.".contains($0) }
                return Double(normalized)
            }
            return nil
        }

        var year = intValue("year") ?? intValue("año")
        if let y = year, !(1950 ... 2035).contains(y) { year = nil }

        return VehicleVisionFill(
            brand: trimmedString("brand") ?? trimmedString("marca") ?? trimmedString("make"),
            model: trimmedString("model") ?? trimmedString("modelo"),
            year: year,
            licensePlate: trimmedString("license_plate") ?? trimmedString("matricula"),
            priceEUR: doubleValue("price_eur") ?? doubleValue("precio_eur"),
            mileageKm: intValue("mileage_km") ?? intValue("kilometraje") ?? intValue("kilometers"),
            fuelType: trimmedString("fuel_type") ?? trimmedString("combustible") ?? trimmedString("fuel"),
            transmission: trimmedString("transmission") ?? trimmedString("transmision")
        )
    }
}
