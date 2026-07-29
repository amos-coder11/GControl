import SwiftUI

struct GControlManualBundleImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let url, let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GrooBrand.primarySoft)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(GrooBrand.primary.opacity(0.5))
                    }
            }
        }
    }
}

struct GControlEmployeeManualView: View {
    @StateObject private var catalog = GControlEmployeeManualCatalog.shared
    @State private var language: GControlManualLanguage = .es
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let loadError = catalog.loadError {
                    ContentUnavailableView(
                        "Manual no disponible",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if !catalog.isLoaded {
                    ProgressView("Cargando manual…")
                } else {
                    manualContent
                }
            }
            .background(GrooClinicDesign.ScreenBackground())
            .navigationTitle(catalog.meta?.titleEs ?? "Manual de empleado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Idioma", selection: $language) {
                        ForEach(GControlManualLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
            }
            .navigationDestination(for: String.self) { pageID in
                GControlEmployeeManualPageView(pageID: pageID, language: language)
            }
            .onAppear { catalog.loadIfNeeded() }
        }
    }

    private var manualContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                searchField

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsSection
                } else {
                    sectionsList
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let meta = catalog.meta {
                Text(meta.brandFull)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrooBrand.primary)
                Text(meta.subtitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(meta.doctor)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
                HStack(spacing: 12) {
                    metaPill("\(meta.sectionCount) secciones", icon: "square.grid.2x2")
                    metaPill("\(meta.pageCount) páginas", icon: "doc.on.doc")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(manualCardBackground)
    }

    private func metaPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(GrooBrand.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(GrooBrand.primarySoft))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DrflowTheme.textTertiary)
            TextField(language == .es ? "Buscar en el manual…" : "Search manual…", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(manualCardBackground)
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language == .es ? "Resultados" : "Results")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)

            let hits = catalog.search(query: searchText, language: language)
            if hits.isEmpty {
                Text(language == .es ? "Sin coincidencias." : "No matches.")
                    .font(.system(size: 14))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(hits) { hit in
                    NavigationLink(value: hit.id) {
                        HStack(spacing: 12) {
                            GControlManualBundleImage(
                                url: catalog.pageIllustrationURL(for: hit.id),
                                contentMode: .fill
                            )
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                            Text("Pág. \(hit.pageIndex) · \(hit.title)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(hit.snippet)
                                .font(.system(size: 12))
                                .foregroundStyle(DrflowTheme.textSecondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(manualCardBackground)
                    }
                }
            }
        }
    }

    private var sectionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language == .es ? "Secciones" : "Sections")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)

            ForEach(catalog.sections) { section in
                NavigationLink {
                    GControlEmployeeManualSectionView(section: section, language: language)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        GControlManualBundleImage(
                            url: catalog.sectionBannerURL(for: section.id),
                            contentMode: .fill
                        )
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title(for: language))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(DrflowTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text("\(section.pageCount) \(language == .es ? "páginas" : "pages")")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DrflowTheme.textSecondary)
                                Text(section.preview(for: language))
                                    .font(.system(size: 11))
                                    .foregroundStyle(DrflowTheme.textTertiary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DrflowTheme.textMuted)
                        }
                        .padding(14)
                    }
                    .background(manualCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var manualCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

struct GControlEmployeeManualSectionView: View {
    let section: GControlManualSection
    let language: GControlManualLanguage
    @StateObject private var catalog = GControlEmployeeManualCatalog.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GControlManualBundleImage(
                    url: catalog.sectionBannerURL(for: section.id),
                    contentMode: .fill
                )
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

                Text(section.preview(for: language))
                    .font(.system(size: 13))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 10) {
                    ForEach(catalog.pages(in: section)) { page in
                        NavigationLink {
                            GControlEmployeeManualPageView(pageID: page.id, language: language)
                        } label: {
                            HStack(spacing: 12) {
                                GControlManualBundleImage(
                                    url: catalog.pageIllustrationURL(for: page.id),
                                    contentMode: .fill
                                )
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(page.pageIndex). \(page.title(for: language))")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(DrflowTheme.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(page.text(for: language))
                                        .font(.system(size: 12))
                                        .foregroundStyle(DrflowTheme.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(DrflowTheme.textMuted)
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(GrooClinicDesign.ScreenBackground())
        .navigationTitle(section.title(for: language))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { catalog.loadIfNeeded() }
    }
}

struct GControlEmployeeManualPageView: View {
    let pageID: String
    let language: GControlManualLanguage
    @StateObject private var catalog = GControlEmployeeManualCatalog.shared
    @State private var showScan = false

    private var page: GControlManualPageRecord? { catalog.page(id: pageID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let page {
                    GControlManualBundleImage(
                        url: catalog.pageIllustrationURL(for: page.id),
                        contentMode: .fit
                    )
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                    if catalog.imageURL(for: page.id) != nil {
                        Toggle(
                            language == .es ? "Ver escaneo original" : "Show original scan",
                            isOn: $showScan
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .tint(GrooBrand.primary)
                    }

                    if showScan, let imageURL = catalog.imageURL(for: page.id),
                       let uiImage = UIImage(contentsOfFile: imageURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    }

                    Text(page.title(for: language))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)

                    Text(page.text(for: language))
                        .font(.system(size: 15))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    navigationButtons
                } else {
                    ContentUnavailableView(
                        "Página no encontrada",
                        systemImage: "doc.questionmark"
                    )
                }
            }
            .padding(16)
        }
        .background(GrooClinicDesign.ScreenBackground())
        .navigationTitle(page.map { "Pág. \($0.pageIndex)" } ?? "Manual")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { catalog.loadIfNeeded() }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        let neighbors = catalog.neighborIDs(for: pageID)
        HStack(spacing: 10) {
            if let previous = neighbors.previous {
                NavigationLink {
                    GControlEmployeeManualPageView(pageID: previous, language: language)
                } label: {
                    Label(language == .es ? "Anterior" : "Previous", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(GrooBrand.primary)
            }

            Spacer(minLength: 0)

            if let next = neighbors.next {
                NavigationLink {
                    GControlEmployeeManualPageView(pageID: next, language: language)
                } label: {
                    Label(language == .es ? "Siguiente" : "Next", systemImage: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(GrooBrand.primary)
            }
        }
        .padding(.top, 8)
    }
}
