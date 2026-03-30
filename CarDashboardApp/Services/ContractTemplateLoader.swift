import Foundation
import PDFKit

/// Carga los PDF de `Resources/ContractTemplates` y extrae texto para usarlo como modelo en el prompt de Claude.
enum ContractTemplateLoader {
    private static let maxCharacters = 28_000

    private static func resourceBaseName(for kind: AIContractDocumentKind) -> String {
        switch kind {
        case .venta: return "ContratoVentaModelo"
        case .compra: return "ContratoCompraModelo"
        case .gv: return "GarantiaGVModelo"
        }
    }

    /// Texto plano del PDF modelo; `nil` si no hay bundle, fallo de lectura o PDF sin capa de texto (escaneado).
    static func plainText(for kind: AIContractDocumentKind) -> String? {
        let base = resourceBaseName(for: kind)
        guard let url = Bundle.main.url(forResource: base, withExtension: "pdf") else { return nil }
        guard let document = PDFDocument(url: url) else { return nil }

        var parts: [String] = []
        parts.reserveCapacity(document.pageCount)
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            guard let s = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
            parts.append(s)
        }

        let full = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return nil }

        if full.count > maxCharacters {
            let end = full.index(full.startIndex, offsetBy: maxCharacters)
            return String(full[..<end]) + "\n\n[… Texto del modelo truncado por límite técnico …]"
        }
        return full
    }
}
