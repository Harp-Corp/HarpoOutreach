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
