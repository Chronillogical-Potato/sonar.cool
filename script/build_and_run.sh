#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# ── terminal styling ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m';  RESET=$'\033[0m';  DIM=$'\033[2m'
  GREEN=$'\033[32m'; RED=$'\033[31m'; CYAN=$'\033[36m'
else
  BOLD=''; RESET=''; DIM=''; GREEN=''; RED=''; CYAN=''
fi

# ── progress tracker ──────────────────────────────────────────────────────────
SONAR_STAGE=''
_SPIN_PID=''
_SPIN_MSG=''
_STEP_N=0
_STEP_TOTAL=8
_STEP_DONE=1   # start "done" so an early ERR before the first step is a no-op

_spin_loop() {
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  while :; do
    printf "\r  ${DIM}[%d/%d]${RESET}  %-42s ${CYAN}%s${RESET} " \
      "$_STEP_N" "$_STEP_TOTAL" "$_SPIN_MSG" "${frames:$(( i % ${#frames} )):1}"
    sleep 0.08
    i=$(( i + 1 ))
  done
}

step() {
  _STEP_N=$(( _STEP_N + 1 ))
  _SPIN_MSG="$1"
  _STEP_DONE=0
  if [[ -t 1 ]]; then
    _spin_loop &
    _SPIN_PID=$!
  else
    printf "  [%d/%d]  %s" "$_STEP_N" "$_STEP_TOTAL" "$_SPIN_MSG"
  fi
}

ok() {
  _STEP_DONE=1
  if [[ -n "$_SPIN_PID" ]]; then
    kill "$_SPIN_PID" 2>/dev/null; wait "$_SPIN_PID" 2>/dev/null || :; _SPIN_PID=''
    printf "\r  ${DIM}[%d/%d]${RESET}  %-42s ${GREEN}✓${RESET}\n" "$_STEP_N" "$_STEP_TOTAL" "$_SPIN_MSG"
  else
    printf " ${GREEN}ok${RESET}\n"
  fi
}

fail() {
  [[ "$_STEP_DONE" == 1 ]] && return 0  # idempotent — don't double-print
  _STEP_DONE=1
  if [[ -n "$_SPIN_PID" ]]; then
    kill "$_SPIN_PID" 2>/dev/null; wait "$_SPIN_PID" 2>/dev/null || :; _SPIN_PID=''
    printf "\r  ${DIM}[%d/%d]${RESET}  %-42s ${RED}✗${RESET}\n" "$_STEP_N" "$_STEP_TOTAL" "$_SPIN_MSG"
  else
    printf " ${RED}FAILED${RESET}\n"
  fi
}

cleanup() {
  [[ -n "$_SPIN_PID" ]] && { kill "$_SPIN_PID" 2>/dev/null; wait "$_SPIN_PID" 2>/dev/null || :; }
  [[ -n "$SONAR_STAGE" ]] && rm -rf "$SONAR_STAGE" || true
}
trap cleanup EXIT
trap 'fail' ERR   # safety net: any unhandled failure marks the active step ✗

# ── banner ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  printf '\n'
  printf "  ${BOLD}${CYAN}╔═╗ ╔═╗ ╔╗╔ ╔═╗ ╦═╗${RESET}\n"
  printf "  ${BOLD}${CYAN}╚═╗ ║ ║ ║╚╗ ╠═╣ ╠╦╝${RESET}\n"
  printf "  ${BOLD}${CYAN}╚═╝ ╚═╝ ╝ ╚ ╩ ╩ ╩╚═${RESET}\n"
  printf '\n'
  printf "  ${DIM}gesture control for macOS${RESET}\n"
  printf '\n'
  printf "  ${DIM}────────────────────────────────${RESET}\n"
  printf '\n'
fi

# ── build ─────────────────────────────────────────────────────────────────────
SONAR_STAGE=$(mktemp -d /private/tmp/sonar-build.XXXXXX)
SONAR_APP="$SONAR_STAGE/Sonar Classic.app"

step "Setting up build environment"
mkdir -p "$SONAR_APP/Contents/MacOS" "$SONAR_APP/Contents/Resources"
ditto assets/zoom "$SONAR_APP/Contents/Resources/Zoom"
ditto assets/gallery "$SONAR_APP/Contents/Resources/Gallery"
cp assets/sonar.png "$SONAR_APP/Contents/Resources/SonarMark.png"
ok

