import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

struct CarsView: View {
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var showSortSheet = false
    @State private var showFilterSheet = false
    @State private var showAddVehicleSheet = false
    @State private var editingCar: Car?
    /// Baja el FAB con la tab bar al hacer scroll hacia abajo (`tabBarMinimizeBehavior(.onScrollDown)`).
    @State private var fabSunkToMatchHiddenTabBar = false
    @FocusState private var browseSearchFieldFocused: Bool

    private var displayedCars: [Car] {
        carsVM.displayedBrowseCars()
    }

    private var resultCountText: String {
        displayedCars.count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    private var browseContextEmpty: Bool {
        carsVM.browseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !carsVM.browseFilters.hasActiveFilters
    }

    private var carsEmptyFootnote: String {
        if carsVM.lastFetchHadZeroRowsFromBackend, browseContextEmpty {
            return "Prueba a limpiar filtros o cambiar la búsqueda.\n\nEl servidor devolvió 0 filas: en Supabase revisa RLS de «vehicles». Para el mismo catálogo en todas las cuentas, permite SELECT a «anon» y «authenticated». Ejemplo en el repo: supabase/migrations/20260330130000_vehicles_marketplace_read_all.sql"
        }
        return "Prueba a limpiar filtros o cambiar la búsqueda."
    }

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                stickyBrowseChrome

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        Text("\(resultCountText) resultados")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)

                        if carsVM.isLoadingVehicles && carsVM.cars.isEmpty {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 32)
                        }

                        if let err = carsVM.vehiclesError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }

                        if !carsVM.isLoadingVehicles || !carsVM.cars.isEmpty {
                            if displayedCars.isEmpty {
                                ContentUnavailableView(
                                    "Sin resultados",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text(carsEmptyFootnote)
                                )
                                .foregroundStyle(.white)
                                .symbolRenderingMode(.hierarchical)
                                .tint(.white.opacity(0.85))
                                .padding(.vertical, 24)
                                .padding(.horizontal, 16)
                            } else {
                                LazyVStack(spacing: 14) {
                                    ForEach(Array(displayedCars.enumerated()), id: \.element.id) { idx, car in
                                        CarListingCard(
                                            car: car,
                                            isSelected: carsVM.isSelected(car)
                                        ) {
                                            carsVM.selectCar(car)
                                            editingCar = car
                                        }
                                        .frame(maxWidth: .infinity)
                                        // Sin prefetch de vecinos: con CDN lento compite por las mismas ranuras HTTP
                                        // que las filas visibles (`HTTPImageDownloadGate`) y deja todo en spinner.
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            if carsVM.isLoadingMoreVehicles {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white.opacity(0.7))
                                    Text("Cargando más vehículos…")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.bottom, 28)
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .onScrollGeometryChange(for: Int.self) { geo in
                    let y = geo.contentOffset.y
                    if y < 40 { return 0 }
                    if y > 72 { return 2 }
                    return 1
                } action: { _, zone in
                    switch zone {
                    case 0:
                        if fabSunkToMatchHiddenTabBar {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                fabSunkToMatchHiddenTabBar = false
                            }
                        }
                    case 2:
                        if !fabSunkToMatchHiddenTabBar {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                fabSunkToMatchHiddenTabBar = true
                            }
                        }
                    default:
                        break
                    }
                }
                .refreshable {
                    await carsVM.loadVehicles(companyId: auth.companyId)
                }
            }
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                addVehicleFAB
                    .padding(.trailing, AppChromeHeaderMetrics.horizontalPadding)
                    .padding(.bottom, 6)
                    .offset(y: fabSunkToMatchHiddenTabBar ? fabOffsetWhenTabBarMinimized : 0)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    LiquidGlassKeyboardAccessoryBar {
                        browseSearchFieldFocused = false
                    }
                }
            }
            .sheet(isPresented: $showSortSheet) {
                CarsSortSheet(sort: $carsVM.browseSort)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFilterSheet) {
                CarsFilterSheet(
                    filters: $carsVM.browseFilters,
                    sourceCars: carsVM.cars,
                    resultCount: carsVM.displayedBrowseCars().count,
                    onClear: {}
                )
            }
            .sheet(isPresented: $showAddVehicleSheet) {
                AddVehicleSheet()
                    .environmentObject(tabRouter)
                    .environmentObject(auth)
                    .environmentObject(carsVM)
            }
            .sheet(item: $editingCar) { car in
                EditVehicleDictationSheet(car: car) {
                    Task { await carsVM.loadVehicles(companyId: auth.companyId) }
                }
            }
            .task {
                if carsVM.cars.isEmpty && !carsVM.isLoadingVehicles {
                    await carsVM.loadVehicles(companyId: auth.companyId)
                }
            }
            .onChange(of: auth.companyId) { oldCompanyId, newCompanyId in
                // Cuando se resuelve el company_id del usuario, recargar vehículos filtrados por empresa.
                // Evita recarga duplicada si el valor no cambió realmente.
                guard oldCompanyId != newCompanyId else { return }
                Task {
                    await carsVM.loadVehicles(companyId: newCompanyId)
                }
            }
        }
    }

    private var stickyBrowseChrome: some View {
        CarsBrowseHeaderBar(
            initials: auth.userInitials,
            profileImage: auth.profileAvatarImage,
            searchText: $carsVM.browseSearchText,
            hasActiveFilters: carsVM.browseFilters.hasActiveFilters,
            searchFieldFocused: $browseSearchFieldFocused,
            onSort: { showSortSheet = true },
            onFilter: { showFilterSheet = true }
        )
        .appChromeHeaderOuterPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Desplazamiento hacia abajo cuando la tab bar se minimiza (ajusta si no calza con tu simulador).
    private let fabOffsetWhenTabBarMinimized: CGFloat = 52

    /// Mismo cromado y tamaño que Ordenar / Filtros (`AppChromeHeaderCircleIconButton`).
    private var addVehicleFAB: some View {
        AppChromeHeaderCircleIconButton(
            systemName: "plus",
            accessibilityLabel: "Añadir vehículo",
            action: { showAddVehicleSheet = true }
        )
        .accessibilityHint("Formulario para dar de alta un vehículo en tu inventario")
    }
}

