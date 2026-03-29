import Foundation
import Supabase

/// Activa el registro en consola (Xcode) de lo que PostgREST devuelve y cómo la app construye la galería.
enum VehicleImageDiagnostics {
    static let userDefaultsKey = "CarDashboardAppLogVehicleImageDiagnostics"

    static var isEnabled: Bool {
        true // Temporalmente activado para diagnosticar galería
        // UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Tras `fetchAll`: qué columnas vienen en JSON, cuántas referencias hay y cuántos `CarImageSlot` finales.
    static func logAfterFetch(rows: [VehicleRow], rawObjects: [JSONObject]) {
        guard isEnabled else { return }

        let sep = String(repeating: "─", count: 72)
        print("\n\(sep)\n[VehicleImageDiagnostics] Carga de vehículos — revisa la consola de Xcode (⌘⇧Y)\n\(sep)")
        print(
            """
            Cómo interpretar esto:
            • claves JSON: nombres de columnas en la respuesta de `select()` que parecen multimedia.
            • galleryRaws: strings únicos que la app usará como fotos (URLs o rutas Storage) antes del listado extra.
            • storagePath / userId: necesarios para listar la carpeta `{user_id}/{vehicle_id}/` en el bucket.
            • slots UI: `Car.resolvedImageSlots` (lo que ve el carrusel). Si aquí sale 1 pero en Storage hay más, suele ser RLS o ruta UUID distinta.
            """
        )

        let sample = min(20, rows.count)
        print("\n— Muestra de \(sample) filas (de \(rows.count)) —\n")

        for idx in 0 ..< sample {
            let row = rows[idx]
            let raw = idx < rawObjects.count ? rawObjects[idx] : [:]
            let keys = mediaRelatedKeys(in: raw)
            let car = row.toCar(index: idx)
            let slots = car.resolvedImageSlots.count
            let rawsPreview = row.imageGalleryRaws.prefix(3).map { truncateMiddle($0) }.joined(separator: " · ")

            print(
                """
                [\(idx)] id=\(row.id.uuidString)
                    claves JSON multimedia: \(keys.isEmpty ? "(ninguna detectada)" : keys.joined(separator: ", "))
                    galleryRaws=\(row.imageGalleryRaws.count) preview: \(rawsPreview.isEmpty ? "—" : rawsPreview)
                    storage_path=\(row.storagePathColumn.map { truncateMiddle($0) } ?? "nil")
                    bucket=\(row.storageBucketColumn ?? "nil")
                    user_id=\(raw["user_id"]?.stringValue ?? raw["userId"]?.stringValue ?? "nil")
                    dealcar_id=\(raw["dealcar_vehicle_id"]?.stringValue ?? raw["dealcarVehicleId"]?.stringValue ?? "nil")
                    → slots en UI=\(slots)
                """
            )
        }

        if rows.count > sample {
            print("\n… \(rows.count - sample) filas más sin listar (sube el límite en VehicleImageDiagnostics si lo necesitas).\n")
        }

        print("\(sep)\n")
    }

    private static func mediaRelatedKeys(in obj: JSONObject) -> [String] {
        let hints = [
            "image", "photo", "media", "gallery", "multimedia", "storage", "foto", "imagen",
            "thumb", "cover", "url", "path", "bucket", "asset", "picture",
        ]
        return obj.keys.filter { key in
            let l = key.lowercased()
            return hints.contains { l.contains($0) }
        }.sorted()
    }

    private static func truncateMiddle(_ s: String, maxLen: Int = 96) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxLen else { return t }
        let half = maxLen / 2 - 2
        let i0 = t.startIndex
        let i1 = t.index(t.startIndex, offsetBy: half)
        let i2 = t.index(t.endIndex, offsetBy: -half)
        return "\(t[i0..<i1])…\(t[i2..<t.endIndex])"
    }
}