step "Compiling icon renderer"
SONAR_ICONSET="$SONAR_STAGE/Sonar.iconset"
mkdir -p "$SONAR_ICONSET"
swiftc -target arm64-apple-macosx14.0 -framework AppKit script/render_icon.swift \
  -o "$SONAR_STAGE/render_icon_bin" >"$SONAR_STAGE/icon_build.log" 2>&1 || {
    fail; cat "$SONAR_STAGE/icon_build.log" >&2; exit 1
  }
"$SONAR_STAGE/render_icon_bin" assets/sonar.png "$SONAR_STAGE/DockIcon.png"
ok

step "Generating app icon"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SONAR_STAGE/DockIcon.png" \
    --out "$SONAR_ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SONAR_STAGE/DockIcon.png" \
    --out "$SONAR_ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SONAR_ICONSET" -o "$SONAR_APP/Contents/Resources/Sonar.icns"
ok

step "Bundling resources"
# Bundle the reading paper; allow an explicit local replacement.
SONAR_LOCAL_PAPER="${SONAR_PAPER_PATH:-assets/paper/SoundWave.pdf}"
if [[ -f "$SONAR_LOCAL_PAPER" ]]; then
  cp "$SONAR_LOCAL_PAPER" "$SONAR_APP/Contents/Resources/SoundWave.pdf"
elif [[ -n "${SONAR_PAPER_PATH:-}" ]]; then
  fail
  printf "  ${RED}PDF not found: %s${RESET}\n" "$SONAR_PAPER_PATH" >&2
  exit 1
fi
# Version, bundle ID and permission text live in script/Info.plist, shared with Package.swift.
cp script/Info.plist "$SONAR_APP/Contents/Info.plist"
ok

step "Compiling Sonar"
swiftc -target arm64-apple-macosx14.0 -O \
  work/SonarCore/Reading.swift work/SonarCore/DistanceEngine.swift \
  work/SonarCore/WaveEngine.swift work/SonarCore/PositionEngine.swift \
  work/Sonar/main.swift work/Sonar/BundleExtension.swift \
  work/Sonar/HardwareAudio.swift work/Sonar/SpeakerVolume.swift \
  work/Sonar/Diagnostics.swift work/Sonar/DeviceSetup.swift \
  work/Sonar/SystemScroll.swift work/Sonar/DemoModes.swift \
  work/Sonar/WaveCalibration.swift work/Sonar/ContentView.swift \
  work/Sonar/ControlModeView.swift work/Sonar/SignalView.swift \
  work/Sonar/AudioSignalView.swift work/Sonar/Distance.swift \
  work/Sonar/Position.swift work/Sonar/EchoFlowView.swift work/Sonar/Zoom.swift \
  -o "$SONAR_APP/Contents/MacOS/Sonar" \
  -framework AppKit -framework SwiftUI -framework AVFoundation \
  -framework Accelerate -framework CoreAudio -framework PDFKit \
  -framework Carbon -framework ApplicationServices \
  >"$SONAR_STAGE/swiftc.log" 2>&1 || {
    fail; cat "$SONAR_STAGE/swiftc.log" >&2; exit 1
  }
ok

step "Signing app"
# A stable certificate preserves permissions across rebuilds. Local builds can
# use ad-hoc signing without owning a paid Apple developer certificate.
SONAR_SIGNING_IDENTITY="${SONAR_SIGNING_IDENTITY:--}"
codesign --force --entitlements script/Sonar.entitlements \
  --sign "$SONAR_SIGNING_IDENTITY" --identifier com.emanuel.sonarlab \
  "$SONAR_APP" >"$SONAR_STAGE/codesign.log" 2>&1 || {
    fail; cat "$SONAR_STAGE/codesign.log" >&2; exit 1
  }
codesign --verify --strict "$SONAR_APP" >>"$SONAR_STAGE/codesign.log" 2>&1 || {
  fail; cat "$SONAR_STAGE/codesign.log" >&2; exit 1
}
ok

step "Running self-tests"
# Verify the failure path exits normally, then test the staged build. No failed
# test build replaces or stops the user's current installed app.
SONAR_TEST_STATUS=0
"$SONAR_APP/Contents/MacOS/Sonar" --self-test-failure-probe \
  >"$SONAR_STAGE/failure-probe.log" 2>&1 || SONAR_TEST_STATUS=$?
