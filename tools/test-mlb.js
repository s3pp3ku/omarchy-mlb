#!/usr/bin/env node
// Exercises mlb.js against live MLB Stats API payloads. Run: node tools/test-mlb.js
const path = require("path");
const mlb = require(path.join(__dirname, "..", "mlb.js"));

const BASE = "https://statsapi.mlb.com/api/v1";

async function get(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  return res.json();
}

let failures = 0;
function check(name, cond, extra) {
  if (cond) {
    console.log(`  ok   ${name}`);
  } else {
    failures++;
    console.log(`  FAIL ${name}${extra !== undefined ? " :: " + JSON.stringify(extra) : ""}`);
  }
}

(async () => {
  console.log("schedule (today window)");
  const sched = await get(`${BASE}/schedule?sportId=1&startDate=2026-10-01&endDate=2026-10-10&hydrate=linescore,decisions`);
  const schedule = mlb.parseSchedule(sched);
  check("parses games", schedule.games.length > 0, schedule.games.length);
  check("has finals", schedule.games.some(g => g.mode === "final"));
  const g0 = schedule.games.find(g => g.mode === "final");
  check("final has scores", g0 && g0.away.score !== null && g0.home.score !== null,
        g0 && { away: g0.away, home: g0.home });
  check("abbrs resolved", g0 && g0.away.abbr.length <= 4 && g0.away.abbr !== g0.away.name,
        g0 && g0.away.abbr);
  check("decisions parsed", !g0 || (typeof g0.winnerName === "string"));

  console.log("postseason bracket");
  const ps = await get(`${BASE}/schedule/postseason?sportId=1&season=2026`);
  const series = mlb.parsePostseason(ps);
  check("series parsed", series.length >= 8, series.length);
  const rounds = new Set(series.map(s => s.round));
  check("has WC/DS/CS/WS", rounds.has("WC") && rounds.has("DS") && rounds.has("CS") && rounds.has("WS"),
        [...rounds]);
  const wc = series.filter(s => s.round === "WC");
  check("4 WC series", wc.length === 4, wc.length);
  const ds = series.filter(s => s.round === "DS");
  check("4 DS series", ds.length === 4, ds.length);
  const decided = series.filter(s => s.clinched !== null);
  check("some series decided", decided.length > 0, decided.map(s => [s.label, s.clinched, s.wins]));
  const dsGames = ds.flatMap(s => s.games);
  check("DS games have real teams", dsGames.length > 0 &&
        dsGames.every(g => !g.away.placeholder || !g.home.placeholder),
        dsGames.slice(0, 2).map(g => [g.away.abbr, g.home.abbr]));

  console.log("bracket layout");
  const layout = mlb.buildBracketLayout(series);
  check("cards laid out", layout.cards.length >= 9, layout.cards.length);
  check("one WS card", layout.cards.filter(c => c.series.round === "WS").length === 1);
  check("card positions in bounds",
        layout.cards.every(c => c.x >= 0 && c.y >= 0 && c.x + c.w <= layout.width && c.y + c.h <= layout.height),
        { width: layout.width, height: layout.height, cards: layout.cards.length });
  check("no overlapping cards", (() => {
    const cs = layout.cards;
    for (let i = 0; i < cs.length; i++)
      for (let j = i + 1; j < cs.length; j++) {
        const a = cs[i], b = cs[j];
        const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
        if (overlap) return false;
      }
    return true;
  })(), layout.cards.map(c => [c.series.label, c.x, c.y]));
  check("connector lines drawn", layout.lines.length > 0, layout.lines.length);
  check("connector points ordered", layout.lines.every(l => l.length >= 2 && l.every(p => isFinite(p.x) && isFinite(p.y))));

  console.log("live feed (finished playoff game, statcast fields)");
  const liveGame = schedule.games.find(g => g.mode === "final") || schedule.games[0];
  const feed = await get(`https://statsapi.mlb.com/api/v1.1/game/${liveGame.gamePk}/feed/live`);
  const parsed = mlb.parseFeed(feed);
  check("inning parsed", parsed.inning !== null, parsed.inning);
  check("statcast hits found", parsed.topHits.length > 0, parsed.topHits.length);
  check("hit rows shaped", parsed.topHits.every(h => isFinite(h.ev) && typeof h.player === "string"));
  check("exit velocity sane", parsed.topHits.every(h => h.ev > 30 && h.ev < 130), parsed.topHits[0]);
  check("fastest pitch found", parsed.fastest && parsed.fastest.speed > 50, parsed.fastest);
  check("top 3 pitches sorted desc", parsed.topPitches.length >= 1 &&
        parsed.topPitches.every((p, i, a) => i === 0 || a[i-1].speed >= p.speed),
        parsed.topPitches.map(p => p.speed));
  check("longest ball found", parsed.longest && parsed.longest.dist > 0, parsed.longest);
  check("longest is max distance", parsed.topHits.every(h => h.dist <= parsed.longest.dist),
        [parsed.longest.dist, parsed.topHits.map(h => h.dist)]);
  check("avg exit sane", parsed.avgEv > 30 && parsed.avgEv < 120, parsed.avgEv);
  check("batted count matches avg basis", parsed.batted >= 1 && parsed.batted <= 500, parsed.batted);
  check("hardHits <= batted", parsed.hardHits <= parsed.batted, [parsed.hardHits, parsed.batted]);
  check("pitch count sane", parsed.pitches > 0 && parsed.pitches <= 600, parsed.pitches);
  check("HR/K are non-negative ints",
        parsed.homeRuns >= 0 && parsed.strikeouts >= 0 &&
        Number.isInteger(parsed.homeRuns) && Number.isInteger(parsed.strikeouts),
        [parsed.homeRuns, parsed.strikeouts]);
  check("tile guards data present",
        [parsed.topHits[0].ev, parsed.longest.ev, parsed.fastest.speed, parsed.avgEv]
          .every(v => isFinite(v)));
  check("bracket fits 640 panel", (() => {
    var L = mlb.buildBracketLayout(series);
    return L.width <= 616;  // 640 card minus padding
  })());
  check("last play text", typeof parsed.lastPlay === "string" && parsed.lastPlay.length > 0);
  check("R-H-E parsed", parsed.awayRHE && parsed.awayRHE.r !== null, parsed.awayRHE);
  check("probable pitchers present on playoff feed", typeof parsed.awayProbable === "string" &&
        parsed.awayProbable.length > 0, [parsed.awayProbable, parsed.homeProbable]);

  console.log("season calendar + standings");
  const season = mlb.parseSeason(await get(`${BASE}/seasons/2027?sportId=1`));
  check("spring date parsed", season && season.springMs > 0, season);
  check("opening day after spring", season.openingMs > season.springMs);
  const standings = mlb.parseStandings(await get(`${BASE}/standings?leagueId=103,104&season=2026&standingsTypes=regularSeason&hydrate=team`));
  const nTeams = Object.keys(standings).length;
  check("30 teams in standings", nTeams === 30, nTeams);
  check("records shaped", Object.values(standings).every(t => typeof t.wins === "number" && typeof t.champ === "boolean"));

  console.log("pill picker");
  const pill = mlb.pickPillGame(schedule, "");
  check("picks a game or empty window handled", schedule.games.length === 0 || pill !== null);
  const favPill = mlb.pickPillGame(schedule, "PHI");
  const playable = schedule.live.concat(schedule.upcoming);
  check("favorite team honored when playing", favPill === null ||
        favPill.away.abbr === "PHI" || favPill.home.abbr === "PHI" ||
        playable.every(g => g.away.abbr !== "PHI" && g.home.abbr !== "PHI"),
        favPill && [favPill.away.abbr, favPill.home.abbr]);

  console.log("favorite-team helpers");
  const laa = mlb.teamFocus(standings, "LAA");
  check("teamFocus finds LAA", laa !== null && laa.abbr === "LAA", laa);
  check("LAA has full name", laa && /^Los Angeles Angels/.test(laa.name), laa && laa.name);
  check("LAA has division", laa && /^AL /.test(laa.division), laa && laa.division);
  check("LAA rank is 1-5", laa && laa.rank >= 1 && laa.rank <= 5, laa && laa.rank);
  check("LAA gb is string", laa && typeof laa.gb === "string", laa && laa.gb);
  check("LAA streak looks like W/L+d", !laa || laa.streak === "" || /^[WL]\d+$/.test(laa.streak), laa && laa.streak);
  check("LAA record adds up", laa && laa.wins + laa.losses >= 160, laa && [laa.wins, laa.losses]);
  check("teamFocus misses on junk", mlb.teamFocus(standings, "XXX") === null);
  check("teamFocus null-safe on empty", mlb.teamFocus(null, "LAA") === null);

  const west = mlb.divisionTable(standings, "AL West");
  check("AL West has 5 teams", west.length === 5, west.length);
  check("AL West sorted by rank", west.every((t, i) => i === 0 || west[i-1].rank <= t.rank),
        west.map(t => t.rank));
  check("AL West rows have abbr+wins", west.every(t => t.abbr.length >= 2 && t.abbr.length <= 3 && t.wins >= 0));

  const gamesWindow = mlb.flatGames(sched);
  const laaGames = mlb.teamNextGames(gamesWindow, "LAA", 3);
  check("teamNextGames returns <=3", laaGames.length <= 3, laaGames.length);
  check("teamNextGames only LAA games",
        laaGames.every(g => g.away.abbr === "LAA" || g.home.abbr === "LAA"),
        laaGames.map(g => [g.away.abbr, g.home.abbr, g.mode]));
  check("teamNextGames excludes finals",
        laaGames.every(g => g.mode !== "final"), laaGames.map(g => g.mode));
  check("teamNextGames misses on junk", mlb.teamNextGames(gamesWindow, "XXX").length === 0);

  console.log("league picker");
  const al = mlb.teamsByLeague("AL"), nl = mlb.teamsByLeague("NL");
  check("AL has 15 teams", al.length === 15, al.length);
  check("NL has 15 teams", nl.length === 15, nl.length);
  check("leagues partition all 30", al.length + nl.length === Object.keys(mlb.TEAMS).length);
  check("no overlap between leagues",
        al.every(a => !nl.some(b => b.abbr === a.abbr)));
  check("chips shaped", [...al, ...nl].every(t => /^[A-Z]{2,3}$/.test(t.abbr) && /^#[0-9A-F]{6}$/i.test(t.color)));
  check("AL sorted", al.every((t, i) => i === 0 || al[i-1].abbr < t.abbr));
  check("leagueFor LAA = AL", mlb.leagueFor("LAA") === "AL");
  check("leagueFor MIL = NL", mlb.leagueFor("MIL") === "NL");
  check("leagueFor junk = ''", mlb.leagueFor("ZZZ") === "");
  check("leagueFor null-safe", mlb.leagueFor(null) === "");

  console.log("selector + hold");
  const at = (h) => { const d = new Date(); d.setHours(h, 0, 0, 0); return d.getTime() }
  const tomorrow = at(19) + 86400000;
  const mk = (pk, mode, ms) => ({ gamePk: pk, mode, startMs: ms,
    away: { abbr: "AA" }, home: { abbr: "BB" } });

  const slate = [mk(1, "final", at(13)), mk(2, "live", at(16)), mk(3, "preview", at(19))];
  const chips = mlb.selectorGames(slate, 8);
  check("selector: 3 today games", chips.length === 3, chips.length);
  check("selector: live leads", chips[0].gamePk === 2, chips.map(g => g.mode));
  check("selector: rest chronological", chips[1].gamePk === 1 && chips[2].gamePk === 3,
        chips.map(g => g.gamePk));
  check("selector: caps at max",
        mlb.selectorGames([...Array(12)].map((_, i) => mk(100 + i, "final", at(13) + i * 60000)), 8).length === 8);
  check("selector: empty window -> []", mlb.selectorGames([], 8).length === 0);
  check("selector: no games today -> upcoming",
        mlb.selectorGames([mk(9, "preview", tomorrow)], 8).map(g => g.gamePk).join() === "9");
  check("selector: yesterday's final IS selectable (review past statcast)",
        mlb.selectorGames([mk(7, "final", at(13) - 86400000)], 8)
          .map(g => g.gamePk).join() === "7");
  check("selector: past finals newest-first",
        (() => {
          const now = Date.now(), H = 3600000, D = 86400000;
          const o = (pk, mode, ms) => ({ gamePk: pk, mode, startMs: ms,
            away: { abbr: "AA" }, home: { abbr: "BB" } });
          const win = [
            o(11, "final", now - D - 3 * D),   // 4 days ago
            o(12, "final", now - D),           // yesterday
            o(13, "live", now - H),            // live now
            o(14, "final", now - 2 * H),       // today, finished
            o(15, "preview", now + 4 * H),     // today, later
            o(16, "preview", now + D)          // tomorrow
          ];
          const ids = mlb.selectorGames(win, 12).map(g => g.gamePk);
          return ids[0] === 13 &&                // live leads
                 ids.indexOf(14) < ids.indexOf(15) &&  // today chronological
                 ids.indexOf(12) < ids.indexOf(11) &&  // past newest-first
                 ids[ids.length - 1] === 16;     // future last
        })());
  check("selector: caps at 12",
        mlb.selectorGames([...Array(20)].map((_, i) =>
          mk(200 + i, "final", Date.now() - i * 3600000)), 12).length === 12);

  const live = { gamePk: 5, mode: "live" }, fin = { gamePk: 5, mode: "final" };
  check("hold: live->final detected", mlb.detectFinalTransition(live, [fin]) === 5);
  check("hold: still live not held", mlb.detectFinalTransition(live, [live]) === -1);
  check("hold: prev already final not re-held", mlb.detectFinalTransition(fin, [fin]) === -1);
  check("hold: null prev safe", mlb.detectFinalTransition(null, [fin]) === -1);
  check("hold: game gone from window safe",
        mlb.detectFinalTransition(live, [{ gamePk: 6, mode: "final" }]) === -1);

  console.log("odds parsers");
  // ESPN scoreboard fixture mirrors the real payload shape.
  const espnFix = { events: [{
    competitions: [{
      competitors: [
        { homeAway: "away", team: { abbreviation: "ATL" } },
        { homeAway: "home", team: { abbreviation: "LAD" } }],
      odds: [{
        provider: { name: "DraftKings" },
        moneyline: {
          away: { close: { odds: "+174" } },
          home: { close: { odds: "-213" } }
        },
        spread: -1.5,
        overUnder: 7.5,
        homeTeamOdds: { favorite: true }
      }]
    }]
  }, { competitions: [{ competitors: [
        { homeAway: "away", team: { abbreviation: "NYM" } },
        { homeAway: "home", team: { abbreviation: "PHI" } }] }] }] };
  const book = mlb.parseEspnOdds(espnFix);
  check("espn: odds keyed away@home", Object.keys(book).join() === "ATL@LAD", Object.keys(book));
  const o = book["ATL@LAD"];
  check("espn: moneyline parsed", o.mlAway === "+174" && o.mlHome === "-213", [o.mlAway, o.mlHome]);
  check("espn: spread/total/favorite", o.spread === -1.5 && o.total === 7.5 && o.spreadHome === true,
        [o.spread, o.total, o.spreadHome]);
  check("espn: game without odds skipped", !book["NYM@PHI"]);
  check("espn: empty payload -> {}", Object.keys(mlb.parseEspnOdds({})).length === 0);
  const line = mlb.formatOdds(o);
  check("formatOdds contains ML/RL/O-U",
        line.includes("ML ATL +174") && line.includes("LAD -213") &&
        line.includes("RL LAD -1.5") && line.includes("O/U 7.5"), line);
  check("formatOdds null-safe", mlb.formatOdds(null) === "");
  // Juice (vig) rides along on the spread/total sub-objects when the book
  // posts it — appended in parentheses to the matching market.
  const juiced = Object.assign({}, o, { rlHome: "-102", rlAway: "-118",
    overOdds: "-117", underOdds: "-110" });
  const jLine = mlb.formatOdds(juiced);
  check("formatOdds: run-line juice shown",
        jLine.includes("RL LAD -1.5 (-102)"), jLine);
  check("formatOdds: total juice shown",
        jLine.includes("O/U 7.5 (-117/-110)"), jLine);
  check("formatOdds: no juice parens when absent", !line.includes("("), line);

  check("americanProb: -213 favorite", Math.abs(mlb.americanProb("-213") - 0.6805) < 0.001,
        mlb.americanProb("-213"));
  check("americanProb: +174 dog", Math.abs(mlb.americanProb("+174") - 0.365) < 0.001,
        mlb.americanProb("+174"));
  check("americanProb: -110 even-ish", Math.abs(mlb.americanProb("-110") - 0.5238) < 0.001,
        mlb.americanProb("-110"));
  check("americanProb null-safe",
        mlb.americanProb(null) === null && mlb.americanProb("junk") === null &&
        mlb.americanProb("0") === null);

  // ESPN abbreviates two clubs differently from the stats API (CHW/CWS,
  // ARI/AZ); the odds map must key them the stats-side way or oddsFor()
  // lookups by schedule abbr silently miss.
  check("ESPN_ABBR covers both known mismatches",
        mlb.ESPN_ABBR.CHW === "CWS" && mlb.ESPN_ABBR.ARI === "AZ");
  check("parseEspnOdds keys White Sox as CWS", (() => {
    const payload = { events: [{
      competitions: [{
        competitors: [
          { homeAway: "away", team: { abbreviation: "CHW" } },
          { homeAway: "home", team: { abbreviation: "CLE" } }],
        odds: [{
          provider: { name: "Book" },
          moneyline: { away: { close: { odds: "+130" } },
                       home: { close: { odds: "-157" } } },
          pointSpread: {}, total: {} }] }] }] };
    const book = mlb.parseEspnOdds(payload);
    return book["CWS@CLE"] !== undefined && book["CHW@CLE"] === undefined;
  })());
  check("parseTeamStats merges hitting+pitching into one branded row", (() => {
    const hit = { stats: [{ splits: [
      { team: { id: 114, name: "Cleveland Guardians" }, season: "2026",
        stat: { gamesPlayed: 10, runs: 40, homeRuns: 20, rbi: 35, avg: ".250",
                obp: ".330", slg: ".400", stolenBases: 12 } }
    ]}]};
    const pit = { stats: [{ splits: [
      { team: { id: 114, name: "Cleveland Guardians" }, season: "2026",
        stat: { wins: 7, losses: 3, runs: 30, era: "3.20", whip: "1.10",
                strikeOuts: 100, baseOnBalls: 40 } }
    ]}]};
    const rows = mlb.parseTeamStats(hit, pit);
    return rows.length === 1 && rows[0].record === "7-3" &&
           rows[0].runsPer === "4.0" && rows[0].againstPer === "3.0" &&
           rows[0].runDiff === 10 && rows[0].abbr === "CLE";
  })());

  check("parseLeaders keeps canonical splits per category", (() => {
    const payload = { leagueLeaders: [
      { leaderCategory: "battingAverage", statGroup: "pitching", leaders: [
          { rank: 1, person: { fullName: "Pitcher Bat" }, value: ".150", team: { name: "X" } } ] },
      { leaderCategory: "battingAverage", statGroup: "hitting", leaders: [
          { rank: 1, person: { fullName: "Yordan Alvarez" }, value: ".316", team: { name: "Houston Astros" } } ] },
      { leaderCategory: "wins", statGroup: "pitching", leaders: [
          { rank: 1, person: { fullName: "Sonny Gray" }, value: "18", team: { name: "Boston Red Sox" } } ] }
    ]};
    const cats = mlb.parseLeaders(payload);
    return cats.length === 2 && cats[0].key === "battingAverage" &&
           cats[0].rows[0].name === "Yordan Alvarez" && cats[1].key === "wins";
  })());

  check("oddsLine strips the provider prefix", (() => {
    const o = { provider: "DraftKings", awayAbbr: "CWS", homeAbbr: "CLE",
                mlAway: "+130", mlHome: "-157" };
    const s = mlb.oddsLine(o);
    return s.indexOf("ML") === 0 && s.indexOf("DraftKings") < 0;
  })());

  check("parseEspnOdds keys D-backs as AZ", (() => {
    const payload = { events: [{
      competitions: [{
        competitors: [
          { homeAway: "away", team: { abbreviation: "ARI" } },
          { homeAway: "home", team: { abbreviation: "LAD" } }],
        odds: [{ provider: { name: "Book" } }] }] }] };
    const book = mlb.parseEspnOdds(payload);
    return book["AZ@LAD"] !== undefined;
  })());
  // Away-favorite: spread is still the home side's line (+1.5).
  const awayFav = mlb.parseEspnOdds({ events: [{ competitions: [{
    competitors: [{ homeAway: "away", team: { abbreviation: "KC" } },
                   { homeAway: "home", team: { abbreviation: "MIN" } }],
    odds: [{ moneyline: { away: { open: { odds: "-130" } }, home: { open: { odds: "+110" } } },
             spread: 1.5, overUnder: 8.0, homeTeamOdds: { favorite: false } }]
  }] }] });
  const af = awayFav["KC@MIN"];
  check("espn: open odds fallback used", af.mlAway === "-130" && af.mlHome === "+110",
        [af.mlAway, af.mlHome]);
  const afLine = mlb.formatOdds(af);
  check("formatOdds away-favorite run line flips sign",
        afLine.includes("RL KC -1.5"), afLine);

  // Polymarket fixture: array payload, prices as array and as string.
  const polyFix = [{ markets: [
    { groupItemTitle: "Los Angeles Dodgers", active: true, closed: false,
      outcomePrices: ["0.365", "0.635"] },
    { groupItemTitle: "Milwaukee Brewers", active: true, closed: false,
      outcomePrices: "[\"0.215\",\"0.785\"]" },
    { groupItemTitle: "Resolved Team", active: false, closed: true,
      outcomePrices: ["1.0", "0.0"] },
    { groupItemTitle: "Bogus", active: true, closed: false,
      outcomePrices: "not-json" }
  ] }];
  const poly = mlb.parsePolyWs(polyFix);
  check("poly: sorted desc", poly.length === 2 && poly[0].abbr === "LAD" && poly[1].abbr === "MIL",
        poly.map(r => r.abbr));
  check("poly: string prices parsed", Math.abs(poly[1].prob - 0.215) < 1e-9, poly[1].prob);
  check("poly: inactive/closed/garbage skipped", poly.every(r => r.name !== "Resolved Team" && r.name !== "Bogus"));
  check("poly: empty -> []", mlb.parsePolyWs([]).length === 0 && mlb.parsePolyWs({}).length === 0);

  // Kalshi fixture: ticker suffix = abbr, active only, dollars = probability.
  const kalFix = { markets: [
    { ticker: "KXMLB-26-LAD", status: "active", last_price_dollars: "0.3820", yes_sub_title: "Los Angeles D" },
    { ticker: "KXMLB-26-MIL", status: "active", last_price_dollars: "0.2360", yes_sub_title: "Milwaukee" },
    { ticker: "KXMLB-26-HOU", status: "finalized", last_price_dollars: "0.0010", yes_sub_title: "Houston" },
    { ticker: "KXMLB-26-XYZ", status: "active", last_price_dollars: null, yes_bid_dollars: "0.0500", yes_sub_title: "Unknown" }
  ] };
  const kal = mlb.parseKalshiWs(kalFix);
  check("kalshi: active only, sorted desc",
        kal.length === 3 && kal[0].abbr === "LAD" && kal[1].abbr === "MIL",
        kal.map(r => r.abbr));
  check("kalshi: price as probability", Math.abs(kal[0].prob - 0.382) < 1e-9, kal[0].prob);
  check("kalshi: bid fallback when no last price", Math.abs(kal[2].prob - 0.05) < 1e-9, kal[2].prob);
  check("kalshi: bad ticker dropped", kal.every(r => /^[A-Z]{2,3}$/.test(r.abbr)));
  check("kalshi: empty -> []", mlb.parseKalshiWs({}).length === 0);

  check("colorForAbbr known/unknown",
        mlb.colorForAbbr("LAD") === "#1E73C8" && mlb.colorForAbbr("ZZ") === "#7A7A7A");

  console.log("label helpers");
  check("compactDesc strips slot", mlb.compactDesc("NLDS 'A' Game 2") === "NLDS Game 2", mlb.compactDesc("NLDS 'A' Game 2"));
  check("pillDesc short", mlb.pillDesc("World Series Game 3") === "World Series G3", mlb.pillDesc("World Series Game 3"));

  console.log("champion recap (completed postseasons)");
  {
    // 2025: LAD through the Wild Card, 7-game WS over TOR.
    const s25 = mlb.parsePostseason(await get(`${BASE}/schedule/postseason?sportId=1&season=2025`));
    const p = mlb.championPath(s25);
    check("2025 champion found", p && p.team.abbr === "LAD", p && p.team);
    check("2025 four rounds, no bye", p && p.rounds.length === 4 && p.rounds.every(r => !r.bye),
          p && p.rounds.map(r => r.round));
    check("2025 WS 4-3 over TOR", p && p.wsWon === 4 && p.wsLost === 3 && p.opp.abbr === "TOR",
          p && [p.wsWon, p.wsLost, p.opp.abbr]);
    check("2025 postseason record 13-4", p && p.wins === 13 && p.losses === 4, p && [p.wins, p.losses]);
    check("2025 seven WS games, last is clincher",
          p && p.wsGames.length === 7 && p.wsGames[6].clincher === true &&
          p.wsGames.filter(g => g.clincher).length === 1);
    check("clinchMs is the last WS game", p && p.clinchMs === p.wsGames[6].startMs);
    // 2024: LAD had a bye.
    const p24 = mlb.championPath(mlb.parsePostseason(await get(`${BASE}/schedule/postseason?sportId=1&season=2024`)));
    check("2024 bye row", p24 && p24.rounds[0].bye === true && p24.rounds[0].name === "NL Wild Card",
          p24 && p24.rounds[0]);
    check("2024 bye not counted", p24 && p24.wins === 11 && p24.losses === 5, p24 && [p24.wins, p24.losses]);
    check("no champion while undecided", mlb.championPath(series.filter(s => s.round !== "WS")) === null);
    check("hasRealTeams on real bracket", mlb.hasRealTeams(s25));
    check("hasRealTeams false on empty", !mlb.hasRealTeams([]));
    check("hasRealTeams false on placeholders",
          !mlb.hasRealTeams([{ realTeams: [] }, { realTeams: [] }]));
    const mvp = mlb.parseAwardWinner(await get(`${BASE}/awards/WSMVP/recipients?season=2025`));
    check("2025 WS MVP parsed", mvp && mvp.name === "Yoshinobu Yamamoto" && mvp.teamAbbr === "LAD", mvp);
    check("award winner null before announced", mlb.parseAwardWinner({ awards: [] }) === null);
  }

  console.log("baseball savant");
  {
    const SAV = "https://baseballsavant.mlb.com/leaderboard/";
    async function text(url) {
      const res = await fetch(url, { signal: AbortSignal.timeout(30000) });
      if (!res.ok) throw new Error(`${res.status} ${url}`);
      return res.text();
    }
    check("csv quoted fields", JSON.stringify(mlb.parseCsv('\uFEFF"a","b, c"\n1,"x ""y"""\n')) ===
          JSON.stringify([{ a: "1", "b, c": 'x "y"' }]), mlb.parseCsv('"a","b, c"\n1,"x ""y"""\n'));
    check("firstLast", mlb.firstLast("Crow-Armstrong, Pete") === "Pete Crow-Armstrong");
    const pctB = mlb.parsePercentiles(await text(`${SAV}percentile-rankings?type=batter&year=2025&csv=true`));
    const ohtani = mlb.percentileBars(pctB[660271], "batter");
    check("batter percentiles parsed", Object.keys(pctB).length > 300, Object.keys(pctB).length);
    check("Ohtani xwOBA elite", ohtani.length > 5 && ohtani[0].key === "xwoba" && ohtani[0].pct >= 90, ohtani[0]);
    const pctP = mlb.parsePercentiles(await text(`${SAV}percentile-rankings?type=pitcher&year=2025&csv=true`));
    check("pitcher percentiles have xERA", mlb.percentileBars(pctP[669373], "pitcher").some(b => b.key === "xera"));
    check("percentile colors", mlb.percentileColor(0) !== mlb.percentileColor(100) &&
          /^#[0-9a-f]{6}$/.test(mlb.percentileColor(50)));
    const boards = mlb.savantLeaderboards({
      xstats: await text(`${SAV}expected_statistics?type=batter&year=2025&position=&team=&min=q&csv=true`),
      statcast: await text(`${SAV}statcast?type=batter&year=2025&position=&team=&min=q&csv=true`),
      bat: "", sprint: "", oaa: "" });
    check("savant boards built", boards.length >= 4 && boards.every(b => b.rows.length === 5),
          boards.map(b => b.label));
    check("empty boards tolerated", mlb.savantLeaderboards({}).length === 0);
    const gf = await get(`https://baseballsavant.mlb.com/gf?game_pk=813024`);
    const sg = mlb.parseSavantGame(gf);
    check("savant game barrels", sg.barrels.away + sg.barrels.home === 9, sg.barrels);
    check("savant game arsenals", sg.arsenals.length === 2 && sg.arsenals[0].mix[0].spin > 1000,
          sg.arsenals.map(a => a.pitcher));
    check("cheap hits sorted by xBA", sg.cheapHits.length && sg.cheapHits[0].xba <= sg.cheapHits[sg.cheapHits.length - 1].xba);
    check("savant game tolerates junk", mlb.parseSavantGame(null).batted === 0);
  }

  console.log("broadcasts");
  {
    const b = mlb.parseBroadcasts([
      { name: "TBS/HBO MAX", type: "TV", language: "en", isNational: true, homeAway: "away" },
      { name: "TBS/HBO MAX", type: "TV", language: "en", isNational: true, homeAway: "home" },
      { name: "WTAM 1100", type: "AM", language: "en", isNational: false, homeAway: "home" },
      { name: "Rangers Sports Network, presented by Progressive", type: "TV", language: "en", isNational: false, homeAway: "away" },
      { name: "Univision/ TUDN", type: "TV", language: "es", isNational: true, homeAway: "home" }
    ], "TEX", "CLE");
    check("national TV deduped and first", JSON.stringify(b.tv) === JSON.stringify(["TBS/HBO MAX", "TEX Rangers Sports Network"]), b.tv);
    check("local radio prefixed", b.radio[0] === "CLE WTAM 1100", b.radio);
    check("spanish split out", b.spanish[0] === "Univision/TUDN", b.spanish);
    check("radio stations structured", b.stations.length === 1 && b.stations[0].side === "home" &&
          b.stations[0].abbr === "CLE" && b.stations[0].query === "WTAM", b.stations);
    check("stationQuery call letters", mlb.stationQuery("KLAC AM570", "Dodgers Radio AM570") === "KLAC");
    check("stationQuery falls back to name", mlb.stationQuery("", "104.3 The Score") === "104.3 The Score");
    check("no broadcasts tolerated", mlb.parseBroadcasts(undefined, "A", "B").tv.length === 0);
    const sb = mlb.parseSchedule(await get(`${BASE}/schedule?sportId=1&startDate=2026-10-10&endDate=2026-10-10&hydrate=broadcasts(all)`));
    check("schedule games carry media", sb.games.length > 0 && sb.games.every(g => g.media && Array.isArray(g.media.tv)));
  }

  console.log("radio streams");
  {
    const st = (o) => Object.assign({ lastcheckok: 1, countrycode: "US", codec: "AAC", clickcount: 1 }, o);
    check("whole-word match only", mlb.pickStream([st({ name: "fmrainbowtamil", url_resolved: "https://a/x" })], "WTAM") === null);
    const p = mlb.pickStream([
      st({ name: "WTAM 1100 relay", url_resolved: "https://b/x", countrycode: "DE", clickcount: 900 }),
      st({ name: "WTAM 1100 - Cleveland, Ohio", url_resolved: "https://a/x", stationuuid: "0510988b-b95f-43a5-b9a7-4ab57ebf7e1d" })
    ], "WTAM");
    check("US listing preferred", p && p.url === "https://a/x" && p.uuid.length === 36, p);
    check("broken stations skipped", mlb.pickStream([st({ name: "KLAC", url_resolved: "https://a/x", lastcheckok: 0 })], "KLAC") === null);
    check("non-http urls rejected", mlb.pickStream([st({ name: "KLAC", url_resolved: "file:///etc/passwd" })], "KLAC") === null &&
          mlb.pickStream([st({ name: "KLAC", url_resolved: "https://a/x --script=evil" })], "KLAC") === null);
    check("regex chars in query safe", mlb.pickStream([st({ name: "104.3 The Score", url_resolved: "https://a/x" })], "104.3 The Score") !== null);
    const live = await (await fetch("https://de1.api.radio-browser.info/json/stations/search?name=KLAC&limit=30&hidebroken=true&order=clickcount&reverse=true",
                                    { headers: { "User-Agent": "omarchy-mlb/0.1" }, signal: AbortSignal.timeout(20000) })).json();
    const k = mlb.pickStream(live, "KLAC");
    check("KLAC resolves live", k && /^https?:\/\//.test(k.url), k);
  }

  console.log("theme palette");
  {
    const pal = mlb.parseThemeColors('mode = "light"\naccent = "#7d82d9"\nred = "#ED5B5A"\ngreen="#92a593"\n# x = "#000000"\n');
    check("named colors parsed", pal.red === "#ED5B5A" && pal.green === "#92a593" && pal.mode === "light", pal);
    check("comments ignored", pal.x === undefined);
    const ansi = mlb.parseThemeColors('color1 = "#aa0000"\ncolor4 = "#0000aa"\n');
    check("ansi fallback", ansi.red === "#aa0000" && ansi.blue === "#0000aa", ansi);
    check("theme pitch color", mlb.themePitchColor("FF", pal) === "#ED5B5A" && mlb.themePitchColor("CH", pal) === "#92a593");
    check("theme pitch falls back", mlb.themePitchColor("FF", {}) === mlb.pitchColor("FF"));
    check("percentile endpoints", mlb.percentileColor(0, "#000010", "#808080", "#100000") === "#000010" &&
          mlb.percentileColor(100, "#000010", "#808080", "#100000") === "#100000");
  }

  console.log("matchup switcher");
  {
    const now = Date.now();
    const mk = (pk, mode, off) => ({ gamePk: pk, mode, startMs: now + off,
      away: { abbr: "A" }, home: { abbr: "H" } });
    const list = mlb.switcherGames([
      mk(1, "final", -3 * 3600e3), mk(2, "live", -3600e3), mk(3, "preview", 2 * 3600e3),
      mk(4, "live", -2 * 3600e3), mk(5, "final", -1800e3), mk(6, "preview", 3 * 86400e3),
      mk(7, "final", -2 * 86400e3)]);
    // Live (earliest first), then later today, then today's finals newest first.
    // Same-day checks can flip near midnight, so only assert the stable parts.
    check("live games lead", list[0].gamePk === 4 && list[1].gamePk === 2, list.map(g => g.gamePk));
    check("other days excluded", !list.some(g => g.gamePk === 6 || g.gamePk === 7), list.map(g => g.gamePk));
    check("cap respected", mlb.switcherGames(Array.from({ length: 30 }, (_, i) => mk(i, "live", -i)), 15).length === 15);
  }

  console.log("live at-bat");
  {
    const lf = mlb.parseLive(await get(`https://statsapi.mlb.com/api/v1.1/game/813024/feed/live`));
    check("live teams", lf.away.abbr === "LAD" && lf.home.abbr === "TOR" && lf.away.r === 5, [lf.away, lf.home]);
    check("live at-bat pitches", lf.pitches.length === 3 && lf.pitches.every(p => p.px !== null && p.code),
          lf.pitches.length);
    check("in-play pitch has EV", lf.pitches[2].inPlay && lf.pitches[2].ev !== null);
    check("batter lines", lf.batter.name === "Alejandro Kirk" && lf.batter.today && lf.batter.avg, lf.batter);
    check("pitcher mix sums ~100", Math.abs(lf.pitcher.mix.reduce((a, m) => a + m.pct, 0) - 100) <= 3,
          lf.pitcher.mix);
    check("postseason label", lf.seasonLabel === "POSTSEASON");
    check("live tolerates junk", mlb.parseLive({}).pitches.length === 0);
    check("shortPitch", mlb.shortPitch("Four-Seam Fastball") === "4-Seam FB");
  }

  console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURES`);
  process.exit(failures === 0 ? 0 : 1);
})().catch(e => { console.error("ERROR", e); process.exit(2); });
