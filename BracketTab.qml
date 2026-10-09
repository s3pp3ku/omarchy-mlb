import QtQuick
import qs.Commons
import qs.Ui

// Bracket tab: four fixed columns (WC, DS, CS, WS) with connector elbows
// under the cards. Geometry comes from mlb.js buildBracketLayout — the
// Canvas and the card Repeater both render that one model, so they can't
// drift apart.
//
// Once the World Series is decided the tab leads with ChampionRecap (the
// champion card, their road, the Series game by game); the finished bracket
// is one click away on the sub-toggle.
Column {
  id: tab

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: tab.panel && tab.panel.hi !== undefined ? tab.panel.hi : Color.accent
  function wash(a) { return tab.panel && tab.panel.wash ? tab.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var panel: null
  spacing: Style.space(8)

  property string subView: "recap"
  readonly property bool hasChamp: panel !== null && panel.champPath !== null
  readonly property bool showBracket: panel !== null && panel.series.length > 0 &&
                                      (!hasChamp || subView === "bracket")

  Item {
    visible: tab.hasChamp
    width: parent.width
    height: subToggle.implicitHeight
    ButtonGroup {
      id: subToggle
      options: [
        { value: "recap", label: "Champions" },
        { value: "bracket", label: "Bracket" }
      ]
      value: tab.subView
      focusable: false
      foreground: Color.popups.text
      background: Color.popups.background
      accent: tab.hi
      fontSize: Style.space(11)
      onChanged: function(v) { tab.subView = v }
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: panel ? panel.bracketSeason + " POSTSEASON" : ""
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
      font.letterSpacing: Style.space(2)
    }
  }

  ChampionRecap {
    panel: tab.panel
    width: parent.width
    visible: tab.hasChamp && tab.subView === "recap"
  }

  // Champion banner above the finished bracket.
  Row {
    visible: tab.showBracket && tab.hasChamp
    spacing: Style.space(7)
    Text {
      textFormat: Text.PlainText
      text: panel.trophy
      color: tab.hi
      font.family: Style.font.family
      font.pixelSize: Style.space(13)
    }
    Text {
      textFormat: Text.PlainText
      text: panel.champion() ? panel.safe(panel.champion().name, 30) + " win the " +
                               panel.bracketSeason + " World Series" : ""
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.space(13)
      font.bold: true
    }
  }

  Text {
    visible: panel !== null && panel.series.length === 0
    width: parent.width
    textFormat: Text.PlainText
    text: panel.loadingBracket ? "Loading bracket…" : "No postseason data for " + panel.thisYear
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  Text {
    visible: panel !== null && panel.series.length === 0 && !panel.loadingBracket
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: {
      var m = panel.nextMilestone()
      return m ? m.label + " " + panel.fmtLong(m.ms - panel.nowMs) : ""
    }
    color: tab.hi
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
    font.bold: true
  }

  Item {
    visible: tab.showBracket
    width: parent.width
    height: bracketBox.height + 2

    Item {
      id: bracketBox
      x: Math.max(0, Math.round((parent.width - width) / 2))
      width: panel ? panel.bracketLayout.width : 0
      height: panel ? panel.bracketLayout.height : 0

      // Connector elbows: pre-flattened axis-aligned rectangles from
      // mlb.js (buildBracketLayout.segs), rendered as plain Rectangles —
      // no Canvas, no nested repeaters.
      Repeater {
        model: panel ? panel.bracketLayout.segs : []
        delegate: Rectangle {
          required property var modelData
          x: modelData.x
          y: modelData.y
          width: modelData.w
          height: modelData.h
          radius: 1
          color: Color.popups.text
          opacity: 0.3
        }
      }

      Repeater {
        model: panel ? panel.bracketLayout.cards : []
        delegate: SeriesCard {
          panel: tab.panel
          card: modelData
          x: modelData.x
          y: modelData.y
        }
      }
    }
  }

  // A bracket series card: header (series label + status), one row per team
  // with the series win count. Winner bold, favorite team accented, undecided
  // slots muted "TBD".
  // Legend fills the fixed-size panel's lower half and explains the marks.
  Column {
    visible: tab.showBracket
    width: parent.width
    spacing: Style.space(3)
    Row {
      visible: !tab.hasChamp
      spacing: Style.space(6)
      Text {
        textFormat: Text.PlainText
        text: "\u25CF"
        color: tab.hi
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }
      Text {
        textFormat: Text.PlainText
        text: "live series \u00B7 accent border marks the game in progress"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Numbers are series wins \u00B7 bold team has clinched \u00B7 click a card for MLB Gameday"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
    }
  }

  component SeriesCard: Rectangle {
    id: sc
    property var panel: null
    property var card: ({})
    readonly property var s: card ? card.series : null
    width: card.w || 124
    height: card.h || 74
    radius: Style.space(5)
    color: hoverSc.containsMouse ? tab.wash(0.07) : tab.wash(0.035)
    border.width: 1
    border.color: s && s.mode === "live" ? tab.hi : tab.wash(0.1)

    function statusText() {
      if (!s) return ""
      if (s.clinched !== null) return "Final"
      if (s.mode === "live") {
        for (var i = 0; i < s.games.length; i++) {
          var g = s.games[i]
          if (g.mode === "live")
            return g.away.score + "-" + g.home.score +
                   (g.inning ? " " + (g.isTop ? "T" : "B") + g.inning : "")
        }
        return "LIVE"
      }
      if (s.mode === "preview" && s.nextGame) {
        // Card space is tight: "Tomorrow" would elide the series label, so
        // only today's game shows its time; the rest show the weekday.
        var ms = s.nextGame.startMs
        return panel.sameDay(ms) ? panel.fmtTime(ms)
             : Qt.formatDateTime(new Date(ms), "ddd")
      }
      return "Final"
    }

    function winsFor(team) { return s ? (s.wins[team.id] || 0) : 0 }
    function isWinner(team) { return s && s.clinched === team.id }
    function isFav(team) { return panel && panel.favTeam !== "" && team.abbr === panel.favTeam }
    function showColors(team) { return panel && panel.teamColorsOn && !team.placeholder }

    MouseArea {
      id: hoverSc
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: sc.s && sc.s.games.length ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (!sc.s || !sc.panel) return
        // Open the series' most relevant game: a live one, else the next.
        var target = null
        for (var i = 0; i < sc.s.games.length; i++) {
          if (sc.s.games[i].mode === "live") { target = sc.s.games[i]; break }
          if (!target && sc.s.games[i].mode !== "final") target = sc.s.games[i]
        }
        if (!target) target = sc.s.games[0]
        if (target) sc.panel.openLink(sc.panel.gamedayUrl(target.gamePk))
      }
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: 0

      // Header: series label left, status right.
      Row {
        width: parent.width
        spacing: Style.space(4)
        Text {
          textFormat: Text.PlainText
          width: parent.width - statusText.width - Style.space(4)
          elide: Text.ElideRight
          text: sc.s ? sc.s.label : ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.bold: true
          font.letterSpacing: Style.space(1)
        }
        Text {
          id: statusText
          textFormat: Text.PlainText
          text: sc.statusText()
          color: sc.s && sc.s.mode === "live" ? tab.hi : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.bold: sc.s && sc.s.mode === "live"
        }
      }

      Repeater {
        model: sc.s ? sc.s.teams : []
        delegate: Item {
          width: parent.width
          height: Style.space(19)
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Rectangle {
              width: Style.space(4)
              height: Style.space(16)
              radius: 1
              anchors.verticalCenter: parent.verticalCenter
              visible: sc.showColors(modelData)
              color: sc.showColors(modelData) ? modelData.color : "transparent"
            }
            Text {
              textFormat: Text.PlainText
              text: modelData.abbr
              color: modelData.placeholder ? Color.muted
                     : sc.isFav(modelData) ? tab.hi
                     : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(14)
              font.bold: sc.isWinner(modelData) || sc.isFav(modelData)
              opacity: sc.s && sc.s.clinched !== null && !sc.isWinner(modelData) ? 0.55 : 1.0
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(sc.winsFor(modelData))
            color: sc.isWinner(modelData) ? tab.hi : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(14)
            font.bold: sc.isWinner(modelData)
          }
        }
      }
    }
  }
}
