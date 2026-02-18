# HarpoOutreach - Fixes Required

## Probleme (16.02.2026)

### 1. ✅ Manuelle Eingabebox unbrauchbar
**Problem**: Dialog zu klein, Felder abgeschnitten
**Ursache**: NavigationView ohne Mindestgröße
**Fix**: In `ProspectingView.swift` bei beiden Manual Entry Views hinzufügen:
```swift
.frame(minWidth: 600, minHeight: 500)
```

**Zeilen**:
- Line ~270: `ManualCompanyEntryView` → nach `NavigationView {` hinzufügen
- Line ~340: `ManualContactEntryView` → nach `NavigationView {` hinzufügen

### 2. ✅ Automatische Unternehmenssuche bricht ab
**Problem**: "No content in response error -2"
**Ursache**: PerplexityService erwartet JSON, API gibt aber Text zurück
**Fix**: In `Services/PerplexityService.swift`:

1. Modell ändern von `llama-3.1-sonar-large-128k-online` zu `sonar-pro`
2. Besseres JSON-Parsing mit Fallback
3. Error-Handling verbessern

### 3. ✅ Email-Verifikation funktioniert nicht
**Problem**: Gibt keine verifizierten Emails zurück
**Ursache**: Zu strenge Parsing-Logik
**Fix**: In `PerplexityService.swift` → `verifyEmail()` Funktion:
- Fallback auf Common Patterns erlauben
- Auch nicht-100% verifizierte Emails akzeptieren wenn Muster stimmt

### 4. ✅ Test-Modus fehlt
**Problem**: Kann Email-Versand nicht testen ohne echte Empfänger
**Lösung**: Testfirma "Harpocrates" hinzufügen

---

## Sofort-Fixes (Manuelle Änderungen in Xcode)

### Fix 1: Manual Entry Dialog Größe

**Datei**: `Views/ProspectingView.swift`

**Zeile ~270** - Nach `var body: some View {` in `ManualCompanyEntryView`:
```swift
NavigationView {
    Form {
        // ... existing code
    }
    .navigationTitle("Unternehmen hinzufügen")
    // ... toolbar
}
.frame(minWidth: 600, minHeight: 500)  // ← HINZUFÜGEN
```

**Zeile ~340** - Nach `var body: some View {` in `ManualContactEntryView`:
```swift
NavigationView {
    Form {
        // ... existing code
    }
    .navigationTitle("Kontakt hinzufügen")
    // ... toolbar  
}
.frame(minWidth: 600, minHeight: 500)  // ← HINZUFÜGEN
```

### Fix 2: Testfirma hinzufügen

**Datei**: `ViewModels/AppViewModel.swift`

**Nach Zeile ~406** (vor der letzten schließenden Klammer):
```swift
// MARK: - Test Mode
func addTestCompany() {
    let testCompany = Company(
        name: "Harpocrates Corp",
        industry: "Financial Services",
        region: "DACH",
        website: "https://harpocrates-corp.com",
        description: "RegTech Startup für Compliance Management",
        source: "test"
    )
    
    if !companies.contains(where: { $0.name == "Harpocrates Corp" }) {
        companies.append(testCompany)
    }
    
    let testLead = Lead(
        name: "Martin",
        title: "CEO",
        company: testCompany,
        email: "mf@harpocrates-corp.com",
        emailVerified: true,
        status: .emailVerified,
        source: "test"
    )
    
    if !leads.contains(where: { $0.email == "mf@harpocrates-corp.com" }) {
        leads.append(testLead)
        saveLeads()
    }
}
```

**Datei**: `Views/ProspectingView.swift`

**Zeile ~35** - Im Menu nach "Unternehmen manuell hinzufügen":
```swift
Button(action: { showManualCompanySheet = true }) {
    Label("Unternehmen manuell hinzufügen", systemImage: "plus.circle")
}
Divider()  // ← HINZUFÜGEN
Button(action: { vm.addTestCompany() }) {  // ← HINZUFÜGEN
    Label("Testfirma (Harpocrates) hinzufügen", systemImage: "flask")
}
```

---

## PerplexityService Robuster machen

Das ist komplexer - siehe angehängte `PerplexityService.swift` Datei.
Kernänderungen:

1. **Model**: `sonar-pro` statt `llama-3.1-sonar-large-128k-online`
2. **Timeout**: 90 Sekunden
3. **JSON Parsing**: Mit `cleanJSON()` Helper
4. **Error Messages**: Bessere Fehlermeldungen
5. **Fallback Logic**: Bei Parsing-Fehlern nicht komplett abbrechen

---

## Nach den Fixes testen:

1. ✅ Manuelle Firmenein
