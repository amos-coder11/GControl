import Foundation
import Supabase

// MARK: - Árbol AnyJSON (PostgREST): columnas `image_url` jsonb u objetos anidados que `Codable` no lee como String.

private enum VehicleJSONImageFinder {
    static func merge(into row: inout VehicleRow, rowJSON: JSONObject) {
        if row.imageSourceRaw == nil {
            row.imageSourceRaw = firstImageString(in: rowJSON)
        }
        if row.storagePathColumn == nil {
            for k in [
                "storage_path", "storagePath", "media_path", "mediaPath", "file_path", "filePath",
                "object_path", "objectPath", "image_path", "imagePath", "primary_image_path", "primaryImagePath",
            ] {
                if let s = rowJSON[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    row.storagePathColumn = s
                    break
                }
            }
        }
        if row.storageBucketColumn == nil {
            for k in ["storage_bucket", "storageBucket", "bucket", "media_bucket", "mediaBucket", "bucket_id", "bucketId"] {
                if let s = rowJSON[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    row.storageBucketColumn = s
                    break
                }
            }
        }
        if row.imageBase64Raw == nil {
            for k in ["image_base64", "imageBase64"] {
                if let s = rowJSON[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    row.imageBase64Raw = s
                    break
                }
            }
        }

        var jsonGallery: [String] = []
        collectAllImageStrings(from: rowJSON, into: &jsonGallery)
        row.imageGalleryRaws = VehicleRow.mergeImageGalleryRaws(row.imageGalleryRaws, jsonGallery)
    }

    private static func collectAllImageStrings(from obj: JSONObject, into out: inout [String]) {
        for (_, v) in obj {
            collectFromAnyJSON(v, into: &out)
        }
    }

    private static func collectFromAnyJSON(_ j: AnyJSON, into out: inout [String]) {
        switch j {
        case let .string(s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= 4096 else { return }
            if VehicleImageResolution.looksLikeImageReference(t) {
                out.append(t)
            }
        case let .array(a):
            for item in a {
                collectFromAnyJSON(item, into: &out)
            }
        case let .object(o):
            for (_, v) in o {
                collectFromAnyJSON(v, into: &out)
            }
        default:
            break
        }
    }

    /// Prioriza columnas habituales; en columnas “de imagen” acepta el texto aunque la heurística sea floja.
    static func firstImageString(in row: JSONObject) -> String? {
        let primary = [
            "image_url", "imageUrl", "photo_url", "photoUrl", "thumbnail_url", "thumbnailUrl",
            "primary_image_url", "primaryImageUrl", "cover_image", "coverImage", "main_image", "mainImage",
            "picture", "vehicle_image", "vehicleImage", "foto", "imagen",
        ]
        for pk in primary {
            guard let val = row[pk] else { continue }
            if let s = stringTrustingImageColumn(val), !s.isEmpty { return s }
        }
        for (k, v) in row {
            let kl = k.lowercased()
            guard ["image", "photo", "thumb", "cover", "gallery", "media", "foto", "imagen", "picture", "asset"]
                .contains(where: { kl.contains($0) }) else { continue }
            if let s = extractLikelyImageString(v) { return s }
        }
        return extractLikelyImageString(.object(row))
    }

    private static func stringTrustingImageColumn(_ j: AnyJSON) -> String? {
        switch j {
        case let .string(s):
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .object, .array:
            return extractLikelyImageString(j)
        default:
            return nil
        }
    }

    private static func extractLikelyImageString(_ j: AnyJSON) -> String? {
        switch j {
        case let .string(s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if VehicleImageResolution.looksLikeImageReference(t) { return t }
            return nil
        case let .array(a):
            for item in a {
                if let s = extractLikelyImageString(item) { return s }
            }
            return nil
        case let .object(o):
            for (_, v) in o {
                if let s = extractLikelyImageString(v) { return s }
            }
            return nil
        default:
            return nil
        }
    }
}

enum VehiclesService {
    /// Lee filas como árbol JSON completo y fusiona imágenes desde `AnyJSON` (p. ej. `image_url` jsonb).
    static func fetchAll(client: SupabaseClient = SupabaseClientProvider.shared) async throws -> [VehicleRow] {
        let objects: [JSONObject] = try await client
            .from("vehicles")
            .select()
            .execute()
            .value

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        var rows: [VehicleRow] = []
        rows.reserveCapacity(objects.count)
        for obj in objects {
            let data = try encoder.encode(obj)
            var row = try decoder.decode(VehicleRow.self, from: data)
            VehicleJSONImageFinder.merge(into: &row, rowJSON: obj)
            rows.append(row)
        }

        // En tu proyecto enlazado puede que `public.vehicles` no devuelva columnas de imagen.
        // En ese caso, replicamos el enfoque del cliente Flutter llamando al RPC que devuelve
        // el path dentro del bucket de Storage.
        do {
            try await VehicleStorageCoverPathsRPC.attachCoverPathsIfNeeded(rows: &rows, client: client)
        } catch {
            // No rompemos el listado si el RPC no existe o si devuelve un formato inesperado.
        }

        return rows
    }
}

private struct VehicleStorageCoverPathsParams: Encodable, Sendable {
    let p_vehicle_ids: [UUID]
}

private enum VehicleStorageCoverPathsRPC {
    static func attachCoverPathsIfNeeded(rows: inout [VehicleRow], client: SupabaseClient) async throws {
        let missingIds = rows
            .filter { $0.storagePathColumn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
            .map(\.id)
        guard !missingIds.isEmpty else { return }

        // Si el RPC no existe o falla, no rompas el listado: la app mostrará el fallback.
        let rpcResult: [JSONObject] = try await client
            .rpc("vehicle_storage_cover_paths", params: VehicleStorageCoverPathsParams(p_vehicle_ids: missingIds))
            .execute()
            .value

        var coverByVehicleId: [UUID: (path: String, bucket: String?)] = [:]
        for row in rpcResult {
            guard let vehicleIdString = row["vehicle_id"]?.stringValue,
                  let vehicleId = UUID(uuidString: vehicleIdString) else { continue }

            guard let rawPath = row["storage_path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawPath.isEmpty else { continue }

            let rawBucket =
                row["storage_bucket"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ??
                row["bucket"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ??
                row["media_bucket"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bucket = rawBucket?.isEmpty == false ? rawBucket : nil

            coverByVehicleId[vehicleId] = (path: rawPath, bucket: bucket)
        }

        for i in rows.indices {
            let current = rows[i].storagePathColumn?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current?.isEmpty != false else { continue }
            guard let cover = coverByVehicleId[rows[i].id] else { continue }
            rows[i].storagePathColumn = cover.path
            if rows[i].storageBucketColumn == nil {
                rows[i].storageBucketColumn = cover.bucket
            }
        }
    }
}
