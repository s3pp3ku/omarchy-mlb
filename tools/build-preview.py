#!/usr/bin/env python3
"""Generate tools/promo.html — the marketplace card — with the tab captures inlined.

The screenshots are embedded as data URIs so the page renders identically from
any working directory and needs nothing fetched at build time.

The composition approach is adapted from com.leafbox.f1 (MIT), by Robert
(leafbox): https://github.com/Snackwrap/omarchy-f1
"""
import base64
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABS = ROOT / "assets" / "tabs"

# The captures are one full popup photo each; rescale them to a common width
# and cut the same vertical band from the top, so the mastheads and tab rows
# align across the grid instead of the tall tabs towering over the short ones.
BAND = 700

PANELS = [
    ("bracket.png",   "BRACKET",   "playoff bracket + series cards"),
    ("games.png",     "GAMES",     "full slate, scores, line 2 info"),
    ("statcast.png",  "STATCAST",  "live feed + season matchup"),
    ("odds.png",      "ODDS",      "book lines, implied, slate"),
]


def uri(name):
    src = TABS / name
    out = subprocess.run(
        ["magick", str(src), "-resize", "880x", "-crop", f"880x{BAND}+0+0",
         "+repage", "png:-"],
        check=True, capture_output=True).stdout
    return "data:image/png;base64," + base64.b64encode(out).decode()


cards = "\n".join(
    f'''      <figure class="card">
        <div class="shot"><img src="{uri(f)}" alt="{label} tab"></div>
        <figcaption><b>{label}</b> {note}</figcaption>
      </figure>''' for f, label, note in PANELS)

HTML = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ width:1600px; height:1000px; background:#1c1b19; overflow:hidden;
         font-family:'JetBrainsMono Nerd Font','JetBrainsMono NF',monospace; position:relative; }}
  .watermark {{ position:absolute; left:-90px; bottom:-140px; opacity:0.045; }}
  .wrap {{ position:relative; display:flex; height:100%; padding:66px 60px; gap:52px; align-items:center; }}
  .left {{ width:566px; flex:none; }}
  .brand {{ display:flex; align-items:center; gap:13px; margin-bottom:30px; }}
  .brand .word {{ color:#706e6b; font-size:15px; font-weight:700; letter-spacing:6px; }}
  h1 {{ color:#fbf1c7; font-size:43px; line-height:1.16; font-weight:800; letter-spacing:-0.5px; }}
  h1 .acc {{ color:#d4bd99; }}
  .sub {{ color:#a89984; font-size:17px; line-height:1.55; margin-top:19px; }}
  .feat {{ list-style:none; margin-top:32px; }}
  .feat li {{ color:#a89984; font-size:15.5px; line-height:1.5; margin-bottom:13px;
              padding-left:22px; position:relative; }}
  .feat li::before {{ content:"\\25B8"; color:#d4bd99; font-weight:700; position:absolute; left:0; }}
  .feat b {{ color:#fbf1c7; }}
  .install {{ margin-top:34px; display:inline-block; background:#26241f; border:1px solid #3b3730;
             border-radius:9px; padding:13px 19px; color:#a89984; font-size:14px; white-space:nowrap; }}
  .install .p {{ color:#706e6b; }} .install .c {{ color:#c2a571; }}
  .grid {{ flex:1; display:grid; grid-template-columns:1fr 1fr; gap:26px 24px; }}
  /* The captures are cut to a common band, so fade the cut edge rather than
     letting each card end on a half-drawn row. */
  .card .shot {{ border-radius:9px; border:1px solid #3b3730; overflow:hidden;
                box-shadow:0 18px 44px rgba(0,0,0,.5);
                -webkit-mask-image:linear-gradient(to bottom,#000 82%,transparent 100%);
                mask-image:linear-gradient(to bottom,#000 82%,transparent 100%); }}
  .card .shot img {{ display:block; width:100%; }}
  .card figcaption {{ margin-top:11px; color:#706e6b; font-size:13px; letter-spacing:.3px; }}
  .card figcaption b {{ color:#d4bd99; letter-spacing:2.2px; margin-right:9px; }}
</style></head><body>
  <svg class="watermark" width="620" height="760" viewBox="0 0 700 860">
    <circle cx="350" cy="430" r="300" fill="none" stroke="#d4bd99" stroke-width="14"/>
    <path d="M50,430 Q200,160 350,430 Q500,700 650,430" fill="none" stroke="#d4bd99" stroke-width="7"/>
  </svg>
  <div class="wrap">
    <div class="left">
      <div class="brand"><span class="word">MLB &middot; FOR OMARCHY</span></div>
      <h1>The full season,<br><span class="acc">not just the playoffs.</span></h1>
      <div class="sub">Five tabs of live baseball in the Omarchy bar. No API key, no account, nothing to set up.</div>
      <ul class="feat">
        <li><b>Bracket + Games</b> &mdash; every game live, with dates, venues, probables</li>
        <li><b>Season-long stats</b> &mdash; matchup card, team table, league leaders</li>
        <li><b>Book lines</b> &mdash; moneyline, run line, total, juice, full daily slate</li>
      </ul>
      <div class="install"><span class="p">$</span> omarchy plugin add <span class="c">github.com/s3pp3ku/omarchy-mlb</span></div>
    </div>
    <div class="grid">
{cards}
    </div>
  </div>
</body></html>"""

(ROOT / "tools" / "promo.html").write_text(HTML, encoding="utf-8")
print("tools/promo.html written")
