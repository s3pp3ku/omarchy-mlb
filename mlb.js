// Data layer for the MLB widget. Pure functions with no QML/Qt dependencies so
// they can be exercised under node against live API payloads (tools/test-mlb.js).

var TEAMS = {
  108: { abbr: "LAA", color: "#BA0021", name: "Los Angeles Angels", lg: "AL" },
  109: { abbr: "AZ", color: "#A71930", name: "Arizona Diamondbacks", lg: "NL" },
  110: { abbr: "BAL", color: "#DF4601", name: "Baltimore Orioles", lg: "AL" },
  111: { abbr: "BOS", color: "#BD3039", name: "Boston Red Sox", lg: "AL" },
  112: { abbr: "CHC", color: "#3E6BD4", name: "Chicago Cubs", lg: "NL" },
  113: { abbr: "CIN", color: "#C6011F", name: "Cincinnati Reds", lg: "NL" },
  114: { abbr: "CLE", color: "#E31937", name: "Cleveland Guardians", lg: "AL" },
  115: { abbr: "COL", color: "#7C50C8", name: "Colorado Rockies", lg: "NL" },
  116: { abbr: "DET", color: "#F26522", name: "Detroit Tigers", lg: "AL" },
  117: { abbr: "HOU", color: "#EB6E1F", name: "Houston Astros", lg: "AL" },
  118: { abbr: "KC", color: "#1D63C4", name: "Kansas City Royals", lg: "AL" },
  119: { abbr: "LAD", color: "#1E73C8", name: "Los Angeles Dodgers", lg: "NL" },
  120: { abbr: "WSH", color: "#C1273D", name: "Washington Nationals", lg: "NL" },
  121: { abbr: "NYM", color: "#FF5910", name: "New York Mets", lg: "NL" },
  133: { abbr: "ATH", color: "#0E9F6E", name: "Athletics", lg: "AL" },
  134: { abbr: "PIT", color: "#FDB827", name: "Pittsburgh Pirates", lg: "NL" },
  135: { abbr: "SD", color: "#D4A74E", name: "San Diego Padres", lg: "NL" },
  136: { abbr: "SEA", color: "#00A79A", name: "Seattle Mariners", lg: "AL" },
  137: { abbr: "SF", color: "#FD5A1E", name: "San Francisco Giants", lg: "NL" },
  138: { abbr: "STL", color: "#C41E3A", name: "St. Louis Cardinals", lg: "NL" },
  139: { abbr: "TB", color: "#62B1E8", name: "Tampa Bay Rays", lg: "AL" },
  140: { abbr: "TEX", color: "#2B62C4", name: "Texas Rangers", lg: "AL" },
  141: { abbr: "TOR", color: "#1D6FD1", name: "Toronto Blue Jays", lg: "AL" },
  142: { abbr: "MIN", color: "#D31145", name: "Minnesota Twins", lg: "AL" },
  143: { abbr: "PHI", color: "#E81828", name: "Philadelphia Phillies", lg: "NL" },
  144: { abbr: "ATL", color: "#CE1141", name: "Atlanta Braves", lg: "NL" },
  145: { abbr: "CWS", color: "#B9BEC4", name: "Chicago White Sox", lg: "AL" },
  146: { abbr: "MIA", color: "#00A3E0", name: "Miami Marlins", lg: "NL" },
  147: { abbr: "NYY", color: "#2E4F94", name: "New York Yankees", lg: "AL" },
  158: { abbr: "MIL", color: "#FFC52F", name: "Milwaukee Brewers", lg: "NL" }
};

function teamRef(id, name) {
  var t = TEAMS[id];
  var placeholder = !t && /Seed|League Champion/i.test(name || "");
  return {
    id: id,
    abbr: t ? t.abbr : (placeholder ? "TBD" : (name || "?")),
    name: name || "",
    color: t ? t.color : "#7A7A7A",
    placeholder: !t
  };
}

// Schedule/game payloads spell scores two different ways depending on state:
// `teams.<side>.score` once a game is live/final, `linescore.teams.<side>.runs`
// only inside the hydrated linescore. Try both so rows never render "?" while a
// number is sitting one key away.
function parseGame(g) {
  if (!g || !g.teams || !g.teams.away) return null;
  var ls = g.linescore || {};
  var status = g.status || {};
  var state = status.abstractGameState || "Preview";
  var mode = state === "Live" ? "live" : (state === "Final" ? "final" : "preview");

  function side(s, key) {
    var r = teamRef(s.team ? s.team.id : 0, s.team ? s.team.name : "");
    var sc = typeof s.score === "number" ? s.score : null;
    if (sc === null && ls.teams && ls.teams[key] && typeof ls.teams[key].runs === "number")
      sc = ls.teams[key].runs;
    r.score = sc;
    return r;
  }

  var dec = g.decisions || {};
  var startMs = Date.parse(g.gameDate || "");
  return {
    gamePk: g.gamePk,
    gameType: g.gameType || "",
    officialDate: g.officialDate || "",
    startMs: isNaN(startMs) ? 0 : startMs,
    mode: mode,
    detail: status.detailedState || "",
    desc: g.description || "",
    seriesDesc: g.seriesDescription || "",
    away: side(g.teams.away, "away"),
    home: side(g.teams.home, "home"),
    inning: typeof ls.currentInning === "number" ? ls.currentInning : null,
    inningState: ls.inningState || "",
    isTop: ls.isTopInning === true,
    outs: typeof ls.outs === "number" ? ls.outs : null,
    balls: typeof ls.balls === "number" ? ls.balls : null,
    strikes: typeof ls.strikes === "number" ? ls.strikes : null,
    winnerName: dec.winner ? dec.winner.fullName : "",
    loserName: dec.loser ? dec.loser.fullName : "",
    saveName: dec.save ? dec.save.fullName : "",
    venue: g.venue ? g.venue.name : ""
  };
}

