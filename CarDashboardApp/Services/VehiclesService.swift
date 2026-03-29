import Foundation
import Supabase

// MARK: - Árbol AnyJSON (PostgREST): columnas `image_url` jsonb u objetos anidados que `Codable` no lee como String.

private enum VehicleJSONImageFinder {
    static func merge(into row: inout VehicleRow, rowJSON: JSONObject) {
        if row.userId == nil {
            for k in [
                "user_id", "userId", "owner_id", "ownerId", "auth_user_id", "authUserId",
                "created_by", "createdBy", "profile_id", "profileId", "seller_id", "sellerId",
                "account_id", "accountId", "uid",
            ] {
                guard let s = rowJSON[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                      let u = UUID(uuidString: s) else { continue }
                row.userId = u
                break
            }
        }

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
    /// Página de vehículos con offset/limit para paginación incremental.
    static func fetchPage(
        offset: Int,
        limit: Int,
        client: SupabaseClient = SupabaseClientProvider.shared
    ) async throws -> [VehicleRow] {
        let objects: [JSONObject] = try await client
            .from("vehicles")
            .select()
            .range(from: offset, to: offset + limit - 1)
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

        // Portada vía RPC (no rompe si falla)
        do {
            try await VehicleStorageCoverPathsRPC.attachCoverPathsIfNeeded(rows: &rows, client: client)
        } catch {}

        // Resolución de galería — secuencial porque cada paso muta `rows` (inout).
        // El RPC de media paths es el más productivo, va primero.
        await VehicleStorageMediaPathsRPC.mergeIntoRows(&rows, client: client)
        await StorageSiblingGallery.mergeIntoRows(&rows, client: client)

        // Estas dos solo se ejecutan si aún faltan imágenes (evita llamadas innecesarias)
        let needsMoreImages = rows.contains { $0.imageGalleryRaws.count < 2 }
        if needsMoreImages {
            await LocalVehicleStorageGallery.mergeFolderListingIntoRows(&rows, client: client)
            await SupabaseStorageURLSiblingGallery.mergeIntoRows(&rows, client: client)
        }

        // Último recurso: si storage.list() falló (RLS), construir URLs secuenciales
        // a partir del cover path (001.jpg → 002.jpg, 003.jpg, etc.) y probar con HEAD.
        let stillNeedGallery = rows.contains { $0.imageGalleryRaws.count < 2 && $0.storagePathColumn != nil }
        if stillNeedGallery {
            await SequentialStorageProbe.mergeIntoRows(&rows)
        }

        VehicleImageDiagnostics.logAfterFetch(rows: rows, rawObjects: objects)

        return rows
    }

    /// Lee filas como árbol JSON completo y fusiona imágenes desde `AnyJSON` (p. ej. `image_url` jsonb).
    /// Mantiene compatibilidad pero ahora usa paginación interna.
    static func fetchAll(client: SupabaseClient = SupabaseClientProvider.shared) async throws -> [VehicleRow] {
        var allRows: [VehicleRow] = []
        let pageSize = 50
        var offset = 0

        while true {
            try Task.checkCancellation()
            let page = try await fetchPage(offset: offset, limit: pageSize, client: client)
            allRows.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        return allRows
    }
}

// MARK: - Hermanos en la misma carpeta que `storage_path` (galería completa)

private enum StorageSiblingGallery {
    static func mergeIntoRows(_ rows: inout [VehicleRow], client: SupabaseClient) async {
        let mediaBucket = SupabaseClientProvider.vehicleMediaBucket
        let jobs: [(index: Int, folder: String, buckets: [String])] = rows.enumerated().compactMap { i, r in
            guard let raw = r.storagePathColumn?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            guard !raw.lowercased().hasPrefix("http") else { return nil }
            let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = clean.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            let folder = parts.dropLast().joined(separator: "/")
            var buckets: [String] = [mediaBucket]
            if let b = trimmedNonEmptyBucket(r.storageBucketColumn),
               b.caseInsensitiveCompare(mediaBucket) != .orderedSame {
                buckets.append(b)
            }
            return (index: i, folder: folder, buckets: buckets)
        }
        guard !jobs.isEmpty else { return }

        await withTaskGroup(of: (Int, [String]).self) { group in
            for job in jobs {
                group.addTask {
                    for b in job.buckets {
                        let paths = await VehicleStorageListHelper.listImagePaths(
                            bucket: b,
                            folderPrefix: job.folder,
                            client: client
                        )
                        if !paths.isEmpty { return (job.index, paths) }
                    }
                    return (job.index, [])
                }
            }
            for await (index, paths) in group where !paths.isEmpty {
                rows[index].imageGalleryRaws = VehicleRow.mergeImageGalleryRaws(rows[index].imageGalleryRaws, paths)
            }
        }
    }

    private static func trimmedNonEmptyBucket(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - Galería desde listado de Storage (paridad con API stock CarHub)

private enum LocalVehicleStorageGallery {
    /// Lista `vehicle-media/{user_id}/{vehicle_id}/` aunque `user_id` falte en la fila si se infiere de `storage_path` o de la URL pública.
    static func mergeFolderListingIntoRows(_ rows: inout [VehicleRow], client: SupabaseClient) async {
        let bucket = SupabaseClientProvider.vehicleMediaBucket
        let jobs: [(index: Int, prefixes: [String])] = rows.enumerated().compactMap { i, r in
            let prefs = folderPrefixesForVehicleMediaListing(r)
            return prefs.isEmpty ? nil : (index: i, prefixes: prefs)
        }
        guard !jobs.isEmpty else { return }

        await withTaskGroup(of: (Int, [String]).self) { group in
            for job in jobs {
                group.addTask {
                    var acc: [String] = []
                    for prefix in job.prefixes {
                        let part = await VehicleStorageListHelper.listImagePaths(
                            bucket: bucket,
                            folderPrefix: prefix,
                            client: client
                        )
                        acc = VehicleRow.mergeImageGalleryRaws(acc, part)
                    }
                    return (job.index, acc)
                }
            }
            for await (index, paths) in group where !paths.isEmpty {
                rows[index].imageGalleryRaws = VehicleRow.mergeImageGalleryRaws(rows[index].imageGalleryRaws, paths)
            }
        }
    }

    private static func folderPrefixesForVehicleMediaListing(_ r: VehicleRow) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ raw: String) {
            let p = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !p.isEmpty, seen.insert(p.lowercased()).inserted else { return }
            out.append(p)
        }
        if let uid = r.userId {
            add("\(uid.uuidString.lowercased())/\(r.id.uuidString.lowercased())")
            if let d = r.dealcar_vehicle_id?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                add("\(uid.uuidString.lowercased())/\(d)")
            }
        }
        if let p = inferTwoUuidFolderPrefix(from: r.storagePathColumn) {
            add(p)
        }
        for raw in r.imageGalleryRaws {
            if let p = supabaseVehicleMediaFolderPrefix(from: raw) {
                add(p)
            }
        }
        if let s = r.imageSourceRaw, let p = supabaseVehicleMediaFolderPrefix(from: s) {
            add(p)
        }
        return out
    }

    /// `user_id/vehicle_id` a partir de ruta objeto (no URL).
    private static func inferTwoUuidFolderPrefix(from raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        guard !s.lowercased().hasPrefix("http") else { return nil }
        let clean = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = clean.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        guard UUID(uuidString: parts[0]) != nil, UUID(uuidString: parts[1]) != nil else { return nil }
        return "\(parts[0].lowercased())/\(parts[1].lowercased())"
    }

    /// Carpeta dentro del bucket para URLs `.../object/public/vehicle-media/{user}/{veh}/001.jpg`.
    private static func supabaseVehicleMediaFolderPrefix(from string: String) -> String? {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = VehicleImageResolution.resolvedHTTPURL(from: t)
                ?? URL(string: t, encodingInvalidCharacters: true) else { return nil }
        guard url.path.contains("/storage/v1/object/") else { return nil }
        let path = url.path
        let marker = "/storage/v1/object/public/"
        guard let range = path.range(of: marker) else { return nil }
        let rest = String(path[range.upperBound...])
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return nil }
        let bucket = parts[0]
        guard bucket.caseInsensitiveCompare(SupabaseClientProvider.vehicleMediaBucket) == .orderedSame else { return nil }
        let objectPath = parts.dropFirst().joined(separator: "/")
        let segs = objectPath.split(separator: "/").map(String.init)
        guard segs.count >= 2 else { return nil }
        return segs.dropLast().joined(separator: "/")
    }
}

// MARK: - URL pública/sign de Supabase → misma carpeta que el archivo (cuando no hay `storage_path` en la fila)

private enum SupabaseStorageURLSiblingGallery {
    private static let skipWhenGalleryCountAtLeast = 2

