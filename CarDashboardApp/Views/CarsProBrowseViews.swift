import SwiftUI

enum CarsBrowseMetrics {
    static let horizontalInset: CGFloat = 10
    static let sectionSpacing: CGFloat = 10
    static let gridSpacing: CGFloat = 8
    static let kpiItemSpacing: CGFloat = 6
}

// MARK: - KPI strip (listado Coches)

struct CarsInventoryKPIStrip: View {
    @ObservedObject var stats: DealershipStatsViewModel
    var leadIndex: CarInventoryLeadIndex?

    private struct KPIItem {
        let icon: String
        let label: String
        let value: String
        let tint: Color
        let trend: String?
        let trendPositive: Bool?
    }

    private var items: [KPIItem] {
        let leadTotal = leadIndex.map { $0.allLeads.count } ?? stats.leadsTotal
        return [
            KPIItem(
                icon: "clock.fill",
                label: "RESP.",
                value: stats.avgResponseLabel,
                tint: .cyan,
                trend: stats.avgResponseLabel != "—" ? "↘ 5 min" : nil,
                trendPositive: true
            ),
            KPIItem(
                icon: "calendar",
                label: "CITAS",
                value: "\(stats.appointmentsCount)",
                tint: Color(red: 0.62, green: 0.45, blue: 0.98),
                trend: stats.appointmentRateTrend,
                trendPositive: true
            ),
            KPIItem(
                icon: "trophy.fill",
                label: "GANADOS",
                value: stats.conversionRate,
                tint: .green,
                trend: stats.wonRateTrend,
                trendPositive: true
            ),
            KPIItem(
                icon: "xmark.circle.fill",
                label: "PERDIDOS",
                value: stats.lostRateLabel,
                tint: .red,
                trend: stats.lostRateTrend,
                trendPositive: false
            ),
            KPIItem(
                icon: "person.3.fill",
                label: "LEADS",
                value: "\(leadTotal)",
                tint: .blue,
                trend: stats.leadsCountTrend,
                trendPositive: true
            ),
        ]
    }

    var body: some View {
        HStack(spacing: CarsBrowseMetrics.kpiItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.tint)
                    Text(item.label)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if let trend = item.trend {
                        Text(trend)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(trendColor(positive: item.trendPositive))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                        }
                }
            }
        }
        .padding(.horizontal, CarsBrowseMetrics.horizontalInset)
    }

    private func trendColor(positive: Bool?) -> Color {
        guard let positive else { return .white.opacity(0.55) }
        return positive ? Color(red: 0.35, green: 0.85, blue: 0.45) : Color(red: 0.95, green: 0.35, blue: 0.35)
    }
}

// MARK: - Chips Todos / Vendidos / Reservados

struct CarsInventorySegmentBar: View {
    @ObservedObject var carsVM: CarsViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CarsInventorySegment.allCases) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        carsVM.browseSegment = segment
                    }
                } label: {
                        HStack(spacing: 6) {
                            Text(segment.title)
                            if let badge = badgeCount(for: segment) {
                                Text(badge)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        carsVM.browseSegment == segment ? .black.opacity(0.75) : .white.opacity(0.55)
                                    )
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            carsVM.browseSegment == segment ? Color.white : Color.white.opacity(0.55)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(
                                    carsVM.browseSegment == segment
                                        ? Color.white.opacity(0.18)
                                        : Color.white.opacity(0.06)
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            carsVM.browseSegment == segment
                                                ? Color(red: 0.95, green: 0.55, blue: 0.18).opacity(0.85)
                                                : Color.white.opacity(0.14),
                                            lineWidth: carsVM.browseSegment == segment ? 1.2 : 0.75
                                        )
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CarsBrowseMetrics.horizontalInset)
    }

    private func badgeCount(for segment: CarsInventorySegment) -> String? {
        switch segment {
        case .all:
            return nil
        case .sold:
            let n = carsVM.soldInventoryCount()
            return n > 0 ? "\(n)" : nil
        case .reserved:
            let n = carsVM.reservedInventoryCount()
            return n > 0 ? "\(n)" : nil
        }
    }
}