function flatGames(payload) {
  var out = [];
  var dates = (payload && payload.dates) || [];
  for (var i = 0; i < dates.length; i++) {
    var games = dates[i].games || [];
    for (var j = 0; j < games.length; j++) {
      var g = parseGame(games[j]);
      if (g) out.push(g);
    }
  }
  out.sort(function(a, b) { return a.startMs - b.startMs; });
  return out;
}

// ---- Full-season stats (Statcast tab season sections) ------------------------
// stats API groups hitting and pitching as separate calls; this merges one row
// per team: record from pitching splits, runs scored/allowed per game, rate
// lines. Teams are joined to the shared TEAMS table for abbr/color.
function parseTeamStats(hittingPayload, pitchingPayload) {
  var byId = {}
  function touch(id, name) {
    if (!byId[id])
      byId[id] = { id: id,
                   abbr: TEAMS[id] ? TEAMS[id].abbr : "",
                   name: TEAMS[id] ? TEAMS[id].name : (name || ""),
                   color: TEAMS[id] ? TEAMS[id].color : "#7A7A7A" }
    return byId[id]
  }
  function ingest(payload, kind) {
    var groups = (payload && payload.stats) || []
    for (var i = 0; i < groups.length; i++) {
      var splits = groups[i].splits || []
      for (var j = 0; j < splits.length; j++) {
        var s = splits[j]
        var id = s.team && s.team.id
        if (!id) continue
        var r = touch(id, s.team.name)
        var st = s.stat || {}
        if (kind === "hitting") {
          r.games = st.gamesPlayed | 0
          r.runsScored = st.runs | 0
          r.homeRuns = st.homeRuns | 0
          r.rbi = st.rbi | 0
          r.avg = st.avg || ""
          r.obp = st.obp || ""
          r.slg = st.slg || ""
          r.stolenBases = st.stolenBases | 0
        } else {
          r.wins = st.wins | 0
          r.losses = st.losses | 0
          r.runsAllowed = st.runs | 0
          r.era = st.era || ""
          r.whip = st.whip || ""
          r.strikeOuts = st.strikeOuts | 0
          r.baseOnBalls = st.baseOnBalls | 0
        }
      }
    }
  }
  ingest(hittingPayload, "hitting")
  ingest(pitchingPayload, "pitching")
  var rows = []
  for (var k in byId) rows.push(byId[k])
  rows.forEach(function(r) {
    var g = r.games || 0
    r.record = (r.wins | 0) + "-" + (r.losses | 0)
    r.runsPer = g ? (r.runsScored / g).toFixed(1) : "\u2014"
    r.againstPer = g ? (r.runsAllowed / g).toFixed(1) : "\u2014"
    r.runDiff = (r.runsScored | 0) - (r.runsAllowed | 0)
  })
  rows.sort(function(a, b) { return (b.wins - a.wins) || (b.runDiff - a.runDiff) })
  return rows
}

// Leader categories come back duplicated across stat groups (hitters / pitchers
// batting / catchers...). Keep the canonical split for each: hitting stats for
// hitters, pitching stats for pitchers.
var LEADER_ORDER = ["battingAverage", "homeRuns", "runsBattedIn", "wins", "earnedRunAverage", "strikeOuts"]
var LEADER_LABELS = { battingAverage: "BATTING AVG", homeRuns: "HOME RUNS",
                      runsBattedIn: "RBI", wins: "PITCHER WINS",
                      earnedRunAverage: "PITCHER ERA", strikeOuts: "STRIKEOUTS" }
function parseLeaders(payload) {
  var WANT = { battingAverage: "hitting", homeRuns: "hitting", runsBattedIn: "hitting",
               wins: "pitching", earnedRunAverage: "pitching", strikeOuts: "pitching" }
  var byCat = {}
  var groups = (payload && payload.leagueLeaders) || []
  for (var i = 0; i < groups.length; i++) {
    var L = groups[i]
    var g = WANT[L.leaderCategory]
    if (!g || L.statGroup !== g) continue
    byCat[L.leaderCategory] = (L.leaders || []).slice(0, 5).map(function(e) {
      return { rank: e.rank, value: e.value === null || e.value === undefined ? "" : String(e.value),
               name: e.person && e.person.fullName ? e.person.fullName : "",
               team: e.team && e.team.name ? e.team.name : "" }
    })
  }
  var out = []
  for (i = 0; i < LEADER_ORDER.length; i++) {
    var key = LEADER_ORDER[i]
    if (byCat[key] && byCat[key].length)
      out.push({ key: key, label: LEADER_LABELS[key], rows: byCat[key] })
  }
  return out
}

// One-line book line for a game object's odds, minus the leading provider
// name (formatOdds starts "DraftKings · ...").
function oddsLine(b) {
  var s = formatOdds(b)
  var i = s.indexOf(" \u00B7 ")
  return i < 0 ? s : s.slice(i + 3)
}

