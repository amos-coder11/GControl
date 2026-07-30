import Foundation

enum GControlManualLanguage: String, CaseIterable, Identifiable {
    case es
    case en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

struct GControlManualMeta: Decodable {
    let brand: String
    let brandFull: String
    let title: String
    let titleEs: String
    let subtitle: String
    let doctor: String
    let pageCount: Int
    let sectionCount: Int
}

struct GControlManualSection: Decodable, Identifiable {
    let id: String
    let titleEs: String
    let titleEn: String
    let pageCount: Int
    let pageIds: [String]
    let previewEs: String
    let previewEn: String

    func title(for language: GControlManualLanguage) -> String {
        language == .es ? titleEs : titleEn
    }

    func preview(for language: GControlManualLanguage) -> String {
        language == .es ? previewEs : previewEn
    }

    var icon: String {
        switch id {
        case "portada": return "book.closed.fill"
        case "indice": return "list.bullet.rectangle"
        case "resumen": return "building.2.fill"
        case "empleo": return "person.badge.key.fill"
        case "conducta": return "checkmark.shield.fill"
        case "compensacion": return "dollarsign.circle.fill"
        case "beneficios": return "heart.text.square.fill"
        case "politicas": return "doc.text.fill"
        case "front-desk": return "desktopcomputer"
        case "billing": return "creditcard.fill"
        case "higiene": return "cross.case.fill"
        case "asistentes": return "stethoscope"
        default: return "folder.fill"
        }
    }
}

struct GControlManualPageRecord: Decodable, Identifiable {
    let id: String
    let sectionId: String
    let pageIndex: Int
    let titleEs: String
    let titleEn: String
    let textEs: String
    let textEn: String

    func title(for language: GControlManualLanguage) -> String {
        language == .es ? titleEs : titleEn
    }

    func text(for language: GControlManualLanguage) -> String {
        language == .es ? textEs : textEn
    }
}

struct GControlManualSearchHit: Identifiable {
    let id: String
    let sectionId: String
    let pageIndex: Int
    let title: String
    let snippet: String
}

@MainActor
final class GControlEmployeeManualCatalog: ObservableObject {
    static let shared = GControlEmployeeManualCatalog()

    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?

    private(set) var meta: GControlManualMeta?
    private(set) var sections: [GControlManualSection] = []
    private var pagesByID: [String: GControlManualPageRecord] = [:]
    private var orderedPageIDs: [String] = []
    private var searchRecords: [GControlManualPageRecord] = []
    private var sectionBannerPaths: [String: String] = [:]
    private var pageIllustrationPaths: [String: String] = [:]

    private init() {}

    func loadIfNeeded() {
        guard !isLoaded, loadError == nil else { return }

        do {
            meta = try decode("meta", as: GControlManualMeta.self)
            sections = try decode("sections", as: [GControlManualSection].self)
            let pages = try decode("pages", as: [GControlManualPageRecord].self)
            pagesByID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
            orderedPageIDs = pages.sorted { $0.pageIndex < $1.pageIndex }.map(\.id)
            searchRecords = pages
            sectionBannerPaths = try decode("section-banners", as: [String: String].self)
            let illustrationPayload = try decode("page-illustrations", as: PageIllustrationPayload.self)
            pageIllustrationPaths = illustrationPayload.byPage
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    func page(id: String) -> GControlManualPageRecord? {
        pagesByID[id]
    }

    func pages(in section: GControlManualSection) -> [GControlManualPageRecord] {
        section.pageIds.compactMap { pagesByID[$0] }
    }

    func neighborIDs(for pageID: String) -> (previous: String?, next: String?) {
        guard let index = orderedPageIDs.firstIndex(of: pageID) else {
            return (nil, nil)
        }
        let previous = index > 0 ? orderedPageIDs[index - 1] : nil
        let next = index + 1 < orderedPageIDs.count ? orderedPageIDs[index + 1] : nil
        return (previous, next)
    }

    func imageURL(for pageID: String) -> URL? {
        Bundle.main.url(
            forResource: pageID,
            withExtension: "jpg",
            subdirectory: "EmployeeManual/Pages"
        )
    }

    func sectionBannerURL(for sectionID: String) -> URL? {
        guard let path = sectionBannerPaths[sectionID] else { return nil }
        return bundleAssetURL(fromWebPath: path)
    }

    func pageIllustrationURL(for pageID: String) -> URL? {
        guard let path = pageIllustrationPaths[pageID] else { return nil }
        return bundleAssetURL(fromWebPath: path)
    }

    func bundleAssetURL(fromWebPath webPath: String) -> URL? {
        let trimmed = webPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        let folder: String
        switch parts[0] {
        case "banners": folder = "Banners"
        case "illustrations": folder = "Illustrations"
        default: return nil
        }

        let filename = parts[1]
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? "webp" : (filename as NSString).pathExtension
        return Bundle.main.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "EmployeeManual/\(folder)"
        )
    }

    func search(query: String, language: GControlManualLanguage) -> [GControlManualSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return searchRecords.compactMap { page in
            let title = page.title(for: language)
            let body = page.text(for: language)
            let haystack = "\(title)\n\(body)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard haystack.contains(needle) else { return nil }

            let snippetSource = body.isEmpty ? title : body
            let snippet = snippetAround(snippetSource, matching: needle, language: language)
            return GControlManualSearchHit(
                id: page.id,
                sectionId: page.sectionId,
                pageIndex: page.pageIndex,
                title: title,
                snippet: snippet
            )
        }
        .prefix(40)
        .map { $0 }
    }

    private func decode<T: Decodable>(_ resource: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "EmployeeManual") else {
            throw ManualCatalogError.missingFile("\(resource).json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func snippetAround(_ text: String, matching needle: String, language: GControlManualLanguage) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let range = folded.range(of: needle) else {
            return String(text.prefix(120))
        }
        let start = text.index(text.startIndex, offsetBy: max(0, text.distance(from: text.startIndex, to: range.lowerBound) - 40), limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(text.startIndex, offsetBy: min(text.count, text.distance(from: text.startIndex, to: range.upperBound) + 80), limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}

private struct PageIllustrationPayload: Decodable {
    let byPage: [String: String]
}

private enum ManualCatalogError: LocalizedError {
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            return "No se encontró \(name) en el paquete de la app."
        }
    }
}
