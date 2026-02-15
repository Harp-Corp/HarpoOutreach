# HarpoOutreach

**macOS App für RegTech Outreach**

Eine professionelle E-Mail-Kampagnen-Management-App für Harpocrates Corp, spezialisiert auf branchenspezifisches Outreach in den Bereichen Healthcare, Financial Services, Energy und Manufacturing.

## 🎯 Übersicht

HarpoOutreach ist eine native macOS-Anwendung, die speziell für Harpocrates entwickelt wurde, um effektive Outreach-Kampagnen für verschiedene Branchen zu erstellen und zu verwalten. Die App bietet:

- ✉️ **Branchenspezifische E-Mail-Templates**
- 📊 **Kampagnen-Analytics und Tracking**
- 👥 **Kontaktmanagement nach Branchen**
- 🎨 **Moderne SwiftUI-Benutzeroberfläche**
- 📈 **Dashboard mit Echtzeit-Statistiken**

## 🏢 Unterstützte Branchen

### Healthcare
- Marktgröße: €650 Mio. (2022) → €1,1 Mrd. (2031)
- Regulierungen: GDPR, HIPAA-äquivalent, MDR, Digitalisierung

### Financial Services
- Marktgröße: €151,6 Mrd. (2024) → €193,5 Mrd. (2030)
- Regulierungen: MiFID II, DSGVO, ESG-Reporting, Basel III

### Energy
- Marktgröße: €5,0 Mrd. (2024) → €7,3 Mrd. (2032)
- Regulierungen: EU ETS, Erneuerbare Energien, ESG-Automation

### Manufacturing
- Marktgröße: €3,6 Mrd. → €7,6 Mrd. (2032)
- Regulierungen: ISO Standards, Grenzüberschreitende Compliance

## 🚀 Features

### Dashboard
- Echtzeit-Statistiken über Kontakte und Kampagnen
- Branchenverteilung visualisiert
- Übersicht über aktive Kampagnen
- Öffnungs- und Klickraten

### Kontaktverwaltung
- Kontakte nach Branchen organisieren
- Tags und Notizen für jeden Kontakt
- Status-Tracking (Neu, Kontaktiert, Engagiert, Konvertiert)
- Import/Export von Kontakten

### Kampagnenmanagement
- Erstellung branchenspezifischer Kampagnen
- Template-basierte E-Mail-Komposition
- Geplante Versendung
- Tracking von Öffnungen und Klicks

### Templates
- Vorgefertigte Templates für jede Branche
- Anpassbare Variablen ({firstName}, {company}, etc.)
- Kategorien: Einführung, Follow-up, Demo-Einladung

### Analytics
- Kampagnen-Performance-Metriken
- Branchen-Vergleiche
- Zeitreihen-Analysen
- Export-Funktionen für Berichte

## 📋 Voraussetzungen

- **macOS**: 13.0 (Ventura) oder neuer
- **Xcode**: 15.0 oder neuer
- **Swift**: 5.9 oder neuer
- **SwiftUI**: Framework

## 🛠️ Installation

### 1. Repository klonen

```bash
git clone https://github.com/Harp-Corp/HarpoOutreach.git
cd HarpoOutreach
```

### 2. Xcode-Projekt öffnen

```bash
open HarpoOutreach.xcodeproj
```

### 3. Dependencies

Das Projekt nutzt native macOS-Frameworks und benötigt keine externen Dependencies.

### 4. Build und Run

1. Wählen Sie ein Ziel (Mac) in Xcode
2. Drücken Sie `Cmd + R` zum Starten

## 📁 Projektstruktur

