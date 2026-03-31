import UIKit

/// Contract form data for professional PDF generation.
struct ContractFormData {
    let kind: AIContractDocumentKind
    let clientName: String
    let clientID: String
    let clientAddress: String
    let vehicleBrand: String
    let vehicleModel: String
    let priceEUR: String
}

// MARK: - Public API

enum ContractPDFExporter {
    static let pdfHeaderWordmark = "ACCAR"

    /// Loads brand logo from Assets. Tries PNG first (LogoACCAR), then SVG (AccarLogo).
    static func loadBrandLogoForPDF() -> UIImage? {
        for name in ["LogoACCAR", "AccarLogo", "CarHubLogo"] {
            guard let img = UIImage(named: name)?.withRenderingMode(.alwaysOriginal) else { continue }
            // Rasterise at 2× for retina quality in PDF context
            let targetH: CGFloat = 90
            let ratio = img.size.width / max(img.size.height, 1)
            let targetW = ratio > 0.1 ? targetH * ratio : 180
            let size = CGSize(width: targetW, height: targetH)
            let renderer = UIGraphicsImageRenderer(size: size)
            let rasterised = renderer.image { _ in
                img.draw(in: CGRect(origin: .zero, size: size))
            }
            return rasterised
        }
        return nil
    }

    static func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch weight {
        case .bold, .heavy:
            return UIFont(name: "HelveticaNeue-Bold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold)
        case .semibold, .medium:
            return UIFont(name: "HelveticaNeue-Medium", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .medium)
        default:
            return UIFont(name: "HelveticaNeue", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .regular)
        }
    }

    /// New professional PDF generator with full contract layout.
    static func makePDFData(clauseBody: String, formData: ContractFormData) -> Data {
        let data = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: PDFLayout.pw, height: PDFLayout.ph)

        UIGraphicsBeginPDFContextToData(data as CFMutableData, pageRect, [
            kCGPDFContextCreator as String: pdfHeaderWordmark,
            kCGPDFContextTitle as String: formData.kind.title,
        ] as [String: Any])

        let renderer = ContractRenderer(formData: formData, logo: loadBrandLogoForPDF())
        renderer.render(clauseBody: clauseBody)

        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Legacy API kept for backward compatibility.
    static func makePDFData(body: String, documentSubtitle: String) -> Data {
        let cleaned = body
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
        let fallback = ContractFormData(
            kind: .venta,
            clientName: "[cliente]", clientID: "[DNI]", clientAddress: "[dirección]",
            vehicleBrand: "[marca]", vehicleModel: "[modelo]", priceEUR: "[precio]"
        )
        return makePDFData(clauseBody: cleaned, formData: fallback)
    }

