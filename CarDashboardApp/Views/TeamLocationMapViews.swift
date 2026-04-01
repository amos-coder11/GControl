import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Región que encaja todos los puntos

enum TeamMapRegionHelper {
    static func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
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
        let latDelta = max((maxLat - minLat) * 1.45, 0.05)
        let lonDelta = max((maxLon - minLon) * 1.45, 0.05)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}

// MARK: - Pin con foto / iniciales (mapa)

struct TeamMapPersonPin: View {
    var diameter: CGFloat
    var borderColor: Color
    var image: UIImage?
    var initials: String

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
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
                Text(initials)
                    .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(borderColor.opacity(0.95), lineWidth: 2.5)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
    }
}

struct TeamMapRemotePersonPin: View {
    let row: CommunityProfilesService.DirectoryRow
    var accessToken: String?
    var diameter: CGFloat
    var borderColor: Color

    @State private var avatarImage: UIImage?

    var body: some View {
        TeamMapPersonPin(
            diameter: diameter,
            borderColor: borderColor,
            image: avatarImage,
            initials: Self.initials(for: row.resolvedDisplayName)
        )
        .task(id: row.id) {
            avatarImage = await UserProfileService.loadProfileAvatarImage(
                avatarRef: row.avatarUrl,
                userId: row.userId,
                client: SupabaseClientProvider.shared,
                accessToken: accessToken
            )
        }
    }

    private static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        if let f = name.first { return String(f).uppercased() }
        return "?"
    }
}

// MARK: - Mapa compartido (tarjeta + panel)

struct TeamLiveMapView: View {
    @Binding var position: MapCameraPosition
    @ObservedObject var community: DashboardCommunityViewModel
    @ObservedObject var locationHub: DashboardLocationHub
    var currentUserId: UUID?
    var accessToken: String?
    var currentUserProfileImage: UIImage?
    var currentUserInitials: String
    var pinDiameter: CGFloat
    var mapCornerRadius: CGFloat?

    private var mapPeers: [CommunityProfilesService.DirectoryRow] {
        community.directory.filter { row in
            row.hasCoordinate && row.userId != currentUserId
        }
    }

    private var myCoordinate: CLLocationCoordinate2D? {
        if let c = locationHub.coordinate, CLLocationCoordinate2DIsValid(c) { return c }
        if let uid = currentUserId,
           let row = community.directory.first(where: { $0.userId == uid && $0.hasCoordinate }) {
            return CLLocationCoordinate2D(latitude: row.latitude!, longitude: row.longitude!)
        }
        return nil
    }

    var body: some View {
        Map(position: $position) {
            if let c = myCoordinate {
                Annotation("Tú", coordinate: c) {
                    TeamMapPersonPin(
                        diameter: pinDiameter,
                        borderColor: .cyan,
                        image: currentUserProfileImage,
                        initials: currentUserInitials
                    )
                }
            }
            ForEach(mapPeers) { row in
                let coord = CLLocationCoordinate2D(latitude: row.latitude!, longitude: row.longitude!)
                Annotation(row.resolvedDisplayName, coordinate: coord) {
                    TeamMapRemotePersonPin(
                        row: row,
                        accessToken: accessToken,
                        diameter: pinDiameter,
                        borderColor: .white
                    )
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .modifier(TeamMapClipModifier(radius: mapCornerRadius))
        .onAppear { updateRegion() }
        .onChange(of: community.directory.count) { _, _ in updateRegion() }
        .onChange(of: locationHub.coordinate?.latitude) { _, _ in updateRegion() }
        .onChange(of: locationHub.coordinate?.longitude) { _, _ in updateRegion() }
    }

    private func updateRegion() {
        var coords: [CLLocationCoordinate2D] = mapPeers.map {
            CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!)
        }
        if let c = myCoordinate { coords.append(c) }
        position = .region(TeamMapRegionHelper.region(fitting: coords))
    }
}

private struct TeamMapClipModifier: ViewModifier {
    let radius: CGFloat?

    func body(content: Content) -> some View {
        if let radius {
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
        }
    }
}

// MARK: - Panel a pantalla completa

struct TeamMapDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var community: DashboardCommunityViewModel
    @ObservedObject var locationHub: DashboardLocationHub
    var currentUserId: UUID?
    var accessToken: String?
    var currentUserProfileImage: UIImage?
    var currentUserInitials: String

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
    )

