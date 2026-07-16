import Foundation

struct DrflowProduct: Identifiable, Hashable {
    let id: String
    let brand: String
    let name: String
    let price: Double
    let imageAssetName: String
    let modelResourceName: String
    let subtitle: String
    let descriptionParagraphs: [String]
    let benefits: [String]
    let supplementFacts: String?
    let directions: String?
    let importantInfo: [String]
    let disclaimer: String
    let shopURL: URL

    var priceFormatted: String {
        DealershipStatsViewModel.formatUSD(price)
    }
}

enum DrflowProductCatalog {
    static let products: [DrflowProduct] = [
        energyFocus,
        nadPlus,
        recoverySleep,
    ]

    static func product(id: String) -> DrflowProduct? {
        products.first { $0.id == id }
    }

    private static let shopBase = URL(string: "https://drgsmileusa.com")!

    static let energyFocus = DrflowProduct(
        id: "energy-focus",
        brand: "drgsmileusa",
        name: "Traders Market Energy Focus",
        price: 67,
        imageAssetName: "ProductDrgsmileEnergyFocus",
        modelResourceName: "Traders Market Energy Focus",
        subtitle: "60 cápsulas · Suplemento dietético",
        descriptionParagraphs: [
            "Traders Market Energy Focus es un suplemento dietético formulado para apoyar la concentración, la energía sostenida y la claridad mental durante el día.",
            "Cada frasco contiene 60 cápsulas con una mezcla pensada para quienes buscan rendimiento mental y vitalidad sin depender de estimulantes agresivos.",
        ],
        benefits: [
            "Enfoque mejorado para tareas diarias y trabajo intenso.",
            "Energía sostenida sin picos bruscos.",
            "Claridad mental y mejor concentración.",
            "Fórmula de 60 cápsulas para uso diario.",
        ],
        supplementFacts: nil,
        directions: "Adultos: tomar según indicación del fabricante o recomendación de un profesional de salud.",
        importantInfo: [
            "No usar si está embarazada o en periodo de lactancia.",
            "Consulte a su médico si toma medicamentos o tiene condiciones médicas.",
            "Conserve en lugar fresco y seco, bien cerrado.",
            "No usar si el sello de seguridad está roto o falta.",
        ],
        disclaimer: "Este producto no ha sido evaluado por la Food and Drug Administration. No está destinado a diagnosticar, tratar, curar o prevenir ninguna enfermedad.",
        shopURL: shopBase
    )

    static let nadPlus = DrflowProduct(
        id: "nad-plus",
        brand: "drgsmileusa",
        name: "NAD +",
        price: 49,
        imageAssetName: "ProductDrgsmileNADPlus",
        modelResourceName: "NAD +",
        subtitle: "NAD+ con Resveratrol · 60 cápsulas vegetarianas",
        descriptionParagraphs: [
            "Potencia tu vitalidad diaria con NAD+ de SC2 Supplements, un suplemento premium formulado para apoyar la energía, la salud celular y el bienestar general.",
            "Esta mezcla avanzada combina Nicotinamida Ribósido, precursor directo del NAD+, con antioxidantes potentes como Resveratrol y extracto de vino tinto, ofreciendo un apoyo integral a nivel celular.",
        ],
        benefits: [
            "Impulsa la energía y la fuerza: favorece niveles naturales de energía y vitalidad física.",
            "Apoya la salud cardiovascular: antioxidantes como el resveratrol contribuyen al bienestar del corazón.",
            "Promueve el bienestar cerebral: formulado para favorecer la claridad cognitiva.",
            "Mejora la función mitocondrial: apoya la producción eficiente de energía celular.",
            "Fomenta un estilo de vida saludable: apoya longevidad y vitalidad diaria.",
        ],
        supplementFacts: """
        Tamaño de porción: 2 cápsulas
        Porciones por envase: 60

        Cantidad por porción:
        • Nicotinamida Ribósido – 400 mg
        • Resveratrol (extracto de raíz Polygonum cuspidatum) – 200 mg
        • Extracto de vino tinto (fruto Vitis vinifera) – 200 mg
        (Valor diario no establecido)

        Otros ingredientes:
        Dióxido de silicio, celulosa microcristalina, estearato de magnesio.
        """,
        directions: "Adultos: tomar dos (2) cápsulas al día, o según recomendación de un profesional de salud.",
        importantInfo: [
            "No usar si está embarazada o en periodo de lactancia.",
            "Si toma medicamentos o tiene condiciones médicas, consulte a su médico antes de usar.",
            "Conserve bien cerrado en lugar fresco y seco a 15–30 °C (59–86 °F).",
            "No usar si el sello de seguridad está roto o falta.",
        ],
        disclaimer: "Este producto no ha sido evaluado por la Food and Drug Administration. No está destinado a diagnosticar, tratar, curar o prevenir ninguna enfermedad.",
        shopURL: shopBase
    )

    static let recoverySleep = DrflowProduct(
        id: "recovery-sleep",
        brand: "drgsmileusa",
        name: "Traders Recovery Sleep & Wellness",
        price: 67,
        imageAssetName: "ProductDrgsmileRecoverySleep",
        modelResourceName: "Traders Recovery Sleep & Wellness",
        subtitle: "60 cápsulas · Suplemento dietético",
        descriptionParagraphs: [
            "Traders Recovery Sleep & Wellness es un suplemento calmante diseñado para apoyar un sueño reparador y la relajación nocturna.",
            "Dormir bien es clave para sentirse con energía y afrontar los retos del día. Esta fórmula aporta nutrientes que refuerzan las funciones naturales del sueño.",
        ],
        benefits: [
            "Ayuda a conciliar el sueño más rápido.",
            "Contribuye a restaurar patrones de sueño normales.",
            "Promueve un descanso reparador y relajante.",
            "Apoya el bienestar general.",
        ],
        supplementFacts: """
        Ingredientes destacados por cápsula:
        • Melatonina 3 mg
        • Magnesio (citrato y glicinato) para relajación muscular
        • Vitamina D3 y selenio para apoyo inmune
        • Mezcla con GABA, 5-HTP y hierba de San Juan

        Otros ingredientes:
        Huevo de pato, dióxido de silicio.
        """,
        directions: "Tomar según indicación del fabricante o recomendación de un profesional de salud, preferiblemente antes de dormir.",
        importantInfo: [
            "Ideal para quienes buscan una forma natural de relajarse sin sedantes fuertes.",
            "No usar si está embarazada o en periodo de lactancia sin consultar a un médico.",
            "Conserve en lugar fresco y seco, bien cerrado.",
        ],
        disclaimer: "Este producto no ha sido evaluado por la Food and Drug Administration. No está destinado a diagnosticar, tratar, curar o prevenir ninguna enfermedad.",
        shopURL: shopBase
    )
}