    static func mergeIntoRows(_ rows: inout [VehicleRow], client: SupabaseClient) async {
        typealias Snap = (index: Int, raws: [String], source: String?)
        let snaps: [Snap] = rows.enumerated().compactMap { i, r in
            guard r.imageGalleryRaws.count < skipWhenGalleryCountAtLeast else { return nil }
            return (i, r.imageGalleryRaws, r.imageSourceRaw)
        }
        guard !snaps.isEmpty else { return }

        await withTaskGroup(of: (Int, [String]).self) { group in
            for snap in snaps {
                group.addTask {
                    var acc: [String] = []
                    var seenFolderKeys = Set<String>()
                    var candidates = snap.raws
                    if let s = snap.source?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                        candidates.append(s)
                    }
                    for s in candidates {
                        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let url = VehicleImageResolution.resolvedHTTPURL(from: t)
                                ?? URL(string: t, encodingInvalidCharacters: true),
                              let scheme = url.scheme?.lowercased(),
                              scheme == "http" || scheme == "https" else { continue }
                        guard url.path.contains("/storage/v1/object/") else { continue }
                        guard let pair = extractBucketAndParentFolder(from: url) else { continue }
                        let key = "\(pair.bucket)|\(pair.folderPrefix)"
                        guard seenFolderKeys.insert(key).inserted else { continue }
                        let paths = await VehicleStorageListHelper.listImagePaths(
                            bucket: pair.bucket,
                            folderPrefix: pair.folderPrefix,
                            client: client
                        )
                        acc = VehicleRow.mergeImageGalleryRaws(acc, paths)
                    }
                    return (snap.index, acc)
                }
            }
            for await (index, paths) in group where !paths.isEmpty {
                rows[index].imageGalleryRaws = VehicleRow.mergeImageGalleryRaws(rows[index].imageGalleryRaws, paths)
            }
        }
    }

