#!/bin/bash
# harpo-sync: Robuster GitHub-Sync (GitHub ist IMMER fuehrend)
# Version 4.0 - Pipeline-Update: Incremental Build, Remote Trigger Support

# Farben fuer Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_DIR="$HOME/SpecialProjects/HarpoOutreach"
REPO_URL="https://github.com/Harp-Corp/HarpoOutreach.git"
FETCH_TIMEOUT=60
TARGET_BRANCH="HarpoOutreachNewsletter"

# CLI Flags
CLEAN_BUILD=false
SKIP_BUILD=false
SKIP_XCODE=false
for arg in "$@"; do
  case $arg in
    --clean)    CLEAN_BUILD=true ;;
    --no-build) SKIP_BUILD=true ;;
    --no-xcode) SKIP_XCODE=true ;;
    --help|-h)
      echo "harpo-sync [options]"
      echo "  --clean     Clean Build (statt incremental)"
      echo "  --no-build  Nur sync, kein Build"
      echo "  --no-xcode  Xcode nicht oeffnen"
      echo "  --help      Diese Hilfe"
      exit 0 ;;
  esac
done

# ANTI-HANG: Verhindert dass git auf Passwort-Eingabe wartet
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

# Self-Update
SCRIPT_VERSION="4.0"
RAW_URL="https://raw.githubusercontent.com/Harp-Corp/HarpoOutreach/HarpoOutreachNewsletter/.github/scripts/harpo-sync.sh"
INSTALLED_SCRIPT="/usr/local/bin/harpo-sync"

self_update() {
  if [ -w "$INSTALLED_SCRIPT" ] || [ -w "$(dirname "$INSTALLED_SCRIPT")" ]; then
    local tmp_script
    tmp_script=$(mktemp)
    if curl --connect-timeout 5 --max-time 15 -fsSL "$RAW_URL" -o "$tmp_script" 2>/dev/null; then
      local remote_ver
      remote_ver=$(grep '^SCRIPT_VERSION=' "$tmp_script" | head -1 | cut -d'"' -f2)
      if [ -n "$remote_ver" ] && [ "$remote_ver" != "$SCRIPT_VERSION" ]; then
        cp "$tmp_script" "$INSTALLED_SCRIPT"
        chmod +x "$INSTALLED_SCRIPT"
        echo -e "${GREEN}AUTO-UPDATE${NC} harpo-sync $SCRIPT_VERSION -> $remote_ver"
        rm -f "$tmp_script"
        exec "$INSTALLED_SCRIPT" "$@"
      fi
    fi
    rm -f "$tmp_script"
  fi
}
self_update "$@"

# Hilfsfunktionen
if $SKIP_BUILD; then TOTAL_STEPS=5; elif $SKIP_XCODE; then TOTAL_STEPS=5; else TOTAL_STEPS=6; fi
STEP_NUM=0
step() { STEP_NUM=$((STEP_NUM + 1)); echo -e "\n${BLUE}[$STEP_NUM/$TOTAL_STEPS]${NC} $1"; }
ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }
fail() { echo -e "  ${RED}FEHLER${NC} $1"; }

# Spinner mit Timeout
spinner_with_timeout() {
  local pid=$1
  local msg=$2
  local timeout_sec=${3:-60}
  local chars='|/-\\'
  local i=0
  local start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    local elapsed=$((SECONDS - start))
    if [ $elapsed -ge $timeout_sec ]; then
      kill "$pid" 2>/dev/null
      sleep 1
      kill -9 "$pid" 2>/dev/null
      printf "\r"
      return 1
    fi
    printf "\r  ${YELLOW}%s${NC} %s (%ds/%ds)" "${chars:i++%4:1}" "$msg" "$elapsed" "$timeout_sec"
    sleep 0.3
  done
  printf "\r"
  return 0
}

