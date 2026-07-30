import UIKit

enum GrooImageProcessing {
    static let smileAIPreviewDisclaimerEN =
        "AI-generated preview for demonstration purposes only. This image illustrates a possible aesthetic outcome and does not guarantee clinical results. Not a substitute for professional dental diagnosis or treatment."

    static func resize(_ image: UIImage, maxSide: CGFloat = 1536) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func jpegData(_ image: UIImage, quality: CGFloat = 0.94) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    /// Pie de imagen profesional (inglés) para vistas previas de sonrisa con IA.
    static func stampAIPreviewDisclaimer(
        _ image: UIImage,
        text: String = smileAIPreviewDisclaimerEN
    ) -> UIImage {
        let size = image.size
        guard size.width > 1, size.height > 1 else { return image }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let sidePad = max(12, size.width * 0.035)
            let bottomPad = max(10, size.height * 0.025)
            let maxTextWidth = size.width - sidePad * 2
            let fontSize = max(9, min(13, size.width * 0.028))
            let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 1.5

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.96),
                .paragraphStyle: paragraph,
                .kern: 0.1,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textBounds = attributed.boundingRect(
                with: CGSize(width: maxTextWidth, height: size.height * 0.35),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let textHeight = ceil(textBounds.height)
            let badgeFont = UIFont.systemFont(ofSize: max(7, fontSize * 0.72), weight: .bold)
            let badge = "AI DEMO PREVIEW"
            let badgeSize = (badge as NSString).size(withAttributes: [
                .font: badgeFont,
                .kern: 0.8,
            ])
            let barHeight = badgeSize.height + textHeight + bottomPad * 2.1
            let barRect = CGRect(
                x: 0,
                y: size.height - barHeight,
                width: size.width,
                height: barHeight
            )

            let colors = [
                UIColor.black.withAlphaComponent(0).cgColor,
                UIColor.black.withAlphaComponent(0.55).cgColor,
                UIColor.black.withAlphaComponent(0.82).cgColor,
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.42, 1]
            ) {
                ctx.cgContext.saveGState()
                ctx.cgContext.addRect(barRect)
                ctx.cgContext.clip()
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: barRect.minY),
                    end: CGPoint(x: 0, y: barRect.maxY),
                    options: []
                )
                ctx.cgContext.restoreGState()
            }

            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
                .kern: 0.8,
            ]
            let badgeRect = CGRect(
                x: (size.width - badgeSize.width) / 2,
                y: barRect.minY + bottomPad * 0.45,
                width: badgeSize.width,
                height: badgeSize.height
            )
            (badge as NSString).draw(in: badgeRect, withAttributes: badgeAttrs)

            let textRect = CGRect(
                x: sidePad,
                y: badgeRect.maxY + max(4, bottomPad * 0.25),
                width: maxTextWidth,
                height: textHeight
            )
            attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }
}