    /// `/storage/v1/object/public/{bucket}/…/archivo.jpg` o `/storage/v1/object/sign/{bucket}/…/archivo.jpg`
    private static func extractBucketAndParentFolder(from url: URL) -> (bucket: String, folderPrefix: String)? {
        let path = url.path
        let markers = [
            "/storage/v1/object/public/",
            "/storage/v1/object/sign/",
            "/storage/v1/object/authenticated/",
        ]
        for marker in markers {
            guard let range = path.range(of: marker) else { continue }
            let rest = String(path[range.upperBound...])
            let parts = rest.split(separator: "/").map(String.init)
            guard parts.count >= 3 else { continue }
            let bucket = parts[0]
            let objectPath = parts.dropFirst().joined(separator: "/")
            let segs = objectPath.split(separator: "/").map(String.init)
            guard segs.count >= 2 else { continue }
            let folderPrefix = segs.dropLast().joined(separator: "/")
            return (bucket, folderPrefix)
        }
        return nil
    }
}

// MARK: - Listado Storage → rutas relativas al bucket (encajan con `CarImageSlot` / bucket privado)

private enum VehicleStorageListHelper {
    static func listImagePaths(bucket: String, folderPrefix: String, client: SupabaseClient) async -> [String] {
        for prefix in folderPathVariants(folderPrefix) {
            let found = await listImagePathsSingle(bucket: bucket, folderPrefix: prefix, client: client)
            if !found.isEmpty { return mapPathsToGalleryStrings(bucket: bucket, relativePaths: found) }
        }
        return []
    }

    /// En `vehicle-media` con bucket público, exponemos URLs https listas para el carrusel (paridad con JS `getPublicUrl`).
    private static func mapPathsToGalleryStrings(bucket: String, relativePaths: [String]) -> [String] {
        let b = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard b.caseInsensitiveCompare(SupabaseClientProvider.vehicleMediaBucket) == .orderedSame else {
            return relativePaths
        }
        return relativePaths.map { SupabaseClientProvider.publicStorageObjectURL(bucket: b, path: $0) }
    }