    private var mapPeers: [CommunityProfilesService.DirectoryRow] {
        community.directory.filter { row in
            row.hasCoordinate && row.userId != currentUserId
        }
    }

    private var myCoordinate: CLLocationCoordinate2D? {
        if let c = locationHub.coordinate, CLLocationCoordinate2DIsValid(c) { return c }
        if let uid = currentUserId,
           let row = community.directory.first(where: { $0.userId == uid && $0.hasCoordinate }) {
            return CLLocationCoordinate2D(latitude: row.latitude!, longitude: row.longitude!)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        TeamLiveMapView(
                            position: $position,
                            community: community,
                            locationHub: locationHub,
                            currentUserId: currentUserId,
                            accessToken: accessToken,
                            currentUserProfileImage: currentUserProfileImage,
                            currentUserInitials: currentUserInitials,
                            pinDiameter: 46,
                            mapCornerRadius: nil
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if locationHub.authorizationStatus == .denied || locationHub.authorizationStatus == .restricted {
                            Text("Activa ubicación en Ajustes para compartir tu posición en tiempo real con el equipo.")
                                .font(.system(size: 12, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(12)
                        }
                    }

                    teamListPanel
                }
            }
            .refreshable {
                await community.refresh()
            }
            .navigationTitle("Ubicación del equipo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var teamListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Posición por usuario")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    if let c = myCoordinate {
                        TeamLocationMemberRow(
                            title: "Tú",
                            subtitle: coordinateSubtitle(c),
                            footnote: myLocationFootnote,
                            profileImage: currentUserProfileImage,
                            initials: currentUserInitials,
                            isSelf: true
                        )
                        if !mapPeers.isEmpty {
                            Divider().background(Color.white.opacity(0.12))
                        }
                    }
                    ForEach(Array(mapPeers.enumerated()), id: \.element.id) { index, row in
                        let coord = CLLocationCoordinate2D(latitude: row.latitude!, longitude: row.longitude!)
                        TeamLocationMemberRow(
                            title: row.resolvedDisplayName,
                            subtitle: coordinateSubtitle(coord),
                            footnote: peerFootnote(row),
                            remoteRow: row,
                            accessToken: accessToken,
                            isSelf: false
                        )
                        if index < mapPeers.count - 1 {
                            Divider().background(Color.white.opacity(0.12))
                        }
                    }
                    if myCoordinate == nil, mapPeers.isEmpty {
                        Text("Nadie del equipo tiene ubicación compartida ahora. Activa la ubicación y espera la sincronización.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(20)
                    }
                }
            }
            .frame(maxHeight: 220)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.black)
    }

    private var myLocationFootnote: String {
        if locationHub.coordinate != nil {
            return "GPS en este dispositivo (en vivo)"
        }
        if let uid = currentUserId,
           let row = community.directory.first(where: { $0.userId == uid }),
           let d = row.locationUpdatedDate {
            return "Última posición en servidor: \(Self.relativeTime(d))"
        }
        return "Posición guardada en tu perfil"
    }

    private func peerFootnote(_ row: CommunityProfilesService.DirectoryRow) -> String {
        if let d = row.locationUpdatedDate {
            return "Actualizado: \(Self.relativeTime(d))"
        }
        return "Ubicación en perfil (sin fecha)"
    }

    private func coordinateSubtitle(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f°, %.5f°", c.latitude, c.longitude)
    }

    private static func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Fila lista

private struct TeamLocationMemberRow: View {
    let title: String
    let subtitle: String
    let footnote: String
    var profileImage: UIImage?
    var initials: String = ""
    var remoteRow: CommunityProfilesService.DirectoryRow?
    var accessToken: String?
    var isSelf: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if isSelf {
                    TeamMapPersonPin(
                        diameter: 48,
                        borderColor: .cyan,
                        image: profileImage,
                        initials: initials.isEmpty ? "?" : initials
                    )
                } else if let remoteRow {
                    TeamMapRemotePersonPin(
                        row: remoteRow,
                        accessToken: accessToken,
                        diameter: 48,
                        borderColor: .white
                    )
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.85))
                Text(footnote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
