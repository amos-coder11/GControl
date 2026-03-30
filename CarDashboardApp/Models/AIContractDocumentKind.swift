import Foundation

/// Tipo de documento legal generado por el asistente (cada uno usa un prompt de sistema distinto).
enum AIContractDocumentKind: String, CaseIterable, Identifiable, Sendable {
    /// Compromiso u orden de compra (énfasis en el comprador y condiciones de la reserva/pago).
    case compra
    /// Contrato de venta / compraventa clásico (énfasis en entrega, titularidad y transferencia).
    case venta
    /// Garantía del vehículo (GV): alcance, plazo, exclusiones, no es un contrato de compraventa.
    case gv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compra: return "Contrato de compra"
        case .venta: return "Contrato de venta"
        case .gv: return "GV (garantía)"
        }
    }

    var shortHint: String {
        switch self {
        case .venta: return "CarHub vende el coche al cliente: entrega, precio y transferencia DGT."
        case .compra: return "CarHub compra el coche al particular: pago al vendedor y entrega del vehículo."
        case .gv: return "Garantía del vehículo (GV): plazo, alcance y exclusiones; no es compraventa."
        }
    }
}