function parseSchedule(payload) {
  var games = flatGames(payload);
  var live = [], today = [], upcoming = [];
  for (var i = 0; i < games.length; i++) {
    var g = games[i];
    if (g.mode === "live") live.push(g);
    if (g.mode !== "final") upcoming.push(g);
    if (g.mode !== "final" || isToday(g.startMs)) today.push(g);
  }
  return { games: games, live: live, upcoming: upcoming, today: today };
}

function isToday(ms) {
  if (!ms) return false;
  var d = new Date(ms), n = new Date();
  return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() &&
         d.getDate() === n.getDate();
}

function seriesKey(desc) {
  return String(desc || "").replace(/\s*Game\s*\d+.*$/, "");
}

// "NLDS 'A' Game 2" → "NLDS Game 2"; "World Series Game 3" stays put.
function compactDesc(desc) {
  return String(desc || "").replace(/'([A-Z])'\s*/, "").replace(/\s+/g, " ").trim();
}

// Even shorter for the bar pill: "NLDS G2".
function pillDesc(desc) {
  return compactDesc(desc).replace(/\bGame\s/g, "G");
}

var ROUND_BY_TYPE = { F: "WC", D: "DS", L: "CS", W: "WS" };
var THRESHOLD = { WC: 2, DS: 3, CS: 4, WS: 4 };

function buildSeries(key, games) {
  games.sort(function(a, b) { return a.startMs - b.startMs; });
  var g0 = games[0];
  var round = ROUND_BY_TYPE[g0.gameType] || "OTHER";
  var lm = /^([AN]L)/.exec(g0.desc || g0.seriesDesc || "");
  var league = lm ? lm[1] : "MLB";
  var sm = /'([A-Z])'/.exec(key);
  var slot = sm ? sm[1] : "";
  var threshold = THRESHOLD[round] || 4;

  var wins = {};
  for (var i = 0; i < games.length; i++) {
    var g = games[i];
    if (g.mode === "final" && g.away.score !== null && g.home.score !== null) {
      var wid = g.away.score > g.home.score ? g.away.id : g.home.id;
      wins[wid] = (wins[wid] || 0) + 1;
    }
  }
  var clinched = null;
  for (var id in wins) {
    if (wins[id] >= threshold) clinched = Number(id);
  }

  var mode = "final", nextGame = null;
  for (i = 0; i < games.length; i++) {
    if (games[i].mode === "live") { mode = "live"; nextGame = null; break; }
    if (games[i].mode !== "final") {
      mode = "preview";
      if (!nextGame) nextGame = games[i];
    }
  }

  // Participants in bracket order: first game's home side is the higher seed in
  // every MLB playoff series (hosts Games 1-2), so it leads the card.
  var teams = [g0.home, g0.away];
  var real = [];
  for (i = 0; i < games.length; i++) {
    for (var s = 0; s < 2; s++) {
      var t = (s === 0 ? games[i].away : games[i].home);
      if (!t.placeholder && real.indexOf(t.id) < 0) real.push(t.id);
    }
  }

  var r = { WC: "WC", DS: "DS", CS: "CS" }[round];
  var label = round === "WS" ? "World Series"
            : (r ? league + " " + r + (slot ? " " + slot : "") : key);

  return {
    key: key, round: round, league: league, slot: slot, label: label,
    games: games, wins: wins, threshold: threshold, clinched: clinched,
    mode: mode, nextGame: nextGame, teams: teams, realTeams: real
  };
}

function parsePostseason(payload) {
  var games = flatGames(payload);
  var order = [], byKey = {};
  for (var i = 0; i < games.length; i++) {
    var key = seriesKey(games[i].desc || games[i].seriesDesc || ("game" + i));
    if (!byKey[key]) { byKey[key] = []; order.push(key); }
    byKey[key].push(games[i]);
  }
  var out = [];
  for (i = 0; i < order.length; i++) {
    var s = buildSeries(order[i], byKey[order[i]]);
    if (s.round !== "OTHER") out.push(s);
  }
  var rank = { WC: 0, DS: 1, CS: 2, WS: 3 };
  out.sort(function(a, b) {
    var d = (rank[a.round] || 9) - (rank[b.round] || 9);
    if (d !== 0) return d;
    if (a.league !== b.league) return a.league === "AL" ? -1 : 1;
    return a.slot < b.slot ? -1 : 1;
  });
  return out;
}

// Matchup chips for the Statcast tab. Every game in the schedule window is
// reachable — live first, then today's slate chronological, then the most
// recent finished games (so previous games' statcast can be reviewed), then
// upcoming games. Past finals are capped at 6 so the recent games stay
// first; total cap keeps the chip row to two wrapped lines.
function selectorGames(games, max) {
  if (!games || !games.length) return []
  var cap = max || 12
  var live = [], todays = [], past = [], future = []
  for (var i = 0; i < games.length; i++) {
    var g = games[i]
    if (g.mode === "live") live.push(g)
    else if (isToday(g.startMs)) todays.push(g)
    else if (g.mode === "final") past.push(g)
    else future.push(g)
  }
  function byTime(a, b) { return a.startMs - b.startMs }
  live.sort(byTime)
  todays.sort(byTime)
  future.sort(byTime)
  // Most recent first: yesterday's games are the ones to review.
  past.sort(function(a, b) { return b.startMs - a.startMs })
  past = past.slice(0, 6)
  return live.concat(todays, past, future).slice(0, cap)
}

