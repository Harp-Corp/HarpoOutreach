import SwiftUI

struct ContentGenerationView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTopic: ContentTopic = .regulatoryUpdate
    @State private var selectedPlatform: SocialPlatform = .linkedIn
    @State private var generatedNewsletterSubject = ""
    @State private var generatedNewsletterBody = ""
    @State private var generatedSocialPost: SocialPost?
    @State private var isGeneratingNewsletter = false
    @State private var isGeneratingSocial = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segment Control
                Picker("Content Type", selection: $selectedTab) {
                    Text("Newsletter").tag(0)
                    Text("Social Post").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    newsletterGenerationSection
                } else {
                    socialPostSection
                }
            }
            .navigationTitle("Content Studio")
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Newsletter Generation
    private var newsletterGenerationSection: some View {
        Form {
            Section("Topic & Audience") {
                Picker("Topic", selection: $selectedTopic) {
                    ForEach(ContentTopic.allCases) { topic in
                        Text(topic.rawValue).tag(topic)
                    }
                }
                
                Text(selectedTopic.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button(action: generateNewsletter) {
                    HStack {
                        if isGeneratingNewsletter {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "sparkles")
                        Text(isGeneratingNewsletter ? "Generating..." : "Generate Newsletter")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isGeneratingNewsletter)
                .buttonStyle(.borderedProminent)
            }
            
            if !generatedNewsletterSubject.isEmpty {
                Section("Generated Subject") {
                    Text(generatedNewsletterSubject)
                        .font(.headline)
                }
                
                Section("Preview") {
                    Text(generatedNewsletterBody.prefix(500) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: createCampaignFromGenerated) {
                        HStack {
                            Image(systemName: "envelope.badge.fill")
                            Text("Create Campaign")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }
    
    // MARK: - Social Post Section
    private var socialPostSection: some View {
        Form {
            Section("Platform & Topic") {
                Picker("Platform", selection: $selectedPlatform) {
                    ForEach(SocialPlatform.allCases, id: \.self) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
                
                Picker("Topic", selection: $selectedTopic) {
                    ForEach(ContentTopic.allCases) { topic in
                        Text(topic.rawValue).tag(topic)
                    }
                }
            }
            
            Section {
                Button(action: generateSocialPost) {
                    HStack {
                        if isGeneratingSocial {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "sparkles")
                        Text(isGeneratingSocial ? "Generating..." : "Generate \(selectedPlatform.rawValue) Post")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isGeneratingSocial)
                .buttonStyle(.borderedProminent)
            }
            
            if let post = generatedSocialPost {
                Section("Generated Post") {
                    Text(post.content)
                        .font(.body)
                }
                
                Section("Hashtags") {
                    FlowLayout(post.hashtags) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                Section {
                    Button(action: publishSocialPost) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Publish to \(post.platform.rawValue)")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    Button(action: saveSocialPostDraft) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save as Draft")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    // MARK: - Actions
    private func generateNewsletter() {
        isGeneratingNewsletter = true
        Task {
            do {
                let industries = viewModel.settings.selectedIndustries
                let result = try await viewModel.perplexityService.generateNewsletterContent(
                    topic: selectedTopic,
                    industries: industries,
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
    
    private func generateSocialPost() {
        isGeneratingSocial = true
        Task {
            do {
                let industries = viewModel.settings.selectedIndustries
                let post = try await viewModel.perplexityService.generateSocialPost(
                    topic: selectedTopic,
                    platform: selectedPlatform,
                    industries: industries,
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
            targetIndustries: viewModel.settings.selectedIndustries,
            targetRegions: viewModel.settings.selectedRegions
        )
        viewModel.campaigns.append(campaign)
    }
    
    private func publishSocialPost() {
        guard var post = generatedSocialPost else { return }
        Task {
            do {
                post = try await viewModel.socialPostService.publish(
                    post: post,
                    settings: viewModel.settings
                )
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