# Fresh Clone
fresh_clone() {
  warn "Loesche altes Repo und klone neu..."
  cd "$HOME" || exit 1
  rm -rf "$PROJECT_DIR"
  git clone --depth=1 -b "$TARGET_BRANCH" "$REPO_URL" "$PROJECT_DIR" 2>&1 &
  local CLONE_PID=$!
  spinner_with_timeout $CLONE_PID "Clone laeuft" 90
  local CLONE_SPINNER=$?
  if [ $CLONE_SPINNER -ne 0 ]; then
    kill $CLONE_PID 2>/dev/null
    kill -9 $CLONE_PID 2>/dev/null
    return 1
  fi
  wait $CLONE_PID 2>/dev/null
  return $?
}

echo -e "${BLUE}${BOLD}harpo-sync v$SCRIPT_VERSION${NC} - GitHub ist fuehrend"
echo "=========================================="
BUILD_START=$SECONDS

# --- Schritt 1: Xcode beenden ---
step "Xcode beenden"
if pgrep -x "Xcode" > /dev/null 2>&1; then
  killall Xcode 2>/dev/null
  sleep 1
  ok "Xcode beendet"
else
  ok "Xcode war nicht aktiv"
fi

# --- Schritt 2: Projektverzeichnis pruefen ---
step "Projektverzeichnis pruefen"
if [ ! -d "$PROJECT_DIR" ]; then
  fail "Verzeichnis nicht gefunden: $PROJECT_DIR"
  echo "  Klone Repository neu..."
  git clone --depth=1 -b "$TARGET_BRANCH" "$REPO_URL" "$PROJECT_DIR" || { fail "Klonen fehlgeschlagen"; exit 1; }
fi
cd "$PROJECT_DIR" || { fail "cd fehlgeschlagen"; exit 1; }
ok "$PROJECT_DIR"

# --- Schritt 3: DerivedData loeschen ---
step "Xcode DerivedData loeschen"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED" ]; then
  find "$DERIVED" -mindepth 1 -maxdepth 1 -name "HarpoOutreach-*" -exec rm -rf {} + 2>/dev/null
  ok "DerivedData bereinigt"
else
  ok "Kein DerivedData vorhanden"
fi

# --- Schritt 4: Git Synchronisierung ---
step "Git Synchronisierung (GitHub -> Lokal)"

git config --local http.lowSpeedLimit 1000
git config --local http.lowSpeedTime 10

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
  warn "Falscher Branch: $CURRENT_BRANCH (erwartet: $TARGET_BRANCH)"
  if fresh_clone; then
    cd "$PROJECT_DIR" || { fail "cd fehlgeschlagen"; exit 1; }
    ok "Fresh Clone auf $TARGET_BRANCH erfolgreich"
  else
    fail "Fresh Clone fehlgeschlagen"
    exit 1
  fi
else
  echo "  Verwerfe lokale Aenderungen..."
  git reset --hard HEAD 2>/dev/null
  git clean -fd 2>/dev/null
  ok "Lokale Aenderungen verworfen"

  echo "  Hole Aenderungen von GitHub..."
  git fetch origin "$TARGET_BRANCH" --depth=1 --no-tags 2>&1 &
  FETCH_PID=$!
  spinner_with_timeout $FETCH_PID "Fetch laeuft" $FETCH_TIMEOUT
  SPINNER_EXIT=$?

  if [ $SPINNER_EXIT -ne 0 ]; then
    warn "Fetch Timeout nach ${FETCH_TIMEOUT}s"
    if fresh_clone; then
      cd "$PROJECT_DIR" || { fail "cd fehlgeschlagen"; exit 1; }
      ok "Fresh Clone erfolgreich"
    else
      fail "Auch Fresh Clone fehlgeschlagen"
      echo "  Pruefe deine Internetverbindung und versuche es erneut."
      exit 1
    fi
  else
    wait $FETCH_PID 2>/dev/null
    FETCH_EXIT=$?
    if [ $FETCH_EXIT -eq 0 ]; then
      ok "Fetch erfolgreich"
    else
      warn "Fetch fehlgeschlagen (Exit: $FETCH_EXIT) - versuche Fresh Clone..."
      if fresh_clone; then
        cd "$PROJECT_DIR" || { fail "cd fehlgeschlagen"; exit 1; }
        ok "Fresh Clone erfolgreich"
      else
        fail "Auch Fresh Clone fehlgeschlagen"
        exit 1
      fi
    fi
  fi

  git reset --hard "origin/$TARGET_BRANCH" 2>/dev/null
