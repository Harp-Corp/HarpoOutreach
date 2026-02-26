import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - AppViewModel+Social
// Handles: social post generation, editing, clipboard, persistence

extension AppViewModel {

    // MARK: - Generate Social Post
    func generateSocialPost(
        topic: ContentTopic,
        platform: SocialPlatform = .linkedin,
        industries: [String] = []
    ) async {
        guard !settings.perplexityAPIKey.isEmpty else {
            errorMessage = "Perplexity API Key missing."
            return
        }
        isLoading = true; currentStep = "Generating \(platform.rawValue) post..."
        do {
            var post = try await pplxService.generateSocialPost(
                topic: topic,
                platform: platform,
                industries: industries.isEmpty ? settings.selectedIndustries : industries,
                existingPosts: socialPosts,
                apiKey: settings.perplexityAPIKey
            )
            post.content = SocialPost.ensureFooter(post.content)
            socialPosts.insert(post, at: 0)
            saveSocialPosts()
            currentStep = "Post created"
        } catch {
            errorMessage = "Post generation failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Delete Social Post
    func deleteSocialPost(_ postID: UUID) {
        socialPosts.removeAll { $0.id == postID }
        saveSocialPosts()
    }

    // MARK: - Update Social Post
    func updateSocialPost(_ post: SocialPost) {
        if let idx = socialPosts.firstIndex(where: { $0.id == post.id }) {
            var fixedPost = post
            fixedPost.content = SocialPost.ensureFooter(post.content)
            socialPosts[idx] = fixedPost
            saveSocialPosts()
        }
    }

    // MARK: - Copy Post to Clipboard
    func copyPostToClipboard(_ post: SocialPost) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SocialPost.ensureFooter(post.content), forType: .string)
        statusMessage = "Post copied to clipboard"
        #endif
    }

    // MARK: - Persistence (delegates to AppViewModel base)
    // saveSocialPosts() and migrateSocialPostFooters() are defined in AppViewModel.swift
    // They are public so they can be called from here.

    // MARK: - Load Social Posts (public helper for views that need to reload)
    func reloadSocialPosts() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent("HarpoOutreach/socialPosts.json")
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([SocialPost].self, from: data) else { return }
        socialPosts = saved
    }
}