// If the game we were following just flipped live → final, return its pk so
// the caller can pin it briefly — otherwise Statcast blanks the instant the
// last out lands instead of keeping the final numbers up.
function detectFinalTransition(prevGame, games) {
  if (!prevGame || prevGame.mode !== "live" || !games) return -1
  for (var i = 0; i < games.length; i++) {
    var g = games[i]
    if (g.gamePk === prevGame.gamePk && g.mode === "final") return g.gamePk
  }
  return -1
}

// --- Bracket layout ---------------------------------------------------------
// Four fixed columns (WC, DS, CS, WS). Each league gets two stacked slot rows
// with its LCS centered between them; the leagues are separated by a gap that
// the World Series card straddles. Card positions are pure pixel math so the
// connector Canvas and the card Repeater agree on geometry without talking.
function buildBracketLayout(series) {
  // Sized for a ~640px panel: cards grow ~24% over the first pass so the
  // team abbrevs and series records read at a glance.
  var W = 124, H = 74, colGap = 30, vgap = 12, blockGap = 50;
  var colX = [0, W + colGap, 2 * (W + colGap), 3 * (W + colGap)];
  var yALa = 0, yALb = H + vgap;
  var yALcs = Math.round((yALa + yALb) / 2 + (H - H) / 2);
  yALcs = Math.round(((yALa + yALb + H) / 2) - H / 2);
  var yNLtop = yALb + H + blockGap;
  var yNLa = yNLtop, yNLb = yNLtop + H + vgap;
  var yNLcs = Math.round(((yNLa + yNLb + H) / 2) - H / 2);
  var yWS = Math.round(((yALcs + yNLcs + H) / 2) - H / 2);

  var byRoundSlot = {};
  for (var i = 0; i < series.length; i++) {
    var s = series[i];
    byRoundSlot[s.league + s.round + (s.slot || "")] = s;
  }

  function find(league, round, slot) { return byRoundSlot[league + round + (slot || "")]; }
  function slotY(league, slot) {
    if (league === "AL") return slot === "B" ? yALb : yALa;
    return slot === "B" ? yNLb : yNLa;
  }

  var cards = [];
  function push(s, col, x, y) {
    if (s) cards.push({ series: s, x: x, y: y, w: W, h: H, col: col });
  }

  // Column 0/1: WC and DS by league+slot. WC cards align to their slot's DS
  // row (crossed connectors handled by the line pass below).
  ["AL", "NL"].forEach(function(league) {
    ["A", "B"].forEach(function(slot) {
      push(find(league, "WC", slot), 0, colX[0], slotY(league, slot));
      push(find(league, "DS", slot), 1, colX[1], slotY(league, slot));
    });
    push(find(league, "CS", ""), 2, colX[2], league === "AL" ? yALcs : yNLcs);
  });
  var ws = series.filter(function(s) { return s.round === "WS"; })[0];
  push(ws, 3, colX[3], yWS);

  var byId = {};
  for (i = 0; i < cards.length; i++) byId[cards[i].series.key] = cards[i];

  function cy(card) { return card.y + H / 2; }
  function elbow(x1, y1, x2, y2) {
    if (Math.abs(y1 - y2) < 1) return [{ x: x1, y: y1 }, { x: x2, y: y2 }];
    var mid = Math.round((x1 + x2) / 2);
    return [{ x: x1, y: y1 }, { x: mid, y: y1 }, { x: mid, y: y2 }, { x: x2, y: y2 }];
  }

  var lines = [];
  // WC → DS: only once the WC winner is known and sits in a DS card, so the
  // line is drawn from reality instead of a guessed slot letter.
  series.forEach(function(s) {
    if (s.round !== "WC" || s.clinched === null) return;
    var wcCard = byId[s.key];
    if (!wcCard) return;
    series.forEach(function(ds) {
      if (ds.round !== "DS" || ds.league !== s.league) return;
      if (ds.realTeams.indexOf(s.clinched) < 0) return;
      var dsCard = byId[ds.key];
      if (dsCard)
        lines.push(elbow(wcCard.x + W, cy(wcCard), dsCard.x, cy(dsCard)));
    });
  });
  // DS → LCS and LCS → WS are structural: those slots always feed forward.
  ["AL", "NL"].forEach(function(league) {
    var cs = find(league, "CS", "");
    var csCard = cs ? byId[cs.key] : null;
    ["A", "B"].forEach(function(slot) {
      var ds = find(league, "DS", slot);
      var card = ds ? byId[ds.key] : null;
      if (card && csCard)
        lines.push(elbow(card.x + W, cy(card), csCard.x, cy(csCard)));
    });
    if (csCard && ws) {
      var wsCard = byId[ws.key];
      if (wsCard) lines.push(elbow(csCard.x + W, cy(csCard), wsCard.x, cy(wsCard)));
    }
  });

  // Flatten the polylines into ready-to-render axis-aligned rectangles so the
  // QML side needs no nested repeaters or paint hooks: [{x,y,w,h}].
  var segs = [];
  for (var li = 0; li < lines.length; li++) {
    var pts = lines[li];
    for (var pi = 1; pi < pts.length; pi++) {
      var a = pts[pi - 1], b = pts[pi];
      if (Math.abs(a.y - b.y) < 0.5)
        segs.push({ x: Math.min(a.x, b.x), y: a.y - 1,
                    w: Math.abs(b.x - a.x) + 1, h: 2 });
      else if (Math.abs(a.x - b.x) < 0.5)
        segs.push({ x: a.x - 1, y: Math.min(a.y, b.y),
                    w: 2, h: Math.abs(b.y - a.y) + 1 });
      else
        segs.push({ x: Math.min(a.x, b.x), y: Math.min(a.y, b.y),
                    w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) });
    }
    // Square the elbow corners so the two runs join cleanly.
    for (pi = 1; pi < pts.length - 1; pi++) {
      var v = pts[pi];
      segs.push({ x: v.x - 1, y: v.y - 1, w: 3, h: 3 });
    }
  }

  return { cards: cards, lines: lines, segs: segs,
           width: colX[3] + W, height: yNLb + H };
}

