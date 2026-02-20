import SwiftUI

struct ContentGenerationView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedTopic: ContentTopic = .regulatoryUpdate
    @State private var generatedNewsletterSubject = ""
    @State private var generatedNewsletterBody = ""
    @State private var generatedSocialPost: SocialPost?
    @State private var isGeneratingNewsletter = false
    @State private var isGeneratingSocial = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedTab = 0

    // Editing states
    @State private var editingPostContent = ""
    @State private var editingPostHashtags = ""
    @State private var editingNewsletterSubject = ""
    @State private var editingNewsletterBody = ""
    @State private var isEditingPost = false
    @State private var isEditingNewsletter = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Content Studio")
                        .font(.largeTitle)
                        .bold()
                    Text("Newsletter und LinkedIn Posts erstellen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            // Segment Control
            Picker("Content Type", selection: $selectedTab) {
                Text("Newsletter").tag(0)
                Text("LinkedIn Post").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Divider().padding(.top, 12)

            if selectedTab == 0 {
                newsletterSection
            } else {
                linkedInPostSection
            }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Newsletter Section
    private var newsletterSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Topic Selection
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Thema")
                            .font(.headline)
                        Picker("Topic", selection: $selectedTopic) {
                            ForEach(ContentTopic.allCases) { topic in
                                Text(topic.rawValue).tag(topic)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(selectedTopic.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                // Generate Button
                Button(action: generateNewsletter) {
                    HStack {
                        if isGeneratingNewsletter {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "sparkles")
                        Text(isGeneratingNewsletter ? "Generiere..." : "Newsletter generieren")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingNewsletter)

                // Generated Newsletter Preview/Edit
                if !generatedNewsletterSubject.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Generierter Newsletter")
                                    .font(.headline)
                                Spacer()
                                Button(isEditingNewsletter ? "Fertig" : "Bearbeiten") {
                                    if isEditingNewsletter {
                                        generatedNewsletterSubject = editingNewsletterSubject
                                        generatedNewsletterBody = editingNewsletterBody
                                    } else {
                                        editingNewsletterSubject = generatedNewsletterSubject
                                        editingNewsletterBody = generatedNewsletterBody
                                    }
                                    isEditingNewsletter.toggle()
                                }
                                .buttonStyle(.bordered)
                            }

                            if isEditingNewsletter {
                                TextField("Betreff", text: $editingNewsletterSubject)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.headline)
                                TextEditor(text: $editingNewsletterBody)
                                    .frame(minHeight: 200)
                                    .font(.system(.body, design: .monospaced))
                                    .border(Color.gray.opacity(0.3))
                            } else {
                                Text(generatedNewsletterSubject)
                                    .font(.headline)
                                Divider()
                                Text(String(generatedNewsletterBody.prefix(500)) + (generatedNewsletterBody.count > 500 ? "..." : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button(action: createCampaignFromGenerated) {
                            HStack {
                                Image(systemName: "envelope.badge.fill")
                                Text("Kampagne erstellen")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - LinkedIn Post Section
    private var linkedInPostSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Topic Selection
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Thema")
                            .font(.headline)
                        Picker("Topic", selection: $selectedTopic) {
                            ForEach(ContentTopic.allCases) { topic in
                                Text(topic.rawValue).tag(topic)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(8)
                }

                // Generate Button
                Button(action: generateLinkedInPost) {
                    HStack {
                        if isGeneratingSocial {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "sparkles")
                        Text(isGeneratingSocial ? "Generiere..." : "LinkedIn Post generieren")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingSocial)

                // Generated Post Preview/Edit
                if let post = generatedSocialPost {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                        .foregroundColor(.blue)
                                    Text("LinkedIn Post")
                                        .font(.headline)
                                }
                                Spacer()
                                Button(isEditingPost ? "Fertig" : "Bearbeiten") {
                                    if isEditingPost {
                                        let tags = editingPostHashtags
                                            .components(separatedBy: ",")
                                            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
                                            .filter { !$0.isEmpty }
                                        generatedSocialPost = SocialPost(
                                            id: post.id,
                                            platform: .linkedIn,
                                            content: editingPostContent,
                                            hashtags: tags
                                        )
                                    } else {
                                        editingPostContent = post.content
                                        editingPostHashtags = post.hashtags.map { "#\($0)" }.joined(separator: ", ")
                                    }
                                    isEditingPost.toggle()
                                }
                                .buttonStyle(.bordered)
                            }

                            if isEditingPost {
                                TextEditor(text: $editingPostContent)
                                    .frame(minHeight: 150)
                                    .border(Color.gray.opacity(0.3))
                                TextField("Hashtags (kommagetrennt)", text: $editingPostHashtags)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Text(post.content)
                                    .font(.body)
                                    .textSelection(.enabled)

                                if !post.hashtags.isEmpty {
                                    FlowLayout(post.hashtags) { tag in
                                        Text("#\(tag)")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button(action: saveSocialPostDraft) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Als Draft speichern")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: publishToLinkedIn) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Auf LinkedIn posten")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Actions
    private func generateNewsletter() {
        isGeneratingNewsletter = true
        isEditingNewsletter = false
        Task {
            do {
                let result = try await viewModel.perplexityService.generateNewsletterContent(
                    topic: selectedTopic,
                    industries: [],
                    apiKey: viewModel.settings.perplexityAPIKey
                )
                await MainActor.run {
                    generatedNewsletterSubject = result.subject
                    generatedNewsletterBody = result.htmlBody
                    isGeneratingNewsletter = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isGeneratingNewsletter = false
                }
            }
        }
    }

    private func generateLinkedInPost() {
        isGeneratingSocial = true
        isEditingPost = false
        Task {
            do {
                let post = try await viewModel.perplexityService.generateSocialPost(
                    topic: selectedTopic,
                    platform: .linkedIn,
                    industries: [],
                    apiKey: viewModel.settings.perplexityAPIKey
                )
                await MainActor.run {
                    generatedSocialPost = post
                    isGeneratingSocial = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isGeneratingSocial = false
                }
            }
        }
    }

    private func createCampaignFromGenerated() {
        let campaign = NewsletterCampaign(
            name: selectedTopic.rawValue + " - " + Date().formatted(date: .abbreviated, time: .omitted),
            subject: generatedNewsletterSubject,
            htmlBody: generatedNewsletterBody,
            plainTextBody: generatedNewsletterBody.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        )
        viewModel.campaigns.append(campaign)
    }

    private func publishToLinkedIn() {
        guard var post = generatedSocialPost else { return }
        guard viewModel.linkedInAuthService.isAuthenticated else {
            errorMessage = "Nicht bei LinkedIn angemeldet. Bitte in Einstellungen verbinden."
            showError = true
            return
        }
        Task {
            do {
                let accessToken = try await viewModel.linkedInAuthService.getAccessToken()
                let postURL = try await viewModel.socialPostService.postToLinkedIn(
                    post: post,
                    accessToken: accessToken,
                    orgId: viewModel.settings.linkedInOrgId
                )
                post.postURL = postURL
                post.status = .published
                post.publishedDate = Date()
                await MainActor.run {
                    viewModel.socialPosts.append(post)
                    generatedSocialPost = post
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func saveSocialPostDraft() {
        guard let post = generatedSocialPost else { return }
        viewModel.socialPosts.append(post)
    }
}

// MARK: - Flow Layout Helper
struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 4) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
    }
}
