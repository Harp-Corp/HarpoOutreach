# READY TO PULL - Die wichtigsten Fixes sind auf GitHub!

## STATUS: TEILWEISE FERTIG

### ✅ BEREITS AUF GITHUB GEFIXT:

1. **Services/PerplexityService.swift**
   - ✅ Model: "sonar" (statt "sonar-pro")
   - ✅ max_tokens: 800 (statt 2000)
   - ✅ JSON Parsing: `choices?[0].message` (statt `.first`)

2. **Views/ProspectingView.swift**
   - ✅ .frame(minWidth: 600, minHeight: 500) für beide Manual Entry Dialogs

### ⚠️ NOCH ERFORDERLICH (manuell in Xcode):

Das JSON-Parsing-Problem könnte noch bestehen, weil die `parseCompanies` Funktion in der aktuellen PerplexityService.swift nicht optimal ist.

**LÖSUNG**: Sehen Sie in die **BUGFIXES.md** - dort steht die komplette `cleanJSON` Funktion die Sie verwenden sollten.

---

## JETZT TUN:

```bash
cd /Users/martinfoerster/SpecialProjects/HarpoOutreach
git pull origin main
```

### Dann in Xcode:

1. **Clean Build** (Cmd+Shift+K)
2. **Build** (Cmd+B)
3. **Run** (Cmd+R)

### Test:
- Automatische Suche starten
- Schauen Sie in die **Xcode Console** nach `[DEBUG]` Ausgaben
- Wenn Companies gefunden wurden: ✅ FERTIG!
- Wenn nicht: Siehe unten

---

## FALLS COMPANIES IMMER NOCH NICHT ANGEZEIGT WERDEN:

Dann müssen Sie die `parseCompanies` Funktion in `Services/PerplexityService.swift` ersetzen.

**Öffnen Sie**: `Services/PerplexityService.swift`

**Suchen Sie nach** (Zeile ~21): 
```swift
return parseCompanies(from: response, industry: industry.rawValue, region: region.rawValue)
```

**Ersetzen Sie diese ganze Funktion** mit der Version aus **BUGFIXES.md** die `parseJSON` verwendet.

ODER einfacher: 

**Löschen Sie Zeile 21** und ersetzen Sie durch:
```swift
let parsed = parseJSON(content).map { d in
    Company(
        name: d["name"] ?? "Unknown",
        industry: d["industry"] ?? industry.rawValue,
        region: d["region"] ?? region.rawValue,
        website: d["website"] ?? "",
        description: d["description"] ?? ""
    )
}
return parsed
```

Und fügen Sie diese Hilfsfunktion am Ende der Datei hinzu (vor dem letzten `}`):

```swift
private func parseJSON(_ content: String) -> [[String: String]] {
    let json = cleanJSON(content)
    guard let data = json.data(using: .utf8) else { return [] }
    do {
        return try JSONDecoder().decode([[String: String]].self, from: data)
    } catch {
        print("JSON Parse Error: \(error)")
        return []
    }
}

private func cleanJSON(_ content: String) -> String {
    var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
    else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
    if s.hasSuffix("```") { s = String(s.dropLast(3)) }
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // WICHTIG!
    if s.hasPrefix("[") || s.hasPrefix("{") { return s }
    
    if let aStart = s.firstIndex(of: "["), let aEnd = s.lastIndex(of: "]") {
        return String(s[aStart...aEnd])
    }
    if let oStart = s.firstIndex(of: "{"), let oEnd = s.lastIndex(of: "}") {
        return String(s[oStart...oEnd])
    }
    return s
}
```

---

## FÜR ABBRECHEN-BUTTON:

Wenn Sie einen Abbrechen-Button während der Suche haben wollen, siehe **BUGFIXES.md** Abschnitt 2.

---

## FÜR GRÖSSERE TEXTFELDER:

Wenn die Manual Entry Dialoge immer noch zu klein sind, siehe **BUGFIXES.md** Abschnitt 3.

---

**ZUSAMMENFASSUNG**: 
- git pull
- Build in Xcode
- Wenn es funktioniert: FERTIG!
- Wenn nicht: Die 2 Code-Snippets oben in PerplexityService.swift einfügen

Viel Erfolg!
