import Foundation

/// Una imagen del vehículo (URL, Storage o base64). Varias por coche forman la galería.
struct CarImageSlot: Identifiable, Hashable {
    enum Payload: Hashable {
        case url(String)
        case publicVehiclesFile(String)
        case signed(bucket: String, path: String)
        case base64(String)
    }

    let id: String
    let payload: Payload

    init?(classifyingRaw raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let kind = VehicleImageResolution.classify(raw: t) else { return nil }
        switch kind {
        case let .absoluteURL(u):
            let s = u.absoluteString
            payload = .url(s)
            id = "u:" + s
        case let .publicVehiclesFileName(name):
            payload = .publicVehiclesFile(name)
            id = "p:" + name
        case let .signedStorage(bucket, path):
            payload = .signed(bucket: bucket, path: path)
            id = "s:\(bucket):" + path
        case let .inlineBase64(b64):
            payload = .base64(b64)
            id = "b:\(b64.count)_\(b64.prefix(96))"
        }
    }

    init(payload: Payload) {
        self.payload = payload
        switch payload {
        case let .url(s):
            id = "u:" + s
        case let .publicVehiclesFile(f):
            id = "p:" + f
        case let .signed(bucket, path):
            id = "s:\(bucket):" + path
        case let .base64(b64):
            id = "b:\(b64.count)_\(b64.prefix(96))"
        }
    }
}