// --- Live game feed ---------------------------------------------------------
// One feed carries the count, the runners, the last play *and* the Statcast
// tracking fields (hitData / pitchData) — the same numbers Baseball Savant
// charts — so the Statcast tab needs no extra request.
function parseFeed(payload) {
  var ld = (payload && payload.liveData) || {};
  var gd = (payload && payload.gameData) || {};
  var ls = ld.linescore || {};
  var plays = (ld.plays && ld.plays.allPlays) || [];
  var off = ls.offense || {};

  // One pass collects every Statcast number the panel shows: exit-velo
  // leaderboard, longest ball, pitch-speed leaderboard, average/hard-hit
  // rates, and the K/HR tallies. All bounded (120 plays x 40 events).
  var topHits = [], topPitches = [], longest = null;
  var evSum = 0, evN = 0, hardHits = 0, pitches = 0, homeRuns = 0, strikeouts = 0;
  var cap = Math.min(plays.length, 120);
  for (var i = 0; i < cap; i++) {
    var p = plays[i];
    // Which side was batting on this play: top of inning = away batting,
    // bottom = home batting. Used to chip-color topHits/longest rows.
    var side = p.about && p.about.isTopInning === true ? "away" : "home";
    var res = p.result;
    if (res && res.eventType === "home_run") homeRuns++;
    else if (res && res.eventType === "strikeout") strikeouts++;
    var evs = p.playEvents || [];
    var ecap = Math.min(evs.length, 40);
    for (var j = 0; j < ecap; j++) {
      var ev = evs[j];
      var hd = ev.hitData;
      if (hd && typeof hd.launchSpeed === "number") {
        var batter = p.matchup && p.matchup.batter ? p.matchup.batter.fullName : "";
        var dist = typeof hd.totalDistance === "number" ? hd.totalDistance : 0;
        topHits.push({
          ev: hd.launchSpeed,
          dist: dist,
          player: batter,
          desc: res ? res.description : "",
          side: side
        });
        evSum += hd.launchSpeed;
        evN++;
        if (hd.launchSpeed >= 95) hardHits++;
        if (!longest || dist > longest.dist)
          longest = { ev: hd.launchSpeed, dist: dist, player: batter, side: side };
      }
      var pd = ev.pitchData;
      if (pd && typeof pd.startSpeed === "number") {
        pitches++;
        topPitches.push({
          speed: pd.startSpeed,
          pitcher: p.matchup && p.matchup.pitcher ? p.matchup.pitcher.fullName : "",
          side: side === "away" ? "home" : "away"
        });
      }
    }
  }
  topHits.sort(function(a, b) { return b.ev - a.ev; });
  topHits = topHits.slice(0, 5);
  topPitches.sort(function(a, b) { return b.speed - a.speed; });
  topPitches = topPitches.slice(0, 3);
  var fastest = topPitches.length ? topPitches[0] : null;

  var lastPlay = "";
  if (plays.length) {
    var lp = plays[plays.length - 1];
    lastPlay = lp.result ? (lp.result.description || "") : "";
  }

  var cur = ld.plays && ld.plays.currentPlay ? ld.plays.currentPlay : null;
  var count = cur && cur.count ? cur.count : null;

  function num(v) { return typeof v === "number" ? v : null; }
  function rhe(side) {
    var t = ls.teams && ls.teams[side];
    return t ? { r: num(t.runs), h: num(t.hits), e: num(t.errors) } : { r: null, h: null, e: null };
  }
  var pp = gd.probablePitchers || {};

  return {
    mode: (gd.status || {}).abstractGameState || "",
    inning: num(ls.currentInning),
    inningState: ls.inningState || "",
    isTop: ls.isTopInning === true,
    outs: num(ls.outs),
    balls: num(ls.balls),
    strikes: num(ls.strikes),
    awayRHE: rhe("away"),
    homeRHE: rhe("home"),
    awayProbable: pp.away ? pp.away.fullName : "",
    homeProbable: pp.home ? pp.home.fullName : "",
    awayRuns: ls.teams && ls.teams.away ? num(ls.teams.away.runs) : null,
    homeRuns: ls.teams && ls.teams.home ? num(ls.teams.home.runs) : null,
    batter: off.batter ? off.batter.fullName : "",
    pitcher: off.pitcher ? off.pitcher.fullName : "",
    on1: !!off.first, on2: !!off.second, on3: !!off.third,
    count: count ? { balls: count.balls, strikes: count.strikes } : null,
    lastPlay: lastPlay,
    topHits: topHits,
    topPitches: topPitches,
    fastest: fastest,
    longest: longest,
    avgEv: evN ? Math.round(evSum / evN * 10) / 10 : 0,
    batted: evN,
    hardHits: hardHits,
    pitches: pitches,
    homeRuns: homeRuns,
    strikeouts: strikeouts
  };
}

