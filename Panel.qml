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

  // Popup tab: bracket | games | statcast | season.
  property string view: "bracket"
  property bool viewPinned: false

  // ---- Data (reassigned wholesale so bindings re-evaluate) ---------------
  property var schedule: ({ games: [], live: [], upcoming: [], today: [] })
  property var series: []
  property var bracketLayout: ({ cards: [], lines: [], width: 0, height: 0 })
  property var seasons: ({})          // year -> parsed season calendar
  property var standings: null        // teamId -> standings row
  property int standingsYear: 0
  property bool standingsLoaded: false
  property var feed: null             // parsed focus-game feed (Statcast etc)
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
  readonly property bool notifyOn: boolSetting("notifyFavorite", false)

  function openFromHotkey() { open() }

  // ---- Remote data hygiene ----------------------------------------------
  // Two ceilings rather than one: curl refuses to download more than the cap,
  // and parseBounded rejects anything that got past it — a chunked response
  // has no Content-Length for curl to check.
  readonly property int maxFeedBytes: 5242880
  readonly property int maxPlainBytes: 1048576

  function fetchArgs(seconds, url, cap) {
    // -q must come first: without it curl reads ~/.curlrc, which could add a
    // proxy, an output file, or --insecure to an otherwise fixed request.
    return ["curl", "-q", "-fsS", "-A", ua,
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
        host !== "baseballsavant.mlb.com") return
    if (raw.length > 400) return
    Qt.openUrlExternally(raw)
  }

  function gamedayUrl(pk) {
    var n = parseInt(pk, 10)
    if (!isFinite(n) || n <= 0) return ""
    return "https://www.mlb.com/gameday/" + n
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
  property var procGen: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var pendingCmd: [null, null, null, null, null, null, null, null, null, null, null, null]
  property var guardStarted: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  readonly property var guardedProcs: [schedProc, bracketProc, seasonProc,
                                       season2Proc, standProc, feedProc,
                                       espnProc, polyProc, kalshiProc, probProc,
                                       teamStatsProc, leadersProc]
  readonly property var guardLimits: [12, 12, 10, 10, 14, 20, 18, 18, 18, 20, 20, 16]

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
      "&endDate=" + ymd(end) + "&hydrate=linescore,decisions"))
  }

  function fetchBracket() {
    loadingBracket = true
    launch(1, fetchArgs(12, base + "schedule/postseason?sportId=1&season=" +
      new Date().getFullYear()))
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
    launch(7, oddsArgs("poly-ws-" + thisYear, "poly",
      "https://gamma-api.polymarket.com/events?slug=mlb-world-series-champion-" + thisYear))
  }

  function fetchKalshiOdds() {
    var yy = String(thisYear).slice(2)
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
    var y = thisYear
    var h = base + "teams/stats?season=" + y + "&group=hitting&sportId=1"
    var p = base + "teams/stats?season=" + y + "&group=pitching&sportId=1"
    var script = "curl -q -fsS -A \"omarchy-mlb/0.1\" --proto \"=https\" --max-time 15 --max-filesize " + maxPlainBytes +
                 " \"" + h + "\"; echo ----SPLIT----; curl -q -fsS -A \"omarchy-mlb/0.1\" --proto \"=https\" --max-time 15 --max-filesize " + maxPlainBytes +
                 " \"" + p + "\""
    launch(10, ["/bin/bash", "-c", script])
  }

  function fetchLeaders() {
    launch(11, fetchArgs(12,
      base + "stats/leaders?leaderCategories=" + Mlb.LEADER_ORDER.join(",") +
      "&season=" + thisYear + "&sportId=1&limit=5"))
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
  // The bracket moves on a schedule of its own (a series wraps, the next
  // round gains teams) — 15 minutes is plenty once it has loaded.
  Timer { interval: 900000; repeat: true; onTriggered: root.fetchBracket() }
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
  // Statcast only while the popup is showing it and the game is running.
  Timer {
    interval: 20000
    repeat: true
    running: root.opened && root.feedLive && (root.view === "games" || root.view === "statcast")
    onTriggered: root.fetchFeed()
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
          var parsed = root.parseBounded(text, root.maxPlainBytes)
          if (!parsed) return
          var next = Mlb.parseSchedule(parsed)
          // Capture the live→final flip against the still-current schedule
          // so Statcast keeps the just-ended game's numbers for holdMs.
          var endedPk = Mlb.detectFinalTransition(root.focusGame, next.games)
          if (endedPk > 0) {
            root.holdPk = endedPk
            root.holdUntil = Date.now() + root.holdMs
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
          root.series = arr
          root.bracketLayout = Mlb.buildBracketLayout(arr)
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
  }
  readonly property bool feedLive: feed !== null && feed.mode === "Live"
  readonly property int thisYear: new Date(nowMs).getFullYear()

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

  // The World Series winner, once decided.
  function champion() {
    for (var i = 0; i < series.length; i++) {
      var s = series[i]
      if (s.round === "WS" && s.clinched !== null) {
        for (var j = 0; j < s.games.length; j++) {
          var g = s.games[j]
          if (g.away.id === s.clinched) return { name: g.away.name, abbr: g.away.abbr }
          if (g.home.id === s.clinched) return { name: g.home.name, abbr: g.home.abbr }
        }
        return { name: "", abbr: "" }
      }
    }
    return null
  }

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
    var m = nextMilestone()
    if (m) return glyph + " " + m.short + " " + fmtShort(m.ms - nowMs)
    return glyph + " MLB"
  }

  readonly property string label: safeBare(rawLabel, 36)

  // The tooltip renders in Text elements the shell owns, so the markup
  // boundary goes on the finished string.
  readonly property string tooltip: safeBareLines(rawTooltip, 84, 6)

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
    if (champ) lines.push("World Series champions: " + champ.name)
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
    if (view === "season") ensureStandings()
    if (view === "games" || view === "statcast") ensureFeed(false)
  }

  onOpenedChanged: {
    if (opened) {
      fetchSchedule()
      fetchOdds()
      // Opening the panel is also a retry opportunity: a fetch that failed at
      // startup would otherwise sit empty until its next interval.
      if (series.length === 0) fetchBracket()
      if (Object.keys(seasons).length === 0) fetchSeasons()
      ensureFeed(true)
      if (view === "season") ensureStandings()
      if (teamStatsRows.length === 0) fetchTeamStats()
      if (leaders.length === 0) fetchLeaders()
    }
  }

  // The default tab follows the setting until the user picks a tab themselves
  // (viewPinned). A one-shot latch doesn't work: `settings` arrives before its
  // values are populated, so a latch reads the fallback and sticks to it.
  onSettingsChanged: {
    if (viewPinned || !settings) return
    var t = String(setting("defaultTab", "bracket"))
    if (t === "games" || t === "statcast" || t === "season" ||
        t === "odds" || t === "bracket") view = t
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
      // Arrow keys scroll the panel body when a tab overflows the card.
      onMoveRequested: function(dx, dy) {
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
              color: Color.accent
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
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
                font.letterSpacing: Style.space(1)
              }
            }
            Text {
              visible: root.champion() !== null
              textFormat: Text.PlainText
              text: root.trophy
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: {
                var champ = root.champion()
                if (champ) return champ.abbr + " " + root.thisYear
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
            { value: "bracket", label: "Bracket" },
            { value: "games", label: "Games" },
            { value: "statcast", label: "Statcast" },
            { value: "odds", label: "Odds" },
            { value: "season", label: "Season" }
          ]
          value: root.view
          focusable: false
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontSize: Style.space(12)
          onChanged: function(v) { root.viewPinned = true; root.view = v }
        }

        BracketTab { panel: root; width: parent.width; visible: root.view === "bracket" }
        OddsTab { panel: root; width: parent.width; visible: root.view === "odds" }
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