// MARK: - Añadir coche (hoja compartida con Inicio)

struct AddVehicleSheet: View {
    private struct StagedPhoto: Identifiable {
        let id = UUID()
        var jpegData: Data
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel

    @State private var brand = ""
    @State private var model = ""
    @State private var yearText = ""
    @State private var plate = ""
    @State private var priceText = ""
    @State private var mileageText = ""
    @State private var powerCvText = ""
    @State private var fuel = ""
    @State private var transmission = ""
    @State private var tenantLine = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var stagedPhotos: [StagedPhoto] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var recentGalleryAssets: [PHAsset] = []
    @State private var galleryAccessDenied = false
    @State private var isLoadingRecentGallery = true
    @State private var isVisionFilling = false
    @State private var listingXF = AddVehicleListingExtendedState()
    @State private var listingEquipmentCodes: Set<String> = []

    private let maxVehiclePhotos = 8

    private var parsedYear: Int? {
        Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        let b = !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let m = !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let y = parsedYear != nil
        let sale = Self.parseOptionalDouble(priceText).map { $0 > 0 } ?? false
        let purchase = Self.parseOptionalDouble(listingXF.purchasePriceText).map { $0 > 0 } ?? false
        let col = !listingXF.colorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let plt = !plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return b && m && y && sale && purchase && col && plt
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.05, blue: 0.1),
                            Color.black,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    Circle()
                        .fill(PremiumAccent.tabActive.opacity(0.12))
                        .frame(width: 300, height: 300)
                        .blur(radius: 90)
                        .offset(x: -150, y: -250)
                    
                    Circle()
                        .fill(PremiumAccent.ice.opacity(0.08))
                        .frame(width: 250, height: 250)
                        .blur(radius: 80)
                        .offset(x: 150, y: -50)
                }
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        introBlock

                        if !tenantLine.isEmpty {
                            tenantNoticeCard
                        }

                        sectionHeader(
                            icon: "photo.on.rectangle.angled",
                            title: "Fotos",
                            subtitle: "Hasta \(maxVehiclePhotos), opcional · Storage seguro"
                        )

                        LiquidGlassDarkFormPanel {
                            vehiclePhotosBlock
                        }

                        sectionHeader(
                            icon: "car.fill",
                            title: "Datos principales",
                            subtitle: "Marca, modelo y año"
                        )

                        LiquidGlassDarkFormPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                formFieldLabel("Marca")
                                formField($brand, prompt: "Ej. BMW")
                                formFieldLabel("Modelo")
                                formField($model, prompt: "Ej. M3 Competition")
                                formFieldLabel("Año")
                                formField($yearText, prompt: "2024", keyboard: .numberPad)
                            }
                        }

                        sectionHeader(
                            icon: "list.bullet.rectangle.fill",
                            title: "Detalles del vehículo",
                            subtitle: "Matrícula, kilometraje, potencia, combustible y transmisión"
                        )

                        LiquidGlassDarkFormPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                formFieldLabel("Matrícula *")
                                formField($plate, prompt: "3344 ABC")
                                formFieldLabel("Kilometraje")
                                formField($mileageText, prompt: "12000", keyboard: .numberPad)
                                formFieldLabel("Caballos (CV)")
                                formField($powerCvText, prompt: "Ej. 184", keyboard: .numberPad)
                                formFieldLabel("Combustible")
                                formField($fuel, prompt: "Gasolina, diésel, eléctrico, híbrido…")
                                formFieldLabel("Transmisión")
                                formField($transmission, prompt: "Manual, automático…")
                            }
                        }

                        sectionHeader(
                            icon: "eurosign.circle.fill",
                            title: "Stock, fiscalidad y anuncio",
                            subtitle: "Precios, IVA, equipamiento, dueño y portales (se guardan en Supabase)"
                        )

                        LiquidGlassDarkFormPanel {
                            AddVehicleListingDetailsForm(
                                xf: $listingXF,
                                equipmentCodes: $listingEquipmentCodes,
                                salePriceText: $priceText,
                                listingFactsSnapshot: {
                                    Self.buildListingAIFacts(
                                        brand: brand,
                                        model: model,
                                        yearText: yearText,
                                        plate: plate,
                                        mileageText: mileageText,
                                        powerCvText: powerCvText,
                                        fuel: fuel,
                                        transmission: transmission,
                                        salePriceText: priceText,
                                        xf: listingXF,
                                        equipmentCodes: listingEquipmentCodes
                                    )
                                },
                                formErrorMessage: $errorMessage
                            )
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PremiumAccent.coral.opacity(0.95))
                                .padding(.horizontal, 4)
                        }

                        saveButton

                        Button {
                            dismiss()
                            tabRouter.selected = .cars
                        } label: {
                            Text("Ir a pestaña Coches")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.42))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 72)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Añadir vehículo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            DashboardChromeHeaderCircleBackground(size: 40)
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                    .buttonStyle(ChromeCirclePressButtonStyle(diameter: 40))
                    .accessibilityLabel("Cerrar")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await refreshTenantLine()
            await loadRecentGalleryStrip()
        }
        .onAppear {
            if yearText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                yearText = String(Calendar.current.component(.year, from: Date()))
            }
        }
        .onChange(of: photoPickerItem) { _, item in
            Task { await handlePickedPhoto(item) }
        }
    }

    private var vehiclePhotosBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("La primera foto será la portada en Coches. Se suben al bucket de medios (p. ej. vehicle-media) en la ruta usuario/id del vehículo.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineSpacing(3)

            recentGalleryStrip

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SELECCIONADAS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.65)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("\(stagedPhotos.count)/\(maxVehiclePhotos)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(stagedPhotos) { photo in
                        vehiclePhotoThumb(photo)
                    }
                    if stagedPhotos.count < maxVehiclePhotos {
                        vehiclePhotoAddTile
                    }
                }
            }

            visionFillFromPhotoRow
        }
    }

    private var recentGalleryStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECIENTES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.65)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 8)
                Text("Desliza · toca para añadir")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))
            }

            Group {
                if isLoadingRecentGallery {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.65)
                            }
                    }
                } else if galleryAccessDenied {
                    Text("Activa el acceso a Fotos en Ajustes para ver aquí tus imágenes más recientes.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.65)
                                }
                        }
                } else if recentGalleryAssets.isEmpty {
                    Text("No hay fotos en la galería o el acceso es limitado.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recentGalleryAssets, id: \.localIdentifier) { asset in
                                AddVehicleRecentGalleryThumb(asset: asset) {
                                    Task { await addPhotoFromGalleryAsset(asset) }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, -4)
                }
            }
        }
    }

    private func loadRecentGalleryStrip() async {
        await MainActor.run {
            isLoadingRecentGallery = true
            galleryAccessDenied = false
        }

        let rawStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let finalStatus: PHAuthorizationStatus
        if rawStatus == .notDetermined {
            finalStatus = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { cont.resume(returning: $0) }
            }
        } else {
            finalStatus = rawStatus
        }

        let denied = finalStatus == .denied || finalStatus == .restricted
        guard !denied, finalStatus == .authorized || finalStatus == .limited else {
            await MainActor.run {
                recentGalleryAssets = []
                galleryAccessDenied = denied
                isLoadingRecentGallery = false
            }
            return
        }

        let assets = await Self.fetchRecentImageAssets(limit: 36)
        await MainActor.run {
            recentGalleryAssets = assets
            galleryAccessDenied = false
            isLoadingRecentGallery = false
        }
    }

    private static func fetchRecentImageAssets(limit: Int) async -> [PHAsset] {
        await MainActor.run {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = limit
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var list: [PHAsset] = []
            list.reserveCapacity(min(limit, result.count))
            result.enumerateObjects { asset, _, stop in
                list.append(asset)
                if list.count >= limit {
                    stop.pointee = true
                }
            }
            return list
        }
    }

    private func addPhotoFromGalleryAsset(_ asset: PHAsset) async {
        guard stagedPhotos.count < maxVehiclePhotos else { return }
        guard let data = await Self.requestImageData(from: asset) else {
            await MainActor.run {
                errorMessage = "No se pudo leer la foto. Prueba otra o usa «Añadir»."
            }
            return
        }
        guard let jpeg = Self.prepareJPEGForUpload(data) else {
            await MainActor.run {
                errorMessage = "Formato no válido para esta imagen."
            }
            return
        }
        await MainActor.run {
            errorMessage = nil
            guard stagedPhotos.count < maxVehiclePhotos else { return }
            stagedPhotos.append(StagedPhoto(jpegData: jpeg))
        }
    }

    private static func requestImageData(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                cont.resume(returning: data)
            }
        }
    }

    private func vehiclePhotoThumb(_ photo: StagedPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let ui = UIImage(data: photo.jpegData) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)

            Button {
                stagedPhotos.removeAll { $0.id == photo.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
            .accessibilityLabel("Quitar foto")
        }
    }

    private var vehiclePhotoAddTile: some View {
        PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
            ZStack {
                LiquidGlassFormFieldBackground(cornerRadius: 16)
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PremiumAccent.ice, PremiumAccent.tabActive.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Añadir")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Añadir foto desde la galería")
    }

    private var visionFillFromPhotoRow: some View {
        let hasKey = OpenAIVehicleVisionClient.isConfigured
        let hasPhoto = !stagedPhotos.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await runVisionFillFromFirstPhoto() }
            } label: {
                HStack(spacing: 12) {
                    if isVisionFilling {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(PremiumAccent.ice)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [PremiumAccent.ice, PremiumAccent.tabActive],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rellenar con IA desde la foto")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("Analiza la 1.ª foto seleccionada (marca, modelo, año, extras si se ven).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasPhoto || isVisionFilling || !hasKey)
            .opacity((!hasPhoto || !hasKey) ? 0.5 : 1)

            if !hasKey {
                Text("Añade OPENAI_API_KEY en DeveloperSettings.local.xcconfig (igual que para Viera) y recompila.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasPhoto {
                Text("Elige o añade una foto arriba para poder detectar el vehículo.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private func runVisionFillFromFirstPhoto() async {
        let first = await MainActor.run { stagedPhotos.first }
        guard let first else {
            await MainActor.run { errorMessage = "Añade primero una foto del coche." }
            return
        }
        guard OpenAIVehicleVisionClient.isConfigured else {
            await MainActor.run { errorMessage = "Falta OPENAI_API_KEY en la configuración local." }
            return
        }

        await MainActor.run {
            isVisionFilling = true
            errorMessage = nil
        }

        do {
            let fill = try await OpenAIVehicleVisionClient.inferVehicleFields(fromJPEG: first.jpegData)
            await MainActor.run {
                applyVisionFill(fill)
                isVisionFilling = false
                if fill.brand == nil, fill.model == nil {
                    errorMessage = "No se identificó marca ni modelo. Prueba otra foto más clara o rellena a mano."
                }
            }
            await autoGenerateListingDescriptionAfterVisionIfPossible()
        } catch {
            await MainActor.run {
                isVisionFilling = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyVisionFill(_ fill: VehicleVisionFill) {
        if let b = fill.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            brand = b
        }
        if let m = fill.model?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            model = m
        }
        if let y = fill.year {
            yearText = String(y)
        }
        if let p = fill.licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            plate = p
        }
        if let pr = fill.priceEUR {
            if abs(pr.rounded() - pr) < 0.01 {
                priceText = String(format: "%.0f", pr)
            } else {
                priceText = String(format: "%.2f", pr)
            }
        }
        if let km = fill.mileageKm {
            mileageText = String(km)
        }
        if let f = fill.fuelType?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            fuel = f
        }
        if let t = fill.transmission?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            transmission = t
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let currentCount = await MainActor.run { stagedPhotos.count }
        guard currentCount < maxVehiclePhotos else {
            await MainActor.run { photoPickerItem = nil }
            return
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run { photoPickerItem = nil }
                return
            }
            guard let jpeg = Self.prepareJPEGForUpload(raw) else {
                await MainActor.run {
                    photoPickerItem = nil
                    errorMessage = "No se pudo convertir la imagen. Prueba con JPG o PNG desde Fotos."
                }
                return
            }
            await MainActor.run {
                photoPickerItem = nil
                guard stagedPhotos.count < maxVehiclePhotos else { return }
                stagedPhotos.append(StagedPhoto(jpegData: jpeg))
            }
        } catch {
            await MainActor.run {
                photoPickerItem = nil
                errorMessage = "No se pudo cargar la imagen. Prueba con otra foto."
            }
        }
    }

    /// Escala y comprime a JPEG para subir a Storage.
    /// Si la imagen es vertical, la normaliza al ratio de tarjeta para mantener coherencia en el listado.
    private static func prepareJPEGForUpload(_ data: Data) -> Data? {
        guard let rawImage = UIImage(data: data) else { return nil }
        let img = normalizedUprightImage(rawImage)
        let maxSide: CGFloat = 2400
        let listingAspectRatio: CGFloat = 1 / 0.66
        let w = img.size.width
        let h = img.size.height
        let longest = max(w, h)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: max(w * scale, 1), height: max(h * scale, 1))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let sourceAspect = target.width / max(target.height, 1)
        let normalizedSize: CGSize
        if sourceAspect < listingAspectRatio * 0.95 {
            // Forzamos un lienzo horizontal para que las portadas verticales no rompan la composición del feed.
            let width = maxSide
            normalizedSize = CGSize(width: width, height: max(width / listingAspectRatio, 1))
        } else {
            normalizedSize = target
        }

        let renderer = UIGraphicsImageRenderer(size: normalizedSize, format: format)
        let drawn = renderer.image { _ in
            let canvas = CGRect(origin: .zero, size: normalizedSize)
            if normalizedSize == target {
                img.draw(in: canvas)
                return
            }

            // Fondo adaptado para fotos verticales: rellena sin huecos.
            img.draw(in: aspectFillRect(imageSize: target, in: canvas))
            UIColor.black.withAlphaComponent(0.32).setFill()
            UIRectFillUsingBlendMode(canvas, .sourceAtop)

            // Imagen principal completa encima, manteniendo proporción.
            let insetCanvas = canvas.insetBy(dx: 24, dy: 24)
            img.draw(in: aspectFitRect(imageSize: target, in: insetCanvas))
        }
        return drawn.jpegData(compressionQuality: 0.82)
    }

    /// Aplana la orientación EXIF para que `size` refleje la imagen visual real.
    private static func normalizedUprightImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = max(
            bounds.width / max(imageSize.width, 1),
            bounds.height / max(imageSize.height, 1)
        )
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(
            bounds.width / max(imageSize.width, 1),
            bounds.height / max(imageSize.height, 1)
        )
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    @ViewBuilder
    private var introBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [PremiumAccent.ice, PremiumAccent.tabActive],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: PremiumAccent.tabActive.opacity(0.4), radius: 6, x: 0, y: 3)
                
            VStack(alignment: .leading, spacing: 4) {
                Text("Supabase RLS Activo")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(PremiumAccent.ice)
                    .textCase(.uppercase)

                Group {
                    if let attr = try? AttributedString(
                        markdown: "Los datos se guardan en **vehicles**. El Row Level Security limita el acceso a **tu organización**."
                    ) {
                        Text(attr)
                    } else {
                        Text("Los datos se guardan en vehicles (Supabase), aislados por organización.")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                }
        }
    }

    private var tenantNoticeCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PremiumAccent.mint.opacity(0.2), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(PremiumAccent.mint)
                    .symbolRenderingMode(.hierarchical)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Entorno corporativo seguro")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(PremiumAccent.mint)
                    .textCase(.uppercase)
                
                Text(tenantLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [PremiumAccent.mint.opacity(0.4), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: PremiumAccent.mint.opacity(0.08), radius: 12, x: 0, y: 6)
        }
    }

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PremiumAccent.ice.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
    }

    private func formFieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(.white.opacity(0.62))
    }

    private func formField(_ text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.54)))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .foregroundStyle(.white)
            .font(.system(size: 17, weight: .medium))
            .tint(PremiumAccent.ice.opacity(0.95))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                LiquidGlassFormFieldBackground()
            }
    }

    private var saveButton: some View {
        Button {
            Task { await saveVehicle() }
        } label: {
            HStack(spacing: 12) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PremiumAccent.amber)
                }
                Text(isSaving ? "Guardando…" : "Añadir a inventario")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                PremiumAccent.tabActive.opacity(0.85),
                                Color(red: 0.1, green: 0.2, blue: 0.8).opacity(0.95),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.2),
                                PremiumAccent.ice.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: PremiumAccent.tabActive.opacity(0.55), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
            .scaleEffect(isSaving ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSaving)
        }
        .buttonStyle(.plain)
        .disabled(isSaving || !canSave)
        .opacity((isSaving || !canSave) ? 0.35 : 1)
    }

    private func refreshTenantLine() async {
        let orgId = await VehiclesService.fetchMyOrganizationId()
        let compId = await VehiclesService.fetchMyCompanyId()
        await MainActor.run {
            if orgId != nil {
                tenantLine = "Tu cuenta usa organización: el coche se guarda con tu organization_id (aislado de otras empresas)."
            } else if compId != nil {
                tenantLine = "Tu cuenta usa empresa (company_id): el coche queda ligado a tu compañía en Supabase."
            } else {
                tenantLine = "Sin organización ni empresa en el perfil: la app no podrá guardar hasta que un administrador te asigne en user_profiles o profiles."
            }
        }
    }

    @MainActor
    private func saveVehicle() async {
        guard let y = parsedYear else {
            errorMessage = "Introduce un año válido."
            return
        }
        guard let sale = Self.parseOptionalDouble(priceText), sale > 0 else {
            errorMessage = "Indica un precio de venta válido."
            return
        }
        guard let purchase = Self.parseOptionalDouble(listingXF.purchasePriceText), purchase > 0 else {
            errorMessage = "Indica el precio de compra."
            return
        }
        let colorTrim = listingXF.colorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !colorTrim.isEmpty else {
            errorMessage = "Indica el color del vehículo."
            return
        }
        let plateTrim = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plateTrim.isEmpty else {
            errorMessage = "Indica la matrícula."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let km = Self.parseOptionalInt(mileageText)
            let powerCv = Self.parseOptionalInt(powerCvText)
            let financed = (sale * 0.9).rounded()
            let extra = VehicleListingExtraJSON(
                acquisitionCategory: listingXF.acquisitionCategory,
                vatDeductible: listingXF.vatDeductible,
                singleOwner: listingXF.singleOwner,
                serviceBook: listingXF.serviceBook,
                officialServiceBook: listingXF.officialServiceBook,
                nationalVehicle: listingXF.nationalVehicle,
                dgtLabelNote: nil,
                storeLocation: Self.trimOptional(listingXF.storeLocationText),
                equipmentCodes: listingEquipmentCodes.isEmpty ? nil : listingEquipmentCodes.sorted(),
                ownerName: Self.trimOptional(listingXF.ownerNameText),
                ownerPhone: Self.trimOptional(listingXF.ownerPhoneText),
                ownerEmail: Self.trimOptional(listingXF.ownerEmailText),
                ownerZone: Self.trimOptional(listingXF.ownerZoneText),
                ownerCanVisitOffice: listingXF.ownerCanVisitOffice,
                publishAllPlatforms: listingXF.publishAll,
                publishAutoScout: listingXF.publishAutoScout,
                publishCochesNet: listingXF.publishCochesNet,
                publishWallapop: listingXF.publishWallapop,
                publishOwnWeb: listingXF.publishWeb,
                lastServiceKm: Self.parseOptionalInt(listingXF.lastServiceKmText),
                lastServiceYear: Self.parseOptionalInt(listingXF.lastServiceYearText)
            )
            let desc = Self.trimOptional(listingXF.listingDescriptionText)
            let payload = VehicleAppListingPayload(
                brand: brand,
                model: model,
                year: y,
                licensePlate: plateTrim,
                salePriceEUR: sale,
                purchasePriceEUR: purchase,
                marketPriceEUR: Self.parseOptionalDouble(listingXF.marketPriceText),
                financedPriceEUR: financed,
                mileageKm: km,
                powerCv: powerCv,
                fuelType: fuel,
                transmission: transmission,
                vin: Self.trimOptional(listingXF.vinText),
                exteriorColor: colorTrim,
                listingDescription: desc,
                dgtLabel: Self.trimOptional(listingXF.dgtLabelText),
                listingExtra: extra
            )
            _ = try await VehiclesService.insertVehicleFromApp(
                payload,
                imagesJPEGData: stagedPhotos.map(\.jpegData)
            )
            await carsVM.loadVehicles(companyId: auth.companyId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tras rellenar con visión, genera borrador de anuncio si aún no hay texto (misma clave OpenAI que Viera).
    private func autoGenerateListingDescriptionAfterVisionIfPossible() async {
        let should = await MainActor.run {
            OpenAIChatClient.isConfigured
                && listingXF.listingDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard should else { return }

        let facts = await MainActor.run {
            Self.buildListingAIFacts(
                brand: brand,
                model: model,
                yearText: yearText,
                plate: plate,
                mileageText: mileageText,
                powerCvText: powerCvText,
                fuel: fuel,
                transmission: transmission,
                salePriceText: priceText,
                xf: listingXF,
                equipmentCodes: listingEquipmentCodes
            )
        }

        do {
            let text = try await OpenAIChatClient.generateVehicleListingDescription(factsBlock: facts)
            await MainActor.run {
                if listingXF.listingDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    listingXF.listingDescriptionText = text
                }
            }
        } catch {
            // No molestamos con error en automático; el usuario puede pulsar «Generar con IA».
        }
    }

    private static func buildListingAIFacts(
        brand: String,
        model: String,
        yearText: String,
        plate: String,
        mileageText: String,
        powerCvText: String,
        fuel: String,
        transmission: String,
        salePriceText: String,
        xf: AddVehicleListingExtendedState,
        equipmentCodes: Set<String>
    ) -> String {
        var lines: [String] = []

        let b = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty { lines.append("Marca: \(b)") }
        if !m.isEmpty { lines.append("Modelo: \(m)") }
        let y = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !y.isEmpty { lines.append("Año: \(y)") }
        let plt = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plt.isEmpty {
            lines.append("Matrícula (contexto interno; no hace falta publicarla en el texto del anuncio): \(plt)")
        }
        let km = mileageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !km.isEmpty { lines.append("Kilometraje: \(km) km") }
        let powerCv = powerCvText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !powerCv.isEmpty { lines.append("Potencia: \(powerCv) CV") }
        let f = fuel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.isEmpty { lines.append("Combustible: \(f)") }
        let tr = transmission.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tr.isEmpty { lines.append("Transmisión: \(tr)") }

        lines.append("Origen stock / categoría: \(acquisitionCategoryLabel(xf.acquisitionCategory))")

        if let purchase = parseOptionalDouble(xf.purchasePriceText), purchase > 0 {
            lines.append("Precio compra (solo interno, no publicar): \(Int(purchase)) €")
        }
        if let market = parseOptionalDouble(xf.marketPriceText), market > 0 {
            lines.append("Precio mercado orientativo (interno): \(Int(market)) €")
        }
        if let pvp = parseOptionalDouble(salePriceText), pvp > 0 {
            lines.append("Precio venta al contado (puede mencionarse si encaja): \(Int(pvp)) €")
        }

        lines.append("IVA deducible: \(vatDeductibleLabel(xf.vatDeductible))")
        lines.append("Único propietario: \(xf.singleOwner ? "sí" : "no")")
        lines.append("Libro de revisiones: \(xf.serviceBook ? "sí" : "no")")
        lines.append("Libro en casa oficial: \(xf.officialServiceBook ? "sí" : "no")")
        lines.append("Nacional o importado: \(xf.nationalVehicle ? "nacional" : "importado")")

        let color = xf.colorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !color.isEmpty { lines.append("Color: \(color)") }

        let dgt = xf.dgtLabelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dgt.isEmpty { lines.append("Etiqueta ambiental DGT: \(dgt)") }

        if let sk = parseOptionalInt(xf.lastServiceKmText) {
            lines.append("Última revisión (km): \(sk)")
        }
        if let sy = parseOptionalInt(xf.lastServiceYearText) {
            lines.append("Última revisión (año): \(sy)")
        }

        let vin = xf.vinText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vin.isEmpty { lines.append("VIN (no publicar): \(vin)") }

        let store = xf.storeLocationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !store.isEmpty { lines.append("Ubicación / tienda: \(store)") }

        if !equipmentCodes.isEmpty {
            let titles = AddVehicleListingDetailsForm.equipmentList
                .filter { equipmentCodes.contains($0.code) }
                .map(\.title)
            if !titles.isEmpty {
                lines.append("Equipamiento destacado: \(titles.joined(separator: ", "))")
            }
        }

        if !xf.ownerNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Hay datos de particular para uso interno (no publicar nombre ni teléfono en el anuncio).")
        }
        lines.append("El particular puede desplazarse a oficinas: \(xf.ownerCanVisitOffice ? "sí" : "no")")

        return lines.joined(separator: "\n")
    }

    private static func acquisitionCategoryLabel(_ id: String) -> String {
        switch id {
        case "compras": return "Compras"
        case "gv_con": return "GV CON"
        case "gv_sin": return "GV SIN"
        case "gv_fotos": return "GV FOTOS"
        case "empenos": return "Empeños"
        case "alquilados": return "Alquilados"
        default: return id
        }
    }

    private static func vatDeductibleLabel(_ id: String) -> String {
        switch id {
        case "yes": return "Sí"
        case "no": return "No"
        case "half": return "50 %"
        default: return id
        }
    }

    private static func trimOptional(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func parseOptionalDouble(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let v = Double(t.replacingOccurrences(of: ",", with: ".")) { return v }
        let filtered = t.filter { $0.isNumber || $0 == "." || $0 == "," }
        let norm = String(filtered).replacingOccurrences(of: ",", with: ".")
        return Double(norm)
    }

    private static func parseOptionalInt(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let digits = t.filter(\.isNumber)
        if digits.isEmpty { return nil }
        return Int(digits)
    }
}

// MARK: - Miniatura reciente (galería del sistema)

private struct AddVehicleRecentGalleryThumb: View {
    let asset: PHAsset
    var onTap: () -> Void

    @State private var thumbnail: UIImage?

    private let side: CGFloat = 72

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(.white.opacity(0.45))
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Añadir foto reciente de la galería")
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        let px = CGSize(width: side * scale, height: side * scale)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: px,
            contentMode: .aspectFill,
            options: opts
        ) { img, _ in
            DispatchQueue.main.async {
                thumbnail = img
            }
        }
    }
}

