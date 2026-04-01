import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Tarjeta resumen financiero (toca → detalle)

struct DashboardFinancialSummaryCard: View {
    @ObservedObject var stats: DealershipStatsViewModel
    @Binding var showDetail: Bool

    private let corner: CGFloat = 24

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Información financiera")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                }

                Text(stats.totalStockValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Valor stock · \(stats.periodDisplayLabel)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                HStack(spacing: 14) {
                    miniPill(title: "Vendidos", value: "\(stats.carsSold)")
                    miniPill(title: "Beneficio", value: stats.salesProfit)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                DashboardChromeCardBackground(cornerRadius: corner)
            }
        }
        .buttonStyle(.plain)
    }

    private func miniPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
    }
}

// MARK: - Detalle financiero (hoja)

struct DashboardFinancialDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var stats: DealershipStatsViewModel

    private let corner: CGFloat = 20

    private var categories: [(icon: String, title: String, subtitle: String, amount: String, pct: String, color: Color)] {
        [
            ("car.fill", "Stock activo", "\(stats.vehiclesInStock) unidades", stats.totalStockValue, stats.vehiclesStockBadge, .cyan),
            ("eurosign.circle.fill", "Beneficio ventas", stats.periodDisplayLabel, stats.salesProfit, "Neto", .mint),
            ("person.2.fill", "Comisiones", stats.commissionsSubtitle, stats.commercialCommissions, "Comercial", .orange),
            ("chart.line.uptrend.xyaxis", "Ingresos concesión", stats.totalEarningsSubtitle, stats.totalDealershipEarnings, "Total", .purple),
            ("camera.metering.centered", "Captación", "+\(stats.capturedChangePercent)% vs periodo", "\(stats.capturedCars) coches", "CRM", .pink),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resumen del periodo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(stats.totalStockValue)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background {
                        DashboardChromeCardBackground(cornerRadius: corner)
                    }

                    Text("Por categoría")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.offset) { index, row in
                            financeCategoryRow(
                                icon: row.icon,
                                title: row.title,
                                subtitle: row.subtitle,
                                amount: row.amount,
                                pct: row.pct,
                                color: row.color
                            )
                            if index < categories.count - 1 {
                                Divider().background(Color.white.opacity(0.12))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .background {
                        DashboardChromeCardBackground(cornerRadius: corner)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Finanzas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func financeCategoryRow(
        icon: String,
        title: String,
        subtitle: String,
        amount: String,
        pct: String,
        color: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(amount)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                Text(pct)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Mapa del equipo

struct DashboardTeamMapCard: View {
    @ObservedObject var community: DashboardCommunityViewModel
    @ObservedObject var locationHub: DashboardLocationHub
    var currentUserId: UUID?

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
    )

    private let corner: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ubicación del equipo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }

            ZStack {
                Map(position: $position) {
                    if let c = locationHub.coordinate {
                        Marker("Tú", coordinate: c)
                            .tint(.cyan)
                    }
                    ForEach(mapPeers) { row in
                        Marker(row.resolvedDisplayName, coordinate: CLLocationCoordinate2D(latitude: row.latitude!, longitude: row.longitude!))
                            .tint(.white)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(true)

                if locationHub.authorizationStatus == .denied || locationHub.authorizationStatus == .restricted {
                    Text("Activa la ubicación para compartir tu posición con el equipo y ver el mapa en vivo.")
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(12)
                }
            }
            .frame(height: 220)

            if community.directory.filter(\.hasCoordinate).filter({ $0.id != currentUserId }).isEmpty,
               locationHub.coordinate == nil
            {
                Text("Cuando los usuarios compartan ubicación, aparecerán aquí. Actualización periódica.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: corner)
        }
        .onAppear { updateRegion() }
        .onChange(of: community.directory.count) { _, _ in updateRegion() }
        .onChange(of: locationHub.coordinate?.latitude) { _, _ in updateRegion() }
    }

    private var mapPeers: [CommunityProfilesService.DirectoryRow] {
        community.directory.filter { row in
            row.hasCoordinate && row.id != currentUserId
        }
    }

    private func updateRegion() {
        var coords: [CLLocationCoordinate2D] = mapPeers.map {
            CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!)
        }
        if let c = locationHub.coordinate { coords.append(c) }
        position = .region(Self.region(fitting: coords))
    }

    private static func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let defaultCenter = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: defaultCenter, span: defaultSpan)
        }
        if coords.count == 1 {
            return MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07)
            )
        }
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude
        for c in coords.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.4, 0.05)
        let lonDelta = max((maxLon - minLon) * 1.4, 0.05)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}

// MARK: - Usuarios conectados (carrusel)

struct DashboardConnectedUsersStrip: View {
    let members: [CommunityProfilesService.DirectoryRow]
    var currentUserId: UUID?
    var accessToken: String?

    private let avatarSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Usuarios conectados")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }

            if visibleMembers.isEmpty {
                Text("Aún no hay otros perfiles en la base de datos o no tienes permisos de lectura.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(visibleMembers) { row in
                            DashboardConnectedMemberCell(row: row, size: avatarSize, accessToken: accessToken)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: 24)
        }
    }

    private var visibleMembers: [CommunityProfilesService.DirectoryRow] {
        guard let uid = currentUserId else { return members }
        return members.filter { $0.id != uid }
    }
}

private struct DashboardConnectedMemberCell: View {
    let row: CommunityProfilesService.DirectoryRow
    let size: CGFloat
    var accessToken: String?

    @State private var avatarImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.45, blue: 0.95),
                                    Color(red: 0.45, green: 0.25, blue: 0.85),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initials(for: row.resolvedDisplayName))
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
            }

            Text(row.resolvedDisplayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .frame(width: size + 12)
        }
        .task(id: row.id) {
            avatarImage = await UserProfileService.loadProfileAvatarImage(
                avatarRef: row.avatarUrl,
                userId: row.id,
                client: SupabaseClientProvider.shared,
                accessToken: accessToken
            )
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        if let f = name.first { return String(f).uppercased() }
        return "?"
    }
}