    static func writeTemporaryPDF(data: Data) throws -> URL {
        let safe = pdfHeaderWordmark.replacingOccurrences(of: " ", with: "_")
        let name = "Contrato_\(safe)_\(Int(Date().timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

// MARK: - Layout Constants

private enum PDFLayout {
    static let pw: CGFloat = 595.28
    static let ph: CGFloat = 841.89
    static let ml: CGFloat = 52
    static let mr: CGFloat = 52
    static let mt: CGFloat = 36
    static let mb: CGFloat = 44
    static let cw: CGFloat = pw - ml - mr
    static let sigH: CGFloat = 70
    static let footH: CGFloat = 20
    /// Maximum Y before we must stop and draw signatures.
    static let maxY: CGFloat = ph - mb - sigH - footH
}

// MARK: - Contract Renderer

private final class ContractRenderer {
    let formData: ContractFormData
    let logo: UIImage?
    var y: CGFloat = 0
    var page: Int = 0

    init(formData: ContractFormData, logo: UIImage?) {
        self.formData = formData
        self.logo = logo
    }

    // MARK: Pagination

    func beginNewPage(isFirst: Bool = false) {
        if page > 0 {
            drawSignatures()
            drawPageNumber()
        }
        UIGraphicsBeginPDFPage()
        page += 1
        y = PDFLayout.mt
        drawLogo()
        if !isFirst {
            y += 6
        }
    }

    func ensureSpace(_ needed: CGFloat) {
        if y + needed > PDFLayout.maxY {
            beginNewPage()
        }
    }

    // MARK: Main Render

    func render(clauseBody: String) {
        beginNewPage(isFirst: true)

        drawDate()
        y += 14
        drawTitle()
        y += 14
        drawReuinidosHeading()
        y += 6
        drawReunidosBody()
        y += 14

        ensureSpace(140)
        drawVehicleTable()
        y += 14

        drawClauseBody(clauseBody)

        // Final page signatures
        drawSignatures()
        drawPageNumber()
    }

    // MARK: Logo (TOP-LEFT, matching templates)

    func drawLogo() {
        if let img = logo {
            let drawH: CGFloat = 50
            let ratio = img.size.width / max(img.size.height, 1)
            let drawW = min(drawH * ratio, 140)
            img.draw(in: CGRect(x: PDFLayout.ml, y: y, width: drawW, height: drawH))
            y += drawH + 6
            return
        }
        // Fallback: draw "Ac Car" styled logo matching templates
        // Dark rectangle with white Eurostile Extended Bold Italic text centered inside

        // Try Eurostile Extended Bold Italic first, then closest geometric alternatives
        let fontSize: CGFloat = 28
        let logoFont: UIFont = {
            // Eurostile Extended Bold Italic (exact match if font is installed)
            let eurostileNames = [
                "EurostileExtended-BoldItalic",
                "EurostileExtended-BoldOblique",
                "Eurostile-ExtendedBoldItalic",
                "EurostileLTStd-BoldExObl",
                "EurostileLT-BoldExtendedTwo",
            ]
            for name in eurostileNames {
                if let f = UIFont(name: name, size: fontSize) { return f }
            }
            // Closest system alternatives: wide geometric sans-serif bold italic
            if let f = UIFont(name: "Futura-BoldOblique", size: fontSize) { return f }
            if let f = UIFont(name: "AvenirNext-BoldItalic", size: fontSize) { return f }
            if let f = UIFont(name: "GillSans-BoldItalic", size: fontSize) { return f }

            // Last resort: create a bold italic system font with extended width
            let desc = UIFont.systemFont(ofSize: fontSize, weight: .bold)
                .fontDescriptor
                .withSymbolicTraits([.traitBold, .traitItalic, .traitExpanded])
            if let d = desc { return UIFont(descriptor: d, size: fontSize) }
            return UIFont.italicSystemFont(ofSize: fontSize)
        }()

        let logoText = "Ac Car"
        let logoAttrs: [NSAttributedString.Key: Any] = [
            .font: logoFont,
            .foregroundColor: UIColor.white,
        ]
        let textSz = (logoText as NSString).size(withAttributes: logoAttrs)

        // Dynamic rectangle: sized symmetrically around the text with padding
        let padH: CGFloat = 12  // horizontal padding on each side
        let padV: CGFloat = 8   // vertical padding on each side
        let logoW = textSz.width + padH * 2
        let logoH = textSz.height + padV * 2
        let bgRect = CGRect(x: PDFLayout.ml, y: y, width: logoW, height: logoH)

        // Dark background (matching template dark navy/black)
        UIColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 1).setFill()
        UIBezierPath(roundedRect: bgRect, cornerRadius: 2).fill()

        // Center text inside rectangle
        let tx = bgRect.midX - textSz.width / 2
        let ty = bgRect.midY - textSz.height / 2
        (logoText as NSString).draw(at: CGPoint(x: tx, y: ty), withAttributes: logoAttrs)

        y += logoH + 6
    }

    // MARK: Date (right-aligned, with real time)

    func drawDate() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let day = cal.component(.day, from: now)
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "es_ES")
        monthFmt.dateFormat = "MMMM"
        let month = monthFmt.string(from: now).uppercased()
        let year = cal.component(.year, from: now)

