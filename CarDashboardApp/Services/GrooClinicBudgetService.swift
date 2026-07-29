import SwiftUI
import UIKit

// MARK: - Formato monetario (español, legible)

enum GrooCurrencyFormat {
    private static let money: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        return f
    }()

    /// Ej: `$ 1.250,00`
    static func format(_ amount: Double) -> String {
        "$ \(plain(amount))"
    }

    static func plain(_ amount: Double) -> String {
        money.string(from: NSNumber(value: amount)) ?? "0,00"
    }
}

// MARK: - Presupuesto

struct GrooBudgetLineItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var quantity: Int
    var unitPrice: Double

    var total: Double { Double(max(quantity, 1)) * unitPrice }
}

struct GrooPatientBudgetDraft: Equatable {
    var patient: GrooPatient
    var clinicName: String
    var professionalName: String
    var issueDate: Date
    var validUntil: Date
    var lineItems: [GrooBudgetLineItem]
    var notes: String
    var alreadyPaid: Double
    var historicalPending: Double

    var subtotal: Double { lineItems.reduce(0) { $0 + $1.total } }
    var totalBudget: Double { subtotal }
    var balanceAfterPaid: Double { max(0, totalBudget - alreadyPaid) }
}

// MARK: - PDF

enum GrooClinicBudgetPDFGenerator {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let margin: CGFloat = 48
    private static let contentWidth: CGFloat = 595 - 96

