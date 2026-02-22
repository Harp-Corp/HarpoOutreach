# BUGFIXES

## API-Proxy Workflow Test

Der direkte API-Zugang ist eingerichtet und funktioniert.

## Aktuelle Fixes
- ScrollView Expansion in ManualContactEntryView
- Citations aus Draft-Emails entfernt
- findCompanies() liefert jetzt 20-25 Ergebnisse
- CompanyRow markiert Unternehmen mit Kontakten
 - LinkedIn OAuth: ViewBridge-Fehler ist benign (macOS RemoteViewService), kein Handlungsbedarf
- LinkedIn Posting: postToLinkedIn() mit OAuth Token + personId (sub) implementiert
- LinkedIn: urn:li:person statt urn:li:organization (w_member_social Scope)
- LinkedIn: PersonId (sub) wird via /v2/userinfo extrahiert und in UserDefaults gespeichert
- SocialPostService: postToLinkedIn(post:accessToken:personId:) gibt Post-URL zurueck
- NewsletterCampaignView: publishLinkedInPost() ruft getAccessToken() + getPersonId() korrekt auf

- ## Browser-Share statt API-Posting
- ContentGenerationView: import AppKit hinzugefuegt
- publishToLinkedIn() nutzt jetzt NSWorkspace.shared.open(LinkedIn Share URL)
- User hat volle Kontrolle ueber den Post im Browser bevor er live geht
- Kein direktes API-Posting mehr - Browser oeffnet linkedin.com/sharing/share-offsite/
- "Auf LinkedIn posten" Button direkt sichtbar in LinkedIn Post Section

## Content-Generierung: Quellenpflicht + Compliance-Fokus
- PerplexityService generateSocialPost: CRITICAL CONTENT RULES im System-Prompt
  - Fokus auf Compliance, RegTech, FinTech, GDPR, DORA, EU AI Act, MiCA
  - Alle Zahlen/Fakten NUR aus verifizierbaren Quellen mit Quellenangabe
  - Keine halluzinierten Inhalte
  - JSON Response enthaelt jetzt 'sources' Array
- PerplexityService generateNewsletterContent: Quellenpflicht im User-Prompt
  - Alle Statistiken muessen Quellenreferenz enthalten
  - Fokus auf comply.reg relevante Themen
