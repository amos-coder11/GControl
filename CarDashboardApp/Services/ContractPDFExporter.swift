import UIKit

/// PDF A4 con cabecera de marca, separador y pie de página; cuerpo sans estilo documento formal.
final class ContractPrintPageRenderer: UIPrintPageRenderer {
    var brandLogo: UIImage?
    var documentSubtitle: String = ""
    var documentStamp: String = ""

    override init() {
        super.init()
        headerHeight = 102
        footerHeight = 30
    }

    override var paperRect: CGRect {
        CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    }

    override var printableRect: CGRect {
        paperRect.insetBy(dx: 52, dy: 56)
    }

    override func drawHeaderForPage(at pageIndex: Int, in headerRect: CGRect) {
        guard pageIndex == 0 else { return }
        let left = printableRect.minX
        let right = printableRect.maxX
        var y = headerRect.minY + 4

        let wordmark = ContractPDFExporter.pdfHeaderWordmark
        let hubFont = UIFont.systemFont(ofSize: 21, weight: .heavy)
        let hubAttrs: [NSAttributedString.Key: Any] = [
            .font: hubFont,
            .foregroundColor: UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1),
        ]

        if let img = brandLogo {
            let maxH: CGFloat = 40
            let intrinsicH = max(img.size.height, 1)
            var w = maxH * img.size.width / intrinsicH
            if !w.isFinite || w < 32 { w = 152 }
            img.draw(in: CGRect(x: left, y: y, width: w, height: maxH))
            y += maxH + 12
        } else {
            (wordmark as NSString).draw(at: CGPoint(x: left, y: y + 2), withAttributes: hubAttrs)
            y += (wordmark as NSString).size(withAttributes: hubAttrs).height + 10
        }

        let subFont = ContractPDFExporter.bodyFont(size: 12.5, weight: .medium)
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1),
            .kern: 0.25,
        ]
        (documentSubtitle as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: subAttrs)
        y += (documentSubtitle as NSString).size(withAttributes: subAttrs).height + 6

        let stampFont = ContractPDFExporter.bodyFont(size: 10, weight: .regular)
        let stampAttrs: [NSAttributedString.Key: Any] = [
            .font: stampFont,
            .foregroundColor: UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1),
        ]
        (documentStamp as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: stampAttrs)
        y += (documentStamp as NSString).size(withAttributes: stampAttrs).height + 12

        let sepY = min(y, headerRect.maxY - 3)
        UIColor(red: 0.88, green: 0.88, blue: 0.91, alpha: 1).setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: left, y: sepY))
        line.addLine(to: CGPoint(x: right, y: sepY))
        line.lineWidth = 0.4
        line.stroke()
    }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let total = max(numberOfPages, 1)
        let foot = "Página \(pageIndex + 1) · \(total)"
        let font = ContractPDFExporter.bodyFont(size: 9, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1),
        ]
        let size = (foot as NSString).size(withAttributes: attrs)
        let x = printableRect.midX - size.width / 2
        let y = footerRect.minY + 6
        (foot as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }
}

enum ContractPDFExporter {
    /// Si no hay `AccarLogo` / `CarHubLogo` en Assets, se dibuja este texto en la cabecera.
    static let pdfHeaderWordmark = "ACCAR"

    /// `AccarLogo` primero, luego `CarHubLogo` (puedes sustituir los SVG en Assets).
    static func loadBrandLogoForPDF() -> UIImage? {
        let candidates = ["AccarLogo", "CarHubLogo"]
        for name in candidates {
            guard let img = UIImage(named: name) else { continue }
            return img.withRenderingMode(.alwaysOriginal)
        }
        return nil
    }