fi

ok "Lokal = GitHub (origin/$TARGET_BRANCH)"

# Letzte Commits anzeigen
echo ""
echo -e "  ${GREEN}${BOLD}Letzte Commits:${NC}"
git log -5 --oneline --format="  %C(yellow)%h%C(reset) %s %C(blue)(%cr)%C(reset)" 2>/dev/null
echo ""

# --- Schritt 5: Xcode oeffnen ---
if ! $SKIP_XCODE; then
  step "Xcode Projekt oeffnen"
  if [ -f "$PROJECT_DIR/HarpoOutreach.xcodeproj/project.pbxproj" ]; then
    open "$PROJECT_DIR/HarpoOutreach.xcodeproj"
    ok "Xcode Projekt geoeffnet"
  else
    fail "project.pbxproj nicht gefunden!"
    exit 1
  fi
fi

# --- Schritt 6: Build ---
if ! $SKIP_BUILD; then
  if $CLEAN_BUILD; then
    step "Clean Build"
    BUILD_ACTION="clean build"
  else
    step "Incremental Build"
    BUILD_ACTION="build"
  fi
  sleep 2
  BUILD_LOG="/tmp/harpo-build.log"
  > "$BUILD_LOG"
  echo "  Kompiliere..."

  xcodebuild -project "$PROJECT_DIR/HarpoOutreach.xcodeproj" \
    -scheme HarpoOutreach \
    -configuration Debug \
    -destination 'platform=macOS' \
    $BUILD_ACTION 2>&1 | while IFS= read -r line; do
    echo "$line" >> "$BUILD_LOG"
    case "$line" in
      *": error:"*)
        echo -e "  ${RED}ERROR${NC} $line"
        ;;
      *": warning:"*)
        echo -e "  ${YELLOW}WARN${NC} $(echo "$line" | sed 's/.*warning: //')"
        ;;
      *"Build Succeeded"*)
        echo -e "  ${GREEN}${BOLD}BUILD SUCCEEDED${NC}"
        ;;
      *"BUILD FAILED"*|*"Build Failed"*)
        echo -e "  ${RED}${BOLD}BUILD FAILED${NC}"
        ;;
      *"Compiling "*|*"CompileSwift"*)
        printf "\r  ${BLUE}Kompiliere${NC} $(echo "$line" | grep -oE '[^ /]+\.swift' | tail -1) "
        ;;
      *"Linking "*|*"Ld "*)
        printf "\r  ${BLUE}Linke${NC} HarpoOutreach \n"
        ;;
    esac
  done

  BUILD_EXIT=${PIPESTATUS[0]}
fi

BUILD_DURATION=$((SECONDS - BUILD_START))

echo ""
echo -e "${BOLD}==========================================${NC}"
if $SKIP_BUILD; then
  echo -e "${GREEN}${BOLD}  SYNC FERTIG (${BUILD_DURATION}s)${NC}"
  echo -e "${GREEN}  Xcode ist bereit - Build manuell starten.${NC}"
elif [ ${BUILD_EXIT:-1} -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  FERTIG - Build erfolgreich! (${BUILD_DURATION}s)${NC}"
  echo -e "${GREEN}  Xcode ist bereit - du kannst loslegen.${NC}"
  osascript -e 'display notification "Build erfolgreich! Xcode ist bereit." with title "HarpoOutreach" sound name "Glass"' 2>/dev/null
else
  echo -e "${RED}${BOLD}  Build fehlgeschlagen (${BUILD_DURATION}s)${NC}"
  echo -e "${YELLOW}  Xcode ist geoeffnet - pruefe die Fehler dort.${NC}"
  echo -e "  Log: $BUILD_LOG"
  osascript -e 'display notification "Build fehlgeschlagen - siehe Xcode" with title "HarpoOutreach" sound name "Basso"' 2>/dev/null
fi
echo -e "${BOLD}==========================================${NC}"
