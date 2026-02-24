# HarpoOutreachWeb

Vapor-basierter Web-Server fuer die HarpoOutreach RegTech Outreach Platform.

## Architektur (Option 2: Swift Backend + Web Frontend)

```
HarpoOutreach/
|-- HarpoOutreach/           # macOS App (SwiftUI) - unveraendert
|-- HarpoOutreachCore/       # Shared Swift Package (Models, DTOs, Enums)
|-- HarpoOutreachWeb/        # Vapor Web Server
|   |-- Package.swift        # Swift Package mit Vapor + Core Dependency
|   |-- Sources/
|   |   |-- App.swift         # REST API Routes + Server Entry Point
|   |-- Public/
|       |-- index.html        # Single Page Application
|       |-- css/style.css     # Dark-Theme Stylesheet
|       |-- js/app.js         # Frontend JavaScript (API Client)
```

## Vorteile

- macOS App bleibt voll funktionsfaehig und unveraendert
- Geteilte Models zwischen macOS und Web ueber HarpoOutreachCore
- Server-seitige API Keys (Perplexity, Gmail OAuth) - keine Secrets im Frontend
- Modernes Dark-Theme Web-UI das die macOS App spiegelt
- CORS-Support fuer lokale Entwicklung

## Voraussetzungen

- Swift 5.9+
- macOS 14+ oder Linux

## Setup & Start

```bash
cd HarpoOutreachWeb
swift build
swift run
```

Server startet auf `http://localhost:8080`

## API Endpoints

| Method | Endpoint | Beschreibung |
|--------|----------|-------------|
| GET | /health | Health Check |
| GET | /api/v1/industries | Alle Branchen |
| GET | /api/v1/regions | Alle Regionen |
| GET | /api/v1/leads | Leads abrufen |
| POST | /api/v1/leads | Neuen Lead erstellen |
| POST | /api/v1/companies/search | Firmensuche (Perplexity AI) |
| POST | /api/v1/email/draft | E-Mail Entwurf generieren |
| POST | /api/v1/email/send | E-Mail senden (Gmail) |
| POST | /api/v1/social/generate | Social Post generieren |
| GET | /api/v1/dashboard | Dashboard Statistiken |
| GET | /api/v1/auth/google | Google OAuth starten |
| GET | /api/v1/auth/callback | OAuth Callback |

## Web Frontend Features

- **Dashboard**: Echtzeit-Statistiken und Pipeline-Uebersicht
- **Leads**: CRUD mit Filter nach Branche, Region, Status
- **Firmensuche**: KI-gestuetzte Suche via Perplexity API
- **E-Mail**: Entwurf-Generierung und Versand via Gmail
- **Social Posts**: Generierung fuer LinkedIn, Twitter/X, XING

## Naechste Schritte (TODOs)

1. PerplexityService server-seitig implementieren
2. GmailService mit OAuth Token-Management verbinden
3. Google Sheets oder DB als Datenquelle anbinden
4. Environment Variables fuer API Keys konfigurieren
5. Docker-Deployment vorbereiten
