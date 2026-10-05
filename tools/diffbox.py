#!/usr/bin/env python3
"""Print the crop geometry of the region where two screenshots differ.

The popup lives inside a fullscreen layer surface, so the compositor cannot
tell us where it is. Shooting the screen with it open and closed and diffing
the two locates it exactly. Same algorithm as the f1 plugin's numpy
diff-box, but stdlib-only: ImageMagick thresholds the difference to a P4
bitmap and this walks the bits.

The bar strip along the top is ignored: the widget's own pill changes when
the popup opens, and the clock ticks between the shots. Opening the popup
also dims the whole desktop, so "any pixel that changed" is the entire
screen — the popup is where a large share of the pixels *in a column*
changed, which the density profile isolates.

Usage: diffbox.py <open.png> <closed.png>   ->  WxH+X+Y  (exit 1 if none)
"""
import subprocess
import sys

BAR_STRIP = 50      # device pixels of bar to ignore along the top
THRESHOLD = 24      # percent (24% ≈ the numpy version's 60/255)
DENSITY = 0.35      # share of a column's peak change density to count as popup
MIN_SIDE = 120      # anything smaller than this is noise, not a popup
MAX_SHARE = 0.55    # a popup never covers this much of the screen


def changed_bitmap(path_a, path_b):
    """(w, h, packed bits) with 1-bits where the two images differ."""
    out = subprocess.run(
        ["magick", path_a, path_b, "-compose", "difference", "-composite",
         "-colorspace", "Gray", "-threshold", f"{THRESHOLD}%", "pbm:-"],
        check=True, capture_output=True).stdout
    if not out.startswith(b"P4"):
        sys.exit("expected a P4 bitmap from ImageMagick")
    fields, pos = [], 2
    while len(fields) < 2:
        while out[pos:pos + 1].isspace():
            pos += 1
        if out[pos:pos + 1] == b"#":
            while out[pos:pos + 1] != b"\n":
                pos += 1
            continue
        start = pos
        while not out[pos:pos + 1].isspace():
            pos += 1
        fields.append(int(out[start:pos]))
    w, h = fields
    return w, h, out[pos + 1:]


def _row_bits(bits, base, stride):
    """Yield the global column index of every set bit in one packed row."""
    for j in range(stride):
        v = bits[base + j] if base + j < len(bits) else 0
        if not v:
            continue
        # P4 packs pixels left to right into the high bits first: pixel k of
        # the byte is 0x80 >> k.
        for k in range(8):
            if v & (0x80 >> k):
                yield j * 8 + k


def col_profile(w, h, bits):
    """Per-column counts of changed pixels (bar strip zeroed)."""
    stride = (w + 7) // 8
    cols = [0] * w
    for r in range(BAR_STRIP, h):
        for c in _row_bits(bits, r * stride, stride):
            cols[c] += 1
    return cols


def window_rows(h, bits, w, x0, x1):
    """Per-row counts of changed pixels restricted to columns x0..x1."""
    stride = (w + 7) // 8
    rows = [0] * h
    for r in range(BAR_STRIP, h):
        rows[r] = sum(1 for c in _row_bits(bits, r * stride, stride)
                      if x0 <= c <= x1)
    return rows


def longest_run(cols):
    """Longest contiguous run of dense columns — the popup block."""
    if not cols:
        return None
    peak = max(cols)
    if peak <= 0:
        return None
    floor = peak * DENSITY
    best = run = None
    for i, count in enumerate(cols):
        if count > floor:
            run = (run[0], i) if run else (i, i)
            if best is None or (run[1] - run[0]) > (best[1] - best[0]):
                best = run
        else:
            run = None
    return best


def extent(rows, floor):
    """First and last row above the floor (vertical reach, not runs)."""
    hits = [i for i, v in enumerate(rows) if v > floor]
    return (hits[0], hits[-1]) if hits else None


def main():
    w, h, bits = changed_bitmap(sys.argv[1], sys.argv[2])
    cols = col_profile(w, h, bits)
    if max(cols) <= 0:
        sys.exit(1)

    x0, x1 = longest_run(cols) or (None, None)
    if x0 is None:
        sys.exit(1)
    win = x1 - x0 + 1
    # Vertical reach uses a floor on the column-window share: a masthead row
    # is sparse and a table row dense, so runs would clip the header off.
    rows = window_rows(h, bits, w, x0, x1)
    y0, y1 = extent([v / win for v in rows], 0.02) or (None, None)
    if y0 is None:
        sys.exit(1)

    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    if bw < MIN_SIDE or bh < MIN_SIDE:
        sys.exit(1)
    if bw > w * MAX_SHARE and bh > h * MAX_SHARE:
        sys.exit(1)
    print(f"{bw}x{bh}+{x0}+{y0}")


if __name__ == "__main__":
    main()
