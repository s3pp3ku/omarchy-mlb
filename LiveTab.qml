import QtQuick
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// Live tab: a Gameday-style view of the focus game's current plate
// appearance. Scoreboard band (score, inning, count, outs, runners), a
// catcher's-eye strike zone with every pitch of the at-bat, the pitch
// sequence with type/speed/result, and matchup cards for the batter and
// pitcher: today's line, season line, Baseball Savant percentile sliders,
// and the pitcher's mix in this game. Before first pitch it shows the
// probable starters' percentiles instead.
//
// Data: panel.live (Mlb.parseLive of the MLB live feed, every 10 s while
// this tab is open on a live game) and panel.pctBatters/pctPitchers (Savant
// percentile CSVs, twice a day).
Column {
  id: tab

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: tab.panel && tab.panel.hi !== undefined ? tab.panel.hi : Color.accent
  function wash(a) { return tab.panel && tab.panel.wash ? tab.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var panel: null
  spacing: Style.space(10)

  readonly property var g: panel ? panel.focusGame : null
  readonly property var lv: (panel !== null && panel.live !== null && g !== null &&
                            panel.feedPk === g.gamePk && panel.live.gamePk === g.gamePk)
                           ? panel.live : null
  readonly property bool isLive: lv !== null && lv.mode === "Live"
  readonly property bool isFinal: lv !== null && lv.mode === "Final"
  readonly property bool hasAtBat: lv !== null && lv.batter.id > 0 && !(g && g.mode === "preview")
  readonly property var f: (panel !== null && panel.feed !== null && g !== null &&
                            panel.feedPk === g.gamePk) ? panel.feed : null

  // Status colors follow the Omarchy theme (Panel.qml cBall/cStrike/cPlay).
  readonly property color ballColor: panel ? panel.cBall : "#3FB950"
  readonly property color strikeColor: panel ? panel.cStrike : "#E5534B"
  readonly property color playColor: panel ? panel.cPlay : "#4C8DFF"

  function ordinal(n) {
    var s = ["th", "st", "nd", "rd"], v = n % 100
    return n + (s[(v - 20) % 10] || s[v] || s[0])
  }
  function callColor(p) {
    return p.inPlay ? playColor : p.isBall ? ballColor : p.isStrike ? strikeColor : Color.muted
  }
  function inningText() {
    if (!lv || !lv.inning) return ""
    if (isFinal) return lv.inning > 9 ? "F/" + lv.inning : "FINAL"
    var st = lv.inningState
    if (st === "Middle" || st === "End") return (st === "Middle" ? "MID " : "END ") + ordinal(lv.inning)
    return (lv.isTop ? "▲ " : "▼ ") + ordinal(lv.inning)
  }

  // ---- Matchup switcher -----------------------------------------------------
  // Every live game, then today's later games, then today's finals. Clicking
  // a chip pins that game (Games/Statcast follow it too); clicking the
  // pinned chip again returns to automatic (favorite team, else first live).
  // ← / → or h / l step through the same list (Panel.qml keyCatcher).
  readonly property var games: panel ? Mlb.switcherGames(panel.schedule.games, 15) : []

  Column {
    visible: tab.games.length > 1
    width: parent.width
    spacing: Style.space(4)

    Row {
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        text: panel && panel.schedule.live.length
              ? panel.schedule.live.length + " LIVE · " + tab.games.length + " TODAY"
              : tab.games.length + " TODAY"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: Style.space(2)
      }
      Text {
        textFormat: Text.PlainText
        text: panel && panel.focusOverride > 0 ? "pinned · click again for auto · ← → to switch"
                                               : "auto · ← → to switch"
        color: Color.muted
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.italic: true
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: tab.games
        delegate: Rectangle {
          id: chip
          required property var modelData
          readonly property bool on: tab.g !== null && tab.g.gamePk === modelData.gamePk
          readonly property bool isLive: modelData.mode === "live"
          readonly property bool fav: tab.panel.favTeam !== "" &&
            (modelData.away.abbr === tab.panel.favTeam || modelData.home.abbr === tab.panel.favTeam)
          width: chipRow.implicitWidth + Style.space(16)
          height: Style.space(26)
          radius: Style.space(5)
          color: on ? tab.wash(0.10) : chipMouse.containsMouse ? tab.wash(0.06) : "transparent"
          border.width: on ? 2 : 1
          border.color: on ? tab.hi : fav ? tab.wash(0.35) : tab.wash(0.14)

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.space(5)
            // Live: a red dot that breathes.
            Rectangle {
              visible: chip.isLive
              width: Style.space(7); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: tab.strikeColor
              SequentialAnimation on opacity {
                running: chip.isLive && chip.visible
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.3; duration: 900 }
                NumberAnimation { from: 0.3; to: 1; duration: 900 }
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var m = chip.modelData
                if (m.mode === "live")
                  return m.away.abbr + " " + (m.away.score || 0) + "  " + m.home.abbr + " " +
                         (m.home.score || 0) + (m.inning ? "  " + (m.isTop ? "▲" : "▼") + m.inning : "")
                if (m.mode === "final")
                  return m.away.abbr + " " + m.away.score + "  " + m.home.abbr + " " + m.home.score + "  F"
                return m.away.abbr + " @ " + m.home.abbr + "  " + tab.panel.fmtTime(m.startMs)
              }
              color: chip.on ? tab.hi : chip.modelData.mode === "final" ? Color.muted : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
              font.bold: chip.on || chip.isLive
            }
          }
          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (tab.panel.focusOverride === chip.modelData.gamePk) tab.panel.focusGameFor(-1)
              else tab.panel.focusGameFor(chip.modelData.gamePk)
            }
          }
        }
      }
    }
  }

  // ---- Empty / waiting states --------------------------------------------
  Text {
    visible: panel !== null && (g === null || (lv === null && g.mode !== "preview"))
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: g === null ? "No games in the next week."
        : panel.loadingFeed ? "Loading the live feed…" : "Waiting for the game feed…"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  // ---- Scoreboard band ---------------------------------------------------
  Rectangle {
    visible: tab.lv !== null
    width: parent.width
    height: Style.space(64)
    radius: Style.space(6)
    color: tab.wash(0.04)
    border.width: 1
    border.color: tab.isLive ? tab.hi : tab.wash(0.12)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(18)

      Repeater {
        model: tab.lv ? [tab.lv.away, tab.lv.home] : []
        delegate: Row {
          required property var modelData
          required property int index
          spacing: Style.space(8)
          readonly property bool batting: tab.isLive && (index === 0) === tab.lv.isTop
          Rectangle {
            width: Style.space(5)
            height: Style.space(34)
            radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: tab.panel.teamColorsOn ? modelData.color : tab.hi
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: modelData.abbr + (batting ? " •" : "")
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: modelData.h + " H · " + modelData.e + " E"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(modelData.r)
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(30)
            font.bold: true
          }
        }
      }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(16)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: tab.inningText()
        color: tab.isLive ? tab.hi : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(14)
        font.bold: true
      }

      // B / S / O lights.
      Column {
        visible: tab.isLive
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Repeater {
          model: tab.lv ? [
            { k: "B", n: tab.lv.balls, max: 4, c: tab.ballColor },
            { k: "S", n: tab.lv.strikes, max: 3, c: tab.strikeColor },
            { k: "O", n: tab.lv.outs, max: 3, c: tab.hi }
          ] : []
          delegate: Row {
            required property var modelData
            spacing: Style.space(4)
            Text {
              width: Style.space(10)
              textFormat: Text.PlainText
              text: modelData.k
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
              model: modelData.max - 1
              delegate: Rectangle {
                required property int index
                width: Style.space(9)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: index < modelData.n ? modelData.c : tab.wash(0.12)
              }
            }
          }
        }
      }

      BaseDiamond {
        panel: tab.panel
        visible: tab.isLive
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: Style.space(40)
        on1: tab.lv ? tab.lv.on1 : false
        on2: tab.lv ? tab.lv.on2 : false
        on3: tab.lv ? tab.lv.on3 : false
      }
    }
  }

  RadioNowPlaying { panel: tab.panel; width: parent.width }

  // ---- Where it's on -------------------------------------------------------
  // From the schedule's broadcasts hydrate (Mlb.parseBroadcasts). Hidden once
  // the game is final; Spanish-language feeds on their own line.
  Column {
    readonly property var media: tab.g && tab.g.media && tab.g.mode !== "final" ? tab.g.media : null
    visible: media !== null && (media.tv.length + media.radio.length + media.spanish.length) > 0
    width: parent.width
    spacing: Style.space(3)
    Repeater {
      model: parent.media ? [
        { tag: "TV", items: parent.media.tv },
        { tag: "RADIO", items: parent.media.radio },
        { tag: "ESPA\u00D1OL", items: parent.media.spanish }
      ] : []
      delegate: Row {
        required property var modelData
        visible: modelData.items.length > 0
        width: tab.width
        spacing: Style.space(8)
        Rectangle {
          width: Style.space(62)
          height: Style.space(18)
          radius: Style.space(4)
          color: modelData.tag === "TV" ? tab.wash(0.10) : tab.wash(0.05)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData.tag
            color: modelData.tag === "TV" ? tab.hi : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(9)
            font.bold: true
            font.letterSpacing: Style.space(1)
          }
        }
        // One-press listen on the radio row: your team's call if they're
        // playing, else the home club's (Panel.defaultStation).
        Rectangle {
          id: listenBtn
          readonly property var station: tab.g ? tab.panel.defaultStation(tab.g) : null
          readonly property bool on: station !== null && tab.panel.radioPlaying && tab.panel.radioNow !== null &&
                                     tab.panel.radioNow.query === station.query
          visible: modelData.tag === "RADIO" && station !== null
          width: visible ? listenText.implicitWidth + Style.space(16) : 0
          height: Style.space(20)
          radius: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          color: on ? Qt.rgba(tab.hi.r, tab.hi.g, tab.hi.b, 0.22)
               : listenMouse.containsMouse ? tab.wash(0.12) : tab.wash(0.05)
          border.width: 1
          border.color: on || listenMouse.containsMouse ? tab.hi : tab.wash(0.14)
          Text {
            id: listenText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: listenBtn.on ? "\u25A0 Stop"
                : listenBtn.station && tab.panel.radioResolving === listenBtn.station.query ? "\u2026 Finding"
                : "\u25B6 Listen"
            color: tab.hi
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
          }
          MouseArea {
            id: listenMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.panel.toggleStation(listenBtn.station, tab.g.gamePk)
          }
        }
        Text {
          width: tab.width - Style.space(78) - listenBtn.width
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: tab.panel ? tab.panel.safe(modelData.items.slice(0, 4).join("  \u00B7  "), 120) : ""
          color: modelData.tag === "TV" ? Color.popups.text : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: modelData.tag === "TV"
        }
      }
    }
  }

  // ---- Zone + pitch sequence ---------------------------------------------
  Item {
    visible: tab.hasAtBat
    width: parent.width
    height: Math.max(zoneView.height, seq.implicitHeight)

    StrikeZone {
      id: zoneView
      panel: tab.panel
      width: Style.space(220)
      height: Style.space(262)
      pitches: tab.lv ? tab.lv.pitches : []
      bats: tab.lv ? tab.lv.batter.bats : ""
    }

    Column {
      id: seq
      anchors.left: zoneView.right
      anchors.leftMargin: Style.space(14)
      anchors.right: parent.right
      spacing: Style.space(3)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: tab.lv ? (tab.isFinal ? "FINAL AT-BAT" : tab.lv.atBatDone ? "LAST AT-BAT" : "THIS AT-BAT") +
                      (tab.lv.pitches.length ? " · " + tab.lv.pitches.length + " pitch" +
                       (tab.lv.pitches.length === 1 ? "" : "es") : "")
                    : ""
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: Style.space(2)
      }

      Text {
        visible: tab.lv !== null && tab.lv.pitches.length === 0
        textFormat: Text.PlainText
        text: tab.lv ? tab.panel.safe(tab.lv.batter.name, 30) + " steps in…" : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(13)
        font.italic: true
      }

      Repeater {
        // Newest first, like Gameday.
        model: tab.lv ? tab.lv.pitches.slice().reverse() : []
        delegate: Rectangle {
          id: prow
          required property var modelData
          required property int index
          width: seq.width
          height: pcol.implicitHeight + Style.space(8)
          radius: Style.space(4)
          color: index === 0 ? tab.wash(0.07) : tab.wash(0.025)

          Rectangle {
            id: pdot
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            height: width
            radius: width / 2
            color: tab.panel.pitchColor(prow.modelData.code)
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(prow.modelData.n)
              color: "#FFFFFF"
              style: Text.Outline
              styleColor: Qt.rgba(0, 0, 0, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
              font.bold: true
            }
          }
          Column {
            id: pcol
            anchors.left: pdot.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            Item {
              width: parent.width
              height: ptype.implicitHeight
              Text {
                id: ptype
                textFormat: Text.PlainText
                text: tab.panel.safe(Mlb.shortPitch(prow.modelData.type), 20) +
                      (prow.modelData.speed !== null ? "  " + prow.modelData.speed.toFixed(1) + " mph" : "")
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                font.bold: prow.index === 0
              }
              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: prow.modelData.count
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
              }
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: tab.panel.safe(prow.modelData.call, 28) +
                    (prow.modelData.ev !== null
                       ? "  ·  " + prow.modelData.ev.toFixed(1) + " mph" +
                         (prow.modelData.la !== null ? ", " + Math.round(prow.modelData.la) + "°" : "") +
                         (prow.modelData.dist ? ", " + Math.round(prow.modelData.dist) + " ft" : "")
                       : "")
              color: tab.callColor(prow.modelData)
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
            }
          }
        }
      }

      // Result of a completed plate appearance.
      Text {
        visible: tab.lv !== null && tab.lv.result !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: 4
        textFormat: Text.PlainText
        text: tab.lv ? tab.panel.safe(tab.lv.result, 220) : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
        font.italic: true
      }

      // Legend for the dot styles.
      Row {
        spacing: Style.space(10)
        topPadding: Style.space(4)
        Repeater {
          model: [{ t: "Ball", c: tab.ballColor }, { t: "Strike", c: tab.strikeColor },
                  { t: "In play", c: tab.playColor }]
          delegate: Row {
            required property var modelData
            spacing: Style.space(4)
            Rectangle {
              width: Style.space(7); height: width; radius: width / 2
              color: modelData.c
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              text: modelData.t
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
            }
          }
        }
      }
    }
  }

  // ---- Matchup: batter | pitcher -----------------------------------------
  Row {
    visible: tab.hasAtBat
    width: parent.width
    spacing: Style.space(10)

    PlayerCard {
      width: (parent.width - Style.space(10)) / 2
      heading: "AT BAT"
      name: tab.lv ? tab.lv.batter.name : ""
      sub: tab.lv ? [tab.lv.batter.number ? "#" + tab.lv.batter.number : "", tab.lv.batter.pos,
                    tab.lv.batter.bats ? "Bats " + tab.lv.batter.bats : ""]
                    .filter(function(x) { return x }).join(" · ") : ""
      today: tab.lv && tab.lv.batter.today ? "Today " + tab.lv.batter.today : ""
      stats: tab.lv ? [
        { k: "AVG", v: tab.lv.batter.avg || "—" },
        { k: "OBP", v: tab.lv.batter.obp || "—" },
        { k: "SLG", v: tab.lv.batter.slg || "—" },
        { k: "HR", v: String(tab.lv.batter.hr) },
        { k: "RBI", v: String(tab.lv.batter.rbi) }
      ] : []
      statsLabel: tab.lv ? tab.lv.seasonLabel : ""
      trips: tab.lv ? tab.lv.batter.trips : []
      bars: tab.lv && tab.panel ? Mlb.percentileBars(tab.panel.pctBatters[tab.lv.batter.id], "batter") : []
      barsYear: tab.panel ? tab.panel.statsYear : 0
    }

    PlayerCard {
      width: (parent.width - Style.space(10)) / 2
      heading: "PITCHING"
      name: tab.lv ? tab.lv.pitcher.name : ""
      sub: tab.lv ? [tab.lv.pitcher.number ? "#" + tab.lv.pitcher.number : "",
                    tab.lv.pitcher.throws ? "Throws " + tab.lv.pitcher.throws : "",
                    tab.lv.pitcher.pitchCount ? tab.lv.pitcher.pitchCount + " pitches (" +
                      tab.lv.pitcher.strikes + " strikes)" : ""]
                    .filter(function(x) { return x }).join(" · ") : ""
      today: tab.lv && tab.lv.pitcher.today ? "Today " + tab.lv.pitcher.today : ""
      stats: tab.lv ? [
        { k: "W-L", v: tab.lv.pitcher.wl },
        { k: "ERA", v: tab.lv.pitcher.era || "—" },
        { k: "WHIP", v: tab.lv.pitcher.whip || "—" },
        { k: "IP", v: tab.lv.pitcher.ip || "—" },
        { k: "SO", v: String(tab.lv.pitcher.so) }
      ] : []
      statsLabel: tab.lv ? tab.lv.seasonLabel : ""
      mix: tab.lv ? tab.lv.pitcher.mix : []
      bars: tab.lv && tab.panel ? Mlb.percentileBars(tab.panel.pctPitchers[tab.lv.pitcher.id], "pitcher") : []
      barsYear: tab.panel ? tab.panel.statsYear : 0
    }
  }

  // ---- Before first pitch: probable starters -----------------------------
  Text {
    visible: tab.g !== null && tab.g.mode === "preview"
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: tab.g ? tab.g.away.abbr + " @ " + tab.g.home.abbr + " · first pitch " +
                  tab.panel.dayWord(tab.g.startMs) + " " + tab.panel.fmtTime(tab.g.startMs) +
                  " (" + tab.panel.fmtLong(tab.g.startMs - tab.panel.nowMs) + ")" : ""
    color: tab.hi
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
    font.bold: true
  }

  Row {
    visible: tab.g !== null && tab.g.mode === "preview" && tab.f !== null &&
             (tab.f.awayProbableId > 0 || tab.f.homeProbableId > 0)
    width: parent.width
    spacing: Style.space(10)
    Repeater {
      model: tab.f ? [
        { side: tab.g ? tab.g.away.abbr : "", id: tab.f.awayProbableId, name: tab.f.awayProbable },
        { side: tab.g ? tab.g.home.abbr : "", id: tab.f.homeProbableId, name: tab.f.homeProbable }
      ] : []
      delegate: PlayerCard {
        required property var modelData
        width: (tab.width - Style.space(10)) / 2
        heading: modelData.side + " PROBABLE"
        name: modelData.name || "TBD"
        bars: modelData.id ? Mlb.percentileBars(tab.panel.pctPitchers[modelData.id], "pitcher") : []
        barsYear: tab.panel.statsYear
      }
    }
  }

  // ---- Links ---------------------------------------------------------------
  Text {
    visible: tab.g !== null
    textFormat: Text.PlainText
    text: "Open in MLB Gameday ↗"
    color: tab.hi
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
    font.underline: gdMouse.containsMouse
    MouseArea {
      id: gdMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.panel.openLink(tab.panel.gamedayUrl(tab.g.gamePk))
    }
  }

  // ---- Player card ---------------------------------------------------------
  component PlayerCard: Rectangle {
    id: card
    property string heading: ""
    property string name: ""
    property string sub: ""
    property string today: ""
    property var stats: []
    property string statsLabel: ""
    property var trips: []
    property var mix: []
    property var bars: []
    property int barsYear: 0

    height: cardCol.implicitHeight + Style.space(20)
    radius: Style.space(6)
    color: tab.wash(0.04)
    border.width: 1
    border.color: tab.wash(0.12)

    Column {
      id: cardCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(10)
      spacing: Style.space(5)

      Text {
        textFormat: Text.PlainText
        text: card.heading
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: Style.space(2)
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tab.panel ? tab.panel.safe(card.name, 32) : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(16)
        font.bold: true
      }
      Text {
        visible: card.sub !== ""
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: card.sub
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }
      Text {
        visible: card.today !== ""
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tab.panel ? tab.panel.safe(card.today, 48) : ""
        color: tab.hi
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
        font.bold: true
      }

      // Earlier trips to the plate today.
      Flow {
        visible: card.trips.length > 0
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: card.trips
          delegate: Rectangle {
            required property var modelData
            width: tripText.implicitWidth + Style.space(10)
            height: Style.space(18)
            radius: Style.space(4)
            readonly property bool good: /Single|Double|Triple|Home Run|Walk|Hit By Pitch/.test(modelData.event)
            color: good ? Util.alpha(tab.panel.cGood, 0.18) : tab.wash(0.06)
            Text {
              id: tripText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: tab.ordinal(modelData.inning) + " " + tab.panel.safe(modelData.event, 18)
              color: parent.good ? tab.panel.cGood : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(10)
            }
          }
        }
      }

      // Season slash line as a row of mini stat cells.
      Text {
        visible: card.stats.length > 0
        textFormat: Text.PlainText
        text: card.statsLabel
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(9)
        font.bold: true
        font.letterSpacing: Style.space(1)
      }
      Row {
        visible: card.stats.length > 0
        width: parent.width
        Repeater {
          model: card.stats
          delegate: Column {
            required property var modelData
            width: cardCol.width / Math.max(1, card.stats.length)
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: tab.panel ? tab.panel.safe(modelData.v, 8) : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
              font.bold: true
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: modelData.k
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(9)
            }
          }
        }
      }

      // Pitcher's mix in this game: share bar per pitch type + velo.
      Text {
        visible: card.mix.length > 0
        topPadding: Style.space(4)
        textFormat: Text.PlainText
        text: "PITCH MIX TODAY"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(9)
        font.bold: true
        font.letterSpacing: Style.space(1)
      }
      Repeater {
        model: card.mix.length > 6 ? card.mix.slice(0, 6) : card.mix
        delegate: Item {
          required property var modelData
          width: cardCol.width
          height: Style.space(16)
          Text {
            id: mixType
            width: Style.space(78)
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: tab.panel ? tab.panel.safe(Mlb.shortPitch(modelData.type), 18) : ""
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
          }
          Rectangle {
            id: mixTrack
            anchors.left: mixType.right
            anchors.leftMargin: Style.space(4)
            anchors.right: mixVal.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(8)
            radius: height / 2
            color: tab.wash(0.07)
            Rectangle {
              width: parent.width * modelData.pct / 100
              height: parent.height
              radius: height / 2
              color: tab.panel.pitchColor(modelData.code)
              Behavior on width { NumberAnimation { duration: 400 } }
            }
          }
          Text {
            id: mixVal
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(78)
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: modelData.pct + "%" + (modelData.velo !== null ? " · " + modelData.velo.toFixed(1) : "")
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
          }
        }
      }

      Text {
        visible: card.bars.length > 0
        topPadding: Style.space(4)
        textFormat: Text.PlainText
        text: "SAVANT PERCENTILES · " + card.barsYear
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(9)
        font.bold: true
        font.letterSpacing: Style.space(1)
      }
      PercentileBars {
        panel: tab.panel
        visible: card.bars.length > 0
        width: parent.width
        labelWidth: Style.space(78)
        model: card.bars
      }
      Text {
        visible: card.bars.length === 0 && card.name !== "" && card.name !== "TBD" &&
                 tab.panel !== null && tab.panel.pctReady
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "No Savant percentiles (not enough " + card.barsYear + " playing time)"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.italic: true
      }
    }
  }
}
