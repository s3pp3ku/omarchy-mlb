import QtQuick
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// Odds tab, top to bottom: individual game lines for the focus game (ML,
// implied probability, run line, total — each with the book's juice when
// it posts one), then the overall tournament market (World Series winner
// from two prediction markets). All three sources are fetched through
// odds.py on open/refresh — never on a timer — so the monthly budget and
// TTL decide when the network is touched.
Column {
  id: tab
  property var panel: null
  spacing: Style.space(8)

  readonly property var odds: panel ? panel.oddsFor(panel.focusGame) : null

  // Games currently lined: today's schedule from now-forward, minus finals
  // (their books drop). Shown beneath the focus game's own lines.
  readonly property var slateGames: panel !== null
    ? panel.schedule.today.filter(function(g) { return g.mode !== "final" }) : []
  readonly property bool hasFocus: panel !== null && panel.focusGame !== null
  readonly property bool noMarkets: panel !== null &&
                                    panel.polyWs.length === 0 &&
                                    panel.kalshiWs.length === 0

  // ---- Focus game header -------------------------------------------------
  Column {
    visible: tab.hasFocus
    width: parent.width
    spacing: Style.space(2)
    Row {
      width: parent.width
      spacing: Style.space(5)
      Rectangle {
        width: Style.space(3)
        height: Style.space(12)
        radius: 1
        anchors.verticalCenter: parent.verticalCenter
        color: panel.focusGame ? Mlb.colorForAbbr(panel.focusGame.away.abbr) : "#7A7A7A"
      }
      Text {
        textFormat: Text.PlainText
        text: panel.focusGame ? panel.focusGame.away.abbr : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(15)
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: " @ "
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(15)
      }
      Rectangle {
        width: Style.space(3)
        height: Style.space(12)
        radius: 1
        anchors.verticalCenter: parent.verticalCenter
        color: panel.focusGame ? Mlb.colorForAbbr(panel.focusGame.home.abbr) : "#7A7A7A"
      }
      Text {
        textFormat: Text.PlainText
        text: panel.focusGame ? panel.focusGame.home.abbr : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(15)
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        elide: Text.ElideRight
        width: parent.width - Style.space(120)
        text: panel.focusGame ? " · " + panel.safe(Mlb.compactDesc(panel.focusGame.desc), 44) : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(15)
        font.bold: true
      }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: {
        var g = panel.focusGame
        if (!g) return ""
        var when = g.mode === "final" ? "Final" :
                   g.mode === "live" ? "Live" :
                   panel.dayWord(g.startMs) + " " + panel.fmtTime(g.startMs)
        return when + " · " + panel.safe(g.venue, 44)
      }
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
    }
  }

  // ---- Section 1: individual game lines -----------------------------------
  PanelSectionHeader {
    visible: tab.odds !== null
    text: "GAME LINES"
    foreground: Color.popups.text
    font.letterSpacing: Style.space(2)
  }

  Text {
    visible: tab.hasFocus && tab.odds === null && panel.loadingOdds
    textFormat: Text.PlainText
    text: "Loading odds…"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  // Offseason and spring training say where the *next* lines come from
  // instead of a dead "no lines" message — the season tab's countdowns
  // carry over here via nextMilestone().
  Text {
    visible: tab.hasFocus && tab.odds === null && !panel.loadingOdds
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: tab.noLinesText()
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
  }

  Text {
    visible: !tab.hasFocus
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "No game selected — pick one in the Games tab."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  // Four tiles: the moneyline's favourite, its implied probability (from
  // the same price), the run line and the total — the latter two show the
  // book's juice in parentheses when it posts one alongside the price.
  Row {
    visible: tab.odds !== null
    width: parent.width
    spacing: Style.space(8)

    LineTile {
      width: (parent.width - Style.space(24)) / 4
      label: "MONEYLINE"
      value: tab.olv("mlFav")
      unit: ""
      sub: tab.olv("mlFavTeam") + " fav · " + tab.olv("mlDog")
    }
    LineTile {
      width: (parent.width - Style.space(24)) / 4
      label: "IMPLIED"
      value: tab.olv("favProb")
      unit: ""
      sub: tab.olv("mlFavTeam") + " win prob"
    }
    LineTile {
      width: (parent.width - Style.space(24)) / 4
      label: "RUN LINE"
      value: tab.olv("line")
      unit: ""
      sub: tab.olv("rlJuice")
    }
    LineTile {
      width: (parent.width - Style.space(24)) / 4
      label: "TOTAL"
      value: tab.olv("total")
      unit: ""
      sub: tab.olv("totJuice")
    }
  }

  // Today's slate: every game's current book line in one compact row.
  Column {
    visible: panel !== null && tab.slateGames.length > 0 && panel.loadingOdds === false
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "TODAY'S SLATE"
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }

    Repeater {
      model: tab.slateGames
      delegate: Row {
        width: tab.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          width: Style.space(64)
          text: {
            var g = modelData
            if (g.mode === "live") return "LIVE"
            return panel ? panel.fmtTime(g.startMs) : ""
          }
          color: modelData.mode === "live" ? Color.accent : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: modelData.mode === "live"
        }
        Row {
          spacing: Style.space(4)
          Rectangle {
            width: Style.space(3)
            height: Style.space(12)
            radius: 1
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.away ? Mlb.colorForAbbr(modelData.away.abbr) : "#7A7A7A"
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.away ? modelData.away.abbr : ""
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: " @ "
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
          }
          Rectangle {
            width: Style.space(3)
            height: Style.space(12)
            radius: 1
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.home ? Mlb.colorForAbbr(modelData.home.abbr) : "#7A7A7A"
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.home ? modelData.home.abbr : ""
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            font.bold: true
          }
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width - Style.space(64 + 120 + 16)
          elide: Text.ElideRight
          text: {
            var book = panel && panel.espnOdds
                 ? panel.espnOdds[modelData.away.abbr + "@" + modelData.home.abbr] : null
            return book ? Mlb.oddsLine(book)
                        : "Lines post closer to first pitch"
          }
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
        }
      }
    }
  }

  // Phase-aware copy for "the books have nothing for this game".
  function noLinesText() {
    if (!panel) return ""
    var ph = panel.currentPhase()
    var m = panel.nextMilestone()
    if (ph === "OFFSEASON")
      return m ? "Offseason — the next lines come with " + m.label + " " +
                 panel.fmtLong(m.ms - panel.nowMs) + "."
               : "Offseason — no game boards until the season starts."
    if (ph === "SPRING TRAINING")
      return m ? "Spring training lines are sparse — expect full boards by " +
                 m.label + " " + panel.fmtLong(m.ms - panel.nowMs) + "."
               : "Spring training lines are sparse right now."
    return "No book lines for this game yet — books post them before first pitch and drop them once play starts."
  }

  // Odds values derived once so the tile bindings stay one-liners.
  function olv(what) {
    var o = tab.odds
    if (!o) return "—"
    var favIsHome = o.spreadHome
    var favAbbr = favIsHome ? o.homeAbbr : o.awayAbbr
    var dogAbbr = favIsHome ? o.awayAbbr : o.homeAbbr
    var favMl = favIsHome ? o.mlHome : o.mlAway
    var dogMl = favIsHome ? o.mlAway : o.mlHome
    switch (what) {
      case "mlFav":     return favMl || "—"
      case "mlFavTeam": return favAbbr
      case "mlDog":     return dogAbbr + " " + (dogMl || "")
      case "line":
        if (o.spread === null || o.spread === undefined) return "—"
        var l = favIsHome ? o.spread : -o.spread
        return (l > 0 ? "+" : "") + l
      case "lineTeam":  return favAbbr
      case "total":     return o.total === null || o.total === undefined ? "—" : String(o.total)
      // Implied probability from the favourite's moneyline price; the
      // book's vig is why the two sides sum above 100%.
      case "favProb":
        var p = Mlb.americanProb(favMl)
        return p === null ? "—" : Math.round(p * 100) + "%"
      // Run line and total carry the juice on their sub-lines: the vig is
      // the book's cut, shown in parentheses next to each side's price.
      case "rlJuice":
        var rj = favIsHome ? o.rlHome : o.rlAway
        return rj ? favAbbr + " (" + rj + ")" : favAbbr
      case "totJuice":
        return o.overOdds ? "O " + o.overOdds + " · U " + o.underOdds : "Over/Under"
    }
    return ""
  }

  // ---- Section 2: World Series winner (tournament market) -----------------
  // A bordered card so it reads as the headline block it is: trophy header,
  // both books side by side, the implied favourite enlarged. Hides itself
  // once the markets resolve/close (parsers filter those out) — after the
  // Series the card simply leaves and the season-gap note below takes over.
  Rectangle {
    visible: panel !== null && (panel.polyWs.length > 0 || panel.kalshiWs.length > 0)
    width: parent.width
    height: wsCol.implicitHeight + Style.space(14)
    radius: Style.space(6)
    color: Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)

    Column {
      id: wsCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(7)
      spacing: Style.space(7)

      // Trophy header.
      Row {
        spacing: Style.space(7)
        Text {
          textFormat: Text.PlainText
          text: panel.trophy
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(15)
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: "WORLD SERIES WINNER"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(14)
          font.bold: true
          font.letterSpacing: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: "implied probability"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(10)
          font.italic: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Two books side by side.
      Row {
        width: parent.width
        spacing: Style.space(14)

        // Polymarket.
        Column {
          width: (parent.width - Style.space(14)) / 2
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            text: "POLYMARKET"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: Style.space(1)
          }
          Text {
            visible: panel.polyWs.length === 0
            textFormat: Text.PlainText
            text: "closed"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
          }
          Repeater {
            model: panel ? panel.polyWs : []
            delegate: MktRow {
              width: parent.width
              rowName: panel.safe(modelData.name, 22)
              rowAbbr: modelData.abbr
              rowColor: Mlb.colorForAbbr(modelData.abbr)
              rowProb: modelData.prob
              leader: index === 0
              showColors: panel.teamColorsOn
            }
          }
        }

        // Kalshi.
        Column {
          width: (parent.width - Style.space(14)) / 2
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            text: "KALSHI"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: Style.space(1)
          }
          Text {
            visible: panel.kalshiWs.length === 0
            textFormat: Text.PlainText
            text: "closed"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
          }
          Repeater {
            model: panel ? panel.kalshiWs : []
            delegate: MktRow {
              width: parent.width
              rowName: panel.safe(modelData.name, 22)
              rowAbbr: modelData.abbr
              rowColor: Mlb.colorForAbbr(modelData.abbr)
              rowProb: modelData.prob
              leader: index === 0
              showColors: panel.teamColorsOn
            }
          }
        }
      }
    }
  }

  // Markets resolved/closed (or the next season's aren't posted yet): the
  // card above hides itself — say why instead of leaving a hole.
  Text {
    visible: tab.noMarkets && panel !== null &&
             panel.currentPhase() !== "" && panel.currentPhase() !== "POSTSEASON"
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "No championship markets right now — they open during the season and close after the World Series."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
    font.italic: true
  }

  // ---- Budget footer -----------------------------------------------------
  Text {
    visible: panel !== null
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: {
      var b = panel.oddsBudget
      var h = Math.round(panel.oddsTtl / 3600)
      var cadence = h >= 24 ? Math.round(h / 24) + "d" : h + "h"
      return "Refresh: \u2264" + b + " pulls/source/month \u00B7 " +
             "cache held ~" + cadence + " \u00B7 stale served when capped"
    }
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(10)
  }

  // ---- Components ---------------------------------------------------------

  // A market row: the leader gets enlarged type and accent colour so the
  // favourite reads at a glance.
  component MktRow: Row {
    // Qt6 injects modelData/index into a delegate only when it declares them
    // required — without these the call-site bindings raise ReferenceError.
    required property var modelData
    required property int index
    required property string rowName
    required property string rowAbbr
    required property string rowColor
    required property real rowProb
    required property bool leader
    required property bool showColors
    // Fixed geometry: chip 4 + 3 gaps of 6 + abbr 48 + pct 56 leaves the
    // name column as the only flexible one — no underlap with the percent.
    spacing: Style.space(6)

    Rectangle {
      width: Style.space(4)
      height: Style.space(parent.leader ? 18 : 14)
      radius: 1
      anchors.verticalCenter: parent.verticalCenter
      visible: parent.showColors
      color: parent.rowColor
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(48)
      elide: Text.ElideRight
      text: parent.rowAbbr !== "" ? parent.rowAbbr : parent.rowName
      color: parent.leader ? Color.accent : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: parent.leader ? Style.space(15) : Style.space(12)
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width - Style.space(4 + 6 + 48 + 6 + 6 + 56)
      elide: Text.ElideRight
      text: parent.rowName
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: parent.leader ? Style.space(12) : Style.space(11)
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      width: Style.space(56)
      horizontalAlignment: Text.AlignRight
      text: (parent.rowProb * 100).toFixed(1) + "%"
      color: parent.leader ? Color.accent : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: parent.leader ? Style.space(17) : Style.space(13)
      font.bold: parent.leader
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Same shape as the Statcast tiles: label, big value, context line.
  component LineTile: Rectangle {
    property string label: ""
    property string value: ""
    property string unit: ""
    property string sub: ""
    height: tileCol.implicitHeight + Style.space(12)
    radius: Style.space(6)
    color: Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Column {
      id: tileCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(6)
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        text: label
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: Style.space(1)
      }
      Row {
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          text: value
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(22)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: unit
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          anchors.baseline: parent.children[0].baseline
        }
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: sub
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
    }
  }
}