// --- Season calendar --------------------------------------------------------
function parseSeason(payload) {
  var s = payload && payload.seasons && payload.seasons[0];
  if (!s) return null;
  function day(str) {
    if (!str) return 0;
    var t = Date.parse(str + "T12:00:00");
    return isNaN(t) ? 0 : t;
  }
  return {
    year: Number(s.seasonId),
    springMs: day(s.springStartDate),
    openingMs: day(s.regularSeasonStartDate),
    allStarMs: day(s.allStarDate),
    postseasonMs: day(s.postSeasonStartDate),
    regularEndMs: day(s.regularSeasonEndDate),
    postseasonEndMs: day(s.postSeasonEndDate)
  };
}

// MLB division ids are not a neat 201-206 run: AL West is 200 and NL West
// is 203. Verified against /api/v1/standings.
var DIVISION_NAMES = {
  200: "AL West", 201: "AL East", 202: "AL Central",
  203: "NL West", 204: "NL East", 205: "NL Central"
};

function parseStandings(payload) {
  var byTeam = {};
  var records = (payload && payload.records) || [];
  for (var i = 0; i < records.length; i++) {
    var leagueId = records[i].league ? records[i].league.id : 0;
    var divId = records[i].division ? records[i].division.id : 0;
    var trs = records[i].teamRecords || [];
    for (var j = 0; j < trs.length; j++) {
      var tr = trs[j];
      if (!tr.team) continue;
      byTeam[tr.team.id] = {
        id: tr.team.id,
        name: tr.team.name || "",
        wins: tr.wins | 0,
        losses: tr.losses | 0,
        pct: tr.winningPercentage || "",
        gb: tr.gamesBack === undefined || tr.gamesBack === null ? "-" : String(tr.gamesBack),
        streak: tr.streak && tr.streak.streakCode ? String(tr.streak.streakCode) : "",
        rank: tr.divisionRank ? parseInt(tr.divisionRank, 10) || 0 : 0,
        champ: tr.divisionRank === "1",
        leagueId: leagueId,
        division: DIVISION_NAMES[divId] || ""
      };
    }
  }
  return byTeam;
}

// The playoff field is the union of WC + DS participants (12 teams: 8 wild-card
// entrants plus the four division winners that drew byes into the DS).
function playoffField(series) {
  var ids = {};
  for (var i = 0; i < series.length; i++) {
    var s = series[i];
    if (s.round === "WC" || s.round === "DS") {
      for (var j = 0; j < s.realTeams.length; j++) ids[s.realTeams[j]] = true;
    }
  }
  return Object.keys(ids).map(Number);
}

// --- Bar pill ---------------------------------------------------------------
// Priority: favorite team live → any live → favorite team today → next game in
// the fetched window → spring-training countdown when the slate is empty.
function pickPillGame(schedule, favoriteAbbr) {
  var fav = String(favoriteAbbr || "").toUpperCase().trim();
  function involves(g) {
    if (!fav) return false;
    return g.away.abbr === fav || g.home.abbr === fav;
  }
  function pick(list) {
    for (var i = 0; i < list.length; i++) if (involves(list[i])) return list[i];
    return list.length ? list[0] : null;
  }
  return pick(schedule.live) || pick(schedule.upcoming) || null;
}

// The favorite team's full standings row, resolved by 3-letter abbr.
// Returns {id,name,abbr,color,division,wins,losses,pct,gb,streak,rank,champ}
// or null when the abbr matches nothing (bad setting, or standings not loaded).
function teamFocus(standings, abbr) {
  if (!standings || !abbr) return null
  var want = String(abbr).toUpperCase().trim()
  for (var id in standings) {
    var row = standings[id]
    var ref = teamRef(Number(id), row.name)
    if (ref.abbr !== want) continue
    return {
      id: row.id, name: row.name, abbr: ref.abbr, color: ref.color,
      division: row.division, wins: row.wins, losses: row.losses,
      pct: row.pct, gb: row.gb, streak: row.streak, rank: row.rank,
      champ: row.champ
    }
  }
  return null
}

// Every team in one division, best record first — the Season tab's full
// division table with the favorite highlighted.
function divisionTable(standings, division) {
  var out = []
  if (!standings) return out
  for (var id in standings) {
    var row = standings[id]
    if (row.division !== division) continue
    var ref = teamRef(Number(id), row.name)
    out.push({
      id: row.id, name: row.name, abbr: ref.abbr, color: ref.color,
      wins: row.wins, losses: row.losses, pct: row.pct, gb: row.gb,
      streak: row.streak, rank: row.rank, champ: row.champ
    })
  }
  out.sort(function(a, b) { return (a.rank || 99) - (b.rank || 99) })
  return out
}

// The team's upcoming (not-yet-final) games from the schedule window,
// earliest first.
function teamNextGames(games, abbr, limit) {
  var out = []
  if (!games || !abbr) return out
  var want = String(abbr).toUpperCase().trim()
  for (var i = 0; i < games.length; i++) {
    var g = games[i]
    if (g.mode === "final") continue
    if (g.away.abbr !== want && g.home.abbr !== want) continue
    out.push(g)
    if (out.length >= (limit || 4)) break
  }
  return out
}

