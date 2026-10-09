# MLB — Omarchy bar plugin

![s3pp3ku.mlb](preview.png)

A tiny baseball pill for the [Omarchy](https://omarchy.org)
bar that turns into seven tabs of live baseball: a pitch-by-pitch Live view, in-widget radio, the playoff bracket, the full
game day schedule with dates and probables, season-long stats for every team,
the latest Statcast numbers for the game you are watching, and whoever's
close to first pitch from the books. Data from the MLB Stats API, Baseball
Savant (percentiles, expected stats, bat tracking), ESPN's public scoreboard, and the two major prediction markets.

No API key, no account, nothing to set up before it works.

## The seven tabs

- **Live** — a Gameday-style view of the game in focus: scoreboard with
  count, outs and runners; a catcher's-eye strike zone plotting every pitch
  of the at-bat (colored by pitch type, newest one pulsing); the pitch
  sequence with type, speed, result and exit velocity on contact; and
  batter/pitcher cards with today's line, season line, earlier trips to the
  plate, the pitcher's mix in this game, and Baseball Savant percentile
  sliders. Before first pitch it shows the probable starters' percentiles.
  Where the game is on (national and local TV, both teams' radio, Spanish
  feeds) sits under the scoreboard; the Games tab and the bar tooltip show
  the TV channel too. Chips across the top switch between today's games
  (← / → also work); click the pinned chip again to go back to automatic.

- **Playoffs** — playoff bracket with series scores, colors, current state
  (TBD / live / final). Once the World Series is decided the tab opens on a
  **Champions** recap: the title card (Series result, postseason record, WS
  MVP), the club's road through each round, and the Series game by game,
  with the finished bracket one click away. Until the next year's field is
  set, the tab keeps showing the defending champions instead of going blank.
- **Schedule** — every game today and through the upcoming stretch, newest games
  with a focused detail card (live count, bases, last play, R-H-E for finals,
  probables for previews), dates and venues on a second line, and an accent
  stripe for games your favorite team plays.
- **Stats** — matchup card: away/home full-season lines side by side, a
  30-team season table sorted by record, and league leaders for hitting &
  pitching. During a game, the top of the tab switches to current hardest
  hits, longest balls, fastest pitches, and exit-velo/pitch-speed boards from
  the same tracking feed as Baseball Savant. Savant's own Gamefeed adds
  barrels, expected batting average on every ball (toughest outs, cheapest
  hits), homers-in-N-of-30-parks, bat speed, and each starter's arsenal
  with spin; the starters' percentile sliders; and season Savant
  leaderboards (xwOBA, barrel %, max exit velo, bat speed, sprint speed,
  Outs Above Average, luckiest/unluckiest by wOBA − xwOBA).
- **Radio** — every game today with each club's radio call, the national
  network and Spanish feeds. Press a station to listen right in the widget:
  the stream comes from [Radio Browser](https://www.radio-browser.info)
  (free, open, no key) and plays through `mpv` in the background, so it keeps
  going with the popup closed — a now-playing strip has volume and stop, and
  the bar pill shows a speaker. Stations Radio Browser doesn't list open on
  TuneIn instead (the ↗ on every chip does that too). The Live tab has a
  one-press **Listen** for your team's (or the home club's) call. Flagships
  are free over the air in their home market; online, some stations swap out
  game audio outside it.
- **Season** — the current season calendar and standings, season-at-a-glance today.
- **Odds** — for the focused game: moneyline, implied probability, run line
  and total with each side's juice. Beneath it, every non-final game on
  today's slate with its current line when ESPN has one. The World Series
  winner market from Polymarket and Kalshi closes off the tab.

Tabs run Live · Schedule · Stats · Odds · Radio · Season · Playoffs.

## Colors

Three schemes, switched with the chip in the popup header (three swatches
and a name — click to cycle) or the **Colors** widget setting:

- **Omarchy** (default) — follows your theme. Highlights use the theme
  accent; live, ball / strike / in play, pitch-type dots and the Savant
  percentile sliders use the theme's own palette (`colors.toml`). Switching
  themes recolors the widget, light themes included.
- **MLB** — the league's red, white and navy: red highlights, navy-washed
  cards, sliders running navy → white → red.
- **Classic** — the theme accent with the familiar MLB Gameday and Baseball
  Savant status colors.

The header chip saves your pick to `~/.local/state/omarchy-mlb-prefs.json`,
so it sticks wherever the widget lives (main bar or an extra bar). Team
stripes are the clubs' real colors and have their own on/off setting.

## The bar pill

The pill shows what's most useful right now — live games (score only), the
next first pitch for your schedule, or the offseason/spring-training
countdown. Favorite-team games always route through it first when they exist.

## Installation

```bash
omarchy plugin add https://github.com/s3pp3ku/omarchy-mlb
```

Remove it with:

```bash
omarchy plugin remove s3pp3ku.mlb
```

Settings live on the widget in your bar (right-click): favorite team, default
tab, colors (follow theme or classic), whether team colors are painted, 12h/24h times, popup
position, notify-on-start, and the monthly odds budget.

## External dependencies

At runtime the plugin uses Omarchy's Quickshell shell, `curl` for API requests,
Python 3 for the rate-limited odds cache helper, and `mpv` for in-widget
radio (optional — without it, use the ↗ TuneIn links). Screenshot regeneration
also uses `grim`, ImageMagick (`magick`), and Chromium; those are only needed
for development, not for using the widget.

## Data & network

Every request asks for gzip (`curl --compressed`): the live feed is ~160 KB
on the wire instead of ~960 KB, Savant's Gamefeed ~175 KB instead of 3 MB.
Baseball Savant has no official API — the widget reads the CSV/JSON exports
behind its pages, and each Savant section hides itself if a format changes.

Everything is fetched at a definable rhythm, cached on disk, and only polled
while a schedule refresh is due or the popup is open:

| Source | Used for | Cadence |
|---|---|---|
| `statsapi.mlb.com` | Schedule, live feed, standings/season/stat tables/leaders | open + 45s (live), 10 min otherwise |
| `statsapi.mlb.com` | Live feed for the Live tab | every 10 s, only while the Live tab is open on a live game |
| `baseballsavant.mlb.com` | Gamefeed (per-game) | once a minute, only while the Stats tab is open on a live game |
| `baseballsavant.mlb.com` | Percentile rankings, leaderboards (CSV) | twice a day, when Live/Stats is opened |
| `statsapi.mlb.com` | Postseason bracket, World Series MVP | 1 min (live), 5 min during the postseason, 6 h once settled |
| `site.api.espn.com` | Game odds | date-gated cache, refreshed on open/refresh, a month's worth budgeted |
| Polymarket + Kalshi gamma APIs | WS-winner price | same budget gate as ESPN |

Odds pulls are: (1) throttled to `oddsBudget` pulls per source per
calendar month (default 31 = roughly one a day), (2) TTL-cached for most of
that window, and (3) stale-served when capped. The budget footer in the Odds
tab shows the current cadence so you can tune it.

## Development

```bash
node tools/test-mlb.js      # unit tests for all parsers and selectors
tools/capture-preview.sh    # refresh assets/tabs/*.png (needs Hyprland running)
tools/build-preview.sh      # regenerate promo.html → preview.png
```

The QML modules hot-reload on save; a `node`-side test suite covers parsers,
odds formatting, selector ordering, bracket shape, and the ESPN-abbreviation
  boundary cases.

## License

MIT — see [LICENSE](LICENSE).

## A note from the author

I'm new to Omarchy plugin development and used AI assistance to help build
this widget. The idea was inspired by the community's Formula 1 bar plugin.
The preview capture/build helpers are adapted from Robert (leafbox)'s
MIT-licensed [Formula 1 plugin](https://github.com/Snackwrap/omarchy-f1).
If you spot a bug, have a suggestion, or can help improve the QML or stats,
please open an issue or pull request — all help is welcome.
