import SwiftUI
import UIKit

/// Genera el PDF del presupuesto que se comparte por WhatsApp o email.
enum GrooClinicBudgetPDFGenerator {

    private static let pageSize = CGSize(width: 595, height: 842) // A4 a 72 dpi
    private static let margin: CGFloat = 48

    static func generatePDF(from draft: GrooPatientBudgetDraft) -> URL? {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize)
        )

        let safeName = draft.patient.fullName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileName = "Presupuesto-\(safeName.isEmpty ? "paciente" : safeName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                draw(draft: draft)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Dibujo

    private static func draw(draft: GrooPatientBudgetDraft) {
        var y: CGFloat = margin

        y = drawHeader(draft: draft, at: y)
        y += 12
        y = drawPatient(draft: draft, at: y)
        y += 20
        y = drawLineItems(draft: draft, at: y)
        y += 16
        y = drawTotals(draft: draft, at: y)

        if !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            y += 20
            drawText("Notas", at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 13))
            y += 18
            drawText(
                draft.notes,
                at: CGPoint(x: margin, y: y),
                font: .systemFont(ofSize: 11),
                color: .darkGray,
                maxWidth: pageSize.width - margin * 2
            )
        }

        drawText(
            "Documento generado con \(draft.clinicName)",
            at: CGPoint(x: margin, y: pageSize.height - margin),
            font: .systemFont(ofSize: 9),
            color: .lightGray
        )
    }

    private static func drawHeader(draft: GrooPatientBudgetDraft, at y: CGFloat) -> CGFloat {
        var cursor = y
        drawText(
            draft.clinicName,
            at: CGPoint(x: margin, y: cursor),
            font: .boldSystemFont(ofSize: 24)
        )
        cursor += 30

        if !draft.professionalName.isEmpty {
            drawText(
                draft.professionalName,
                at: CGPoint(x: margin, y: cursor),
                font: .systemFont(ofSize: 12),
                color: .darkGray
            )
            cursor += 18
        }

        drawText(
            "Presupuesto · \(shortDate(draft.issueDate))",
            at: CGPoint(x: margin, y: cursor),
            font: .systemFont(ofSize: 12),
            color: .darkGray
        )
        cursor += 18

        drawText(
            "Válido hasta \(shortDate(draft.validUntil))",
            at: CGPoint(x: margin, y: cursor),
            font: .systemFont(ofSize: 12),
            color: .darkGray
        )
        return cursor + 18
    }

    private static func drawPatient(draft: GrooPatientBudgetDraft, at y: CGFloat) -> CGFloat {
        var cursor = y
        drawSeparator(at: cursor)
        cursor += 14

        drawText("Paciente", at: CGPoint(x: margin, y: cursor), font: .boldSystemFont(ofSize: 13))
        cursor += 20
        drawText(draft.patient.fullName, at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 12))
        cursor += 16

        if !draft.patient.phone.isEmpty {
            drawText(draft.patient.phone, at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 12), color: .darkGray)
            cursor += 16
        }
        return cursor
    }

    private static func drawLineItems(draft: GrooPatientBudgetDraft, at y: CGFloat) -> CGFloat {
        var cursor = y
        drawSeparator(at: cursor)
        cursor += 14

        let priceX = pageSize.width - margin - 80
        let qtyX = priceX - 60

        drawText("Concepto", at: CGPoint(x: margin, y: cursor), font: .boldSystemFont(ofSize: 11), color: .gray)
        drawText("Cant.", at: CGPoint(x: qtyX, y: cursor), font: .boldSystemFont(ofSize: 11), color: .gray)
        drawText("Total", at: CGPoint(x: priceX, y: cursor), font: .boldSystemFont(ofSize: 11), color: .gray)
        cursor += 20

        for item in draft.lineItems {
            drawText(item.title, at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 12))
            drawText("\(item.quantity)", at: CGPoint(x: qtyX, y: cursor), font: .systemFont(ofSize: 12))
            drawText(
                GrooCurrencyFormat.format(item.total),
                at: CGPoint(x: priceX, y: cursor),
                font: .boldSystemFont(ofSize: 12)
            )
            cursor += 16

            if !item.detail.isEmpty {
                drawText(
                    item.detail,
                    at: CGPoint(x: margin, y: cursor),
                    font: .systemFont(ofSize: 10),
                    color: .gray
                )
                cursor += 14
            }
            cursor += 4
        }
        return cursor
    }

    private static func drawTotals(draft: GrooPatientBudgetDraft, at y: CGFloat) -> CGFloat {
        var cursor = y
        drawSeparator(at: cursor)
        cursor += 14

        let labelX = pageSize.width - margin - 220
        let valueX = pageSize.width - margin - 80

        func row(_ label: String, _ value: Double, bold: Bool = false) {
            let font: UIFont = bold ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 12)
            drawText(label, at: CGPoint(x: labelX, y: cursor), font: font, color: bold ? .black : .darkGray)
            drawText(GrooCurrencyFormat.format(value), at: CGPoint(x: valueX, y: cursor), font: font)
            cursor += bold ? 22 : 18
        }

        row("Subtotal", draft.subtotal)
        if draft.historicalPending > 0.01 {
            row("Saldo anterior", draft.historicalPending)
        }
        if draft.alreadyPaid > 0.01 {
            row("Ya abonado", draft.alreadyPaid)
        }
        row("Total a pagar", draft.totalBudget, bold: true)
        return cursor
    }

    // MARK: - Utilidades

    private static func drawSeparator(at y: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        UIColor.systemGray4.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor = .black,
        maxWidth: CGFloat? = nil
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        if let maxWidth {
            let rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: 200)
            text.draw(with: rect, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        } else {
            text.draw(at: point, withAttributes: attributes)
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

/// Hoja nativa de compartir para el PDF generado.
struct GrooSharePDFSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