// MARK: - Edición por dictado (tap en tarjeta de coche)

struct EditVehicleDictationSheet: View {
    let car: Car
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var transcriber = LiveSpeechTranscriber()
    @State private var isDictating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    @State private var brand = ""
    @State private var model = ""
    @State private var yearText = ""
    @State private var plate = ""
    @State private var priceText = ""
    @State private var mileageText = ""
    @State private var powerCvText = ""
    @State private var fuel = ""
    @State private var transmission = ""
    @State private var color = ""
    @State private var dgtLabel = ""
    @State private var listingDescription = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edita los datos del vehículo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("Puedes modificar campos manualmente o usar el micrófono de arriba.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if isDictating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Escuchando… toca el micrófono para terminar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    if !transcriber.partialText.isEmpty {
                        Text(transcriber.partialText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    field("Marca", text: $brand)
                    field("Modelo", text: $model)
                    field("Año", text: $yearText, keyboard: .numberPad)
                    field("Matrícula", text: $plate)
                    field("Precio", text: $priceText, keyboard: .decimalPad)
                    field("Kilómetros", text: $mileageText, keyboard: .numberPad)
                    field("Potencia CV", text: $powerCvText, keyboard: .numberPad)
                    field("Combustible", text: $fuel)
                    field("Transmisión", text: $transmission)
                    field("Color", text: $color)
                    field("Etiqueta DGT", text: $dgtLabel)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Descripción")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.62))
                        TextEditor(text: $listingDescription)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    if let infoMessage, !infoMessage.isEmpty {
                        Text(infoMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green.opacity(0.9))
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red.opacity(0.95))
                    }

                    Button {
                        Task { await saveChanges() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Guardando..." : "Guardar cambios")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.6 : 1)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Editar coche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await toggleDictation() }
                    } label: {
                        Image(systemName: isDictating ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isDictating ? Color.red.opacity(0.95) : Color.white.opacity(0.95))
                    }
                    .accessibilityLabel(isDictating ? "Detener dictado" : "Iniciar dictado")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { stopDictationIfNeeded() }
        .task {
            loadFromCar()
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
            TextField("", text: text)
                .keyboardType(keyboard)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @MainActor
    private func toggleDictation() async {
        if isDictating {
            stopDictationAndApply()
        } else {
            await startDictation()
        }
    }

    @MainActor
    private func startDictation() async {
        errorMessage = nil
        infoMessage = nil
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            errorMessage = "Activa micrófono en Ajustes para dictar."
            return
        }
        let speechGranted = await transcriber.requestSpeechAuthorization()
        guard speechGranted else {
            errorMessage = "Activa reconocimiento de voz en Ajustes."
            return
        }
        do {
            isDictating = true
            try transcriber.startLiveTranscription()
        } catch {
            isDictating = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func stopDictationAndApply() {
        let spoken = transcriber.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.stopLiveTranscription()
        isDictating = false
        guard !spoken.isEmpty else { return }
        applyDictatedText(spoken)
    }

    private func stopDictationIfNeeded() {
        guard isDictating else { return }
        transcriber.stopLiveTranscription()
        isDictating = false
    }

    private func applyDictatedText(_ spoken: String) {
        let parsed = VehicleDictationParser.parse(spoken)
        if let v = parsed.brand { brand = v }
        if let v = parsed.model { model = v }
        if let v = parsed.year { yearText = String(v) }
        if let v = parsed.plate { plate = v }
        if let v = parsed.price { priceText = String(format: "%.0f", v) }
        if let v = parsed.mileage { mileageText = String(v) }
        if let v = parsed.powerCv { powerCvText = String(v) }
        if let v = parsed.fuelType { fuel = v }
        if let v = parsed.transmission { transmission = v }
        if let v = parsed.color { color = v }
        if let v = parsed.dgtLabel { dgtLabel = v }
        if let v = parsed.description { listingDescription = v }
        infoMessage = "Dictado aplicado. Revisa los campos antes de guardar."
    }

    @MainActor
    private func saveChanges() async {
        errorMessage = nil
        infoMessage = nil
        isSaving = true
        defer { isSaving = false }

        guard let year = Int(yearText.filter(\.isNumber)), (1950 ... 2035).contains(year) else {
            errorMessage = "Año no válido."
            return
        }
        let price = Self.parseOptionalDouble(priceText)
        let mileage = Self.parseOptionalInt(mileageText)
        let power = Self.parseOptionalInt(powerCvText)

        let payload = VehicleAppListingPayload(
            brand: brand,
            model: model,
            year: year,
            licensePlate: Self.trimmed(plate),
            salePriceEUR: price,
            purchasePriceEUR: nil,
            marketPriceEUR: nil,
            financedPriceEUR: nil,
            mileageKm: mileage,
            powerCv: power,
            fuelType: Self.trimmed(fuel),
            transmission: Self.trimmed(transmission),
            vin: nil,
            exteriorColor: Self.trimmed(color),
            listingDescription: Self.trimmed(listingDescription),
            dgtLabel: Self.trimmed(dgtLabel),
            listingExtra: nil
        )

        do {
            _ = try await VehiclesService.updateVehicleFromApp(vehicleId: car.id, payload: payload)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFromCar() {
        brand = car.brandName ?? ""
        model = car.model
        yearText = String(car.year)
        plate = car.plate == "—" ? "" : car.plate
        if let p = car.listPriceEUR {
            priceText = String(format: "%.0f", p)
        }
        if let km = car.mileageKm {
            mileageText = String(km)
        }
        if let p = car.powerCv {
            powerCvText = String(p)
        }
        fuel = car.fuelType ?? ""
        transmission = car.transmission ?? ""
        color = car.exteriorColorLabel ?? ""
        dgtLabel = car.dgtLabel ?? ""
    }

    private static func trimmed(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func parseOptionalDouble(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let normalized = t
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Double(normalized)
    }

    private static func parseOptionalInt(_ raw: String) -> Int? {
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }
}

private struct VehicleDictationFields {
    var brand: String?
    var model: String?
    var year: Int?
    var plate: String?
    var price: Double?
    var mileage: Int?
    var powerCv: Int?
    var fuelType: String?
    var transmission: String?
    var color: String?
    var dgtLabel: String?
    var description: String?
}

private enum VehicleDictationParser {
    private static let stopWords = [
        "modelo", "año", "ano", "matricula", "matrícula", "precio", "kilometros", "kilómetros",
        "combustible", "transmision", "transmisión", "color", "descripcion", "descripción", "potencia", "cv", "dgt",
    ]

    static func parse(_ text: String) -> VehicleDictationFields {
        var out = VehicleDictationFields()
        out.brand = extract(after: "marca", in: text)
        out.model = extract(after: "modelo", in: text)
        if let y = extract(after: "año", in: text) ?? extract(after: "ano", in: text) {
            out.year = Int(y.filter(\.isNumber))
        }
        if let m = extract(after: "matrícula", in: text) ?? extract(after: "matricula", in: text) {
            out.plate = m.replacingOccurrences(of: " ", with: "").uppercased()
        }
        if let p = extract(after: "precio", in: text) {
            out.price = parseDouble(p)
        }
        if let km = extract(after: "kilómetros", in: text) ?? extract(after: "kilometros", in: text) {
            out.mileage = Int(km.filter(\.isNumber))
        }
        if let cv = extract(after: "potencia", in: text) ?? extract(after: "cv", in: text) {
            out.powerCv = Int(cv.filter(\.isNumber))
        }
        out.fuelType = extract(after: "combustible", in: text)
        out.transmission = extract(after: "transmisión", in: text) ?? extract(after: "transmision", in: text)
        out.color = extract(after: "color", in: text)
        out.dgtLabel = extract(after: "dgt", in: text)
        out.description = extract(after: "descripción", in: text) ?? extract(after: "descripcion", in: text)
        return out
    }

    private static func extract(after field: String, in text: String) -> String? {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let key = field.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let range = normalized.range(of: key) else { return nil }
        let start = normalized[range.upperBound...]
        var candidate = start.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix(":") || candidate.hasPrefix("-") {
            candidate.removeFirst()
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if candidate.isEmpty { return nil }
        let endIndex = firstStopWordIndex(in: candidate)
        let value = endIndex.map { String(candidate[..<$0]) } ?? String(candidate)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstStopWordIndex(in text: String) -> String.Index? {
        let lower = text.lowercased()
        var best: String.Index?
        for word in stopWords {
            guard let r = lower.range(of: " \(word)") else { continue }
            if let b = best {
                if r.lowerBound < b { best = r.lowerBound }
            } else {
                best = r.lowerBound
            }
        }
        return best
    }

    private static func parseDouble(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Double(normalized)
    }
}

#Preview {
    NavigationStack {
        CarsView()
            .environmentObject(CarsViewModel())
            .environmentObject(AuthViewModel())
            .environmentObject(MainTabRouter())
    }
}

