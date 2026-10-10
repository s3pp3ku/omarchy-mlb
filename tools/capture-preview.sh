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
# honours. This widget normally lives in an extra bar
# (~/.config/omarchy/extra-bars.json), but the shell's summon/hide IPC only
# reaches widgets registered in the *main* bar's shell.json layout (it looks
# the id up in Bar.qml's own module slots, which extra bars never populate).
# So for the run, this script temporarily appends the widget's id to
# shell.json's bar.layout.right, drives it from there, and removes it again
# once every tab is captured — the extra-bars.json copy is never touched and
# keeps running the whole time.
#
# Usage:  tools/capture-preview.sh [tab ...]      (default: all of them)
set -euo pipefail

ID="s3pp3ku.mlb"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/assets/tabs"
SHELL_CFG="$HOME/.config/omarchy/shell.json"
TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
  if [ -n "${ORIGINAL_WS:-}" ]; then
    hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIGINAL_WS\" })" >/dev/null 2>&1 || true
  fi
  if [ -n "${added_main:-}" ]; then
    remove_main_entry >/dev/null 2>&1 || true
    omarchy restart shell >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

TABS=("$@")
[ ${#TABS[@]} -eq 0 ] && TABS=(live games statcast odds radio season bracket)

# Append {"id": ID} to the main bar's right section, if it isn't there already.
add_main_entry() {
  python3 - "$ID" "$SHELL_CFG" <<'PYEOF'
import json, sys
ident, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
layout = data.setdefault("bar", {}).setdefault("layout", {})
for section in ("left", "center", "right"):
    for e in layout.get(section, []):
        if (e if isinstance(e, str) else e.get("id")) == ident:
            sys.exit()
layout.setdefault("right", []).append({"id": ident})
json.dump(data, open(path, "w"), indent=2)
PYEOF
}

# Set defaultTab on the main bar's temporary entry for this widget.
set_tab() {
  python3 - "$ID" "$SHELL_CFG" "$1" <<'PYEOF'
import json, sys
ident, path, tab = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
layout = data.get("bar", {}).get("layout", {})
for section in ("left", "center", "right"):
    lst = layout.get(section, [])
    for i, e in enumerate(lst):
        eid = e if isinstance(e, str) else e.get("id")
        if eid == ident:
            settings = {} if isinstance(e, str) else {k: v for k, v in e.items() if k != "id"}
            settings["defaultTab"] = tab
            lst[i] = {"id": ident, **settings}
json.dump(data, open(path, "w"), indent=2)
PYEOF
}

# Remove the temporary main-bar entry for this widget entirely.
remove_main_entry() {
  python3 - "$ID" "$SHELL_CFG" <<'PYEOF'
import json, sys
ident, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
layout = data.get("bar", {}).get("layout", {})
for section in ("left", "center", "right"):
    lst = layout.get(section, [])
    layout[section] = [e for e in lst if (e if isinstance(e, str) else e.get("id")) != ident]
json.dump(data, open(path, "w"), indent=2)
PYEOF
}

mkdir -p "$OUTDIR"

# Never save shots with another app visible behind the translucent popup.
# Find an empty workspace and restore the user's active one after capturing.
ORIGINAL_WS=$(hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
CAPTURE_WS=$(python3 -c '
import json, subprocess
workspaces = json.loads(subprocess.run(["hyprctl", "workspaces", "-j"], capture_output=True, text=True).stdout)
clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
# A workspace whose only window is the screensaver is as safe to shoot as a
# truly empty one — it shows nothing but black, by design.
by_ws = {}
for c in clients:
    by_ws.setdefault(c.get("workspace", {}).get("id"), []).append(c.get("class", ""))
def safe(wid):
    cls = by_ws.get(wid, [])
    return len(cls) == 0 or all(c == "org.omarchy.screensaver" for c in cls)
empty = [w["id"] for w in workspaces if safe(w["id"])]
if empty:
    print(empty[0])
else:
    # Hyprland drops empty, non-active workspaces from this listing entirely,
    # so none showing up here does not mean none are free — ask for a fresh
    # id above anything currently in use; focusing it creates it with nothing
    # on it.
    used = [w["id"] for w in workspaces]
    print(max(used, default=0) + 1)
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

# Temporarily register the widget on the main bar so summon/hide can reach
# it. The extra-bars.json copy is untouched and keeps running throughout.
add_main_entry
added_main=1

for tab in "${TABS[@]}"; do
  set_tab "$tab"
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

remove_main_entry
added_main=""
omarchy restart shell || true
for _ in $(seq 1 25); do
  omarchy-shell shell ping >/dev/null 2>&1 && break
  sleep 1
done
hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIGINAL_WS\" })" >/dev/null 2>&1 || true
echo "Done. Now run tools/build-preview.sh to compose preview.png."