    static func generatePDF(from draft: GrooPatientBudgetDraft) -> URL? {
        let pdfMeta = [
            kCGPDFContextTitle: "Presupuesto \(draft.patient.fullName)",
            kCGPDFContextAuthor: draft.clinicName,
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = pdfMeta as [String: Any]
            return f
        }())

        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin
            y = drawHeader(draft: draft, y: y)
            y = drawPatientBlock(draft: draft, y: y + 16)
            y = drawTable(draft: draft, y: y + 20)
            y = drawTotals(draft: draft, y: y + 24)
            _ = drawFooter(draft: draft, y: y + 20)
        }

        let safeName = draft.patient.fullName
            .replacingOccurrences(of: " ", with: "_")
            .folding(options: .diacriticInsensitive, locale: .current)
        let fileName = "Presupuesto_\(safeName)_\(Int(draft.issueDate.timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func drawHeader(draft: GrooPatientBudgetDraft, y: CGFloat) -> CGFloat {
        let brand = draft.clinicName
        drawText(brand, rect: CGRect(x: margin, y: y, width: contentWidth, height: 28), font: .boldSystemFont(ofSize: 22), color: UIColor(red: 0.35, green: 0.54, blue: 0.98, alpha: 1))
        drawText("PRESUPUESTO CLÍNICO", rect: CGRect(x: margin, y: y + 30, width: contentWidth, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: .darkGray)
        let dateStr = draft.issueDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es_ES")))
        drawText("Fecha: \(dateStr)", rect: CGRect(x: margin, y: y + 50, width: contentWidth, height: 16), font: .systemFont(ofSize: 11), color: .gray)
        let validStr = draft.validUntil.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es_ES")))
        drawText("Válido hasta: \(validStr)", rect: CGRect(x: margin, y: y + 66, width: contentWidth, height: 16), font: .systemFont(ofSize: 11), color: .gray)
        return y + 88
    }

    private static func drawPatientBlock(draft: GrooPatientBudgetDraft, y: CGFloat) -> CGFloat {
        fillRect(CGRect(x: margin, y: y, width: contentWidth, height: 88), color: UIColor(white: 0.97, alpha: 1), radius: 8)
        var innerY = y + 12
        drawText("Paciente", rect: CGRect(x: margin + 14, y: innerY, width: 120, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: .gray)
        drawText(draft.patient.fullName, rect: CGRect(x: margin + 14, y: innerY + 14, width: contentWidth - 28, height: 18), font: .boldSystemFont(ofSize: 15), color: .black)
        innerY += 36
        drawText("Tel: \(draft.patient.phone)", rect: CGRect(x: margin + 14, y: innerY, width: contentWidth * 0.5, height: 14), font: .systemFont(ofSize: 11), color: .darkGray)
        if let email = draft.patient.email, !email.isEmpty {
            drawText("Email: \(email)", rect: CGRect(x: margin + 14 + contentWidth * 0.48, y: innerY, width: contentWidth * 0.48, height: 14), font: .systemFont(ofSize: 11), color: .darkGray)
        }
        innerY += 18
        drawText("Tratamiento: \(draft.patient.treatment)", rect: CGRect(x: margin + 14, y: innerY, width: contentWidth - 28, height: 14), font: .systemFont(ofSize: 11), color: .darkGray)
        return y + 88
    }

    private static func drawTable(draft: GrooPatientBudgetDraft, y: CGFloat) -> CGFloat {
        let colConcept: CGFloat = contentWidth * 0.46
        let colQty: CGFloat = 50
        let colUnit: CGFloat = 100
        let colTotal: CGFloat = contentWidth - colConcept - colQty - colUnit
        let headerH: CGFloat = 28
        fillRect(CGRect(x: margin, y: y, width: contentWidth, height: headerH), color: UIColor(red: 0.35, green: 0.54, blue: 0.98, alpha: 1), radius: 6)
        drawText("Concepto", rect: CGRect(x: margin + 10, y: y + 7, width: colConcept, height: 16), font: .boldSystemFont(ofSize: 11), color: .white)
        drawText("Cant.", rect: CGRect(x: margin + colConcept, y: y + 7, width: colQty, height: 16), font: .boldSystemFont(ofSize: 11), color: .white, alignment: .center)
        drawText("Precio", rect: CGRect(x: margin + colConcept + colQty, y: y + 7, width: colUnit, height: 16), font: .boldSystemFont(ofSize: 11), color: .white, alignment: .right)
        drawText("Total", rect: CGRect(x: margin + colConcept + colQty + colUnit, y: y + 7, width: colTotal - 10, height: 16), font: .boldSystemFont(ofSize: 11), color: .white, alignment: .right)

        var rowY = y + headerH
        for (index, item) in draft.lineItems.enumerated() {
            let rowH: CGFloat = item.detail.isEmpty ? 32 : 44
            if index % 2 == 0 {
                fillRect(CGRect(x: margin, y: rowY, width: contentWidth, height: rowH), color: UIColor(white: 0.98, alpha: 1), radius: 0)
            }
            drawText(item.title, rect: CGRect(x: margin + 10, y: rowY + 8, width: colConcept - 12, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: .black)
            if !item.detail.isEmpty {
                drawText(item.detail, rect: CGRect(x: margin + 10, y: rowY + 24, width: colConcept - 12, height: 14), font: .systemFont(ofSize: 9), color: .gray)
            }
            drawText("\(item.quantity)", rect: CGRect(x: margin + colConcept, y: rowY + 10, width: colQty, height: 16), font: .systemFont(ofSize: 11), color: .black, alignment: .center)
            drawText(GrooCurrencyFormat.format(item.unitPrice), rect: CGRect(x: margin + colConcept + colQty, y: rowY + 10, width: colUnit - 6, height: 16), font: .systemFont(ofSize: 11), color: .black, alignment: .right)
            drawText(GrooCurrencyFormat.format(item.total), rect: CGRect(x: margin + colConcept + colQty + colUnit, y: rowY + 10, width: colTotal - 10, height: 16), font: .boldSystemFont(ofSize: 11), color: .black, alignment: .right)
            rowY += rowH
        }
        return rowY
    }

    private static func drawTotals(draft: GrooPatientBudgetDraft, y: CGFloat) -> CGFloat {
        let boxW: CGFloat = 260
        let boxX = margin + contentWidth - boxW
        var innerY = y
        innerY = drawTotalRow("Subtotal presupuesto", value: GrooCurrencyFormat.format(draft.subtotal), x: boxX, y: innerY, bold: false)
        innerY = drawTotalRow("Ya abonado", value: GrooCurrencyFormat.format(draft.alreadyPaid), x: boxX, y: innerY, bold: false)
        if draft.historicalPending > 0.01 {
            innerY = drawTotalRow("Saldo clínico previo", value: GrooCurrencyFormat.format(draft.historicalPending), x: boxX, y: innerY, bold: false)
        }
        fillRect(CGRect(x: boxX - 8, y: innerY, width: boxW + 8, height: 34), color: UIColor(red: 0.35, green: 0.54, blue: 0.98, alpha: 0.12), radius: 8)
        innerY = drawTotalRow("TOTAL A PAGAR", value: GrooCurrencyFormat.format(draft.totalBudget + draft.historicalPending), x: boxX, y: innerY + 4, bold: true)
        return innerY + 34
    }

    private static func drawTotalRow(_ label: String, value: String, x: CGFloat, y: CGFloat, bold: Bool) -> CGFloat {
        let font = bold ? UIFont.boldSystemFont(ofSize: 13) : UIFont.systemFont(ofSize: 11)
        drawText(label, rect: CGRect(x: x, y: y + 4, width: 140, height: 18), font: font, color: bold ? .black : .darkGray)
        drawText(value, rect: CGRect(x: x + 130, y: y + 4, width: 120, height: 18), font: font, color: bold ? UIColor(red: 0.12, green: 0.58, blue: 0.28, alpha: 1) : .black, alignment: .right)
        return y + 26
    }

    private static func drawFooter(draft: GrooPatientBudgetDraft, y: CGFloat) -> CGFloat {
        var innerY = y
        if !draft.notes.isEmpty {
            drawText("Observaciones", rect: CGRect(x: margin, y: innerY, width: contentWidth, height: 14), font: .boldSystemFont(ofSize: 11), color: .darkGray)
            innerY += 18
            drawText(draft.notes, rect: CGRect(x: margin, y: innerY, width: contentWidth, height: 60), font: .systemFont(ofSize: 10), color: .gray)
            innerY += 64
        }
        drawText("Profesional: \(draft.professionalName)", rect: CGRect(x: margin, y: innerY, width: contentWidth, height: 14), font: .systemFont(ofSize: 10), color: .gray)
        innerY += 18
        drawText("Documento generado por \(draft.clinicName). Los importes incluyen IVA según normativa vigente.", rect: CGRect(x: margin, y: innerY, width: contentWidth, height: 28), font: .systemFont(ofSize: 9), color: .lightGray)
        return innerY + 28
    }

    private static func drawText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let p = NSMutableParagraphStyle()
        p.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        text.draw(in: rect, withAttributes: attrs)
    }

    private static func fillRect(_ rect: CGRect, color: UIColor, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        color.setFill()
        path.fill()
    }
}

// MARK: - Compartir PDF

struct GrooSharePDFSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
