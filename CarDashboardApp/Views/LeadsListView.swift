import SwiftUI

/// Listado de leads desde Supabase `public.leads_crm` (paridad con la app Flutter).
struct LeadsListView: View {
    @StateObject private var vm = LeadsViewModel()

    var body: some View {
        RevolutChromeContainer {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    SectionHeader(
                        title: "Leads",
                        subtitle: vm.isLoading ? "Cargando…" : "\(vm.leads.count) contactos (leads_crm)",
                        lightOnDark: true
                    )

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Reintentar") {
                            Task { await vm.load() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PremiumAccent.tabActive)
                    } else if !vm.isLoading, vm.leads.isEmpty {
                        Text(
                            "No hay filas en leads_crm o RLS no devuelve datos para tu sesión. Inicia sesión y revisa políticas en Supabase."
                        )
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(vm.leads) { lead in
                                leadRow(lead)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Leads")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await vm.load()
        }
        .task {
            if vm.leads.isEmpty, !vm.isLoading {
                await vm.load()
            }
        }
    }

    private func leadRow(_ lead: LeadCrm) -> some View {
        GlassCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(lead.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                if !lead.subtitle.isEmpty {
                    Text(lead.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let notes = lead.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .lineLimit(4)
                }

                if let created = lead.createdAt, !created.isEmpty {
                    Text(created)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        LeadsListView()
    }
}