    /// Prueba la ruta tal cual y variantes de mayúsculas en los dos primeros segmentos (UUID en Storage a veces en minúsculas).
    private static func folderPathVariants(_ prefix: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ s: String) {
            guard seen.insert(s).inserted else { return }
            out.append(s)
        }
        add(prefix)
        let parts = prefix.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return out }
        let low = "\(parts[0].lowercased())/\(parts[1].lowercased())"
        if parts.count > 2 {
            let rest = parts.dropFirst(2).joined(separator: "/")
            add("\(low)/\(rest)")
        } else {
            add(low)
        }
        let up = "\(parts[0].uppercased())/\(parts[1].uppercased())"
        if parts.count > 2 {
            let rest = parts.dropFirst(2).joined(separator: "/")
            add("\(up)/\(rest)")
        } else if up != low {
            add(up)
        }
        return out
    }

    private static func listImagePathsSingle(
        bucket: String,
        folderPrefix: String,
        client: SupabaseClient
    ) async -> [String] {
        do {
            let options = SearchOptions(
                limit: 200,
                offset: 0,
                sortBy: SortBy(column: "name", order: "asc")
            )
            let files = try await client.storage.from(bucket).list(path: folderPrefix, options: options)
            return files.compactMap { file -> String? in
                guard isRenderableStorageFile(file) else { return nil }
                return "\(folderPrefix)/\(file.name)"
            }
        } catch {
            return []
        }
    }

    private static func isRenderableStorageFile(_ file: FileObject) -> Bool {
        if file.name == ".emptyFolderPlaceholder" { return false }
        if file.id != nil { return true }
        let n = file.name.lowercased()
        return n.hasSuffix(".jpg") || n.hasSuffix(".jpeg") || n.hasSuffix(".png")
            || n.hasSuffix(".webp") || n.hasSuffix(".gif") || n.hasSuffix(".avif")
    }
}

private struct VehicleStorageCoverPathsParams: Encodable, Sendable {
    let p_vehicle_ids: [UUID]
}

/// RPC definido en CarHub: `supabase/migrations/20260329231000_vehicle_storage_media_paths.sql`
private enum VehicleStorageMediaPathsRPC {
    private static let chunkSize = 80

    static func mergeIntoRows(_ rows: inout [VehicleRow], client: SupabaseClient) async {
        let allIds = rows.map(\.id)
        guard !allIds.isEmpty else { return }

        var pathStringsByVehicle: [UUID: [String]] = [:]

        for chunkStart in stride(from: 0, to: allIds.count, by: chunkSize) {
            let end = min(chunkStart + chunkSize, allIds.count)
            let chunk = Array(allIds[chunkStart ..< end])
            do {
                let rpcResult: [JSONObject] = try await client
                    .rpc("vehicle_storage_media_paths", params: VehicleStorageCoverPathsParams(p_vehicle_ids: chunk))
                    .execute()
                    .value
                for row in rpcResult {
                    guard let vidStr = row["vehicle_id"]?.stringValue,
                          let vid = UUID(uuidString: vidStr) else { continue }
                    let path = row["storage_path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let p = path, !p.isEmpty else { continue }
                    pathStringsByVehicle[vid, default: []].append(p)
                }
            } catch {
                break
            }
        }

        let bucket = SupabaseClientProvider.vehicleMediaBucket
        for i in rows.indices {
            let id = rows[i].id
            guard let paths = pathStringsByVehicle[id], !paths.isEmpty else { continue }
            let urls = paths.map { p -> String in
                let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
                let l = t.lowercased()
                if l.hasPrefix("http://") || l.hasPrefix("https://") { return t }
                return SupabaseClientProvider.publicStorageObjectURL(bucket: bucket, path: t)
            }
            rows[i].imageGalleryRaws = VehicleRow.mergeImageGalleryRaws(rows[i].imageGalleryRaws, urls)
        }
    }
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

// MARK: - Sondeo secuencial: construye URLs 002…030.jpg a partir del cover (001.jpg) y comprueba con HEAD

/// Cuando `storage.list()` falla (p. ej. por RLS), esta estrategia construye las URLs públicas de
/// objetos secuenciales (`002.jpg`, `003.jpg` … `030.jpg`) basándose en la carpeta del cover path
/// (`001.jpg`) y hace peticiones HEAD concurrentes para verificar cuáles existen.
enum SequentialStorageProbe {

    /// Número máximo de archivo a probar (001.jpg ya está como cover)
    private static let maxProbe = 30

    /// Concurrencia máxima de HEAD requests por vehículo
    private static let concurrencyPerVehicle = 6

    /// URLSession ligera para HEADs: timeout corto, sin body
    private static let headSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 8
        cfg.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: cfg)
    }()

