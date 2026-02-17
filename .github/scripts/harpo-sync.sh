#!/bin/bash
# harpo-sync: Aggressiver GitHub-Sync (GitHub ist IMMER führend)

set -e

PROJECT_DIR="$HOME/SpecialProjects/HarpoOutreach"
REPO_URL="https://github.com/Harp-Corp/HarpoOutreach.git"

echo "🔄 harpo-sync: GitHub ist führend - lokale Änderungen werden VERWORFEN"

cd "$PROJECT_DIR" 2>/dev/null || {
  echo "❌ Fehler: Projekt-Verzeichnis nicht gefunden: $PROJECT_DIR"
  exit 1
}

# 1. Xcode beenden (falls läuft)
echo "📱 Schliesse Xcode..."
killall Xcode 2>/dev/null || true

# 2. Xcode Derived Data löschen
echo "🗑️  Lösche Xcode Derived Data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null || true

# 3. Git Status speichern (nur zur Info)
echo "📊 Aktueller Git Status:"
git status --short

# 4. AGGRESSIVE Synchronisierung
echo "⚡ AGGRESSIVE Synchronisierung von GitHub..."

# Alle lokalen Änderungen verwerfen
git reset --hard HEAD

# Alle untracked files löschen
git clean -fdx

# Remote aktualisieren
git fetch origin --prune

# Lokalen Branch auf Remote zurücksetzen (HARD)
git reset --hard origin/main

# Sicherstellen, dass wir auf main sind
git checkout main

# Nochmal pullen (sollte "Already up to date" sein)
git pull origin main

# 5. Verify
echo "✅ Synchronisierung abgeschlossen!"
echo "📍 Aktueller Commit:"
git log -1 --oneline

echo ""
echo "🎯 Projekt ist jetzt 100% synchron mit GitHub"

echo ""
# 6. Xcode Projekt öffnen und bauen
echo "📂 Öffne Xcode Projekt..."
open "$PROJECT_DIR/HarpoOutreach.xcodeproj"

# Kurz warten bis Xcode gestartet ist
sleep 3

# Clean Build durchführen
echo "🔨 Starte Clean Build..."
xcodebuild -project "$PROJECT_DIR/HarpoOutreach.xcodeproj" \
  -scheme HarpoOutreach \
  -configuration Debug \
  clean build \
  | xcpretty || true

echo ""
echo "✅ Synchronisierung und Build abgeschlossen!"
echo "💡 Xcode ist jetzt geöffnet mit dem aktuellen Projekt" 
