import SwiftUI

struct SocialPostView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedTopic: ContentTopic = .regulatoryUpdate
    @State private var selectedPlatform: SocialPlatform = .linkedin
    @State private var editingPost: SocialPost?
    @State private var editContent: String = ""
    @State private var newsletterPost: SocialPost?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Social Posts")
                        .font(.title2.bold())
                    Text("\(vm.socialPosts.count) Posts erstellt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Generate Button
                HStack(spacing: 12) {
                    Picker("Thema", selection: $selectedTopic) {
                        ForEach(ContentTopic.allCases) { topic in
                            Text(topic.rawValue).tag(topic)
                        }
                    }
                    .frame(width: 180)
                    Picker("Plattform", selection: $selectedPlatform) {
                        ForEach(SocialPlatform.allCases) { platform in
                            Text(platform.rawValue).tag(platform)
                        }
                    }
                    .frame(width: 120)
                    Button(action: {
                        Task {
                            await vm.generateSocialPost(topic: selectedTopic, platform: selectedPlatform)
                        }
                    }) {
                        Label("Post generieren", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading)
                }
            }
            .padding()

            Divider()

            if vm.isLoading {
                VStack {
                    ProgressView()
                    Text(vm.currentStep)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.socialPosts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Noch keine Posts")
                        .font(.headline)
                    Text("Waehle ein Thema und generiere deinen ersten LinkedIn Post")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(vm.socialPosts) { post in
                            socialPostCard(post)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $editingPost) { post in
            editSheet(post)
        }
        .sheet(item: $newsletterPost) { post in
            NewsletterRecipientSheet(post: post, vm: vm)
        }
    }

    @ViewBuilder
    private func socialPostCard(_ post: SocialPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: post.platform == .linkedin ? "link" : "bird")
                    .foregroundColor(.blue)
                Text(post.platform.rawValue)
                    .font(.caption.bold())
                Spacer()
                Text(post.createdDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(SocialPost.ensureFooter(post.content))
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(nil)
            Divider()
            if post.content.contains("harpocrates-corp.com") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Footer vorhanden")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("WARNUNG: Footer fehlt!")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
            }
            // Actions
            HStack(spacing: 12) {
                Button(action: { vm.copyPostToClipboard(post) }) {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                Button(action: {
                    editContent = post.content
                    editingPost = post
                }) {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                Button(action: { newsletterPost = post }) {
                    Label("Als Newsletter", systemImage: "envelope.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                Spacer()
                Button(role: .destructive, action: { vm.deleteSocialPost(post.id) }) {
                    Label("Loeschen", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func editSheet(_ post: SocialPost) -> some View {
        VStack(spacing: 16) {
            Text("Post bearbeiten")
                .font(.headline)
            TextEditor(text: $editContent)
                .font(.body)
                .frame(minHeight: 300)
                .border(Color.gray.opacity(0.3))
            HStack {
                Button("Abbrechen") { editingPost = nil }
                Spacer()
                Button("Speichern") {
                    var updated = post
                    updated.content = SocialPost.ensureFooter(editContent)
                    vm.updateSocialPost(updated)
                    editingPost = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Newsletter Recipient Sheet
// Workflow: Post generieren -> "Als Newsletter" -> Empfaenger filtern -> Drafts erstellen
struct NewsletterRecipientSheet: View {
    let post: SocialPost
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var filterIndustries: [String] = []
    @State private var filterRegions: [String] = []
    @State private var filterSizes: [String] = []
    @State private var draftsCreated: Int = 0
    @State private var showConfirmation = false

    /// Build a lookup from company name -> Company for filtering
    private var companyLookup: [String: Company] {
        Dictionary(uniqueKeysWithValues: vm.companies.map { ($0.name, $0) })
    }

    /// Filter leads: must be verified, and match company-level industry/region/size filters
    private var filteredLeads: [Lead] {
        vm.leads.filter { lead in
            guard lead.emailVerified || lead.isManuallyCreated else { return false }
            guard lead.dateEmailSent == nil else { return false }
            if let company = companyLookup[lead.company] {
                if !filterIndustries.isEmpty && !filterIndustries.contains(company.industry) {
                    return false
                }
                if !filterRegions.isEmpty && !filterRegions.contains(company.region) {
                    return false
                }
                if !filterSizes.isEmpty {
                    let matchesSize = filterSizes.contains { sizeRaw in
                        guard let size = CompanySize(rawValue: sizeRaw) else { return false }
                        return company.employeeCount > 0 && size.matches(employeeCount: company.employeeCount)
                    }
                    if !matchesSize && company.employeeCount > 0 { return false }
                }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Newsletter aus Post erstellen")
                        .font(.title2.bold())
                    Text("\(post.platform.rawValue) Post vom \(post.createdDate, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Schliessen") { dismiss() }
            }
            .padding()
            Divider()
            HStack(alignment: .top, spacing: 20) {
                // Left: Post preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Post Inhalt")
                        .font(.headline)
                    ScrollView {
                        Text(post.content)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                }
                .frame(minWidth: 300)
                Divider()
                // Right: Filters + Recipients
                VStack(alignment: .leading, spacing: 12) {
                    Text("Empfaenger filtern")
                        .font(.headline)
                    GroupBox("Industrie filtern") {
                        FlowLayout(spacing: 6) {
                            ForEach(Industry.allCases, id: \.self) { ind in
                                FilterToggleButton(
                                    title: ind.shortName,
                                    isSelected: filterIndustries.contains(ind.rawValue)
                                ) {
                                    if filterIndustries.contains(ind.rawValue) {
                                        filterIndustries.removeAll { $0 == ind.rawValue }
                                    } else {
                                        filterIndustries.append(ind.rawValue)
                                    }
                                }
                            }
                        }
                        Text("Leer = alle Industrien")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    GroupBox("Region filtern") {
                        FlowLayout(spacing: 6) {
                            ForEach(Region.allCases, id: \.self) { reg in
                                FilterToggleButton(
                                    title: reg.rawValue,
                                    isSelected: filterRegions.contains(reg.rawValue)
                                ) {
                                    if filterRegions.contains(reg.rawValue) {
                                        filterRegions.removeAll { $0 == reg.rawValue }
                                    } else {
                                        filterRegions.append(reg.rawValue)
                                    }
                                }
                            }
                        }
                        Text("Leer = alle Regionen")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    GroupBox("Groesse filtern") {
                        FlowLayout(spacing: 6) {
                            ForEach(CompanySize.allCases, id: \.self) { size in
                                FilterToggleButton(
                                    title: size.shortName,
                                    isSelected: filterSizes.contains(size.rawValue)
                                ) {
                                    if filterSizes.contains(size.rawValue) {
                                        filterSizes.removeAll { $0 == size.rawValue }
                                    } else {
                                        filterSizes.append(size.rawValue)
                                    }
                                }
                            }
                        }
                        Text("Leer = alle Groessen")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(filteredLeads.count) Empfaenger")
                                .font(.headline)
                            Text("Verified Leads die den Filtern entsprechen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: createNewsletterDrafts) {
                            Label("\(filteredLeads.count) Drafts erstellen", systemImage: "envelope.badge.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(filteredLeads.isEmpty)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 600)
        .alert("Drafts erstellt", isPresented: $showConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text("\(draftsCreated) Email-Drafts wurden erstellt und sind im Outbox bereit.")
        }
    }

    private func createNewsletterDrafts() {
        var count = 0
        let subject = "[Newsletter] \(post.platform.rawValue) Update"
        for lead in filteredLeads {
            if let idx = vm.leads.firstIndex(where: { $0.id == lead.id }) {
                vm.leads[idx].draftedEmail = OutboundEmail(
                    subject: subject,
                    body: post.content
                )
                vm.leads[idx].status = .emailDrafted
                count += 1
            }
        }
        vm.saveLeads()
        draftsCreated = count
        showConfirmation = true
    }
}