// Division winners as rows ready for the Season tab, in AL→NL league order.
function divisionChamps(standings, teamColor) {
  var order = ["AL East", "AL Central", "AL West", "NL East", "NL Central", "NL West"];
  var out = [];
  for (var id in standings) {
    var t = standings[id];
    if (!t.champ || !t.division) continue;
    var ref = teamRef(Number(id), "");
    out.push({
      division: t.division,
      abbr: ref.abbr,
      wins: t.wins,
      losses: t.losses,
      pct: t.pct,
      color: teamColor ? teamColor(Number(id)) : ref.color
    });
  }
  out.sort(function(a, b) { return order.indexOf(a.division) - order.indexOf(b.division); });
  return out;
}

// The picker shows one league at a time: 15 clubs per section, sorted by
// abbreviation.
function teamsByLeague(lg) {
  var out = []
  for (var id in TEAMS) {
    if (TEAMS[id].lg !== lg) continue
    out.push({ abbr: TEAMS[id].abbr, color: TEAMS[id].color })
  }
  out.sort(function(a, b) { return a.abbr < b.abbr ? -1 : 1 })
  return out
}

// League ("AL"/"NL") of a team abbreviation, or "" when unknown — used to
// preselect the picker section when a favorite is already set.
function leagueFor(abbr) {
  var want = String(abbr || "").toUpperCase().trim()
  for (var id in TEAMS)
    if (TEAMS[id].abbr === want) return TEAMS[id].lg
  return ""
}

// ---- Odds ----------------------------------------------------------------
// Three cheap sources, all fetched through odds.py (TTL + monthly cap):
//  - ESPN scoreboard: per-game DraftKings moneyline / run line / total
//  - Polymarket: World Series winner probabilities (Gamma API, by slug)
//  - Kalshi: World Series winner prices (trade-api v2, KXMLB-<yy>)

// ESPN scoreboard odds for one date. Keyed "AWAY@HOME" (same orientation as
// our schedule games) so lookup is a direct hit.
// ESPN's book feed abbreviates two clubs differently from the stats API
// that every other part of the widget uses. Key the odds map with the
// stats-side abbreviations so oddsFor() lookups by schedule abbr match.
var ESPN_ABBR = { CHW: "CWS", ARI: "AZ" }

function parseEspnOdds(payload) {
  var out = {}
  var events = (payload && payload.events) || []
  for (var i = 0; i < events.length; i++) {
    var comp = (events[i].competitions || [])[0]
    if (!comp) continue
    var book = (comp.odds || [])[0]
    if (!book) continue
    var away = "", home = ""
    var comps = comp.competitors || []
    for (var j = 0; j < comps.length; j++) {
      var c = comps[j]
      var abbr = c.team && c.team.abbreviation ? c.team.abbreviation : ""
      abbr = ESPN_ABBR[abbr] || abbr
      if (c.homeAway === "away") away = abbr
      else if (c.homeAway === "home") home = abbr
    }
    if (!away || !home) continue
    var ml = book.moneyline || {}
    function side(k) {
      var o = ml[k]
      if (!o) return null
      var v = (o.close && o.close.odds) || (o.open && o.open.odds)
      return v === undefined || v === null ? null : String(v)
    }
    // The vig ("juice") sits on the spread/total sub-objects; either close
    // or open line depending on whether the book has settled for the day.
    function juice(marketSide) {
      if (!marketSide) return null
      var v = (marketSide.close && marketSide.close.odds) ||
              (marketSide.open && marketSide.open.odds)
      return v === undefined || v === null ? null : String(v)
    }
    var ps = book.pointSpread || {}
    var tot = book.total || {}
    out[away + "@" + home] = {
      awayAbbr: away,
      homeAbbr: home,
      provider: book.provider && book.provider.name ? String(book.provider.name) : "",
      mlAway: side("away"),
      mlHome: side("home"),
      spread: typeof book.spread === "number" ? book.spread : null,
      spreadHome: !!(book.homeTeamOdds && book.homeTeamOdds.favorite),
      total: typeof book.overUnder === "number" ? book.overUnder : null,
      rlHome: juice(ps.home),
      rlAway: juice(ps.away),
      overOdds: juice(tot.over),
      underOdds: juice(tot.under)
    }
  }
  return out
}

// One-line odds summary for the focus card, or "" when nothing is usable:
//   "DraftKings · ML SD +148 · MIL -176 · RL MIL -1.5 · O/U 7.5"
function formatOdds(o) {
  if (!o) return ""
  var parts = []
  if (o.provider) parts.push(o.provider)
  if (o.mlAway && o.mlHome)
    parts.push("ML " + o.awayAbbr + " " + o.mlAway + " · " + o.homeAbbr + " " + o.mlHome)
  if (o.spread !== null && o.spread !== undefined) {
    // ESPN's spread is the home side's line; show the favorite's side.
    var fav = o.spreadHome ? o.homeAbbr : o.awayAbbr
    var line = o.spreadHome ? o.spread : -o.spread
    var rl = "RL " + fav + " " + (line > 0 ? "+" + line : String(line))
    var juice = o.spreadHome ? o.rlHome : o.rlAway
    if (juice) rl += " (" + juice + ")"
    parts.push(rl)
  }
  if (o.total !== null && o.total !== undefined) {
    var tot = "O/U " + o.total
    if (o.overOdds) tot += " (" + o.overOdds + (o.underOdds ? "/" + o.underOdds : "") + ")"
    parts.push(tot)
  }
  return parts.join(" · ")
}

