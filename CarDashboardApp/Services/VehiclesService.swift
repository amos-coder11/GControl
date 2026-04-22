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

private struct MarketplaceVehiclesPageParams: Encodable, Sendable {
    let p_limit: Int
    let p_offset: Int
    let p_company_id: String?

    /// PostgREST solo resuelve `marketplace_vehicles_page(integer, integer)` si el cuerpo JSON no incluye la tercera clave.
    /// Enviar `p_company_id: null` hace que falle el matcheo con la función de 2 argumentos (BD sin migración `20260412100000`).
    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_offset
        case p_company_id
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encode(p_offset, forKey: .p_offset)
        if let p_company_id {
            try c.encode(p_company_id, forKey: .p_company_id)
        }
    }
}

enum VehiclesService {
    /// Decodifica JSON PostgREST y enriquece imágenes.
    /// - `forMarketplaceList`: solo usa columnas JSON (`images`, `main_image_url`, etc.). Omite RPC Storage y sondas HEAD
    ///   para que el listado de Coches aparezca en segundos con cientos de filas; el detalle puede enriquecer después.
    private static func decodeAndEnrichVehicleRows(
        rawObjects: [JSONObject],
        client: SupabaseClient,
        forMarketplaceList: Bool
    ) async -> [VehicleRow] {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        var rows: [VehicleRow] = []
        rows.reserveCapacity(rawObjects.count)
        for obj in rawObjects {
            guard let data = try? encoder.encode(obj),
                  var row = try? decoder.decode(VehicleRow.self, from: data) else { continue }
            VehicleJSONImageFinder.merge(into: &row, rowJSON: obj)
            rows.append(row)
        }

        if forMarketplaceList {
            return rows
        }

        do {
            try await VehicleStorageCoverPathsRPC.attachCoverPathsIfNeeded(rows: &rows, client: client)
        } catch {}

        await VehicleStorageMediaPathsRPC.mergeIntoRows(&rows, client: client)
        await StorageSiblingGallery.mergeIntoRows(&rows, client: client)

        let needsMoreImages = rows.contains { $0.imageGalleryRaws.count < 2 }
        if needsMoreImages {
            await LocalVehicleStorageGallery.mergeFolderListingIntoRows(&rows, client: client)
            await SupabaseStorageURLSiblingGallery.mergeIntoRows(&rows, client: client)
        }

        let stillNeedGallery = rows.contains { $0.imageGalleryRaws.count < 2 && $0.storagePathColumn != nil }
        if stillNeedGallery {
            await SequentialStorageProbe.mergeIntoRows(&rows)
        }

        VehicleImageDiagnostics.logAfterFetch(rows: rows, rawObjects: rawObjects)
        return rows
    }

    /// Página de vehículos con offset/limit para paginación incremental.
    /// Si se pasa `companyId`, filtra solo los vehículos de esa empresa (+ los de company_id NULL = catálogo público).
    static func fetchPage(
        offset: Int,
        limit: Int,
        companyId: UUID? = nil,
        organizationId: UUID? = nil,
        ownerUserId: UUID? = nil,
        client: SupabaseClient = SupabaseClientProvider.shared,
        forMarketplaceList: Bool = true
    ) async throws -> [VehicleRow] {
        var query = client
            .from(SupabaseClientProvider.vehiclesTableName)
            .select()

        if let uid = ownerUserId {
            query = query.eq("user_id", value: uid.uuidString.lowercased())
        }

        if let oid = organizationId {
            query = query.eq("organization_id", value: oid.uuidString.lowercased())
        }

        if let cid = companyId {
            // Filtra por empresa: muestra los de la empresa + los de catálogo público (company_id IS NULL).
            query = query.or("company_id.eq.\(cid.uuidString),company_id.is.null")
        }

        do {
            let objects: [JSONObject] = try await query
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
            return await decodeAndEnrichVehicleRows(
                rawObjects: objects,
                client: client,
                forMarketplaceList: forMarketplaceList
            )
        } catch {
            // Si la tabla aún no tiene `company_id` (migración pendiente), PostgREST rechaza el `.or(...)` sobre esa columna.
            if companyId != nil {
                return try await fetchPage(
                    offset: offset,
                    limit: limit,
                    companyId: nil,
                    organizationId: organizationId,
                    ownerUserId: ownerUserId,
                    client: client,
                    forMarketplaceList: forMarketplaceList
                )
            }
            throw error
        }
    }