if [[ "$SONAR_TEST_STATUS" != 1 ]] || \
   ! /usr/bin/grep -q 'Intentional clean-exit probe' "$SONAR_STAGE/failure-probe.log"; then
  fail
  cat "$SONAR_STAGE/failure-probe.log" >&2
  printf "  ${RED}Test failure handling did not exit cleanly; keeping the installed app.${RESET}\n" >&2
  exit 1
fi
"$SONAR_APP/Contents/MacOS/Sonar" --self-test >"$SONAR_STAGE/self-test.log" 2>&1 || {
  fail; cat "$SONAR_STAGE/self-test.log" >&2; exit 1
}
ok

step "Packaging build"
mkdir -p outputs
# Replace generated output so an optional PDF from an older build cannot linger.
rm -rf outputs/Sonar.app "outputs/Sonar Classic.app"
ditto --noextattr --norsrc "$SONAR_APP" "outputs/Sonar Classic.app"
ditto -c -k --keepParent --noextattr "outputs/Sonar Classic.app" "outputs/Sonar Classic.zip"
ok

if [[ -t 1 ]]; then
  printf '\n'
  printf "  ${DIM}────────────────────────────────${RESET}\n"
  printf '\n'
fi

if [[ "${1:-}" == "--build-only" ]]; then
  printf "  ${GREEN}${BOLD}✓  Built and tested:${RESET}  outputs/Sonar Classic.app\n\n"
  exit 0
fi

# ── install ───────────────────────────────────────────────────────────────────
_STEP_N=0
_STEP_TOTAL=3
_STEP_DONE=1
if [[ -t 1 ]]; then printf "  ${BOLD}Installing${RESET}\n\n"; fi

SONAR_INSTALLED_APP="${SONAR_INSTALL_PATH:-$HOME/Applications/Sonar Classic.app}"

# Do not silently replace a certificate-signed installation with an ad-hoc build.
if [[ -d "$SONAR_INSTALLED_APP" && "$SONAR_SIGNING_IDENTITY" == "-" ]] && \
   codesign -dv "$SONAR_INSTALLED_APP" 2>&1 | /usr/bin/grep -q '^Authority='; then
  printf "  ${RED}✗  Set SONAR_SIGNING_IDENTITY to the existing certificate before replacing this installation.${RESET}\n\n" >&2
  exit 1
fi

step "Stopping running instance"
# Stop the legacy executable during upgrades as well.
pkill -x SonarLab >/dev/null 2>&1 || true
pkill -x Sonar >/dev/null 2>&1 || true
ok

SONAR_DISPLAY_PATH="${SONAR_INSTALLED_APP/#$HOME/~}"
step "Installing to $SONAR_DISPLAY_PATH"
mkdir -p "$(dirname "$SONAR_INSTALLED_APP")"
# Save the existing bundle, then install into an empty destination. Merging
# bundles leaves removed resources behind and invalidates the new signature.
SONAR_BACKUP="$(mktemp -d "$(dirname "$SONAR_INSTALLED_APP")/.sonar-backup.XXXXXX")"
if [[ -e "$SONAR_INSTALLED_APP" ]]; then mv "$SONAR_INSTALLED_APP" "$SONAR_BACKUP/Previous.app"; fi
if ! (ditto --noextattr --norsrc "$SONAR_APP" "$SONAR_INSTALLED_APP" &&
      xattr -cr "$SONAR_INSTALLED_APP" &&
      codesign --verify --strict "$SONAR_INSTALLED_APP" >/dev/null 2>&1); then
  fail
  rm -rf "$SONAR_INSTALLED_APP"
  if [[ -e "$SONAR_BACKUP/Previous.app" ]]; then mv "$SONAR_BACKUP/Previous.app" "$SONAR_INSTALLED_APP"; fi
  rmdir "$SONAR_BACKUP"
  exit 1
fi
rm -rf "$SONAR_BACKUP"
ok

step "Launching Sonar"
if [[ "${1:-}" == "--verify-scroll" || "${1:-}" == "--verify-audio" ]]; then
  open -n "$SONAR_INSTALLED_APP" --args "$1"
else
  open -n "$SONAR_INSTALLED_APP"
fi
ok

if [[ -t 1 ]]; then
  printf '\n'
  printf "  ${DIM}────────────────────────────────${RESET}\n"
  printf "  ${GREEN}${BOLD}✓  Sonar is running.${RESET}\n\n"
fi

if [[ "${1:-}" == "--verify" ]]; then
  sleep 1
  pgrep -x Sonar
fi