// American moneyline odds -> implied probability, e.g. "-213" -> 0.68.
function americanProb(ml) {
  if (!ml) return null
  var n = parseFloat(String(ml).replace(/^\+/, ""))
  if (!isFinite(n) || n === 0) return null
  return n > 0 ? 100 / (n + 100) : Math.abs(n) / (Math.abs(n) + 100)
}

// Full team name -> abbreviation ("New York Yankees" -> NYY). Handles the
// two-word-prefix drift between books ("Sacramento Athletics" -> ATH) by
// falling back to a word-boundary suffix match.
function teamByName(name) {
  var norm = function(v) {
    return String(v || "").toLowerCase().replace(/[^a-z0-9 ]/g, " ")
      .replace(/\s+/g, " ").replace(/^the /, "").trim()
  }
  var want = norm(name)
  if (!want) return ""
  var id, n
  for (id in TEAMS) if (norm(TEAMS[id].name) === want) return TEAMS[id].abbr
  for (id in TEAMS) {
    n = norm(TEAMS[id].name)
    if (want.length > n.length && want.slice(want.length - n.length) === n &&
        want.charAt(want.length - n.length - 1) === " ") return TEAMS[id].abbr
    if (n.length > want.length && n.slice(n.length - want.length) === want &&
        n.charAt(n.length - want.length - 1) === " ") return TEAMS[id].abbr
  }
  return ""
}

// Polymarket World Series event -> top winner probabilities. The endpoint
// returns a bare array of events; markets carry groupItemTitle (team name)
// and Yes-price as outcomePrices[0] (string or array depending on vintage).
function parsePolyWs(payload) {
  var out = []
  var events = Array.isArray(payload) ? payload
             : (payload && payload.events) ? payload.events : []
  var markets = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    if (e && e.markets && e.markets.length) { markets = e.markets; break }
  }
  for (i = 0; i < markets.length; i++) {
    var m = markets[i]
    if (m.active === false || m.closed) continue
    var title = m.groupItemTitle || ""
    if (!title) continue
    var prices = m.outcomePrices
    if (typeof prices === "string") {
      try { prices = JSON.parse(prices) } catch (e2) { continue }
    }
    if (!Array.isArray(prices) || prices.length < 1) continue
    var prob = parseFloat(prices[0])
    if (!isFinite(prob) || prob <= 0 || prob > 1) continue
    out.push({ abbr: teamByName(title), name: String(title), prob: prob })
  }
  out.sort(function(a, b) { return b.prob - a.prob })
  return out.slice(0, 6)
}

// Kalshi KXMLB-<yy> markets -> active World Series winner prices.
// Ticker suffix is the team abbreviation (KXMLB-26-LAD); price is dollars
// where 1.00 = certainty, i.e. the implied probability.
function parseKalshiWs(payload) {
  var out = []
  var markets = (payload && payload.markets) || []
  for (var i = 0; i < markets.length; i++) {
    var m = markets[i]
    if (m.status !== "active") continue
    var ticker = String(m.ticker || "")
    var abbr = ticker.slice(ticker.lastIndexOf("-") + 1)
    if (!/^[A-Z]{2,3}$/.test(abbr)) continue
    var price = m.last_price_dollars !== undefined && m.last_price_dollars !== null
      ? parseFloat(m.last_price_dollars) : NaN
    if (!isFinite(price)) price = m.yes_bid_dollars ? parseFloat(m.yes_bid_dollars) : NaN
    if (!isFinite(price) || price <= 0 || price > 1) continue
    out.push({ abbr: abbr, name: m.yes_sub_title || abbr, prob: price })
  }
  out.sort(function(a, b) { return b.prob - a.prob })
  return out.slice(0, 6)
}

// Chip color for a bare abbreviation (odds rows arrive without team ids).
function colorForAbbr(abbr) {
  var want = String(abbr || "").toUpperCase().trim()
  for (var id in TEAMS)
    if (TEAMS[id].abbr === want) return TEAMS[id].color
  return "#7A7A7A"
}

var API = {
  TEAMS: TEAMS,
  teamRef: teamRef,
  parseGame: parseGame,
  flatGames: flatGames,
  parseSchedule: parseSchedule,
  parseTeamStats: parseTeamStats,
  parseLeaders: parseLeaders,
  oddsLine: oddsLine,
  LEADER_ORDER: LEADER_ORDER,
  seriesKey: seriesKey,
  compactDesc: compactDesc,
  pillDesc: pillDesc,
  buildSeries: buildSeries,
  parsePostseason: parsePostseason,
  selectorGames: selectorGames,
  detectFinalTransition: detectFinalTransition,
  buildBracketLayout: buildBracketLayout,
  parseFeed: parseFeed,
  parseSeason: parseSeason,
  teamsByLeague: teamsByLeague,
  parseEspnOdds: parseEspnOdds,
  ESPN_ABBR: ESPN_ABBR,
  americanProb: americanProb,
  formatOdds: formatOdds,
  teamByName: teamByName,
  colorForAbbr: colorForAbbr,
  parsePolyWs: parsePolyWs,
  parseKalshiWs: parseKalshiWs,
  leagueFor: leagueFor,
  parseStandings: parseStandings,
  divisionChamps: divisionChamps,
  teamFocus: teamFocus,
  divisionTable: divisionTable,
  teamNextGames: teamNextGames,
  playoffField: playoffField,
  pickPillGame: pickPillGame
};

if (typeof module !== "undefined" && module.exports) module.exports = API;
