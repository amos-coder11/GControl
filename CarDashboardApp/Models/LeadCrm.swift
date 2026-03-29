import Foundation
import Supabase

/// Fila de `public.leads_crm`. Mapeo flexible de columnas (igual criterio que `LeadCrmDto` en Flutter).
struct LeadCrm: Identifiable, Hashable, Sendable {
    let id: String
    var name: String?
    var email: String?
    var phone: String?
    var company: String?
    var status: String?
    var source: String?
    var notes: String?
    var createdAt: String?

    var title: String {
        if let name, !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        if let phone, !phone.isEmpty { return phone }
        return "Lead \(id)"
    }

    var subtitle: String {
        var parts: [String] = []
        if let company, !company.isEmpty { parts.append(company) }
        if let email, !email.isEmpty { parts.append(email) }
        if let phone, !phone.isEmpty { parts.append(phone) }
        if let status, !status.isEmpty { parts.append(status) }
        if let source, !source.isEmpty { parts.append(source) }
        var seen = Set<String>()
        var dedup: [String] = []
        for p in parts {
            if p == title { continue }
            if seen.contains(p) { continue }
            seen.insert(p)
            dedup.append(p)
        }
        return dedup.joined(separator: " · ")
    }

    init?(json: JSONObject) {
        guard let idRaw = json["id"] else { return nil }
        let idStr = Self.scalarString(idRaw) ?? ""
        if idStr.isEmpty { return nil }
        id = idStr

        name = Self.firstString(json, [
            "name", "full_name", "contact_name", "lead_name", "nombre", "title", "subject",
        ])
        email = Self.firstString(json, ["email", "correo", "email_address"])
        phone = Self.firstString(json, ["phone", "telefono", "phone_number", "mobile", "tel"])
        company = Self.firstString(json, ["company", "empresa", "organization", "business_name"])
        status = Self.firstString(json, ["status", "estado", "stage", "pipeline_stage"])
        source = Self.firstString(json, ["source", "origin", "origen", "lead_source"])
        notes = Self.firstString(json, ["notes", "description", "notas", "message", "comentarios"])

        createdAt = Self.firstString(json, ["created_at", "inserted_at", "updated_at"])
    }

    private static func firstString(_ json: JSONObject, _ keys: [String]) -> String? {
        for k in keys {
            guard let v = json[k] else { continue }
            if let s = scalarString(v), !s.isEmpty { return s }
        }
        return nil
    }

    private static func scalarString(_ v: AnyJSON) -> String? {
        switch v {
        case let .string(s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let .integer(i):
            return String(i)
        case let .double(d):
            if d.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(d)) }
            return String(d)
        case let .bool(b):
            return b ? "true" : "false"
        default:
            return nil
        }
    }
}