    /// Catálogo vía RPC `SECURITY DEFINER`. Si se pasa `companyId`, filtra por empresa.
    private static func fetchAllViaMarketplaceRPC(
        client: SupabaseClient,
        companyId: UUID? = nil,
        onAccumulated: (([VehicleRow]) async -> Void)? = nil
    ) async throws -> [VehicleRow] {
        var all: [VehicleRow] = []
        var offset = 0
        let pageSize = 50
        while true {
            try Task.checkCancellation()
            let objects: [JSONObject] = try await client.rpc(
                SupabaseClientProvider.marketplaceVehiclesRPCName,
                params: MarketplaceVehiclesPageParams(
                    p_limit: pageSize,
                    p_offset: offset,
                    p_company_id: companyId?.uuidString
                )
            )
            .execute()
            .value
            if objects.isEmpty { break }
            let chunk = await decodeAndEnrichVehicleRows(
                rawObjects: objects,
                client: client,
                forMarketplaceList: true
            )
            all.append(contentsOf: chunk)
            if let onAccumulated {
                await onAccumulated(dedupeVehicleRowsForMarketplace(all))
            }
            if objects.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    /// Lee filas como árbol JSON completo y fusiona imágenes desde `AnyJSON` (p. ej. `image_url` jsonb).
    /// Mantiene compatibilidad pero ahora usa paginación interna. Filtra por `companyId` si se indica.
    static func fetchAll(
        companyId: UUID? = nil,
        organizationId: UUID? = nil,
        ownerUserId: UUID? = nil,
        client: SupabaseClient = SupabaseClientProvider.shared,
        onPartial: (([VehicleRow]) async -> Void)? = nil
    ) async throws -> [VehicleRow] {
        var allRows: [VehicleRow] = []
        let pageSize = 50
        var offset = 0

        while true {
            try Task.checkCancellation()
            let page = try await fetchPage(
                offset: offset,
                limit: pageSize,
                companyId: companyId,
                organizationId: organizationId,
                ownerUserId: ownerUserId,
                client: client
            )
            allRows.append(contentsOf: page)
            if let onPartial {
                await onPartial(dedupeVehicleRowsForMarketplace(allRows))
            }
            if page.count < pageSize { break }
            offset += pageSize
        }

        return allRows
    }

    /// Paginación completa sin propagar error (p. ej. consultas `anon` cuando RLS devuelve 403 o falla la red).
    private static func accumulatePagesLenient(companyId: UUID? = nil, client: SupabaseClient) async -> [VehicleRow] {
        var all: [VehicleRow] = []
        var offset = 0
        let pageSize = 50
        while true {
            do {
                let page = try await fetchPage(
                    offset: offset,
                    limit: pageSize,
                    companyId: companyId,
                    organizationId: nil,
                    ownerUserId: nil,
                    client: client
                )
                if page.isEmpty { break }
                all.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            } catch {
                break
            }
        }
        return all
    }

    private static func mergeVehicleRowsByIdPreferSession(_ anon: [VehicleRow], _ session: [VehicleRow]) -> [VehicleRow] {
        var byId: [UUID: VehicleRow] = [:]
        for r in anon { byId[r.id] = r }
        for r in session { byId[r.id] = r }
        return byId.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func normalizedPlateKey(_ r: VehicleRow) -> String? {
        let raw = [r.plate, r.license_plate, r.matricula]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "—" }
        return raw?.lowercased()
    }

    /// Quita duplicados: mismo `id`, mismo `dealcar_vehicle_id`, o misma matrícula (evita filas duplicadas en BD).
    private static func dedupeVehicleRowsForMarketplace(_ rows: [VehicleRow]) -> [VehicleRow] {
        var seenIds = Set<UUID>()
        var seenDealcar = Set<String>()
        var seenPlates = Set<String>()
        var out: [VehicleRow] = []
        out.reserveCapacity(rows.count)
        for r in rows {
            if seenIds.contains(r.id) { continue }
            seenIds.insert(r.id)
            if let raw = r.dealcar_vehicle_id?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let k = raw.lowercased()
                if seenDealcar.contains(k) { continue }
                seenDealcar.insert(k)
            }
            if let pk = normalizedPlateKey(r) {
                if seenPlates.contains(pk) { continue }
                seenPlates.insert(pk)
            }
            out.append(r)
        }
        return out
    }

    /// Unión del inventario visible como `anon` y con JWT (`shared`). Así el listado refleja todas las filas que
    /// permita cualquiera de los dos conjuntos de políticas RLS (p. ej. anuncios públicos + stock del concesionario).
    /// Si se pasa `companyId`, filtra por empresa del usuario (solo ve coches de su empresa + catálogo público).
    ///
    /// `onPartial`: notificación tras cada página de la RPC (y una vez al terminar la ruta por tabla) para pintar el listado al instante.
    static func fetchAllMergedForMarketplace(
        companyId: UUID? = nil,
        onPartial: (([VehicleRow]) async -> Void)? = nil
    ) async throws -> [VehicleRow] {
        // Inventario de la organización del perfil (`user_profiles.organization_id` → `vehicles.organization_id`).
        if SupabaseClientProvider.vehiclesBrowseLimitToOrganization {
            let orgId = await fetchMyOrganizationId()
            guard let orgId else {
                if let onPartial { await onPartial([]) }
                return []
            }
            let rows = try await fetchAll(
                companyId: companyId,
                organizationId: orgId,
                ownerUserId: nil,
                client: SupabaseClientProvider.shared,
                onPartial: onPartial
            )
            return dedupeVehicleRowsForMarketplace(rows)
        }

        // Inventario solo del usuario con sesión: útil si cada vendedor tiene su `user_id` en filas.
        if SupabaseClientProvider.vehiclesBrowseLimitToSessionUser {
            let uid: UUID
            do {
                uid = try await SupabaseClientProvider.shared.auth.session.user.id
            } catch {
                if let onPartial { await onPartial([]) }
                return []
            }
            let rows = try await fetchAll(
                companyId: companyId,
                organizationId: nil,
                ownerUserId: uid,
                client: SupabaseClientProvider.shared,
                onPartial: onPartial
            )
            return dedupeVehicleRowsForMarketplace(rows)
        }

        if SupabaseClientProvider.prefersMarketplaceVehiclesRPC {
            do {
                try Task.checkCancellation()
                let viaRpc = try await fetchAllViaMarketplaceRPC(
                    client: SupabaseClientProvider.shared,
                    companyId: companyId,
                    onAccumulated: onPartial
                )
                if !viaRpc.isEmpty { return dedupeVehicleRowsForMarketplace(viaRpc) }
            } catch {
                // La RPC aún no existe en el proyecto o falló: se sigue con lectura por tabla.
            }
        }

        // El cliente anon no tiene company_id (no hay sesión), así que solo trae catálogo público (company_id IS NULL via RLS).
        async let fromAnonTask = accumulatePagesLenient(client: SupabaseClientProvider.catalogAnon)
        let fromSession: [VehicleRow]
        do {
            try Task.checkCancellation()
            // La lectura por tabla filtra via RLS (vehicles_company_select_authenticated)
            // + filtro explícito por company_id en la query PostgREST.
            fromSession = try await fetchAll(companyId: companyId, client: SupabaseClientProvider.shared)
        } catch {
            let anonOnly = await fromAnonTask
            if anonOnly.isEmpty { throw error }
            let sorted = dedupeVehicleRowsForMarketplace(anonOnly.sorted { $0.id.uuidString < $1.id.uuidString })
            if let onPartial { await onPartial(sorted) }
            return sorted
        }
        let anonRows = await fromAnonTask
        let merged = dedupeVehicleRowsForMarketplace(mergeVehicleRowsByIdPreferSession(anonRows, fromSession))
        if let onPartial { await onPartial(merged) }
        return merged
    }

    private struct UserProfileOrganizationRow: Decodable, Sendable {
        let organization_id: UUID?
    }

    /// Organización del usuario (`user_profiles.organization_id` / tabla en `USER_PROFILES_TABLE`).
    static func fetchMyOrganizationId() async -> UUID? {
        do {
            let uid = try await SupabaseClientProvider.shared.auth.session.user.id
            let rows: [UserProfileOrganizationRow] = try await SupabaseClientProvider.shared
                .from(SupabaseClientProvider.profilesTableName)
                .select("organization_id")
                .eq("user_id", value: uid.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
            return rows.first?.organization_id
        } catch {
            return nil
        }
    }

    /// Obtiene el `company_id` del usuario autenticado llamando a la RPC `get_my_company_id`.
    /// La RPC devuelve `uuid`; Supabase lo serializa como string JSON.
    static func fetchMyCompanyId() async -> UUID? {
        // Intentar decodificar directamente como String (formato habitual de Supabase para uuid).
        do {
            let result: String = try await SupabaseClientProvider.shared
                .rpc("get_my_company_id")
                .execute()
                .value
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
            return UUID(uuidString: trimmed)
        } catch {
            // Si falla como String, intentar como JSON arbitrario por si viene como null o formato inesperado.
            do {
                let data = try await SupabaseClientProvider.shared
                    .rpc("get_my_company_id")
                    .execute()
                    .data
                guard let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\""))) else { return nil }
                if raw == "null" || raw.isEmpty { return nil }
                return UUID(uuidString: raw)
            } catch {
                return nil
            }
        }
    }

    enum InsertVehicleError: LocalizedError {
        case notAuthenticated
        case noTenantAssigned
        case invalidForm(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Inicia sesión para añadir vehículos."
            case .noTenantAssigned:
                return "Tu cuenta no tiene organización ni empresa asignada. Un administrador debe enlazar tu perfil en Supabase (user_profiles.organization_id o profiles.company_id)."
            case let .invalidForm(msg):
                return msg
            }
        }
    }

    /// Insert: ficha completa + columnas de anuncio cuando existen en BD (`listing_extra` jsonb, precios, etc.).
    private struct VehicleInsertRow: Encodable, Sendable {
        let id: UUID
        let user_id: UUID
        let organization_id: UUID?
        let company_id: UUID?
        let brand: String
        let model: String
        let year: Int
        let license_plate: String?
        let price: Double?
        let mileage: Int?
        let power_cv: Int?
        let fuel_type: String?
        let transmission: String?
        let vin: String?
        let exterior_color: String?
        let dgt_label: String?
        let purchase_price: Double?
        let market_price: Double?
        let financed_price: Double?
        let listing_description: String?
        let listing_extra: VehicleListingExtraJSON?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: VehiclesInsertDynamicKey.self)
            try c.encode(id, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.id))
            try c.encode(user_id, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.userId))
            try c.encodeIfPresent(organization_id, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.organizationId))
            try c.encodeIfPresent(company_id, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.companyId))
            try c.encode(brand, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.brand))
            try c.encode(model, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.model))
            try c.encode(year, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.year))
            try c.encodeIfPresent(license_plate, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.licensePlate))
            try c.encodeIfPresent(price, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.price))
            try c.encodeIfPresent(mileage, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.mileage))
            try c.encodeIfPresent(power_cv, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.powerCv))
            try c.encodeIfPresent(fuel_type, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.fuelType))
            try c.encodeIfPresent(transmission, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.transmission))
            try c.encodeIfPresent(vin, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.vin))
            try c.encodeIfPresent(exterior_color, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.color))
            try c.encodeIfPresent(dgt_label, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.dgtLabel))
            try c.encodeIfPresent(purchase_price, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.purchasePrice))
            try c.encodeIfPresent(market_price, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.marketPrice))
            try c.encodeIfPresent(financed_price, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.financedPrice))
            try c.encodeIfPresent(listing_description, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.listingDescription))
            try c.encodeIfPresent(listing_extra, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.listingExtra))
        }
    }

    /// Inserta en `vehicles` con el tenant del usuario.
    /// Si hay JPEG, se suben a `vehicle-media/{user_id}/{vehicle_id}/` y se intenta guardar la URL pública en `main_image_url` (migración `20260419160000_vehicles_main_image_url_and_update_rls.sql`).
    static func insertVehicleFromApp(
        _ payload: VehicleAppListingPayload,
        imagesJPEGData: [Data] = [],
        client: SupabaseClient = SupabaseClientProvider.shared
    ) async throws -> VehicleRow {
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw InsertVehicleError.notAuthenticated
        }
        let uid = session.user.id

        async let orgTask = fetchMyOrganizationId()
        let compId = await fetchMyCompanyId()
        let orgId = await orgTask

        guard orgId != nil || compId != nil else {
            throw InsertVehicleError.noTenantAssigned
        }

        let b = payload.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty, !m.isEmpty else {
            throw InsertVehicleError.invalidForm("Marca y modelo son obligatorios.")
        }

        let y = payload.year
        guard (1950...2035).contains(y) else {
            throw InsertVehicleError.invalidForm("El año debe estar entre 1950 y 2035.")
        }

        let plateRaw = payload.licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plate: String? = plateRaw.isEmpty ? nil : plateRaw

        let vehicleId = UUID()

        let extra = Self.sanitizedListingExtra(payload.listingExtra)

        // ── 1. Insertar el vehículo ───────────────────────────────────
        let row = VehicleInsertRow(
            id: vehicleId,
            user_id: uid,
            organization_id: orgId,
            company_id: compId,
            brand: b,
            model: m,
            year: y,
            license_plate: plate,
            price: payload.salePriceEUR,
            mileage: payload.mileageKm,
            power_cv: payload.powerCv,
            fuel_type: Self.trimmedNilIfEmpty(payload.fuelType),
            transmission: Self.trimmedNilIfEmpty(payload.transmission),
            vin: Self.trimmedNilIfEmpty(payload.vin),
            exterior_color: Self.trimmedNilIfEmpty(payload.exteriorColor),
            dgt_label: Self.sanitizedDGTLabelForStorage(payload.dgtLabel),
            purchase_price: payload.purchasePriceEUR,
            market_price: payload.marketPriceEUR,
            financed_price: payload.financedPriceEUR,
            listing_description: Self.trimmedNilIfEmpty(payload.listingDescription),
            listing_extra: extra
        )

        let inserted: VehicleRow = try await client
            .from(SupabaseClientProvider.vehiclesTableName)
            .insert(row)
            .select()
            .single()
            .execute()
            .value

        let trimmedJPEG = imagesJPEGData.filter { !$0.isEmpty }
        guard !trimmedJPEG.isEmpty else {
            return inserted
        }

        let mediaBucket = SupabaseClientProvider.vehicleMediaBucket
        let folder = "\(uid.uuidString.lowercased())/\(vehicleId.uuidString.lowercased())"
        let maxBytes = 14 * 1024 * 1024
        let maxFiles = 8

        // Subida en serie: menos presión QUIC y errores RLS más claros que muchas tareas a la vez.
        var coverUploadOK = false
        for (index, jpegData) in trimmedJPEG.prefix(maxFiles).enumerated() {
            guard jpegData.count <= maxBytes else {
                print("[VehiclesService] Imagen \(index + 1) supera 14 MB, omitida.")
                continue
            }
            let fileName = String(format: "%03d.jpg", index + 1)
            let storagePath = "\(folder)/\(fileName)"
            do {
                _ = try await client.storage
                    .from(mediaBucket)
                    .upload(
                        storagePath,
                        data: jpegData,
                        options: FileOptions(contentType: "image/jpeg", upsert: true)
                    )
                if index == 0 { coverUploadOK = true }
            } catch {
                print("[VehiclesService] Error subiendo imagen \(fileName): \(error)")
            }
        }

        let coverPublicURL = SupabaseClientProvider.publicStorageObjectURL(
            bucket: mediaBucket,
            path: "\(folder)/001.jpg"
        )
        if coverUploadOK {
            await patchVehicleMainImageURLColumn(
                client: client,
                vehicleId: vehicleId,
                publicURLString: coverPublicURL
            )
        }

        do {
            let refreshed: VehicleRow = try await client
                .from(SupabaseClientProvider.vehiclesTableName)
                .select()
                .eq("id", value: vehicleId.uuidString.lowercased())
                .single()
                .execute()
                .value
            return refreshed
        } catch {
            return inserted
        }
    }

    /// Actualiza la columna configurable (`main_image_url` por defecto) para que el listado marketplace muestre la portada sin listar Storage.
    private static func patchVehicleMainImageURLColumn(
        client: SupabaseClient,
        vehicleId: UUID,
        publicURLString: String
    ) async {
        struct Patch: Encodable {
            let value: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: VehiclesInsertDynamicKey.self)
                try c.encode(value, forKey: VehiclesInsertDynamicKey(VehiclesInsertColumnMap.mainImageURL))
            }
        }
        do {
            try await client
                .from(SupabaseClientProvider.vehiclesTableName)
                .update(Patch(value: publicURLString))
                .eq("id", value: vehicleId.uuidString.lowercased())
                .execute()
        } catch {
            print("[VehiclesService] No se pudo guardar \(VehiclesInsertColumnMap.mainImageURL) (¿columna o política UPDATE?): \(error)")
        }
    }

    private static func trimmedNilIfEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// No guardar «ECO» como distintivo: en alta suele colarse por error; la tarjeta tampoco lo muestra.
    private static func sanitizedDGTLabelForStorage(_ s: String?) -> String? {
        guard let t = trimmedNilIfEmpty(s) else { return nil }
        let folded = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
        let compact = folded.lowercased().replacingOccurrences(of: " ", with: "")
        if compact == "eco" || compact == "dgteco" { return nil }
        return t
    }

    /// Evita escribir `listing_extra` vacío en jsonb.
    private static func sanitizedListingExtra(_ raw: VehicleListingExtraJSON?) -> VehicleListingExtraJSON? {
        guard var e = raw else { return nil }
        if let codes = e.equipmentCodes, codes.isEmpty { e.equipmentCodes = nil }
        let empty =
            e.acquisitionCategory == nil
            && e.vatDeductible == nil
            && e.singleOwner == nil
            && e.serviceBook == nil
            && e.officialServiceBook == nil
            && e.nationalVehicle == nil
            && e.dgtLabelNote == nil
            && e.storeLocation == nil
            && (e.equipmentCodes == nil || e.equipmentCodes?.isEmpty == true)
            && e.ownerName == nil
            && e.ownerPhone == nil
            && e.ownerEmail == nil
            && e.ownerZone == nil
            && e.ownerCanVisitOffice == nil
            && e.publishAllPlatforms == nil
            && e.publishAutoScout == nil
            && e.publishCochesNet == nil
            && e.publishWallapop == nil
            && e.publishOwnWeb == nil
            && e.lastServiceKm == nil
            && e.lastServiceYear == nil
        return empty ? nil : e
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
