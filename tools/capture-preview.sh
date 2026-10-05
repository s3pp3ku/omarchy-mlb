#!/usr/bin/env bash
# Capture the popup, one PNG per tab, for the marketplace listing assets.
# The capture/diff workflow is adapted from com.leafbox.f1 (MIT), by Robert
# (leafbox): https://github.com/Snackwrap/omarchy-f1
#
# Two things make this awkward to do by hand, and this script works around both:
#
#   * Clicking a terminal closes the popup, so it has to be driven over IPC
#     (`omarchy-shell shell summon`) rather than opened with the mouse.
#   * The popup is drawn inside a fullscreen layer surface, so the compositor
#     cannot tell us its rectangle. We shoot the screen with the popup open and
#     again with it closed, and diff the two — the region that changed *is* the
#     popup, which crops it exactly with no drag-select.
#
# Tab selection uses `defaultTab` + a shell restart, which the MLB panel
# honours.
#
# Usage:  tools/capture-preview.sh [tab ...]      (default: all of them)
set -euo pipefail

ID="s3pp3ku.mlb"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/assets/tabs"
TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
  if [ -n "${ORIGINAL_WS:-}" ]; then
    hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIGINAL_WS\" })" >/dev/null 2>&1 || true
  fi
  if [ -n "${restore_tab:-}" ]; then
    omarchy bar set "$ID" defaultTab "$restore_tab" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

TABS=("$@")
[ ${#TABS[@]} -eq 0 ] && TABS=(bracket games statcast season odds)

mkdir -p "$OUTDIR"

# Never save shots with another app visible behind the translucent popup.
# Find an empty workspace and restore the user's active one after capturing.
ORIGINAL_WS=$(hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
CAPTURE_WS=$(hyprctl workspaces -j | python3 -c '
import json,sys
workspaces=json.load(sys.stdin)
empty=[w["id"] for w in workspaces if w.get("windows", 0) == 0]
print(empty[0] if empty else "")
')
if [ -z "$CAPTURE_WS" ]; then
  echo "!! No empty workspace found; refusing to capture other app contents." >&2
  exit 1
fi
hyprctl dispatch "hl.dsp.focus({ workspace = \"$CAPTURE_WS\" })" >/dev/null
sleep 1

# Park the pointer in a corner once, up front. Whichever row it rests on picks
# up its hover fill and reads like a selection in the screenshot. It has to be
# done once rather than per tab: moving it switches focus under
# focus-follows-mouse, and that window's redraw is exactly the kind of change
# the diff below would mistake for the popup.
hyprctl dispatch 'hl.dsp.cursor.move({x=4,y=796})' >/dev/null 2>&1 \
  || hyprctl dispatch movecursor 4 796 >/dev/null 2>&1 || true
sleep 1.5

# Read the current tab setting, restored after the run. If an earlier capture
# crashed and left the file clobbered, this just round-trips the stale value —
# not ideal, but no worse than before; humans can always `omarchy bar set` it
# back.
restore_tab=$(python3 - "$ID" <<'PYEOF'
import json, os, sys
cfg = json.load(open(os.path.expanduser("~/.config/omarchy/shell.json")))
for slot in cfg.get("bar", {}).get("layout", {}).values():
    for w in slot:
        if w.get("id") == sys.argv[1] and "defaultTab" in w:
            print(w["defaultTab"])
PYEOF
)

for tab in "${TABS[@]}"; do
  omarchy bar set "$ID" defaultTab "$tab"
  # Restart before each tab so the panel re-opens on the new view. The restart
  # can race its own predecessor out of the socket and the binary then exits
  # with "already running", so wait for a shell that actually pings.
  omarchy restart shell || true
  ready=""
  for _ in $(seq 1 25); do
    if omarchy-shell shell ping >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
  done
  [ -n "$ready" ] || { echo "!! shell never came up" >&2; exit 1; }
  sleep 2

  # Closed and open shots go back to back with nothing printed between them, so
  # the popup is the only thing that differs and the diff crops it exactly. If
  # something else on screen redraws anyway the box comes back implausibly wide,
  # so take the shot again rather than shipping a screenshot of the desktop.
  box=""
  for attempt in 1 2 3; do
    omarchy-shell shell hide "$ID" 2>/dev/null || true
    sleep 0.7
    grim "$TMP/closed.png"
    omarchy-shell shell summon "$ID"
    # Don't let a failed summon fall through to a screenshot of the desktop.
    visible=""
    for _ in $(seq 1 20); do
      if hyprctl layers 2>/dev/null | grep -q omarchy-keyboard-panel; then
        visible=1
        break
      fi
      sleep 0.15
    done
    if [ -z "$visible" ]; then
      echo "   $tab: popup did not open, retrying" >&2
      continue
    fi
    sleep 4.0                    # let the fetch land and the panel settle
    grim "$TMP/open.png"
    omarchy-shell shell hide "$ID" 2>/dev/null || true

    box=$(python3 "$ROOT/tools/diffbox.py" "$TMP/open.png" "$TMP/closed.png") || box=""
    [ -n "$box" ] && break
    echo "   $tab: attempt $attempt caught the desktop, retrying" >&2
  done
  if [ -z "$box" ]; then
    echo "!! $tab: could not isolate the popup, skipping" >&2
    continue
  fi
  magick "$TMP/open.png" -crop "$box" +repage "$OUTDIR/$tab.png"
  echo "   $tab -> assets/tabs/$tab.png ($box)"
done

omarchy bar set "$ID" defaultTab "${restore_tab:-bracket}"
omarchy restart shell || true
for _ in $(seq 1 25); do
  omarchy-shell shell ping >/dev/null 2>&1 && break
  sleep 1
done
hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIGINAL_WS\" })" >/dev/null 2>&1 || true
echo "Done. Now run tools/build-preview.sh to compose preview.png."
