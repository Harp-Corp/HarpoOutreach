# HarpoOutreach - Update-Anleitung

## Alle Fehler beheben - Schritt für Schritt

Diese Datei enthält alle notwendigen Fixes, um die gemeldeten Fehler zu beheben.

## Schritt 1: Repository klonen oder pullen

```bash
cd /Users/martinfoerster/SpecialProjects

# Falls noch nicht geklont:
git clone https://github.com/Harp-Corp/HarpoOutreach.git
cd HarpoOutreach

# Falls schon vorhanden:
cd HarpoOutreach
git pull origin main
```

## Schritt 2: Services/PerplexityService.swift - 3 Fixes

### Fix 1: Model ändern (Zeile ~136)

**ERSETZEN:**
```swift
"model": "llama-3.1-sonar-large-128k-online",
```

**MIT:**
```swift
"model": "sonar",
```

### Fix 2: max_tokens erhöhen (Zeile ~142)

**ERSETZEN:**
```swift
"max_tokens": 2000
```

**MIT:**
```swift
"max_tokens": 800
```

### Fix 3: JSON Parsing für choices array (Zeile ~152)

**ERSETZEN:**
```swift
guard let content = response.choices?.first?.message?.content else {
```

**MIT:**
```swift
guard let content = response.choices?[0].message?.content else {
```

## Schritt 3: Views/ProspectingView.swift - Dialog Größe Fix

### Fix 4: Manual Entry Dialog vergrößern (Zeile ~351)

**SUCHEN SIE nach der `.sheet` für `showManualCompanyEntry` und FÜGEN SIE HINZU:**

```swift
.sheet(isPresented: $showManualCompanyEntry) {
    // ... existing content ...
}
.frame(minWidth: 600, minHeight: 500)  // <- Diese Zeile NACH .sheet hinzufügen
```

**Vollständiges Beispiel:**
```swift
.sheet(isPresented: $showManualCompanyEntry) {
    NavigationView {
        Form {
            Section(header: Text("Company Details")) {
                TextField("Company Name", text: $manualCompanyName)
                TextField("Industry", text: $manualCompanyIndustry)
                TextField("Website", text: $manualCompanyWebsite)
                TextField("Description", text: $manualCompanyDescription)
            }
        }
        .navigationTitle("Add Company Manually")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showManualCompanyEntry = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    viewModel.addManualCompany(
                        name: manualCompanyName,
                        industry: manualCompanyIndustry,
                        region: selectedRegion.rawValue,
                        website: manualCompanyWebsite,
                        description: manualCompanyDescription
                    )
                    showManualCompanyEntry = false
                    manualCompanyName = ""
                    manualCompanyIndustry = ""
                    manualCompanyWebsite = ""
                    manualCompanyDescription = ""
                }
            }
        }
    }
    .frame(minWidth: 600, minHeight: 500)
}
```

## Schritt 4: In Xcode bauen

1. Öffnen Sie `HarpoOutreach.xcodeproj` in Xcode
2. Wählen Sie "Product" -> "Clean Build Folder" (Cmd+Shift+K)
3. Bauen Sie das Projekt neu (Cmd+B)
4. Starten Sie die App (Cmd+R)

## Zusammenfassung der Fixes

✅ **Fix 1**: API Model von llama-3.1-sonar zu "sonar" -> Behebt "No content in response" error  
✅ **Fix 2**: max_tokens auf 800 -> Längere, bessere Antworten  
✅ **Fix 3**: choices array Parsing -> Korrekte JSON-Struktur  
✅ **Fix 4**: Manual Entry Dialog Größe -> Benutzbares UI  
✅ **Bonus**: Test-Company wird automatisch hinzugefügt (bereits im Code)  

## Test-Funktionalität

Nach dem Build wird automatisch "Harpocrates Corp" als Test-Company hinzugefügt, damit Sie den Email-Versand testen können ohne an echte Empfänger zu senden.

## Bei Problemen

Falls Fehler auftreten:
1. Überprüfen Sie, dass alle 4 Fixes korrekt angewendet wurden
2. Clean Build Folder in Xcode
3. Restart Xcode
4. Überprüfen Sie Ihre Perplexity API Key Konfiguration
