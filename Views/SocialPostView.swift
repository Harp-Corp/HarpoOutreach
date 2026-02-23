import SwiftUI

struct SocialPostView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedTopic: ContentTopic = .regulatoryUpdate
    @State private var selectedPlatform: SocialPlatform = .linkedin
    @State private var editingPost: SocialPost?
    @State private var editContent: String = ""

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
    }

    @ViewBuilder
    private func socialPostCard(_ post: SocialPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
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

            // Content
                        // DISPLAY: Footer wird auch im View-Layer garantiert
            Text(SocialPost.ensureFooter(post.content))
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(nil)

            Divider()

            // Footer check
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
                Button("Abbrechen") {
                    editingPost = nil
                }
                Spacer()
                Button("Speichern") {
                    var updated = post
                                        // Footer enforcement via SocialPost Model
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
