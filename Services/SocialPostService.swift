import Foundation

class SocialPostService {

    // MARK: - LinkedIn API
    private let linkedInAPIURL = "https://api.linkedin.com/v2"

    // MARK: - Post to LinkedIn (Organization Post)
    func postToLinkedIn(post: SocialPost, accessToken: String, orgId: String) async throws -> String {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SocialPostError.notConfigured(platform: "LinkedIn - Access Token fehlt. Bitte in Einstellungen eintragen.")
        }
        guard !orgId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SocialPostError.notConfigured(platform: "LinkedIn - Organization ID fehlt. Bitte in Einstellungen eintragen.")
        }

        let url = URL(string: "\(linkedInAPIURL)/ugcPosts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2.0.0", forHTTPHeaderField: "X-Restli-Protocol-Version")

        let contentWithHashtags = post.content + "\n\n" + post.hashtags.map { "#\($0)" }.joined(separator: " ")

        let body: [String: Any] = [
            "author": "urn:li:organization:\(orgId)",
            "lifecycleState": "PUBLISHED",
            "specificContent": [
                "com.linkedin.ugc.ShareContent": [
                    "shareCommentary": [
                        "text": contentWithHashtags
                    ],
                    "shareMediaCategory": "NONE"
                ]
            ],
            "visibility": [
                "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[LinkedIn] Posting mit Token: \(accessToken.prefix(8))... OrgId: \(orgId)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SocialPostError.invalidResponse
        }

        guard http.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 {
                throw SocialPostError.apiError(code: 401, message: "LinkedIn Access Token ungueltig oder abgelaufen. Bitte in Einstellungen erneuern.")
            }
            throw SocialPostError.apiError(code: http.statusCode, message: String(body.prefix(300)))
        }

        // Extract post ID from response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let postId = json["id"] as? String {
            return "https://www.linkedin.com/feed/update/\(postId)"
        }
        return ""
    }

    // MARK: - Publish Social Post
    func publish(post: SocialPost, settings: AppSettings) async throws -> SocialPost {
        var updatedPost = post

        guard !settings.linkedInAccessToken.isEmpty else {
            throw SocialPostError.notConfigured(platform: "LinkedIn - Access Token fehlt")
        }

        do {
            let postURL = try await postToLinkedIn(
                post: post,
                accessToken: settings.linkedInAccessToken,
                orgId: settings.linkedInOrgId
            )
            updatedPost.postURL = postURL
            updatedPost.status = .published
            updatedPost.publishedDate = Date()
        } catch {
            updatedPost.status = .failed
            throw error
        }

        return updatedPost
    }
}

// MARK: - Errors
enum SocialPostError: LocalizedError {
    case invalidResponse
    case apiError(code: Int, message: String)
    case notConfigured(platform: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ungueltige Antwort von Social API"
        case .apiError(let code, let msg):
            return "Social API Error \(code): \(msg)"
        case .notConfigured(let platform):
            return "\(platform) ist nicht konfiguriert"
        }
    }
}
