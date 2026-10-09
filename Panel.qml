import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// The MLB widget core: fetches the schedule window, the postseason bracket,
// the season calendar, standings and a per-game Statcast feed from the MLB
// Stats API (statsapi.mlb.com — the source behind mlb.com and Baseball
// Savant), exposes `label`/`tooltip` for the bar pill, and hosts the four
// popup tabs. Tab bodies live in *Tab.qml; this file owns data + plumbing.
Panel {
  id: root
  moduleName: "s3pp3ku.mlb"
  ipcTarget: "s3pp3ku.mlb"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Live clock tick so countdowns advance without refetching.
  property double nowMs: Date.now()

  // Popup tab: live | bracket | games | statcast | odds | radio | season.
  property string view: "bracket"
  property bool viewPinned: false

  // ---- Data (reassigned wholesale so bindings re-evaluate) ---------------
  property var schedule: ({ games: [], live: [], upcoming: [], today: [] })
  property var series: []
  property var bracketLayout: ({ cards: [], lines: [], width: 0, height: 0 })
  // Season the bracket belongs to. Until this year's field is set, the tab
  // shows last year's postseason (and its champion) instead of a blank page.
  property int bracketSeason: 0
  property int bracketReqYear: 0
  property var champPath: null        // Mlb.championPath(series), once decided
  property var wsMvp: null            // {name, teamAbbr, pos} or null
  property int wsMvpSeason: 0
  property var seasons: ({})          // year -> parsed season calendar
  property var standings: null        // teamId -> standings row
  property int standingsYear: 0
  property bool standingsLoaded: false
  property var feed: null             // parsed focus-game feed (Statcast etc)
  property var live: null             // Mlb.parseLive of the same feed (Live tab)
  property int feedPk: -1
  property bool loadingSchedule: false
  property bool loadingBracket: false
  property bool loadingStandings: false
  property bool loadingFeed: false
  property string lastError: ""

  // gamePks already announced, so a poll can't re-notify.
  property var notifiedPks: ({})

  // ---- Odds (see odds.py: TTL + monthly-cap gated, fetched on demand) ----
  property var espnOdds: ({})      // "AWAY@HOME" -> {mlAway,mlHome,spread,total,...}
  property string espnDate: ""     // officialDate the odds map belongs to
  property var polyWs: []          // Polymarket WS-winner probabilities
  property var kalshiWs: []        // Kalshi WS-winner prices
  property bool loadingOdds: false

  // Full-season team stats + league leaders (Statcast tab season sections).
  property var teamStatsRows: []    // sorted rows, one entry per team
  property var teamStatsById: ({})  // team id -> same row object
  property var leaders: []          // [{key, label, rows:[{rank,value,name,team}]}]

  // ---- Baseball Savant (see mlb.js: CSV/JSON exports, no API key) ---------
  property var savantBoards: []     // [{label, hint, rows:[{name,team,value}]}]
  property double savantBoardsAt: 0
  property var pctBatters: ({})     // MLBAM id -> {name, pct:{col: 0-100}}
  property var pctPitchers: ({})
  property double pctAt: 0
  readonly property bool pctReady: Object.keys(pctPitchers).length > 0
  property var savantGame: null     // Mlb.parseSavantGame for savantGamePk
  property int savantGamePk: -1
  property int savantReqPk: -1
  // Season boards and percentiles move once a day at most.
  readonly property int savantMaxAgeMs: 43200000

  // Monthly budget per source, spread evenly: oddsTtl = month / budget, so
  // budget 31 ≈ one pull a day, budget 60 ≈ one every 12h. The helper stops
  // at the budget entirely — stale cache is served instead of the network.
  readonly property int oddsBudget: Math.max(1, parseInt(String(setting("oddsBudget", 31)), 10) || 31)
  readonly property int oddsTtl: Math.round(2678400 / oddsBudget)

  readonly property string base: "https://statsapi.mlb.com/api/v1/"
  readonly property string ua: "omarchy-mlb/0.1"
  // fa-baseball / fa-trophy from Nerd Fonts.
  readonly property string glyph: "\uED5C"
  readonly property string trophy: "\uF091"

  // ---- Settings ----------------------------------------------------------
  readonly property string timeFormat: String(setting("timeFormat", "12h"))
  readonly property string tPattern: timeFormat === "12h" ? "h:mm AP" : "HH:mm"
  readonly property string favTeam: String(setting("favoriteTeam", "")).toUpperCase().trim()

  function boolSetting(name, dflt) {
    var v = setting(name, dflt)
    return v === true || v === "true" || v === 1
  }
  readonly property bool teamColorsOn: boolSetting("teamColors", true)

  // ---- Color schemes -------------------------------------------------------
  //  theme   — everything follows the active Omarchy theme: highlights use
  //            its accent; live / ball / strike / in-play, pitch-type dots and
  //            percentile sliders use its named palette (colors.toml).
  //  mlb     — MLB's red, white and navy: red highlights, navy-washed cards,
  //            navy → white → red sliders.
  //  classic — the Omarchy accent with MLB Gameday / Baseball Savant status
  //            colors.
  // Picked with the chip in the popup header (saved to a small prefs file so
  // it works on any bar, including extra-bars) or the widget setting.
  readonly property var schemes: [
    { value: "theme", label: "Omarchy" },
    { value: "mlb", label: "MLB" },
    { value: "classic", label: "Classic" }
  ]
  property string schemePref: ""      // from prefs.json; wins over the setting
  readonly property string scheme: {
    var v = schemePref || String(setting("colorScheme", "theme"))
    return v === "mlb" || v === "classic" ? v : "theme"
  }
  readonly property bool classicColors: scheme === "classic"
  readonly property bool mlbColors: scheme === "mlb"
  readonly property string schemeLabel: scheme === "mlb" ? "MLB" : scheme === "classic" ? "Classic" : "Omarchy"

  // MLB logo colors, lifted a little so they read on dark popups.
  readonly property color mlbRed: "#E0173F"
  readonly property color mlbBlue: "#3D7BD9"
  readonly property color mlbNavy: "#1F4A8F"
  readonly property color mlbSilver: "#C8D1DC"

  readonly property color hi: mlbColors ? mlbRed : Color.accent
  // Card / border / hover wash: neutral (theme text color at alpha, which
  // works on light and dark themes) or MLB navy.
  function wash(a) {
    // A floor keeps even the faintest row fills visibly navy; borders and
    // hovers (higher a) go near-solid.
    if (mlbColors) return Qt.rgba(mlbNavy.r, mlbNavy.g, mlbNavy.b, Math.min(0.95, 0.14 + a * 6))
    return Util.alpha(Color.popups.text, a)
  }

  readonly property string prefsPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy-mlb-prefs.json"
  FileView {
    id: prefsFile
    path: root.prefsPath
    printErrors: false
    onLoaded: {
      try {
        var p = JSON.parse(text() || "{}")
        root.schemePref = typeof p.colorScheme === "string" ? p.colorScheme.slice(0, 16) : ""
      } catch (e) { root.schemePref = "" }
    }
  }
  function setScheme(v) {
    if (v !== "theme" && v !== "mlb" && v !== "classic") return
    schemePref = v
    prefsFile.setText(JSON.stringify({ colorScheme: v }) + "\n")
  }
  function cycleScheme() {
    for (var i = 0; i < schemes.length; i++)
      if (schemes[i].value === scheme) { setScheme(schemes[(i + 1) % schemes.length].value); return }
    setScheme("theme")
  }

  property var themePal: ({})
  FileView {
    id: themeFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.themePal = Mlb.parseThemeColors(text())
    onFileChanged: reload()
  }
  // A theme switch swaps the `current/theme` symlink and pushes new colors to
  // the shell's Color singleton; follow it rather than trusting the watcher.
  Connections {
    target: Color
    function onAccentChanged() { themeFile.reload() }
    function onBackgroundChanged() { themeFile.reload() }
  }
  function themeColor(key, classic) {
    return scheme === "theme" && themePal[key] ? themePal[key] : classic
  }
  readonly property color cLive: mlbColors ? mlbRed : themeColor("red", "#E5534B")
  readonly property color cStrike: mlbColors ? mlbRed : themeColor("red", "#E5534B")
  readonly property color cBall: mlbColors ? mlbSilver : themeColor("green", "#3FB950")
  readonly property color cPlay: mlbColors ? mlbBlue : themeColor("blue", "#4C8DFF")
  readonly property color cGood: mlbColors ? mlbBlue : themeColor("green", "#7EE787")
  function pitchColor(code) {
    return scheme === "theme" ? Mlb.themePitchColor(code, themePal) : Mlb.pitchColor(code)
  }
  function pctColor(p) {
    if (mlbColors) return Mlb.percentileColor(p, "#1F4FA3", "#D7DEE8", String(mlbRed))
    if (classicColors) return Mlb.percentileColor(p)
    return Mlb.percentileColor(p, themePal.blue, String(Color.muted), themePal.red)
  }
  readonly property bool notifyOn: boolSetting("notifyFavorite", false)

  function openFromHotkey() { open() }

  // ---- Remote data hygiene ----------------------------------------------
  // Two ceilings rather than one: curl refuses to download more than the cap,
  // and parseBounded rejects anything that got past it — a chunked response
  // has no Content-Length for curl to check.
  readonly property int maxFeedBytes: 5242880
  readonly property int maxPlainBytes: 1048576
  // A two-week regular-season window with broadcasts is ~1.6 MB of JSON
  // (~150 KB gzipped); without headroom a busy stretch would silently fail.
  readonly property int maxScheduleBytes: 4194304

  function fetchArgs(seconds, url, cap) {
    // -q must come first: without it curl reads ~/.curlrc, which could add a
    // proxy, an output file, or --insecure to an otherwise fixed request.
    // --compressed: the live feed is ~960 KB as JSON but ~160 KB gzipped.
    return ["curl", "-q", "-fsS", "--compressed", "-A", ua,
            "--proto", "=https",
            "--max-time", String(seconds),
            "--max-filesize", String(cap || maxPlainBytes),
            url]
  }

  function parseBounded(raw, cap) {
    var text = String(raw || "")
    if (text.length === 0 || text.length > (cap || maxPlainBytes)) return null
    return JSON.parse(text)
  }

  // Qt's Text defaults to AutoText, rendering strings as rich text when they
  // look like markup. Every remote value goes through safe(); the pill and
  // tooltip are rendered by the shell, so markup has to come out of the
  // finished string via safeBare.
  function safeBareLines(v, perLine, maxLines) {
    var lines = String(v === null || v === undefined ? "" : v).split("\n")
    var out = []
    for (var i = 0; i < lines.length && out.length < (maxLines || 12); i++)
      out.push(safeBare(lines[i], perLine || 80))
    return out.join("\n")
  }

  function safeBare(v, limit) {
    return safe(v, limit).replace(/[<>&]/g, " ")
  }

  function safe(v, limit) {
    var text = String(v === null || v === undefined ? "" : v)
    text = text.replace(/[\u0000-\u001F\u007F-\u009F]+/g, " ")
                   .replace(/[\u061C\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF]/g, "")
                   .replace(/^\s+|\s+$/g, "")
    var cap = limit || 72
    return text.length > cap ? text.slice(0, cap) + "\u2026" : text
  }

  function boundedList(v, cap) {
    if (!v || !v.length) return []
    return v.length > cap ? v.slice(0, cap) : v
  }

  // Links: https only, host allowlist checked before handing the string to
  // the browser — both hosts are the sources this data comes from.
  function openLink(u) {
    var raw = String(u || "")
    if (raw.indexOf("https://") !== 0) return
    var rest = raw.slice(8)
    var slash = rest.indexOf("/")
    var host = (slash < 0 ? rest : rest.slice(0, slash)).toLowerCase()
    if (host.indexOf("@") >= 0) return
    if (host.indexOf(":") >= 0) host = host.slice(0, host.indexOf(":"))
    if (host !== "www.mlb.com" && host !== "mlb.com" &&
        host !== "baseballsavant.mlb.com" && host !== "tunein.com") return
    if (raw.length > 400) return
    Qt.openUrlExternally(raw)
  }

  function gamedayUrl(pk) {
    var n = parseInt(pk, 10)
    if (!isFinite(n) || n <= 0) return ""
    return "https://www.mlb.com/gameday/" + n
  }
  // Free station streams: TuneIn's search for the station's call letters
  // (MLB's data names stations but carries no stream URLs).
  function radioUrl(query) {
    var q = String(query || "").replace(/[^A-Za-z0-9 .&'-]/g, "").trim().slice(0, 60)
    return q ? "https://tunein.com/search/?query=" + encodeURIComponent(q) : ""
  }
  // MLB's own player for the game (audio needs a free MLB account in-app).
  function mlbAudioUrl(pk) {
    var n = parseInt(pk, 10)
    if (!isFinite(n) || n <= 0) return ""
    return "https://www.mlb.com/tv/g" + n
  }
  // ---- In-widget radio ---------------------------------------------------
  // Station chips resolve through Radio Browser (radio-browser.info: free,
  // open, no key) to a direct stream, played by mpv in the background so it
  // keeps going with the popup closed. Lookups happen on press only and are
  // cached; a station Radio Browser doesn't list falls back to TuneIn.
  property var streamCache: ({})      // query -> Mlb.pickStream result | false
  property string radioResolving: ""  // query being looked up
  property var radioPending: null     // {st, label, gamePk} waiting on lookup
  property var radioNow: null         // {query, label, gamePk, stream}
  property var radioQueued: null      // next start while the old mpv exits
  property bool radioStopping: false
  property string radioNote: ""
  property int radioVolume: 80
  readonly property bool radioPlaying: playerProc.running
  readonly property string radioSock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") +
                                      "/omarchy-mlb-radio.sock"

  function radioLabel(st) {
    return (st.abbr ? st.abbr + " " : "") + st.name
  }

  // Press on a station chip: stop if it's the one playing, else look it up
  // (or use the cache) and play.
  function toggleStation(st, gamePk) {
    if (!st || !st.query) return
    if (radioNow && radioNow.query === st.query && (radioPlaying || radioQueued)) {
      stopRadio()
      return
    }
    radioNote = ""
    var hit = streamCache[st.query]
    if (hit === false) { radioFallback(st); return }
    if (hit) { startStream(hit, st, gamePk); return }
    radioPending = { st: st, gamePk: gamePk }
    radioResolving = st.query
    // Only letters, digits, space, dot, ampersand, hyphen reach the URL, and
    // encodeURIComponent leaves none of them able to break the quoting.
    var q = encodeURIComponent(String(st.query).replace(/[^A-Za-z0-9 .&-]/g, "").slice(0, 60))
    var path = "/json/stations/search?name=" + q +
               "&limit=40&hidebroken=true&order=clickcount&reverse=true"
    // Radio Browser runs several mirrors; try the next if one is down.
    var hosts = ["de1", "nl1", "at1"], parts = []
    for (var i = 0; i < hosts.length; i++)
      parts.push("curl -q -fsS --compressed -A '" + ua + "' --proto '=https' --max-time 8" +
                 " --max-filesize " + maxPlainBytes +
                 " 'https://" + hosts[i] + ".api.radio-browser.info" + path + "'")
    launch(16, ["/bin/bash", "-c", parts.join(" || ")])
  }

  function radioFallback(st) {
    radioNote = st.name + " isn't in Radio Browser — opened it on TuneIn instead"
    openLink(radioUrl(st.query))
  }

  function startStream(stream, st, gamePk) {
    var item = { query: st.query, label: radioLabel(st), gamePk: gamePk || 0, stream: stream }
    if (playerProc.running) {
      // Swap stations: let the old mpv exit, then start the new one.
      radioQueued = item
      radioStopping = true
      playerProc.running = false
      radioNow = item
      return
    }
    launchPlayer(item)
  }

  function launchPlayer(item) {
    var url = String(item.stream.url || "")
    if (!/^https?:\/\/[^\s"'<>]+$/.test(url)) { radioNote = "That stream address looks wrong"; return }
    radioNow = item
    radioQueued = null
    // "--" ends option parsing, so a URL can never be read as an mpv flag;
    // --ytdl=no keeps mpv from handing the URL to yt-dlp.
    playerProc.command = ["mpv", "--no-video", "--ytdl=no", "--no-terminal", "--force-window=no",
                          "--audio-display=no", "--volume=" + radioVolume,
                          "--input-ipc-server=" + radioSock, "--title=omarchy-mlb-radio",
                          "--", url]
    playerProc.running = true
    // Radio Browser asks clients to report plays (it ranks stations by them).
    var uuid = String(item.stream.uuid || "")
    if (/^[0-9a-f-]{36}$/.test(uuid)) {
      clickProc.command = ["curl", "-q", "-fsS", "-o", "/dev/null", "-A", ua, "--proto", "=https",
                           "--max-time", "8", "https://de1.api.radio-browser.info/json/url/" + uuid]
      clickProc.running = true
    }
  }

  function stopRadio() {
    radioQueued = null
    radioPending = null
    radioResolving = ""
    if (playerProc.running) { radioStopping = true; playerProc.running = false }
    radioNow = null
  }

  function setRadioVolume(v) {
    radioVolume = Math.max(0, Math.min(130, Math.round(v)))
    if (!playerProc.running) return
    // mpv's JSON IPC; python3 is already a dependency (odds.py).
    volProc.command = ["/usr/bin/python3", "-I", "-c",
      "import socket,sys\n" +
      "s=socket.socket(socket.AF_UNIX)\ns.settimeout(2)\ns.connect(sys.argv[1])\n" +
      "s.sendall(('{\"command\":[\"set_property\",\"volume\",'+sys.argv[2]+']}\\n').encode())\ns.close()",
      radioSock, String(radioVolume)]
    volProc.running = true
  }

  // Default station for a game: your team's radio call if they're playing,
  // else the home club's, else the first English feed.
  function defaultStation(g) {
    var st = g && g.media ? g.media.stations : []
    var want = favTeam && (g.away.abbr === favTeam || g.home.abbr === favTeam) ? favTeam : g ? g.home.abbr : ""
    for (var i = 0; i < st.length; i++)
      if (st[i].lang === "en" && !st[i].national && st[i].abbr === want) return st[i]
    for (i = 0; i < st.length; i++) if (st[i].lang === "en") return st[i]
    return null
  }

  function savantUrl(pk) {
    var n = parseInt(pk, 10)
    if (!isFinite(n) || n <= 0) return ""
    return "https://baseballsavant.mlb.com/gamefeed?game_pk=" + n
  }

  // ---- Fetch machinery ---------------------------------------------------
  // Six guarded slots (schedule, bracket, seasons x2, standings, feed). A
  // completion whose generation no longer matches is discarded; a request
  // arriving while its slot is busy is queued, never raced.
  property int fetchGen: 0
  property var procGen: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var pendingCmd: [null, null, null, null, null, null, null, null,
                            null, null, null, null, null, null, null, null, null]
  property var guardStarted: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  readonly property var guardedProcs: [schedProc, bracketProc, seasonProc,
                                       season2Proc, standProc, feedProc,
                                       espnProc, polyProc, kalshiProc, probProc,
                                       teamStatsProc, leadersProc, mvpProc,
                                       savantBoardsProc, pctProc, savantGameProc, stationProc]
  readonly property var guardLimits: [12, 12, 10, 10, 14, 20, 18, 18, 18, 20, 20, 16, 10,
                                      60, 30, 25, 30]

  function launch(i, cmd) {
    var pc = pendingCmd
    pc[i] = cmd
    pendingCmd = pc
    var proc = guardedProcs[i]
    if (proc.running) { proc.running = false; return }
    startPending(i)
  }

  function startPending(i) {
    var started = guardStarted
    started[i] = 0
    guardStarted = started
    var cmd = pendingCmd[i]
    if (!cmd) return
    var pc = pendingCmd
    pc[i] = null
    pendingCmd = pc
    var g = procGen
    g[i] = fetchGen
    procGen = g
    var proc = guardedProcs[i]
    proc.command = cmd
    started = guardStarted
    started[i] = Date.now()
    guardStarted = started
    proc.running = true
  }

  function fresh(i) { return procGen[i] === fetchGen }

  function invalidate() {
    fetchGen += 1
    var pc = pendingCmd
    for (var i = 0; i < guardedProcs.length; i++) {
      pc[i] = null
      if (guardedProcs[i].running) guardedProcs[i].running = false
    }
    pendingCmd = pc
    loadingSchedule = false
    loadingBracket = false
    loadingStandings = false
    loadingFeed = false
  }

  // curl --max-time bounds every request; this watchdog kills anything that
  // wedges without exiting, which also unsticks the loading flags.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      var now = Date.now()
      var started = root.guardStarted
      for (var i = 0; i < root.guardedProcs.length; i++) {
        var proc = root.guardedProcs[i]
        if (!proc.running) { started[i] = 0; continue }
        if (!started[i]) { started[i] = now; continue }
        if (now - started[i] > (root.guardLimits[i] + 5) * 1000) {
          proc.running = false
          started[i] = 0
          root.loadingSchedule = false
          root.loadingBracket = false
          root.loadingStandings = false
          root.loadingFeed = false
        }
      }
      root.guardStarted = started
    }
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n }
  function ymd(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
  }

  function fetchSchedule() {
    var now = new Date()
    // Six days back so the Statcast selector can review recent games, seven
    // days forward for upcoming matchups. Past finals drop out of every
    // other consumer via mode filters (upcoming excludes finals; the Games
    // tab reads schedule.today, which excludes past dates).
    var start = new Date(now.getTime() - 6 * 86400000)
    var end = new Date(now.getTime() + 7 * 86400000)
    loadingSchedule = true
    launch(0, fetchArgs(12, base + "schedule?sportId=1&startDate=" + ymd(start) +
      "&endDate=" + ymd(end) + "&hydrate=linescore,decisions,broadcasts(all)",
      maxScheduleBytes))
  }

  property real lastBracketFetch: 0
  // Refetch unless one just landed (opening the panel and switching to the
  // Bracket tab both ask, usually within the same moment).
  function refreshBracketIfStale(maxAgeMs) {
    if (Date.now() - lastBracketFetch >= (maxAgeMs || 30000)) fetchBracket()
  }

  // Always asks for this year first; the collector falls back to last year
  // when this year's bracket is still all placeholders (or not posted yet).
  function fetchBracket(year) {
    var y = year || new Date().getFullYear()
    lastBracketFetch = Date.now()
    loadingBracket = true
    bracketReqYear = y
    launch(1, fetchArgs(12, base + "schedule/postseason?sportId=1&season=" + y +
      "&hydrate=decisions"))
  }

  function fetchMvp(year) {
    launch(12, fetchArgs(10, base + "awards/WSMVP/recipients?season=" + year))
  }

  function fetchSeasons() {
    var y = new Date().getFullYear()
    launch(2, fetchArgs(10, base + "seasons/" + y + "?sportId=1"))
    launch(3, fetchArgs(10, base + "seasons/" + (y + 1) + "?sportId=1"))
  }

  // Standings of the season that last made sense: before pitchers and
  // catchers report there are no games in the new year yet, so the prior
  // year's final standings are the ones worth displaying.
  function standingsYearFor(nowMs) {
    var y = new Date(nowMs).getFullYear()
    var cal = seasons[y]
    if (cal && cal.springMs && nowMs < cal.springMs) return y - 1
    return y
  }

  function fetchStandings() {
    var year = standingsYearFor(nowMs)
    standingsYear = year
    loadingStandings = true
    launch(4, fetchArgs(14, base + "standings?leagueId=103,104&season=" + year +
      "&standingsTypes=regularSeason&hydrate=team"))
  }

  // ---- Probable-pitcher feed queue ----------------------------------------
  // Probable starters aren't in the schedule payload — they live in each
  // game's feed. Queue nearby preview games one at a time so the Games tab
  // can show who's pitching without fanning out parallel requests.
  property var probFeedQueue: []
  property int probActivePk: -1
  property var feeds: ({})      // gamePk -> parsed feed (bounded)

  function queuePreviewFeeds(games) {
    if (!games || !games.length) return
    var q = probFeedQueue.slice()
    var changed = false
    for (var i = 0; i < games.length; i++) {
      var g = games[i]
      if (g.mode !== "preview") continue
      if (g.startMs - nowMs > 2 * 86400000) continue  // only the next 2 days
      if (feeds.hasOwnProperty(String(g.gamePk))) continue
      if (q.indexOf(g.gamePk) >= 0 || probActivePk === g.gamePk) continue
      q.push(g.gamePk)
      changed = true
      if (q.length >= 5) break  // bounded work per schedule refresh
    }
    if (changed) { probFeedQueue = q; pumpProbQueue() }
  }

  function pumpProbQueue() {
    if (probProc.running) return
    if (!probFeedQueue.length) { probActivePk = -1; return }
    var pk = probFeedQueue[0]
    probFeedQueue = probFeedQueue.slice(1)
    probActivePk = pk
    var started = guardStarted
    started[9] = Date.now()
    guardStarted = started
    probProc.command = fetchArgs(15,
      "https://statsapi.mlb.com/api/v1.1/game/" + pk + "/feed/live", maxFeedBytes)
    probProc.running = true
  }

  // ---- Odds fetchers -----------------------------------------------------
  // All three go through odds.py: it serves the on-disk cache while it's
  // younger than oddsTtl, stops at oddsBudget pulls for the calendar month,
  // and serves stale data when either gate blocks — the network is touched
  // at most budget times per month per source, spread by ttl.
  function oddsHelper() {
    return String(Qt.resolvedUrl("odds.py")).replace("file://", "")
  }

  // <cache-key> <budget-key> <url> <ttl> <cap>: the cache key is per-day for
  // ESPN so each date costs one pull; the budget key is per-source so the
  // month's cap covers every day's cache.
  function oddsArgs(cacheKey, budgetKey, url) {
    return ["/usr/bin/python3", oddsHelper(), cacheKey, budgetKey, url,
            String(oddsTtl), String(oddsBudget)]
  }

  function fetchGameOdds(dateStr) {
    // ESPN takes YYYYMMDD; cache per day so each day costs at most one pull.
    launch(6, oddsArgs("espn-" + dateStr, "espn",
      "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?dates=" +
      dateStr.replace(/-/g, "")))
  }

  function fetchPolyOdds() {
    launch(7, oddsArgs("poly-ws-" + marketYear, "poly",
      "https://gamma-api.polymarket.com/events?slug=mlb-world-series-champion-" + marketYear))
  }

  function fetchKalshiOdds() {
    var yy = String(marketYear).slice(2)
    launch(8, oddsArgs("kalshi-ws-" + yy, "kalshi",
      "https://external-api.kalshi.com/trade-api/v2/markets?event_ticker=KXMLB-" +
      yy + "&limit=40"))
  }

  // Pull all three sources — called on open and on explicit refresh, never on
  // a timer: the helper's TTL/cap make repeat calls free when fresh.
  function fetchOdds() {
    loadingOdds = true
    var d = focusGame && focusGame.officialDate ? focusGame.officialDate : ymd(new Date())
    fetchGameOdds(d)
    fetchPolyOdds()
    fetchKalshiOdds()
  }

  // Odds for a specific game, gated on the date its lines were fetched for.
  function oddsFor(g) {
    if (!g || espnDate === "") return null
    if (g.officialDate && g.officialDate !== espnDate) return null
    return espnOdds[g.away.abbr + "@" + g.home.abbr] || null
  }

  property int requestedPk: -1
  function fetchFeed() {
    if (!focusGame) { feed = null; feedPk = -1; return }
    // Stamp the pk at request time: the collector must attribute the payload
    // to the game we asked for, not whatever focus happens to be on arrival.
    requestedPk = focusGame.gamePk
    loadingFeed = true
    launch(5, fetchArgs(20, "https://statsapi.mlb.com/api/v1.1/game/" +
      requestedPk + "/feed/live", maxFeedBytes))
  }

  // Clicking a row in the Games tab pins the focus game; cleared automatically
  // when that game drops out of the schedule window.
  property int focusOverride: -1
  // Just-finished hold: when the game we're watching flips live → final, we
  // keep it in focus for holdMs so the Statcast tab holds its final numbers
  // instead of flipping to the next game's empty preview. A live game
  // elsewhere always wins; the hold only papers over the gap between the
  // last out and the next first pitch.
  property int holdPk: -1
  property double holdUntil: 0
  readonly property int holdMs: 600000
  function focusGameFor(pk) {
    var n = parseInt(pk, 10)
    focusOverride = isFinite(n) && n > 0 ? n : -1
    // focusGame re-derives; onFocusGameChanged fetches the new feed. The
    // old feed stays loaded until the new one lands (the tabs compare
    // feedPk against focusGame, so stale data never renders anyway).
  }

  // Live tab ←/→: move the pin along the matchup switcher, wrapping around.
  function stepGame(dir) {
    var list = Mlb.switcherGames(schedule.games, 15)
    if (list.length < 2) return
    var at = -1
    for (var i = 0; i < list.length; i++)
      if (focusGame && list[i].gamePk === focusGame.gamePk) at = i
    var next = at < 0 ? 0 : (at + dir + list.length) % list.length
    focusGameFor(list[next].gamePk)
  }

  function ensureStandings() {
    if (standingsLoaded && standingsYear === standingsYearFor(nowMs)) return
    if (standProc.running) return
    fetchStandings()
  }

  function ensureFeed(force) {
    if (!focusGame) { feed = null; feedPk = -1; return }
    if (force || feedPk !== focusGame.gamePk) fetchFeed()
    else if (feedLive && !feedProc.running) fetchFeed()
  }

  // Team season stats come as two stats-api calls (hitting, pitching) on a
  // single Process; the delimiter line splits them for parsing.
  function fetchTeamStats() {
    var y = statsYear
    var h = base + "teams/stats?season=" + y + "&group=hitting&sportId=1"
    var p = base + "teams/stats?season=" + y + "&group=pitching&sportId=1"
    launch(10, ["/bin/bash", "-c", multiCurl([h, p], 15)])
  }

  // Several fixed URLs on one Process, separated by ----SPLIT---- lines.
  // URLs are built here from constants and integers only, never from
  // remote data, so single-quoting them for bash is sufficient.
  function multiCurl(urls, seconds) {
    var parts = []
    for (var i = 0; i < urls.length; i++)
      parts.push("curl -q -fsS --compressed -A '" + ua + "' --proto '=https' --max-time " +
                 seconds + " --max-filesize " + maxPlainBytes + " '" + urls[i] + "'")
    return parts.join("; echo; echo ----SPLIT----; ")
  }

  readonly property string savantBase: "https://baseballsavant.mlb.com/leaderboard/"

  function fetchSavantBoards() {
    var y = statsYear
    savantBoardsAt = Date.now()
    launch(13, ["/bin/bash", "-c", multiCurl([
      savantBase + "expected_statistics?type=batter&year=" + y + "&position=&team=&min=q&csv=true",
      savantBase + "statcast?type=batter&year=" + y + "&position=&team=&min=q&csv=true",
      savantBase + "bat-tracking?type=batter&minSwings=q&gameType=Regular&dateStart=" + y +
        "-01-01&dateEnd=" + y + "-12-31&csv=true",
      savantBase + "sprint_speed?year=" + y + "&position=&team=&min=10&csv=true",
      savantBase + "outs_above_average?type=Fielder&startYear=" + y + "&endYear=" + y +
        "&split=no&team=&range=year&min=q&pos=&roles=&viz=hide&csv=true"
    ], 20)])
  }

  function fetchPercentiles() {
    var y = statsYear
    pctAt = Date.now()
    launch(14, ["/bin/bash", "-c", multiCurl([
      savantBase + "percentile-rankings?type=batter&year=" + y + "&csv=true",
      savantBase + "percentile-rankings?type=pitcher&year=" + y + "&csv=true"
    ], 15)])
  }

  function ensureSavant() {
    var now = Date.now()
    if (now - savantBoardsAt > savantMaxAgeMs && !savantBoardsProc.running) fetchSavantBoards()
    if (now - pctAt > savantMaxAgeMs && !pctProc.running) fetchPercentiles()
  }

  // Savant's Gamefeed: ~3 MB of JSON (~175 KB gzipped). Pulled for the
  // focus game when the Statcast tab shows it, once a minute while live.
  readonly property int maxSavantGameBytes: 10485760
  function fetchSavantGame() {
    var g = focusGame
    if (!g || g.mode === "preview") return
    savantReqPk = g.gamePk
    launch(15, fetchArgs(20, "https://baseballsavant.mlb.com/gf?game_pk=" + g.gamePk,
                         maxSavantGameBytes))
  }

  function ensureSavantGame() {
    var g = focusGame
    if (!g || g.mode === "preview") return
    if (savantGamePk !== g.gamePk && !(savantGameProc.running && savantReqPk === g.gamePk))
      fetchSavantGame()
  }

  function fetchLeaders() {
    launch(11, fetchArgs(12,
      base + "stats/leaders?leaderCategories=" + Mlb.LEADER_ORDER.join(",") +
      "&season=" + statsYear + "&sportId=1&limit=5"))
  }

  function refresh() {
    invalidate()
    fetchSchedule()
    fetchBracket()
    fetchSeasons()
    ensureFeed(true)
    if (view === "season") ensureStandings()
    fetchOdds()
    fetchTeamStats()
    fetchLeaders()
    fetchSavantBoards()
    fetchPercentiles()
    if (view === "statcast") fetchSavantGame()
  }

  Component.onCompleted: {
    fetchSchedule()
    fetchBracket()
    fetchSeasons()
  }

  // Schedule polling: 45s while anything is live (the pill tracks the
  // score), 10 min otherwise; refetched on every open so the popup is fresh.
  Timer {
    interval: 45000
    repeat: true
    running: root.schedule.live.length > 0
    onTriggered: root.fetchSchedule()
  }
  Timer {
    interval: 600000
    repeat: true
    running: root.schedule.live.length === 0
    onTriggered: root.fetchSchedule()
  }
  // The bracket carries series scores, so it follows the games: every minute
  // while something is live, every five minutes while the postseason is
  // running (a series wraps, the next round gains teams), and every six
  // hours once it's settled — a finished bracket only changes when the next
  // year's field is set. Opening the panel, the Bracket tab, and a game
  // ending also refresh it (see onOpenedChanged / onViewChanged / schedProc).
  readonly property bool bracketSettled: series.length > 0 &&
    (champPath !== null || bracketSeason < thisYear)
  Timer {
    interval: root.schedule.live.length > 0 ? 60000
            : root.bracketSettled ? 21600000 : 300000
    repeat: true
    running: true
    onTriggered: root.fetchBracket()
  }
  // Network can be down for a beat at shell startup (right after login or a
  // shell restart); a failed first fetch would otherwise leave the bracket
  // empty for 15 minutes. Retry every 30s until both datasets land.
  Timer {
    interval: 30000
    repeat: true
    running: root.series.length === 0 || Object.keys(root.seasons).length === 0
    onTriggered: {
      if (root.series.length === 0) root.fetchBracket()
      if (Object.keys(root.seasons).length === 0) root.fetchSeasons()
    }
  }
  Timer { interval: 21600000; repeat: true; onTriggered: root.fetchSeasons() }
  // The live feed only while the popup is showing it and the game is
  // running: every 10 s on the Live tab (the API's own cache window, so
  // faster gains nothing), every 20 s on Games/Statcast.
  Timer {
    interval: root.view === "live" ? 10000 : 20000
    repeat: true
    running: root.opened && root.feedLive &&
             (root.view === "live" || root.view === "games" || root.view === "statcast")
    onTriggered: root.fetchFeed()
  }
  // Savant's game feed refreshes slower than MLB's and is bigger: once a
  // minute, Statcast tab only.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened && root.view === "statcast" && root.focusGame !== null &&
             root.focusGame.mode === "live"
    onTriggered: root.fetchSavantGame()
  }
  // One-second countdown tick + notification check.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: { root.nowMs = Date.now(); root.checkNotify() }
  }

  // ---- Fetch results -----------------------------------------------------
  Process {
    id: schedProc
    command: ["true"]
    onExited: root.startPending(0)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(0)) return
        root.loadingSchedule = false
        try {
          var parsed = root.parseBounded(text, root.maxScheduleBytes)
          if (!parsed) return
          var next = Mlb.parseSchedule(parsed)
          // Capture the live→final flip against the still-current schedule
          // so Statcast keeps the just-ended game's numbers for holdMs.
          var endedPk = Mlb.detectFinalTransition(root.focusGame, next.games)
          if (endedPk > 0) {
            root.holdPk = endedPk
            root.holdUntil = Date.now() + root.holdMs
            root.fetchBracket()   // a game just ended: series score changed
          }
          root.schedule = next
          root.queuePreviewFeeds(next.games)
          root.lastError = ""
        } catch (e) { root.lastError = "schedule parse error" }
      }
    }
  }

  Process {
    id: bracketProc
    command: ["true"]
    onExited: root.startPending(1)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(1)) return
        root.loadingBracket = false
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (!parsed) return
          var arr = Mlb.parsePostseason(parsed)
          var year = root.bracketReqYear
          // This year's field isn't set yet: show last year's bracket (and
          // champion) rather than a page of TBDs. One step back only.
          if (!Mlb.hasRealTeams(arr) && year === new Date().getFullYear()) {
            root.fetchBracket(year - 1)
            return
          }
          root.series = arr
          root.bracketSeason = year
          root.bracketLayout = Mlb.buildBracketLayout(arr)
          root.champPath = Mlb.championPath(arr)
          if (root.champPath && (root.wsMvp === null || root.wsMvpSeason !== year))
            root.fetchMvp(year)
          root.lastError = ""
        } catch (e) { root.lastError = "bracket parse error" }
      }
    }
  }

  Process {
    id: seasonProc
    command: ["true"]
    onExited: root.startPending(2)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(2)) return
        try {
          var parsed = root.parseBounded(text, 65536)
          if (!parsed) return
          var cal = Mlb.parseSeason(parsed)
          if (!cal) return
          var copy = {}
          for (var k in root.seasons) copy[k] = root.seasons[k]
          copy[cal.year] = cal
          root.seasons = copy
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: season2Proc
    command: ["true"]
    onExited: root.startPending(3)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(3)) return
        try {
          var parsed = root.parseBounded(text, 65536)
          if (!parsed) return
          var cal = Mlb.parseSeason(parsed)
          if (!cal) return
          var copy = {}
          for (var k in root.seasons) copy[k] = root.seasons[k]
          copy[cal.year] = cal
          root.seasons = copy
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: standProc
    command: ["true"]
    onExited: root.startPending(4)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(4)) return
        root.loadingStandings = false
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (!parsed) return
          root.standings = Mlb.parseStandings(parsed)
          root.standingsLoaded = true
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: feedProc
    command: ["true"]
    onExited: root.startPending(5)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(5)) return
        root.loadingFeed = false
        try {
          var parsed = root.parseBounded(text, root.maxFeedBytes)
          if (!parsed) return
          root.feed = Mlb.parseFeed(parsed)
          root.live = Mlb.parseLive(parsed)
          root.feedPk = root.requestedPk
        } catch (e) { root.lastError = "feed parse error" }
      }
    }
  }

  // ---- Odds collectors ---------------------------------------------------
  // odds.py prints either fresh/stale JSON or nothing (blocked/failed with no
  // cache); parseBounded turns the empty case into null, keeping last-good.
  Process {
    id: espnProc
    command: ["true"]
    onExited: root.startPending(6)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(6)) return
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (!parsed) { root.loadingOdds = false; return }
          root.espnOdds = Mlb.parseEspnOdds(parsed)
          // Cache key carries the date: espn-YYYY-MM-DD.
          var key = String(root.guardedProcs[6].command[2] || "")
          root.espnDate = key.slice(5)
          root.lastError = ""
        } catch (e) { /* keep last-good */ }
        root.loadingOdds = false
      }
    }
  }

  Process {
    id: polyProc
    command: ["true"]
    onExited: root.startPending(7)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(7)) return
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (parsed) root.polyWs = Mlb.parsePolyWs(parsed)
        } catch (e) { /* keep last-good */ }
        root.loadingOdds = false
      }
    }
  }

  Process {
    id: kalshiProc
    command: ["true"]
    onExited: root.startPending(8)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(8)) return
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (parsed) root.kalshiWs = Mlb.parseKalshiWs(parsed)
        } catch (e) { /* keep last-good */ }
        root.loadingOdds = false
      }
    }
  }

  // One feed at a time; the collector stores by probActivePk, onExited
  // advances the queue. No generation stamp: a single consumer, and an
  // invalidated (killed) run simply yields no parse and moves on.
  Process {
    id: probProc
    command: ["true"]
    onExited: {
      root.probActivePk = -1
      root.pumpProbQueue()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var pk = root.probActivePk
        if (pk <= 0) return
        try {
          var parsed = root.parseBounded(text, root.maxFeedBytes)
          if (!parsed) return
          var copy = {}
          for (var k in root.feeds) copy[k] = root.feeds[k]
          copy[pk] = Mlb.parseFeed(parsed)
          // Bounded: numeric keys iterate ascending = oldest game first.
          var keys = Object.keys(copy)
          if (keys.length > 8) delete copy[keys[0]]
          root.feeds = copy
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: teamStatsProc
    command: ["true"]
    onExited: root.startPending(10)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(10)) return
        try {
          var parts = String(text || "").split("----SPLIT----")
          var h = root.parseBounded(parts[0], root.maxPlainBytes)
          var p = parts.length > 1 ? root.parseBounded(parts[1], root.maxPlainBytes) : null
          if (!h || !p) return
          var rows = Mlb.parseTeamStats(h, p)
          var byId = {}
          for (var i = 0; i < rows.length; i++) byId[rows[i].id] = rows[i]
          root.teamStatsRows = rows
          root.teamStatsById = byId
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: leadersProc
    command: ["true"]
    onExited: root.startPending(11)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(11)) return
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (parsed) root.leaders = Mlb.parseLeaders(parsed)
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: mvpProc
    command: ["true"]
    onExited: root.startPending(12)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(12)) return
        try {
          var parsed = root.parseBounded(text, 65536)
          var w = parsed ? Mlb.parseAwardWinner(parsed) : null
          if (w) { root.wsMvp = w; root.wsMvpSeason = root.bracketSeason }
        } catch (e) { /* not announced yet; the next bracket poll retries */ }
      }
    }
  }

  Process {
    id: savantBoardsProc
    command: ["true"]
    onExited: root.startPending(13)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(13)) return
        try {
          var parts = String(text || "").split("----SPLIT----")
          if (text.length > 6 * root.maxPlainBytes) return
          var boards = Mlb.savantLeaderboards({
            xstats: parts[0] || "", statcast: parts[1] || "", bat: parts[2] || "",
            sprint: parts[3] || "", oaa: parts[4] || "" })
          if (boards.length) root.savantBoards = boards
          else root.savantBoardsAt = 0
        } catch (e) { root.savantBoardsAt = 0 }
      }
    }
  }

  Process {
    id: pctProc
    command: ["true"]
    onExited: root.startPending(14)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(14)) return
        try {
          if (text.length > 3 * root.maxPlainBytes) return
          var parts = String(text || "").split("----SPLIT----")
          var b = Mlb.parsePercentiles(parts[0] || "")
          var p = Mlb.parsePercentiles(parts[1] || "")
          if (Object.keys(b).length) root.pctBatters = b
          if (Object.keys(p).length) root.pctPitchers = p
          if (!Object.keys(b).length && !Object.keys(p).length) root.pctAt = 0
        } catch (e) { root.pctAt = 0 }
      }
    }
  }

  Process {
    id: savantGameProc
    command: ["true"]
    onExited: root.startPending(15)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(15)) return
        try {
          var parsed = root.parseBounded(text, root.maxSavantGameBytes)
          if (!parsed) return
          var g = root.gameByPk(root.savantReqPk)
          root.savantGame = Mlb.parseSavantGame(parsed, g ? g.away.id : 0, g ? g.home.id : 0)
          root.savantGamePk = root.savantReqPk
        } catch (e) { /* keep last-good */ }
      }
    }
  }

  Process {
    id: stationProc
    command: ["true"]
    onExited: root.startPending(16)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.fresh(16)) return
        var pend = root.radioPending
        var q = root.radioResolving
        root.radioResolving = ""
        root.radioPending = null
        if (!pend || pend.st.query !== q) return
        var pick = null
        try {
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          pick = parsed ? Mlb.pickStream(parsed, q) : null
        } catch (e) { pick = null }
        if (text.length === 0) { root.radioNote = "Couldn't reach Radio Browser"; return }
        var c = {}
        for (var k in root.streamCache) c[k] = root.streamCache[k]
        c[q] = pick || false
        root.streamCache = c
        if (pick) root.startStream(pick, pend.st, pend.gamePk)
        else root.radioFallback(pend.st)
      }
    }
  }

  Process {
    id: playerProc
    command: ["true"]
    onExited: function(code) {
      if (root.radioStopping) {
        root.radioStopping = false
        if (root.radioQueued) root.launchPlayer(root.radioQueued)
        return
      }
      // Ended on its own: stream dropped or never connected.
      if (root.radioNow) {
        root.radioNote = root.radioNow.label + " stopped" + (code ? " (stream unavailable)" : "")
        root.radioNow = null
      }
    }
  }
  Process { id: clickProc; command: ["true"] }
  Process { id: volProc; command: ["true"] }

  Process { id: notifyProc; command: ["true"] }

  // ---- Derived values ----------------------------------------------------
  // The focus game is the one the Games/Statcast tabs and the feed follow:
  // an explicitly clicked game, else a live one (favorite team first), else
  // a just-finished game while its hold lasts, else the next to be played.
  // A click pin that falls out of the window is dropped rather than left
  // dangling, and the hold never outranks a live game — it only covers the
  // gap where auto would show an empty preview.
  readonly property var focusGame: {
    if (focusOverride > 0) {
      var pinned = gameByPk(focusOverride)
      if (pinned) return pinned
    }
    var auto = Mlb.pickPillGame(schedule, favTeam)
    if (auto && auto.mode === "live") return auto
    if (holdPk > 0 && nowMs < holdUntil) {
      var held = gameByPk(holdPk)
      if (held) return held
    }
    return auto
  }

  function gameByPk(pk) {
    var games = schedule.games || []
    for (var i = 0; i < games.length; i++)
      if (games[i].gamePk === pk) return games[i]
    return null
  }

  // The focus moved to a *different* game (hold expired, schedule rolled,
  // chip clicked): fetch that game's feed while the popup is up. The pk
  // comparison keeps ordinary schedule refreshes (new objects, same game)
  // from triggering a redundant fetch.
  onFocusGameChanged: {
    if (opened && focusGame && feedPk !== focusGame.gamePk) fetchFeed()
    if (opened && view === "statcast") ensureSavantGame()
  }
  readonly property bool feedLive: feed !== null && feed.mode === "Live"
  readonly property int thisYear: new Date(nowMs).getFullYear()
  // Season whose stats are worth showing: last year's until spring training.
  readonly property int statsYear: standingsYearFor(nowMs)
  // Championship markets: once this year's title is decided, next year's
  // futures are the only live ones.
  readonly property int marketYear: champPath !== null && bracketSeason === thisYear
                                    ? thisYear + 1 : thisYear

  function seasonCal(year) { return seasons[year] || null }

  // Offseason-aware phase label for the masthead.
  function currentPhase() {
    var cal = seasonCal(thisYear)
    if (!cal) return ""
    if (cal.springMs && nowMs < cal.springMs) return "OFFSEASON"
    if (cal.openingMs && nowMs < cal.openingMs) return "SPRING TRAINING"
    if (cal.regularEndMs && nowMs <= cal.regularEndMs) return "REGULAR SEASON"
    if (cal.postseasonEndMs && nowMs <= cal.postseasonEndMs) return "POSTSEASON"
    return "OFFSEASON"
  }

  // The next date worth counting down to, across this year and next.
  function milestones() {
    var want = [
      ["springMs", "Spring Training", "SPRING"],
      ["openingMs", "Opening Day", "OPENING"],
      ["allStarMs", "All-Star Game", "ALL-STAR"],
      ["postseasonMs", "Postseason", "POSTSEASON"]
    ]
    var out = []
    var years = [thisYear, thisYear + 1]
    for (var y = 0; y < years.length; y++) {
      var cal = seasonCal(years[y])
      if (!cal) continue
      for (var i = 0; i < want.length; i++) {
        var ms = cal[want[i][0]]
        if (ms && ms > nowMs)
          out.push({ ms: ms, label: want[i][1], short: want[i][2], year: cal.year })
      }
    }
    out.sort(function(a, b) { return a.ms - b.ms })
    var seen = {}, dedup = []
    for (i = 0; i < out.length; i++) {
      if (seen[out[i].label]) continue
      seen[out[i].label] = true
      dedup.push(out[i])
    }
    return boundedList(dedup, 5)
  }

  function nextMilestone() {
    var m = milestones()
    return m.length ? m[0] : null
  }

  // The World Series winner of the bracket season, once decided.
  function champion() {
    return champPath ? { name: champPath.team.name, abbr: champPath.team.abbr,
                         year: bracketSeason } : null
  }

  // The bar pill celebrates for a week after the final out.
  readonly property bool champFresh: champPath !== null && champPath.clinchMs > 0 &&
                                     nowMs - champPath.clinchMs < 7 * 86400000

  // ---- Favorite team -----------------------------------------------------
  // One league's clubs for the Season tab's picker (15 chips), sorted by
  // abbreviation. Defaults to the AL when the league is unrecognized.
  function teamPicker(lg) {
    return Mlb.teamsByLeague(lg === "NL" ? "NL" : "AL")
  }

  // Persist the pick through `omarchy bar set`, which rewrites the widget's
  // shell.json entry; the bar hot-reloads config and re-injects `settings`,
  // so favTeam (and everything bound to it) updates without a panel reload.
  function setFavorite(abbr) {
    if (!bar) return
    var v = String(abbr || "").toUpperCase().trim()
    if (v !== "" && !Mlb.TEAMS.hasOwnProperty(teamIdFor(v))) return
    bar.run("omarchy bar set " + moduleName + " favoriteTeam " + bar.shellQuote(v))
  }

  function teamIdFor(abbr) {
    for (var id in Mlb.TEAMS)
      if (Mlb.TEAMS[id].abbr === abbr) return id
    return ""
  }

  // ---- Time formatting ---------------------------------------------------
  function fmtShort(ms) {
    if (ms <= 0) return "now"
    var s = Math.floor(ms / 1000)
    var d = Math.floor(s / 86400); s -= d * 86400
    var h = Math.floor(s / 3600); s -= h * 3600
    var m = Math.floor(s / 60)
    if (d > 0) return d + "d"
    if (h > 0) return h + "h"
    if (m > 0) return m + "m"
    return "<1m"
  }

  function fmtLong(ms) {
    if (ms <= 0) return "now"
    var s = Math.floor(ms / 1000)
    var d = Math.floor(s / 86400); s -= d * 86400
    var h = Math.floor(s / 3600); s -= h * 3600
    var m = Math.floor(s / 60)
    var parts = []
    if (d > 0) parts.push(d + "d")
    if (h > 0) parts.push(h + "h")
    parts.push(m + "m")
    return "in " + parts.join(" ")
  }

  function sameDay(ms) {
    var d = new Date(ms), n = new Date(nowMs)
    return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() &&
           d.getDate() === n.getDate()
  }

  function dayWord(ms) {
    var d = new Date(ms), n = new Date(nowMs)
    var diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) -
                           new Date(n.getFullYear(), n.getMonth(), n.getDate())) / 86400000)
    if (diff === 0) return "Today"
    if (diff === 1) return "Tomorrow"
    return Qt.formatDateTime(d, "ddd")
  }

  function fmtTime(ms) { return Qt.formatTime(new Date(ms), tPattern) }
  function fmtWhen(ms) {
    if (sameDay(ms)) return fmtTime(ms)
    return dayWord(ms)
  }

  // ---- Bar pill ----------------------------------------------------------
  readonly property string rawLabel: {
    if (schedule.games.length === 0 && lastError !== "")
      return glyph + " MLB"
    var game = Mlb.pickPillGame(schedule, favTeam)
    if (game) {
      if (game.mode === "live") {
        var inning = game.inning ? ((game.isTop ? "T" : "B") + game.inning) : ""
        var score = game.away.abbr + " " + (game.away.score === null ? 0 : game.away.score) +
                    "-" + (game.home.score === null ? 0 : game.home.score) + " " + game.home.abbr
        return glyph + " " + score + (inning ? " " + inning : "")
      }
      return glyph + " " + game.away.abbr + "-" + game.home.abbr + " " + fmtWhen(game.startMs)
    }
    if (champFresh) return trophy + " " + champPath.team.abbr + " CHAMPS"
    var m = nextMilestone()
    if (m) return glyph + " " + m.short + " " + fmtShort(m.ms - nowMs)
    return glyph + " MLB"
  }

  // A speaker on the pill while the radio is on.
  readonly property string label: safeBare(rawLabel, 36) + (radioPlaying ? " \uF028" : "")

  // The tooltip renders in Text elements the shell owns, so the markup
  // boundary goes on the finished string.
  readonly property string tooltip: safeBareLines(
    (radioPlaying && radioNow ? "Listening: " + radioNow.label + "\n" : "") + rawTooltip, 84, 7)

  readonly property string rawTooltip: {
    var lines = []
    var lives = boundedList(schedule.live, 4)
    if (lives.length) {
      for (var i = 0; i < lives.length; i++) {
        var g = lives[i]
        var inning = g.inning ? (" · " + (g.isTop ? "Top " : "Bot ") + g.inning) : ""
        lines.push(g.away.abbr + " " + g.away.score + ", " + g.home.abbr + " " +
                   g.home.score + inning + " · " + Mlb.compactDesc(g.desc))
      }
      return lines.join("\n")
    }
    var game = Mlb.pickPillGame(schedule, favTeam)
    if (game) {
      lines.push(game.away.name + " @ " + game.home.name)
      lines.push(dayWord(game.startMs) + " " + fmtTime(game.startMs) + " · " +
                 safe(game.venue, 40))
      if (game.media && game.media.tv.length && game.mode !== "final")
        lines.push("TV: " + safe(game.media.tv.slice(0, 3).join(", "), 70))
      lines.push(Mlb.compactDesc(game.desc))
      if (game.mode === "final") {
        lines.push((game.winnerName ? "W " + game.winnerName : "") +
                   (game.loserName ? " · L " + game.loserName : ""))
      }
      return lines.join("\n")
    }
    lines.push("No games in the next 7 days")
    var m = nextMilestone()
    if (m)
      lines.push(m.label + " · " + Qt.formatDateTime(new Date(m.ms), "d MMM yyyy") +
                 " · " + fmtLong(m.ms - nowMs))
    var champ = champion()
    if (champ) lines.push(champ.year + " World Series champions: " + champ.name +
                          " (" + champPath.wsWon + "-" + champPath.wsLost + " over " +
                          champPath.opp.abbr + ")")
    return lines.join("\n")
  }

  // ---- Notifications -----------------------------------------------------
  // Only for the configured favorite team, once per gamePk, at the moment
  // the scoreboard flips to live.
  function checkNotify() {
    if (!notifyOn || !favTeam) return
    var games = boundedList(schedule.games, 40)
    var marked = false
    var noted = notifiedPks
    for (var i = 0; i < games.length; i++) {
      var g = games[i]
      if (g.mode !== "live") continue
      if (g.away.abbr !== favTeam && g.home.abbr !== favTeam) continue
      if (noted[g.gamePk]) continue
      noted[g.gamePk] = true
      marked = true
      notifyProc.command = ["omarchy-notification-send", "-g", glyph, "-u", "normal",
        safe(g.away.abbr + " @ " + g.home.abbr, 40),
        safe(Mlb.compactDesc(g.desc) + " · Live now", 80)]
      notifyProc.running = true
    }
    if (marked) notifiedPks = noted
  }

  onViewChanged: {
    if (view === "bracket") refreshBracketIfStale(30000)
    if (view === "season") ensureStandings()
    if (view === "games" || view === "statcast" || view === "live") ensureFeed(false)
    if (view === "statcast") { ensureSavant(); ensureSavantGame() }
    if (view === "live") ensureSavant()
  }

  onOpenedChanged: {
    if (opened) {
      fetchSchedule()
      fetchOdds()
      // Opening the panel is also a retry opportunity: a fetch that failed at
      // startup would otherwise sit empty until its next interval.
      refreshBracketIfStale(30000)
      if (Object.keys(seasons).length === 0) fetchSeasons()
      ensureFeed(true)
      if (view === "season") ensureStandings()
      if (teamStatsRows.length === 0) fetchTeamStats()
      if (leaders.length === 0) fetchLeaders()
      if (view === "statcast" || view === "live") ensureSavant()
      if (view === "statcast") ensureSavantGame()
    }
  }

  // The default tab follows the setting until the user picks a tab themselves
  // (viewPinned). A one-shot latch doesn't work: `settings` arrives before its
  // values are populated, so a latch reads the fallback and sticks to it.
  onSettingsChanged: {
    if (viewPinned || !settings) return
    var t = String(setting("defaultTab", "bracket"))
    if (t === "live" || t === "games" || t === "statcast" || t === "season" ||
        t === "odds" || t === "radio" || t === "bracket") view = t
  }

  // ---- Popup -------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: String(root.setting("popupPosition", "icon")) === "center"
    focusTarget: keyCatcher
    // One size for every tab: a fixed 640x640 card so switching tabs never
    // resizes the dropdown. Tabs with more content than fits scroll inside
    // the card (Flickable below) instead of growing it.
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r") root.refresh() }
      // Arrow keys scroll the panel body when a tab overflows the card; on
      // the Live tab, left/right step through today's matchups.
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.view === "live") { root.stepGame(dx); return }
        scroller.contentY = Math.max(0, Math.min(
          scroller.contentHeight - scroller.height,
          scroller.contentY - dy * Style.space(56)))
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(10)

        // Masthead: glyph + wordmark, phase/season on the right.
        Item {
          width: parent.width
          height: brandRow.implicitHeight
          Row {
            id: brandRow
            spacing: Style.space(7)
            anchors.left: parent.left
            Text {
              textFormat: Text.PlainText
              text: root.glyph
              color: root.hi
              font.family: Style.font.family
              font.pixelSize: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: "MAJOR LEAGUE BASEBALL"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
              font.bold: true
              font.letterSpacing: Style.space(3)
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            // Color-scheme switcher: click cycles Omarchy → MLB → Classic.
            Rectangle {
              id: schemeChip
              anchors.verticalCenter: parent.verticalCenter
              width: schemeRow.implicitWidth + Style.space(14)
              height: Style.space(20)
              radius: Style.space(10)
              color: schemeMouse.containsMouse ? root.wash(0.12) : root.wash(0.05)
              border.width: 1
              border.color: schemeMouse.containsMouse ? root.hi : root.wash(0.16)
              Row {
                id: schemeRow
                anchors.centerIn: parent
                spacing: Style.space(4)
                // Three swatches previewing the active scheme.
                Repeater {
                  model: root.mlbColors ? [root.mlbNavy, "#FFFFFF", root.mlbRed]
                       : root.classicColors ? ["#3262C7", "#B2B2B2", "#D62934"]
                       : [root.themePal.blue || Color.muted, root.hi, root.themePal.red || Color.urgent]
                  delegate: Rectangle {
                    required property var modelData
                    width: Style.space(6); height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData
                    border.width: 1
                    border.color: root.wash(0.3)
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.schemeLabel
                  color: schemeMouse.containsMouse ? root.hi : Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              MouseArea {
                id: schemeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleScheme()
              }
            }
            // Favorite-team chip: color square + abbr, ties the header to
            // the personalization below.
            Row {
              visible: root.favTeam !== ""
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              Rectangle {
                width: Style.space(4)
                height: Style.space(11)
                radius: 1
                anchors.verticalCenter: parent.verticalCenter
                visible: root.teamColorsOn
                color: {
                  for (var id in Mlb.TEAMS)
                    if (Mlb.TEAMS[id].abbr === root.favTeam) return Mlb.TEAMS[id].color
                  return Color.muted
                }
              }
              Text {
                textFormat: Text.PlainText
                text: root.favTeam
                color: root.hi
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                font.letterSpacing: Style.space(1)
              }
            }
            Text {
              visible: root.champion() !== null && root.bracketSeason === root.thisYear
              textFormat: Text.PlainText
              text: root.trophy
              color: root.hi
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: {
                var champ = root.champion()
                if (champ && champ.year === root.thisYear) return champ.abbr + " " + champ.year
                var ph = root.currentPhase()
                return (ph ? ph + " · " : "") + root.thisYear
              }
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
            }
          }
        }

        PanelSeparator { foreground: Color.popups.text }

        // Tab bar: the shell's segmented control.
        ButtonGroup {
          options: [
            // Values stay as they were (saved defaultTab settings keep
            // working); only labels and order changed.
            { value: "live", label: "Live" },
            { value: "games", label: "Schedule" },
            { value: "statcast", label: "Stats" },
            { value: "odds", label: "Odds" },
            { value: "radio", label: "Radio" },
            { value: "season", label: "Season" },
            { value: "bracket", label: "Playoffs" }
          ]
          value: root.view
          focusable: false
          foreground: Color.popups.text
          background: Color.popups.background
          accent: root.hi
          fontSize: Style.space(12)
          onChanged: function(v) { root.viewPinned = true; root.view = v }
        }

        LiveTab { panel: root; width: parent.width; visible: root.view === "live" }
        BracketTab { panel: root; width: parent.width; visible: root.view === "bracket" }
        OddsTab { panel: root; width: parent.width; visible: root.view === "odds" }
        RadioTab { panel: root; width: parent.width; visible: root.view === "radio" }
        GamesTab { panel: root; width: parent.width; visible: root.view === "games" }
        StatcastTab { panel: root; width: parent.width; visible: root.view === "statcast" }
        SeasonTab { panel: root; width: parent.width; visible: root.view === "season" }

        // Error footer
        Text {
          textFormat: Text.PlainText
          visible: root.lastError !== "" && root.schedule.games.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Couldn't load (" + root.lastError + ") — press r to retry"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
        }
        }
      }
    }
  }
}