```
HarpoOutreach/
├── HarpoOutreach/
│   ├── HarpoOutreachApp.swift          # App Entry Point
│   ├── ContentView.swift                # Hauptansicht
│   ├── Models/
│   │   ├── Contact.swift                # Kontakt-Datenmodell
│   │   ├── Campaign.swift               # Kampagnen-Datenmodell
│   │   ├── EmailTemplate.swift          # Template-Modell
│   │   └── Industry.swift               # Branchen-Enum
│   ├── Views/
│   │   ├── DashboardView.swift          # Dashboard
│   │   ├── ContactsView.swift           # Kontaktverwaltung
│   │   ├── ContactDetailView.swift      # Kontakt-Details
│   │   ├── CampaignView.swift           # Kampagnen-Übersicht
│   │   ├── EmailComposerView.swift      # E-Mail-Editor
│   │   ├── TemplatesView.swift          # Template-Verwaltung
│   │   └── AnalyticsView.swift          # Analytics-Dashboard
│   ├── ViewModels/
│   │   ├── ContactsViewModel.swift      # Kontakt-Logik
│   │   ├── CampaignViewModel.swift      # Kampagnen-Logik
│   │   └── AnalyticsViewModel.swift     # Analytics-Logik
│   ├── Services/
│   │   ├── EmailService.swift           # E-Mail-Versand
│   │   ├── DataService.swift            # Datenpersistenz
│   │   └── TemplateService.swift        # Template-Management
│   └── Resources/
│       ├── Assets.xcassets/             # Bilder und Icons
│       └── Templates/                   # E-Mail-Templates
└── README.md
```

## 💻 Verwendung

### Kontakte hinzufügen

1. Navigieren Sie zur **Kontakte**-Ansicht
2. Klicken Sie auf **+ Neuer Kontakt**
3. Füllen Sie die Kontaktdaten aus:
   - Name, E-Mail, Firma
   - Branche auswählen
   - Position und Land
   - Tags hinzufügen
4. Speichern

### Kampagne erstellen

1. Gehen Sie zu **Kampagnen**
2. Klicken Sie auf **+ Neue Kampagne**
3. Wählen Sie:
   - Branche
   - Template
   - Zielkontakte
4. Passen Sie den E-Mail-Inhalt an
5. Planen oder sofort senden

### Templates verwenden

1. Öffnen Sie **Templates**
2. Wählen Sie eine Branche
3. Bearbeiten Sie vorhandene Templates oder erstellen Sie neue
4. Verwenden Sie Variablen:
   - `{firstName}` - Vorname des Kontakts
   - `{lastName}` - Nachname
   - `{company}` - Firmenname
   - `{industry}` - Branche
   - `{position}` - Position

## 🎨 Design-Prinzipien

- **Native macOS**: Verwendet macOS Design Guidelines
- **SwiftUI**: Moderne, deklarative UI
- **Accessibility**: Unterstützung für VoiceOver und Tastaturnavigation
- **Dark Mode**: Vollständige Unterstützung
- **Performance**: Optimiert für große Kontaktlisten

## 🔒 Datenschutz

- Alle Daten werden lokal gespeichert
- Keine Cloud-Synchronisation ohne Zustimmung
- GDPR-konform
- Verschlüsselte Speicherung sensibler Daten

## 🗺️ Roadmap

### Version 1.1
- [ ] CSV-Import für Kontakte
- [ ] Erweiterte Filteroptionen
- [ ] Kampagnen-Duplikation

### Version 1.2
- [ ] Integration mit CRM-Systemen
- [ ] A/B-Testing für E-Mails
- [ ] Erweiterte Analytics mit Grafiken

### Version 2.0
- [ ] iOS/iPadOS Companion App
- [ ] Team-Funktionen und Kollaboration
- [ ] API für Automatisierung
- [ ] KI-gestützte E-Mail-Optimierung

## 🤝 Contributing

Dieses Projekt ist intern für Harpocrates Corp. Für Fragen oder Verbesserungsvorschläge kontaktieren Sie das Entwicklerteam.

## 📄 Lizenz

Proprietary - © 2026 Harpocrates Corp. Alle Rechte vorbehalten.

## 📞 Support

Für Support und Fragen:
- **Website**: [https://harpocrates-corp.com](https://harpocrates-corp.com)
- **E-Mail**: support@harpocrates-corp.com

## ✨ Über Harpocrates

Harpocrates ist ein führendes RegTech-Unternehmen, spezialisiert auf Compliance-Automatisierung für verschiedene Branchen. Die HARPOCRATES Comply Engine unterstützt Unternehmen bei der Navigation durch komplexe regulatorische Rahmenbedingungen.

---

**Entwickelt mit ❤️ für Harpocrates Corp**