// MARK: - Detalle vehículo (galería + specs + leads)

struct CarDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var tabRouter: MainTabRouter

    let car: Car
    @ObservedObject var leadIndex: CarInventoryLeadIndex
    var onEdit: () -> Void

    @StateObject private var stats = DealershipStatsViewModel()
    @State private var galleryIndex = 0
    @State private var leadsTab: CarDetailLeadsTab = .leads
    @State private var showVehicleDetailsExpanded = false

    private var imageSlots: [CarImageSlot] { car.resolvedImageSlots }
    private var carChatThreads: [ChatThread] { chatInbox.leadThreads(for: car) }
    private var displayedLeadThreads: [ChatThread] { Array(carChatThreads.prefix(5)) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                gallerySection
                titlePriceSection
                specsSection
                CarsInventoryKPIStrip(stats: stats, leadIndex: nil)
                    .padding(.top, 2)
                leadsTabBar
                leadsTabContent
                vehicleInfoSection
            }
            .padding(.bottom, 36)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar", action: onEdit)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .task(id: auth.session?.accessToken) {
            if let token = auth.session?.accessToken {
                await stats.refreshFromBackend(token: token)
                await chatInbox.refreshLeadThreadsForVehicle(car, accessToken: token)
            }
        }
    }

    private var gallerySection: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if imageSlots.isEmpty {
                        ZStack {
                            Color.white.opacity(0.08)
                            Image(systemName: car.icon)
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    } else {
                        TabView(selection: $galleryIndex) {
                            ForEach(Array(imageSlots.enumerated()), id: \.element.id) { idx, slot in
                                CarHeroImageSlotView(slot: slot, presentation: .cover)
                                    .tag(idx)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 248)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if car.isInventorySold {
                    CarListingSoldPhotoOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else if car.isInventoryReserved {
                    CarListingReservedPhotoOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if imageSlots.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(min(galleryIndex + 1, imageSlots.count))/\(imageSlots.count)")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
                }
            }

            if imageSlots.count > 1 {
                VStack(spacing: 8) {
                    ForEach(Array(imageSlots.prefix(3).enumerated()), id: \.element.id) { idx, slot in
                        Button {
                            galleryIndex = idx
                        } label: {
                            CarHeroImageSlotView(slot: slot, presentation: .cover)
                                .frame(width: 76, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            galleryIndex == idx ? Color.orange : Color.white.opacity(0.2),
                                            lineWidth: galleryIndex == idx ? 2 : 0.75
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    if imageSlots.count > 3 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                            Text("+\(imageSlots.count - 3)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 76, height: 56)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var titlePriceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(car.displayBrandUppercased)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            if !car.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(car.model)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
            CarListingPricePill(priceText: car.displayListPriceText)
                .scaleEffect(1.04, anchor: .leading)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
    }

    private var specsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if let km = car.mileageKm, km > 0 {
                    detailSpecItem(icon: "speedometer", text: "\(formatInt(km)) km")
                }
                if let fuel = car.fuelType?.trimmingCharacters(in: .whitespacesAndNewlines), !fuel.isEmpty {
                    detailSpecItem(icon: "fuelpump.fill", text: fuel.uppercased())
                }
                if let cv = car.powerCv, cv > 0 {
                    detailSpecItem(icon: "engine.combustion.fill", text: "\(cv) CV")
                }
                if let t = car.transmission?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    detailSpecItem(icon: "gearshape.fill", text: t.uppercased())
                }
                if let bt = car.bodyType?.trimmingCharacters(in: .whitespacesAndNewlines), !bt.isEmpty {
                    detailSpecItem(icon: "car.side.fill", text: bt.uppercased())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func detailSpecItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.72))
    }

    private func formatInt(_ v: Int) -> String {
        v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    private var leadsTabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: 22) {
                ForEach(CarDetailLeadsTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { leadsTab = tab }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab == .leads ? "Leads (\(carChatThreads.count))" : "Actividad")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(leadsTab == tab ? .white : .white.opacity(0.42))
                            Capsule()
                                .fill(leadsTab == tab ? Color.orange : Color.clear)
                                .frame(height: 3)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var leadsTabContent: some View {
        if leadsTab == .leads {
            VStack(spacing: 12) {
                ForEach(displayedLeadThreads) { thread in
                    Button {
                        openChatThread(thread)
                    } label: {
                        CarDetailModernLeadRow(thread: thread)
                    }
                    .buttonStyle(.plain)
                }

                if carChatThreads.isEmpty {
                    Text("Sin leads vinculados a este vehículo.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 16)
                }

                if carChatThreads.count > displayedLeadThreads.count {
                    Button {
                        if let first = carChatThreads.first { openChatThread(first) }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Ver todos los leads")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Text("Historial de actividad próximamente.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 16)
        }
    }

    private var vehicleInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Información del vehículo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showVehicleDetailsExpanded.toggle()
                    }
                } label: {
                    Text(showVehicleDetailsExpanded ? "Ver menos" : "Ver más detalles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                vehicleFactCell("Marca / Modelo", "\(car.displayBrandUppercased) \(car.model)")
                vehicleFactCell("Año", "\(car.year)")
                if showVehicleDetailsExpanded {
                    if let km = car.mileageKm {
                        vehicleFactCell("Kilometraje", "\(formatInt(km)) km")
                    }
                    if let fuel = car.fuelType {
                        vehicleFactCell("Combustible", fuel)
                    }
                    if let cv = car.powerCv {
                        vehicleFactCell("Potencia", "\(cv) CV")
                    }
                    if let loc = car.locationText {
                        vehicleFactCell("Ubicación", loc)
                    }
                    if let color = car.exteriorColorLabel {
                        vehicleFactCell("Color", color)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func vehicleFactCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
                }
        }
    }

    private func openChatThread(_ thread: ChatThread) {
        chatNav.threadToOpen = thread
        tabRouter.selected = .chat
    }
}

private enum CarDetailLeadsTab: CaseIterable {
    case leads
    case activity
}

private struct CarDetailModernLeadRow: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore

    let thread: ChatThread

    private var contactPhone: String? {
        chatInbox.contactPhone(for: thread)
    }

    private var contactPhoneLabel: String? {
        chatInbox.contactPhoneDisplay(for: thread)
    }

    private var canCallLead: Bool {
        chatInbox.canCallLead(thread)
    }

    private var callTint: Color {
        switch thread.socialSource {
        case .instagram:
            return Color(red: 0.79, green: 0.38, blue: 0.92)
        case .whatsApp:
            return Color(red: 0.12, green: 0.72, blue: 0.38)
        default:
            return .cyan
        }
    }

    private var status: (label: String, color: Color) {
        if (thread.unread ?? 0) > 0 {
            return ("NUEVO", .purple)
        }
        return ("SEGUIMIENTO", Color(red: 0.22, green: 0.48, blue: 0.95))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadAvatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(thread.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(status.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(status.color.opacity(0.88), in: Capsule())
                }

                Text(thread.preview.isEmpty ? "Consulta sobre este vehículo" : thread.preview)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text(thread.time.isEmpty ? "Reciente" : thread.time)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.38))

                if canCallLead, let label = contactPhoneLabel, let phone = contactPhone {
                    Button {
                        PhoneCallLauncher.call(phone)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(callTint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                if canCallLead, let phone = contactPhone {
                    Button {
                        PhoneCallLauncher.call(phone)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(callTint, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("Sin asignar") {}
                    Button("Juan Pérez") {}
                    Button("María López") {}
                } label: {
                    HStack(spacing: 4) {
                        Text("Sin asignar")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
                }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var leadAvatar: some View {
        ChatThreadAvatarView(
            thread: thread,
            accessToken: auth.session?.accessToken,
            diameter: 48
        )
    }
}