    // MARK: - Punto de entrada

    static func mergeIntoRows(_ rows: inout [VehicleRow]) async {
        // Recopilar índices y carpetas que necesitan sondeo
        struct Job {
            let index: Int
            let folderPrefix: String   // e.g. "b6a9890c-…/3865d176-…/"
            let bucket: String
            let ext: String            // e.g. "jpg"
        }

        var jobs: [Job] = []
        for (i, row) in rows.enumerated() {
            guard row.imageGalleryRaws.count < 2,
                  let sp = row.storagePathColumn?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sp.isEmpty else { continue }

            // Extraer carpeta y extensión del cover path (e.g. "uid/vid/001.jpg")
            let parts = sp.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let folder = parts.dropLast().joined(separator: "/") + "/"
            let filename = String(parts.last!)
            let ext = filename.split(separator: ".").last.map(String.init) ?? "jpg"
            let bucket = row.storageBucketColumn ?? SupabaseClientProvider.vehicleMediaBucket

            jobs.append(Job(index: i, folderPrefix: folder, bucket: bucket, ext: ext))
        }

        guard !jobs.isEmpty else { return }

        // Procesar en lotes de 10 vehículos simultáneamente para no saturar la red
        let batchSize = 10
        for batchStart in stride(from: 0, to: jobs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, jobs.count)
            let batch = Array(jobs[batchStart..<batchEnd])

            // Cada job se procesa en paralelo; devuelve (index, [urls encontradas])
            let results: [(Int, [String])] = await withTaskGroup(of: (Int, [String]).self) { group in
                for job in batch {
                    group.addTask {
                        let found = await probeSequential(
                            folder: job.folderPrefix,
                            bucket: job.bucket,
                            ext: job.ext
                        )
                        return (job.index, found)
                    }
                }
                var collected: [(Int, [String])] = []
                for await r in group { collected.append(r) }
                return collected
            }

            for (idx, urls) in results where !urls.isEmpty {
                rows[idx].imageGalleryRaws = VehicleRow.mergeImageGalleryRaws(rows[idx].imageGalleryRaws, urls)
            }
        }
    }

    // MARK: - Sondeo para un vehículo

    /// Construye URLs públicas para 002…030 y hace HEAD en paralelo con concurrencia limitada.
    private static func probeSequential(folder: String, bucket: String, ext: String) async -> [String] {
        // Generar las URLs candidatas (002 a maxProbe)
        let candidates: [(Int, String)] = (2...maxProbe).map { n in
            let file = String(format: "%03d.%@", n, ext)
            let path = folder + file
            let url = SupabaseClientProvider.publicStorageObjectURL(bucket: bucket, path: path)
            return (n, url)
        }

        // Probar con HEAD concurrente (con TaskGroup limitada a `concurrencyPerVehicle`)
        let found: [String] = await withTaskGroup(of: (Int, String?).self) { group in
            var pending = candidates.makeIterator()
            var active = 0
            var collected: [(Int, String)] = []

            // Lanzar las primeras `concurrencyPerVehicle` tareas
            while active < concurrencyPerVehicle, let (n, url) = pending.next() {
                group.addTask { (n, await headCheck(urlString: url) ? url : nil) }
                active += 1
            }

            // Conforme terminan, lanzar nuevas
            // Si encontramos un gap (404), seguimos probando un poco por si hay huecos
            var consecutiveFailures = 0
            let maxConsecutiveFailures = 3

            for await (num, result) in group {
                if let url = result {
                    collected.append((num, url))
                    consecutiveFailures = 0
                } else {
                    consecutiveFailures += 1
                }

                // Lanzar siguiente si no hemos alcanzado demasiados fallos seguidos
                if consecutiveFailures < maxConsecutiveFailures, let (n, url) = pending.next() {
                    group.addTask { (n, await headCheck(urlString: url) ? url : nil) }
                } else if consecutiveFailures >= maxConsecutiveFailures {
                    // Cancelar lo que quede
                    group.cancelAll()
                    break
                }
            }

            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return found
    }

    // MARK: - HEAD request

    private static func headCheck(urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, resp) = try await headSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
