# HarpoOutreach - Aktuelle Bugfixes

Datum: 16. Februar 2026

## Problem 1: Suchergebnisse werden nicht angezeigt

**Symptom**: Die Perplexity API liefert korrekte JSON-Daten (sichtbar in Debugger), aber keine Companies erscheinen in der UI.

**Ursache**: Das JSON-Parsing in `PerplexityService.swift` schlägt fehl, weil `cleanJSON()` die Array-Grenzen nicht korrekt erkennt wenn das JSON escaped Backslashes enthält.

**Lösung**: Ersetzen Sie in `Services/PerplexityService.swift` die `cleanJSON` Funktion (ganz am Ende der Datei):

```swift
private func cleanJSON(_ content: String) -> String {
    var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Entferne Markdown Code-Blocks
    if s.hasPrefix("```json") {
        s = String(s.dropFirst(7))
    } else if s.hasPrefix("```") {
        s = String(s.dropFirst(3))
    }
    if s.hasSuffix("```") {
        s = String(s.dropLast(3))
    }
    
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // WICHTIG: Direkt zurückgeben, wenn es mit [ oder { beginnt
    if s.hasPrefix("[") || s.hasPrefix("{") {
        return s
    }
    
    // Fallback: Suche nach Array oder Object
    if let aStart = s.firstIndex(of: "["), let aEnd = s.lastIndex(of: "]") {
        return String(s[aStart...aEnd])
    }
    if let oStart = s.firstIndex(of: "{"), let oEnd = s.lastIndex(of: "}") {
        return String(s[oStart...oEnd])
    }
    
    return s
}
```

**Wichtiger Zusatz**: Fügen Sie am Anfang der `findCompanies` Funktion (Zeile ~20) Debug-Logging hinzu:

```swift
let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
print("[DEBUG] Raw response length: \(response.count)")
print("[DEBUG] Response preview: \(String(response.prefix(200)))")

let parsed = parseCompanies(from: response, industry: industry.rawValue, region: region.rawValue)
print("[DEBUG] Parsed companies count: \(parsed.count)")
return parsed
```

---

## Problem 2: Kein "Abbrechen"-Button während der Suche

**Symptom**: Wenn die automatische Suche läuft, gibt es keine Möglichkeit sie abzubrechen.

**Lösung**: Fügen Sie in `ViewModels/AppViewModel.swift` ein:

### Schritt 1: Neue Property für Cancellation hinzufügen (nach `@Published var isRunning`)

```swift
private var currentTask: Task<Void, Never>?
```

### Schritt 2: `findCompanies()` Funktion wrappen

**Ersetzen Sie die gesamte `findCompanies()` Funktion**:

```swift
@MainActor
func findCompanies(industry: Industry, region: Region, apiKey: String) async throws -> [Company] {
    // Checke ob Task cancelled wurde
    try Task.checkCancellation()
    
    let pplx = PerplexityService()
    return try await pplx.findCompanies(industry: industry, region: region, apiKey: apiKey)
}
```

### Schritt 3: Neue `cancelSearch()` Funktion hinzufügen

```swift
func cancelSearch() {
    currentTask?.cancel()
    currentTask = nil
    isRunning = false
    statusMessage = "Suche abgebrochen"
}
```

### Schritt 4: ProspectingView.swift - "Abbrechen" Button hinzufügen

Suchen Sie in `Views/ProspectingView.swift` nach dem Button "Automatische Suche" (Zeile ~36) und fügen Sie **direkt darunter** ein:

```swift
if vm.isLoading {
    Button("Abbrechen") {
        vm.cancelSearch()
    }
    .buttonStyle(.bordered)
}
```

**Vollständiges Beispiel** (Zeile 36-47):

```swift
Button(action: { Task { await vm.findCompanies() } }) {
    Label("Automatische Suche", systemImage: "magnifyingglass")
}
.buttonStyle(.borderedProminent)
.disabled(vm.companies.isEmpty || vm.isLoading)