    static func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch weight {
        case .bold, .heavy:
            return UIFont(name: "HelveticaNeue-Bold", size: size)
                ?? UIFont(name: "Helvetica Neue Bold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        case .semibold:
            return UIFont(name: "HelveticaNeue-Medium", size: size)
                ?? UIFont(name: "HelveticaNeue-Bold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        case .medium:
            return UIFont(name: "HelveticaNeue-Medium", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .medium)
        default:
            return UIFont(name: "HelveticaNeue", size: size)
                ?? UIFont(name: "Helvetica Neue", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .regular)
        }
    }

    static func makePDFData(body: String, documentSubtitle: String) -> Data {
        let cleaned = body
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")

        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateStyle = .long
        df.timeStyle = .short
        let stamp = df.string(from: Date())

        let bodyAttr = attributedContractBody(from: cleaned)

        let formatter = UISimpleTextPrintFormatter(attributedText: bodyAttr)
        formatter.perPageContentInsets = UIEdgeInsets(top: 18, left: 0, bottom: 10, right: 0)

        let renderer = ContractPrintPageRenderer()
        renderer.brandLogo = loadBrandLogoForPDF()
        renderer.documentSubtitle = documentSubtitle
        renderer.documentStamp = stamp
        let hasLogo = renderer.brandLogo != nil
        renderer.headerHeight = hasLogo ? 118 : 108

        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let data = NSMutableData()
        let pageRect = renderer.paperRect
        UIGraphicsBeginPDFContextToData(data as CFMutableData, pageRect, [
            kCGPDFContextCreator as String: pdfHeaderWordmark,
            kCGPDFContextTitle as String: documentSubtitle,
        ] as [String: Any])

        for i in 0 ..< renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            let bounds = UIGraphicsGetPDFContextBounds()
            renderer.drawPage(at: i, in: bounds)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    private static func attributedContractBody(from cleaned: String) -> NSAttributedString {
        let font = bodyFont(size: 11.5, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 11
        paragraph.lineBreakMode = .byWordWrapping

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1),
            .paragraphStyle: paragraph,
        ]

        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "", attributes: baseAttrs)
        }

        let blocks = trimmed.components(separatedBy: "\n\n")
        let result = NSMutableAttributedString()

        for (index, rawBlock) in blocks.enumerated() {
            let block = rawBlock.trimmingCharacters(in: .whitespacesAndNewlines)
            if block.isEmpty { continue }

            if index > 0 {
                result.append(NSAttributedString(string: "\n\n", attributes: baseAttrs))
            }

            let upperBlock = block.uppercased()
            if index == 0, upperBlock.hasPrefix("AVISO LEGAL") {
                result.append(avisoLegalAttributedBlock(block, baseParagraph: paragraph))
                continue
            }

            let lines = block.components(separatedBy: "\n")
            for (lineIndex, line) in lines.enumerated() {
                if lineIndex > 0 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
                let styled = styledLine(line, baseParagraph: paragraph, baseFont: font)
                result.append(styled)
            }
        }

        return result
    }

    private static func avisoLegalAttributedBlock(_ block: String, baseParagraph: NSParagraphStyle) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.setParagraphStyle(baseParagraph)
        p.lineSpacing = 5
        p.paragraphSpacing = 14
        p.paragraphSpacingBefore = 2
        p.firstLineHeadIndent = 0
        p.headIndent = 10

        let font = bodyFont(size: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1),
            .paragraphStyle: p,
        ]
        return NSAttributedString(string: block, attributes: attrs)
    }

    private static func styledLine(_ line: String, baseParagraph: NSParagraphStyle, baseFont: UIFont) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()
        let isAllCapsLine = trimmed.count >= 6 && trimmed == upper && trimmed.filter { $0.isLetter }.count > 3
        let isLegalLead = upper.hasPrefix("AVISO LEGAL")

        let p = NSMutableParagraphStyle()
        p.setParagraphStyle(baseParagraph)

        if isLegalLead || (isAllCapsLine && trimmed.count <= 120) {
            let heavy = bodyFont(size: isLegalLead ? 11 : 11, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: heavy,
                .foregroundColor: UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1),
                .paragraphStyle: p,
            ]
            return NSAttributedString(string: trimmed, attributes: attrs)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1),
            .paragraphStyle: p,
        ]
        return NSAttributedString(string: trimmed, attributes: attrs)
    }

    static func writeTemporaryPDF(data: Data) throws -> URL {
        let safe = pdfHeaderWordmark.replacingOccurrences(of: " ", with: "_")
        let name = "Contrato_\(safe)_\(Int(Date().timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