        let timeStr = String(format: "%02d:%02d", hour, minute)
        let text = "En Madrid a \(day) de \(month) de \(year) a las \(timeStr) horas"
        let font = ContractPDFExporter.bodyFont(size: 10)
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black, .paragraphStyle: para,
        ]
        let sz = textSize(text, attrs: attrs)
        let rect = CGRect(x: PDFLayout.ml, y: y, width: PDFLayout.cw, height: sz.height + 2)
        (text as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        y += sz.height + 2
    }

    // MARK: Title

    func drawTitle() {
        let title: String
        switch formData.kind {
        case .compra:
            title = "CONTRATO DE COMPRA - VENTA DE VEHÍCULOS DE OCASIÓN y GESTION DE VENTA"
        case .venta:
            title = "CONTRATO DE COMPRAVENTA DE VEHÍCULOS DE OCASIÓN (V.O)"
        case .gv:
            title = "CONTRATO DE COMPRAVENTA DE VEHÍCULO USADO"
        }
        let font = ContractPDFExporter.bodyFont(size: 14, weight: .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black,
            .paragraphStyle: para, .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let sz = textSize(title, attrs: attrs)
        let rect = CGRect(x: PDFLayout.ml, y: y, width: PDFLayout.cw, height: sz.height + 4)
        (title as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        y += sz.height + 4
    }

    // MARK: REUNIDOS

    func drawReuinidosHeading() {
        let font = ContractPDFExporter.bodyFont(size: 12, weight: .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black, .paragraphStyle: para,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let rect = CGRect(x: PDFLayout.ml, y: y, width: PDFLayout.cw, height: 18)
        ("REUNIDOS" as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        y += 20
    }

    func drawReunidosBody() {
        let blocks = reunidosBlocks()
        let font = ContractPDFExporter.bodyFont(size: 9.5)
        let boldFont = ContractPDFExporter.bodyFont(size: 9.5, weight: .bold)

        for block in blocks {
            ensureSpace(60)
            let attrStr = buildAttributedReunidos(block, baseFont: font, boldFont: boldFont)
            let sz = attrStr.boundingRect(
                with: CGSize(width: PDFLayout.cw, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
            let rect = CGRect(x: PDFLayout.ml, y: y, width: PDFLayout.cw, height: sz.height + 4)
            attrStr.draw(with: rect, options: .usesLineFragmentOrigin, context: nil)
            y += sz.height + 6
        }
    }

    private func reunidosBlocks() -> [String] {
        let cn = formData.clientName.isEmpty ? "[nombre completo]" : formData.clientName
        let ci = formData.clientID.isEmpty ? "[DNI/NIE]" : formData.clientID
        let ca = formData.clientAddress.isEmpty ? "[dirección]" : formData.clientAddress

        switch formData.kind {
        case .compra:
            return [
                "De una parte y en calidad de COMPRADOR\nAC GROUP CONCESIONARIO MULTIMARCA SL, con CIF B44909265\ny COMERCIAL AUTORIZADO de la mercantil D. , con domicilio a efectos del presente y notificaciones en AVENIDA DESPEÑAPERROS S/N( MADRID) 28729\n–Venturada (Madrid). EMAIL ACCAR@ACCAR.ES",
                "De otra parte, en calidad de VENDEDOR :\nD/ \(cn), mayor de edad, con DNI/NIE: \(ci), con domicilio a efectos del presente contrato y notificaciones en \(ca)",
            ]
        case .venta:
            return [
                "De una parte y en calidad de COMPRADOR:\nAC GROUP CONCESIONARIO MULTIMARCA SL, con CIF: B44909265, en comercial autorizado de la mercantil D/ Daniel Angel Cámara de Domingo, con DNI:03145064k con domicilio a efectos del presente y notificaciones en AVENIDA DESPEÑAPERROS S/N VENTURADA. MADRID. CP: 28729\n918786215 CORREO ELECTRÓNICO: accar@accar.es",
                "De otra parte y en calidad de VENDEDOR:\nD/ \(cn), mayor de edad, con DNI: \(ci), con domicilio a efectos del presente en \(ca)",
            ]
        case .gv:
            return [
                "De una parte, en calidad de VENDEDOR:\nAC CAR CONCESIONARIO MULTIMARCA S.L, con CIF:B87130639, en representación de la mercantil D/ MIGUEL ANGEL GONZALEZ RODRIGUEZ, con domicilio a efectos del presente contrato y notificaciones en calle Francisco Alonso nº 5 (naves 3-4)\n28806 Alcalá de Henares (Madrid).\nEmail: accar@accar.es",
                "De otra parte, en calidad de COMPRADOR:\nD/ \(cn), mayor de edad, con DNI: \(ci), con domicilio a efectos del presente contrato y notificaciones en \(ca)",
            ]
        }
    }

    private func buildAttributedReunidos(_ text: String, baseFont: UIFont, boldFont: UIFont) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont, .foregroundColor: UIColor.black, .paragraphStyle: para,
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont, .foregroundColor: UIColor.black, .paragraphStyle: para,
        ]
        let underBoldAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont, .foregroundColor: UIColor.black, .paragraphStyle: para,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]

        let result = NSMutableAttributedString(string: text, attributes: baseAttrs)
        let nsText = text as NSString

        // Bold keywords
        for kw in ["COMPRADOR", "VENDEDOR", "VENDEDOR :", "CIF", "DNI/NIE:", "DNI:", "EMAIL", "CORREO ELECTRÓNICO",
                    "AC GROUP CONCESIONARIO MULTIMARCA SL", "AC CAR CONCESIONARIO MULTIMARCA S.L",
                    "D/ Daniel Angel Cámara de Domingo,", "D/ MIGUEL ANGEL GONZALEZ RODRIGUEZ,", "D."] {
            var sr = NSRange(location: 0, length: nsText.length)
            while sr.location < nsText.length {
                let found = nsText.range(of: kw, options: [], range: sr)
                if found.location == NSNotFound { break }
                result.addAttributes(boldAttrs, range: found)
                sr.location = found.location + found.length
                sr.length = nsText.length - sr.location
            }
        }

        // Underline + bold for "De una parte..." / "De otra parte..."
        for kw in ["De una parte y en calidad de", "De una parte, en calidad de",
                    "De otra parte y en calidad de", "De otra parte, en calidad de"] {
            let r = nsText.range(of: kw)
            if r.location != NSNotFound {
                result.addAttributes(underBoldAttrs, range: r)
            }
        }
        return result
    }

    // MARK: Vehicle Table

    func drawVehicleTable() {
        switch formData.kind {
        case .gv:
            drawVerticalVehicleTable()
        default:
            drawGridVehicleTable()
        }
    }

    /// Grid table for compra/venta (4 rows × 3 cols matching templates)
    private func drawGridVehicleTable() {
        let rows: [[(String, String)]] = [
            [("TIPO: ", "TURISMO"), ("MARCA: ", formData.vehicleBrand), ("MODEL: ", formData.vehicleModel)],
            [("POTENCIA: ", "CV"), ("CILINDRADA: ", "cc"), ("COLOR: ", "")],
            [("KILOMETRAJE: ", "KMS"), ("MATRICULA: ", ""), ("COMBUSTIBLE: ", "")],
            [("N.º BASTIDOR: ", ""), ("FECHA 1ª MATRICULACIÓN: ", ""), ("", "")],
        ]
        let colW = PDFLayout.cw / 3
        let rowH: CGFloat = 26
        let pad: CGFloat = 5
        let labelFont = ContractPDFExporter.bodyFont(size: 8.5, weight: .bold)
        let valueFont = ContractPDFExporter.bodyFont(size: 8.5)

        for (ri, row) in rows.enumerated() {
            let ry = y + CGFloat(ri) * rowH
            for (ci, cell) in row.enumerated() {
                let cx = PDFLayout.ml + CGFloat(ci) * colW
                let cellRect = CGRect(x: cx, y: ry, width: colW, height: rowH)
                let path = UIBezierPath(rect: cellRect)
                path.lineWidth = 0.5
                UIColor.black.setStroke()
                path.stroke()

                if !cell.0.isEmpty {
                    let la: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: UIColor.black]
                    let lsz = (cell.0 as NSString).size(withAttributes: la)
                    (cell.0 as NSString).draw(at: CGPoint(x: cx + pad, y: ry + pad), withAttributes: la)
                    if !cell.1.isEmpty {
                        let va: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: UIColor.black]
                        (cell.1 as NSString).draw(at: CGPoint(x: cx + pad + lsz.width + 2, y: ry + pad), withAttributes: va)
                    }
                }
            }
        }
        y += CGFloat(rows.count) * rowH
    }

    /// Vertical 2-column table for GV (DATOS DEL VEHÍCULO | DETALLE)
    private func drawVerticalVehicleTable() {
        let headerFont = ContractPDFExporter.bodyFont(size: 9, weight: .bold)
        let cellFont = ContractPDFExporter.bodyFont(size: 9)
        let leftW: CGFloat = PDFLayout.cw * 0.45
        let rightW: CGFloat = PDFLayout.cw * 0.55
        let rowH: CGFloat = 20
        let pad: CGFloat = 5

        let fields = [
            ("Marca", formData.vehicleBrand),
            ("Modelo", formData.vehicleModel),
            ("Tipo", "Turismo"),
            ("Color", ""),
            ("Matrícula", ""),
            ("Nº Bastidor", ""),
            ("Cilindrada", ""),
            ("Potencia", ""),
            ("Combustible", ""),
            ("Kilometraje", ""),
            ("Fecha 1ª matriculación", ""),
            ("Próxima ITV", ""),
        ]

        // Header row
        let hdr: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.black]
        let hRect = CGRect(x: PDFLayout.ml, y: y, width: leftW, height: rowH)
        UIBezierPath(rect: hRect).stroke()
        ("DATOS DEL VEHÍCULO" as NSString).draw(at: CGPoint(x: PDFLayout.ml + pad, y: y + pad), withAttributes: hdr)
        let hRect2 = CGRect(x: PDFLayout.ml + leftW, y: y, width: rightW, height: rowH)
        UIBezierPath(rect: hRect2).stroke()
        ("DETALLE" as NSString).draw(at: CGPoint(x: PDFLayout.ml + leftW + pad, y: y + pad), withAttributes: hdr)
        y += rowH

        // Data rows
        let la: [NSAttributedString.Key: Any] = [.font: cellFont, .foregroundColor: UIColor.black]
        for (label, value) in fields {
            let r1 = CGRect(x: PDFLayout.ml, y: y, width: leftW, height: rowH)
            UIColor.black.setStroke()
            UIBezierPath(rect: r1).stroke()
            (label as NSString).draw(at: CGPoint(x: PDFLayout.ml + pad, y: y + 4), withAttributes: la)

            let r2 = CGRect(x: PDFLayout.ml + leftW, y: y, width: rightW, height: rowH)
            UIBezierPath(rect: r2).stroke()
            if !value.isEmpty {
                (value as NSString).draw(at: CGPoint(x: PDFLayout.ml + leftW + pad, y: y + 4), withAttributes: la)
            }
            y += rowH
        }
    }

    // MARK: Clause Body (multi-page)

    func drawClauseBody(_ body: String) {
        let cleaned = body
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let font = ContractPDFExporter.bodyFont(size: 10)
        let boldFont = ContractPDFExporter.bodyFont(size: 10, weight: .bold)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 2
        paraStyle.paragraphSpacing = 4
        paraStyle.lineBreakMode = .byWordWrapping
        paraStyle.alignment = .justified

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor(white: 0.08, alpha: 1), .paragraphStyle: paraStyle,
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont, .foregroundColor: UIColor.black, .paragraphStyle: paraStyle,
        ]

        let paragraphs = cleaned.components(separatedBy: "\n\n")

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let lines = trimmed.components(separatedBy: "\n")
            for line in lines {
                let ln = line.trimmingCharacters(in: .whitespaces)
                if ln.isEmpty { continue }

                let isHeader = isAllCapsHeader(ln)
                let attrs = isHeader ? boldAttrs : baseAttrs
                let sz = textSize(ln, attrs: attrs)

                ensureSpace(sz.height + 6)
                let rect = CGRect(x: PDFLayout.ml, y: y, width: PDFLayout.cw, height: sz.height + 2)
                (ln as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                y += sz.height + 2
            }
            y += 3
        }
    }

    // MARK: Signatures (matching template style)

    func drawSignatures() {
        let sigY = PDFLayout.ph - PDFLayout.mb - PDFLayout.sigH
        let font = ContractPDFExporter.bodyFont(size: 9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]

        // Separator line
        UIColor(white: 0.3, alpha: 1).setStroke()
        let sep = UIBezierPath()
        sep.move(to: CGPoint(x: PDFLayout.ml, y: sigY))
        sep.addLine(to: CGPoint(x: PDFLayout.pw - PDFLayout.mr, y: sigY))
        sep.lineWidth = 0.5
        sep.stroke()

        let labelY = sigY + 28
        // Left: FIRMA DEL VENDEDOR
        ("FIRMA DEL VENDEDOR" as NSString).draw(at: CGPoint(x: PDFLayout.ml, y: labelY), withAttributes: attrs)
        // Right: FIRMA DEL COMPRADOR
        let rightLabel = "FIRMA DEL COMPRADOR"
        let rsz = (rightLabel as NSString).size(withAttributes: attrs)
        (rightLabel as NSString).draw(at: CGPoint(x: PDFLayout.pw - PDFLayout.mr - rsz.width, y: labelY), withAttributes: attrs)
    }

    // MARK: Page Number

    func drawPageNumber() {
        let text = "Página \(page)"
        let font = ContractPDFExporter.bodyFont(size: 8)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor(white: 0.5, alpha: 1),
        ]
        let sz = (text as NSString).size(withAttributes: attrs)
        let x = (PDFLayout.pw - sz.width) / 2
        let pny = PDFLayout.ph - PDFLayout.mb + 4
        (text as NSString).draw(at: CGPoint(x: x, y: pny), withAttributes: attrs)
    }

    // MARK: Helpers

    private func isAllCapsHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 5 else { return false }
        let letters = t.filter { $0.isLetter }
        guard letters.count > 3 else { return false }
        return t == t.uppercased()
    }

    private func textSize(_ text: String, attrs: [NSAttributedString.Key: Any]) -> CGSize {
        let constraintSize = CGSize(width: PDFLayout.cw, height: .greatestFiniteMagnitude)
        return (text as NSString).boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        ).size
    }
}