if vm.isLoading {
    Button("Abbrechen") {
        vm.cancelSearch()
    }
    .buttonStyle(.bordered)
}
```

---

## Problem 3: Eingabefelder im Manual Entry Dialog zu klein

**Symptom**: Der Dialog ist jetzt größer (.frame(minWidth: 600, minHeight: 500)), aber die TextFields sind immer noch winzig.

**Lösung**: Die TextFields brauchen explizite Höhe. Erstellen Sie eine neue View-Datei oder bearbeiten Sie direkt in den Manual Entry Views.

### Option A: Schnellfix in ProspectingView.swift

Suchen Sie nach `ManualCompanyEntryView` und `ManualContactEntryView` Definitionen. Falls diese inline in ProspectingView.swift sind:

**Ersetzen Sie alle `TextField` durch**:

```swift
TextField("Company Name", text: $manualCompanyName)
    .textFieldStyle(.roundedBorder)
    .frame(height: 32)  // <- Diese Zeile hinzufügen
```

### Option B: Separate View-Dateien erstellen (empfohlen)

Falls `ManualCompanyEntryView` und `ManualContactEntryView` **separate Dateien** in `/Views` sind:

**In `Views/ManualCompanyEntryView.swift`** - Alle TextField wie folgt ändern:

```swift
Form {
    Section(header: Text("Unternehmensdaten")) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Firmenname")
                .font(.headline)
            TextField("z.B. Volkswagen AG", text: $companyName)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            Text("Branche")
                .font(.headline)
            TextField("z.B. Automotive", text: $industry)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            Text("Website")
                .font(.headline)
            TextField("z.B. https://vw.com", text: $website)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            Text("Beschreibung")
                .font(.headline)
            TextEditor(text: $description)
                .frame(minHeight: 80)
                .border(Color.gray.opacity(0.3))
        }
        .padding(.vertical, 8)
    }
}
```

**Gleiche Änderungen** in `Views/ManualContactEntryView.swift`.

### Option C: Globaler Modifier (Beste Lösung)

Fügen Sie am **Ende** von `Services/PerplexityService.swift` (oder besser: neue Datei `Utilities/ViewModifiers.swift`) hinzu:

```swift
import SwiftUI

struct LargeTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 36)
            .padding(.vertical, 4)
    }
}

extension View {
    func largeTextField() -> some View {
        modifier(LargeTextFieldStyle())
    }
}
```

Dann in **allen** Manual Entry Views:

```swift
TextField("Company Name", text: $name)
    .largeTextField()  // <- Statt .textFieldStyle
```

---

## Test-Checkliste

Nach Anwendung der Fixes:

- [ ] Build erfolgreich in Xcode
- [ ] Automatische Suche zeigt Unternehmen in der Liste an
- [ ] "Abbrechen"-Button erscheint während der Suche
- [ ] Abbrechen stoppt die Suche und setzt Status zurück
- [ ] Manual Entry Dialog: Alle Felder sind gut lesbar und nutzbar
- [ ] Manual Entry Dialog: Speichern fügt Company/Contact zur Liste hinzu

---

## Wenn Probleme bleiben

### Debug-Schritte:

1. **JSON Parsing**: Schauen Sie in die Xcode Console nach `[DEBUG]` Ausgaben
2. **Task Cancellation**: Schauen Sie nach "Task was cancelled" Errors
3. **UI Updates**: Stellen Sie sicher, dass `@MainActor` vor allen ViewModel Funktionen steht

### Häufige Fehlerquellen:

- **SwiftData vs. @Published**: Falls Sie SwiftData verwenden, müssen `companies` und `leads` dort gespeichert werden, nicht nur in `@Published` Arrays
- **Async Context**: `findCompanies` muss mit `await` aufgerufen werden
- **API Key**: Überprüfen Sie dass `settings.perplexityAPIKey` gesetzt ist

---

## Nächste Schritte nach Fixes

1. Testen Sie die komplette Pipeline: Suche → Kontakte → Email Verifikation → Email Draft
2. Exportieren Sie Test-Daten nach CSV/Excel
3. Testen Sie Gmail-Integration (falls implementiert)

---

**Viel Erfolg!**
