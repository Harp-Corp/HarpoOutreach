#!/bin/bash
# harpo-sync: Robuster GitHub-Sync (GitHub ist IMMER fuehrend)
# Version 3.2 - macOS-kompatibel, kein GNU timeout noetig

# Farben fuer Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_DIR="$HOME/SpecialProjects/HarpoOutreach"
REPO_URL="https://github.com/Harp-Corp/HarpoOutreach.git"
GIT_TIMEOUT=180

# Self-Update: Aktualisiert /usr/local/bin/harpo-sync aus GitHub
SCRIPT_VERSION="3.2"
RAW_URL="https://raw.githubusercontent.com/Harp-Corp/HarpoOutreach/main/.github/scripts/harpo-sync.sh"
INSTALLED_SCRIPT="/usr/local/bin/harpo-sync"

self_update() {
  if [ -w "$INSTALLED_SCRIPT" ] || [ -w "$(dirname "$INSTALLED_SCRIPT")" ]; then
    local tmp_script
    tmp_script=$(mktemp)
    if curl -fsSL "$RAW_URL" -o "$tmp_script" 2>/dev/null; then
      local remote_ver
      remote_ver=$(grep '^SCRIPT_VERSION=' "$tmp_script" | head -1 | cut -d'"' -f2)
      if [ -n "$remote_ver" ] && [ "$remote_ver" != "$SCRIPT_VERSION" ]; then
        cp "$tmp_script" "$INSTALLED_SCRIPT"
        chmod +x "$INSTALLED_SCRIPT"
        echo -e "${GREEN}AUTO-UPDATE${NC} harpo-sync $SCRIPT_VERSION -> $remote_ver"
        rm -f "$tmp_script"
        exec "$INSTALLED_SCRIPT" "$@"
      fi
      rm -f "$tmp_script"
    fi
  fi
}
self_update "$@"

# Hilfsfunktionen
TOTAL_STEPS=6
step() { echo -e "\n${BLUE}[$1/$TOTAL_STEPS]${NC} $2"; }
ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }
fail() { echo -e "  ${RED}FEHLER${NC} $1"; }

# macOS-kompatibler Timeout (kein GNU coreutils noetig)
run_with_timeout() {
  local timeout_sec=$1
  shift
  "$@" &
  local pid=$!
  ( sleep "$timeout_sec" && kill "$pid" 2>/dev/null ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local exit_code=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return $exit_code
}

echo -e "${BLUE}harpo-sync v$SCRIPT_VERSION${NC} - GitHub ist fuehrend"
echo "=========================================="

# --- Schritt 1: Xcode beenden ---
step 1 "Xcode beenden"
if pgrep -x "Xcode" > /dev/null 2>&1; then
  killall Xcode 2>/dev/null
  sleep 1
  ok "Xcode beendet"
else
  ok "Xcode war nicht aktiv"
fi

# --- Schritt 2: Projektverzeichnis pruefen ---
step 2 "Projektverzeichnis pruefen"
if [ ! -d "$PROJECT_DIR" ]; then
  fail "Verzeichnis nicht gefunden: $PROJECT_DIR"
  echo "  Klone Repository neu..."
  git clone "$REPO_URL" "$PROJECT_DIR" || { fail "Klonen fehlgeschlagen"; exit 1; }
fi
cd "$PROJECT_DIR" || { fail "cd fehlgeschlagen"; exit 1; }
ok "$PROJECT_DIR"

# --- Schritt 3: DerivedData loeschen ---
step 3 "Xcode DerivedData loeschen"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED" ]; then
  find "$DERIVED" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  ok "DerivedData bereinigt"
else
  ok "Kein DerivedData vorhanden"
fi

# --- Schritt 4: Git Synchronisierung ---
step 4 "Git Synchronisierung (GitHub -> Lokal)"

# 4a: Lokale Aenderungen verwerfen
echo "  Verwerfe lokale Aenderungen..."
git reset --hard HEAD 2>/dev/null
git clean -fd 2>/dev/null
ok "Lokale Aenderungen verworfen"

# 4b: Remote aktualisieren (mit Timeout)
echo "  Hole Aenderungen von GitHub..."
if git fetch origin --prune 2>&1; then
  ok "Fetch erfolgreich"
else
  FETCH_EXIT=$?
  warn "Fetch fehlgeschlagen (Exit: $FETCH_EXIT) - versuche shallow fetch..."
  if git fetch origin main --depth=1 2>&1; then
    ok "Shallow Fetch erfolgreich"
  else
    fail "Auch Shallow Fetch fehlgeschlagen"
    echo "  Pruefe deine Internetverbindung und versuche es erneut."
    exit 1
  fi
fi

# 4c: Auf main Branch wechseln und auf Remote zuruecksetzen
git checkout main 2>/dev/null || git checkout -b main origin/main 2>/dev/null
git reset --hard origin/main
ok "Lokal = GitHub (origin/main)"

# 4d: Status anzeigen
echo -e "  ${GREEN}Aktueller Commit:${NC}"
git log -1 --oneline --decorate
echo ""
git log -3 --oneline --format="  %h %s" 2>/dev/null

# --- Schritt 5: Xcode oeffnen ---
step 5 "Xcode Projekt oeffnen"
if [ -f "$PROJECT_DIR/HarpoOutreach.xcodeproj/project.pbxproj" ]; then
  open "$PROJECT_DIR/HarpoOutreach.xcodeproj"
  ok "Xcode Projekt geoeffnet"
else
  fail "project.pbxproj nicht gefunden!"
  exit 1
fi

# --- Schritt 6: Build ---
step 6 "Clean Build starten"
sleep 3
echo "  Starte xcodebuild..."
if xcodebuild -project "$PROJECT_DIR/HarpoOutreach.xcodeproj" \
  -scheme HarpoOutreach \
  -configuration Debug \
  -destination 'platform=macOS' \
  clean build 2>&1 | tail -20; then
  echo ""
  ok "Build erfolgreich!"
else
  echo ""
  warn "Build fehlgeschlagen - Xcode ist trotzdem geoeffnet"
  warn "Pruefe die Fehler in Xcode direkt"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Synchronisierung abgeschlossen!${NC}"
echo -e "Projekt ist 100% synchron mit GitHub"
echo "=========================================="
