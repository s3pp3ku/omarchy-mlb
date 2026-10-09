import QtQuick
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// Games tab: a focus-game detail card (count/runners/last play when live,
// R-H-E line when final, probables when preview) over the today-and-ahead
// slice of the schedule (the schedule window reaches back 6 days so the
// Statcast selector can review recent games — past finals are filtered out
// here via schedule.today). The detail card follows the focus game;
// clicking a row re-focuses it.
Column {
  id: tab

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: tab.panel && tab.panel.hi !== undefined ? tab.panel.hi : Color.accent
  function wash(a) { return tab.panel && tab.panel.wash ? tab.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var panel: null
  spacing: Style.space(6)

  Text {
    visible: panel !== null && panel.schedule.today.length === 0
    width: parent.width
    textFormat: Text.PlainText
    text: panel.loadingSchedule ? "Loading games…" : "No games today or ahead"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  Text {
    visible: panel !== null && panel.schedule.today.length === 0 && !panel.loadingSchedule
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

  // Focus-game detail card.
  Rectangle {
    visible: panel !== null && panel.focusGame !== null && panel.feed !== null &&
             panel.feedPk === panel.focusGame.gamePk
    width: parent.width
    height: focusCol.implicitHeight + Style.space(12)
    radius: Style.space(6)
    color: tab.wash(0.04)
    border.width: 1
    border.color: panel.feedLive ? tab.hi : tab.wash(0.12)

    Column {
      id: focusCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(6)
      spacing: Style.space(4)

      // Score line + state.
      Row {
        spacing: Style.space(8)
        Rectangle {
          width: Style.space(3)
          height: Style.space(12)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: panel && panel.focusGame ? Mlb.colorForAbbr(panel.focusGame.away.abbr) : "#7A7A7A"
        }
        Text {
          textFormat: Text.PlainText
          text: panel.focusGame ? panel.focusGame.away.abbr : ""
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: panel.feed && panel.feed.awayRuns !== null ? String(panel.feed.awayRuns) : "-"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
        }
        Text {
          textFormat: Text.PlainText
          text: "@"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
        }
        Rectangle {
          width: Style.space(3)
          height: Style.space(12)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: panel && panel.focusGame ? Mlb.colorForAbbr(panel.focusGame.home.abbr) : "#7A7A7A"
        }
        Text {
          textFormat: Text.PlainText
          text: panel.focusGame ? panel.focusGame.home.abbr : ""
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: panel.feed && panel.feed.homeRuns !== null ? String(panel.feed.homeRuns) : "-"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
        }
        Item { width: Style.space(6); height: 1 }
        Text {
          textFormat: Text.PlainText
          text: {
            var f = panel.feed
            if (!f) return ""
            if (f.mode === "Live")
              return (f.inningState ? f.inningState + " " : "") + (f.inning || "") +
                     (f.outs !== null ? " · " + f.outs + " out" : "")
            if (f.mode === "Final") return "Final"
            return "First pitch " + (panel.focusGame ? panel.fmtTime(panel.focusGame.startMs) : "")
          }
          color: panel.feedLive ? tab.hi : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: panel.feedLive
        }
      }

      // Live: count + bases diamond + who's due.
      Row {
        visible: panel.feedLive
        spacing: Style.space(10)
        Text {
          textFormat: Text.PlainText
          text: {
            var f = panel.feed
            if (!f) return ""
            var bits = []
            if (f.balls !== null && f.strikes !== null)
              bits.push("B " + f.balls + " · S " + f.strikes)
            if (f.outs !== null) bits.push(f.outs + " out")
            return bits.join(" · ")
          }
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
        }
        BaseDiamond {
        panel: tab.panel
          on1: panel.feed ? panel.feed.on1 : false
          on2: panel.feed ? panel.feed.on2 : false
          on3: panel.feed ? panel.feed.on3 : false
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(190)
          elide: Text.ElideRight
          text: {
            var f = panel.feed
            if (!f) return ""
            if (f.batter) return panel.safe(f.batter, 24) + " up · " + panel.safe(f.pitcher, 20)
            return ""
          }
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
        }
      }

      // Live: last play.
      Text {
        // Single-expression guard: mixing a derived bool (feedLive) with a raw
        // feed read in one binding races when feed becomes null.
        visible: panel.feed && panel.feed.mode === "Live" && panel.feed.lastPlay !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        textFormat: Text.PlainText
        text: panel.feed ? panel.safe(panel.feed.lastPlay, 160) : ""
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }

      // Final: R-H-E line.
      Column {
        visible: panel.feed && panel.feed.mode === "Final" &&
                 panel.feed.awayRHE && panel.feed.awayRHE.r !== null
        spacing: Style.space(2)
        Row {
          spacing: Style.space(8)
          Text { textFormat: Text.PlainText; text: ""; width: Style.space(40) }
          RheHead { label: "R" }
          RheHead { label: "H" }
          RheHead { label: "E" }
        }
        Repeater {
          model: [
            { abbr: panel.focusGame ? panel.focusGame.away.abbr : "",
              rhe: panel.feed ? panel.feed.awayRHE : null },
            { abbr: panel.focusGame ? panel.focusGame.home.abbr : "",
              rhe: panel.feed ? panel.feed.homeRHE : null }
          ]
          delegate: Row {
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: modelData.abbr
              width: Style.space(40)
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
            }
            RheCell { value: modelData.rhe && modelData.rhe.r !== null ? String(modelData.rhe.r) : "-" }
            RheCell { value: modelData.rhe && modelData.rhe.h !== null ? String(modelData.rhe.h) : "-" }
            RheCell { value: modelData.rhe && modelData.rhe.e !== null ? String(modelData.rhe.e) : "-" }
          }
        }
      }

      // Preview: probables.
      Text {
        visible: panel.feed && panel.feed.mode === "Preview" &&
                 (panel.feed.awayProbable !== "" || panel.feed.homeProbable !== "")
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: {
          var f = panel.feed
          if (!f) return ""
          return "Probables: " + panel.safe(f.awayProbable || "TBD", 24) +
                 " vs " + panel.safe(f.homeProbable || "TBD", 24)
        }
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
    }
  }

  component RheHead: Text {
    required property string label
    textFormat: Text.PlainText
    text: label
    width: Style.space(24)
    color: Color.muted
    horizontalAlignment: Text.AlignRight
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
  }

  component RheCell: Text {
    required property string value
    textFormat: Text.PlainText
    text: value
    width: Style.space(24)
    color: Color.popups.text
    horizontalAlignment: Text.AlignRight
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
  }

  // The schedule list itself.
  Repeater {
    model: panel ? panel.boundedList(panel.schedule.today, 14) : []
    delegate: GameRow {
      panel: tab.panel
      game: modelData
      width: tab.width
      onPick: panel.focusGameFor(modelData.gamePk)
    }
  }

  component GameRow: Rectangle {
    id: gr
    property var panel: null
    property var game: ({})
    signal pick()
    height: rowCol.implicitHeight + Style.space(8)
    radius: Style.space(4)
    color: mouse.containsMouse ? tab.wash(0.06) : "transparent"

    readonly property bool focused: panel && panel.focusGame && game &&
                                     panel.focusGame.gamePk === game.gamePk
    readonly property bool involvesFav: panel && panel.favTeam !== "" && game &&
                                        (game.away.abbr === panel.favTeam ||
                                         game.home.abbr === panel.favTeam)
    function teamColor(side) {
      if (panel && panel.favTeam && side && side.abbr === panel.favTeam) return tab.hi
      return Color.popups.text
    }

    // Accent stripe marks the favorite team's games at a glance.
    Rectangle {
      visible: gr.involvesFav
      width: Style.space(3)
      height: parent.height - Style.space(6)
      radius: 1.5
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      color: tab.hi
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: gr.pick()
    }

    Column {
      id: rowCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(4)
      spacing: Style.space(1)

      Row {
        width: parent.width
        spacing: Style.space(8)

        // State / time.
        Text {
          textFormat: Text.PlainText
          width: Style.space(64)
          text: {
            var g = gr.game
            if (g.mode === "live")
              return "LIVE " + (g.inning ? (g.isTop ? "T" : "B") + g.inning : "")
            if (g.mode === "final") return "Final"
            return panel ? panel.fmtTime(g.startMs) : ""
          }
          color: gr.game.mode === "live" ? tab.hi : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: gr.game.mode === "live" || gr.focused
        }

        // Away. Chip is always laid out (transparent when team colors are
        // off) so the right-hand note column width stays exact.
        Rectangle {
          width: Style.space(3)
          height: Style.space(12)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: panel.teamColorsOn && gr.game.away
                 ? Mlb.colorForAbbr(gr.game.away.abbr) : "transparent"
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(34)
          horizontalAlignment: Text.AlignRight
          text: gr.game.away ? gr.game.away.abbr : ""
          color: gr.game.away && panel && panel.favTeam === gr.game.away.abbr ? tab.hi
                 : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: (gr.game.away && gr.game.away.score > gr.game.home.score) ||
                     gr.involvesFav && gr.game.away && panel && panel.favTeam === gr.game.away.abbr
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(22)
          horizontalAlignment: Text.AlignRight
          text: gr.game.away && gr.game.away.score !== null ? String(gr.game.away.score) : "-"
          color: gr.game.mode === "live" ? tab.hi : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: true
        }

        Item { width: Style.space(10); height: 1 }

        // Home.
        Rectangle {
          width: Style.space(3)
          height: Style.space(12)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: panel.teamColorsOn && gr.game.home
                 ? Mlb.colorForAbbr(gr.game.home.abbr) : "transparent"
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(34)
          horizontalAlignment: Text.AlignRight
          text: gr.game.home ? gr.game.home.abbr : ""
          color: gr.game.home && panel && panel.favTeam === gr.game.home.abbr ? tab.hi
                 : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: (gr.game.home && gr.game.home.score > gr.game.away.score) ||
                     gr.involvesFav && gr.game.home && panel && panel.favTeam === gr.game.home.abbr
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(22)
          horizontalAlignment: Text.AlignRight
          text: gr.game.home && gr.game.home.score !== null ? String(gr.game.home.score) : "-"
          color: gr.game.mode === "live" ? tab.hi : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: true
        }

        // Series / result note.
        Text {
          textFormat: Text.PlainText
          width: parent.width - Style.space(64 + 3 + 34 + 22 + 10 + 3 + 34 + 22 + 64)
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight
          text: gr.panel ? gr.panel.safe(Mlb.compactDesc(gr.game.desc), 32) : ""
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }
      }

      // Line 2: date plus the game's particulars — probable pitchers when a
      // preview feed has been queued, winning decisions when final, venue
      // otherwise. One line, elided.
      Text {
        textFormat: Text.PlainText
        width: parent.width
        elide: Text.ElideRight
        text: {
          var g = gr.game
          if (!g || !g.startMs) return ""
          var bits = [Qt.formatDateTime(new Date(g.startMs), "ddd d MMM")]
          // Where it's on, for anything not over yet.
          if (g.mode !== "final" && g.media && g.media.tv.length)
            bits.push(panel.safe(g.media.tv.slice(0, 2).join(", "), 36))
          var p = panel && panel.feeds ? panel.feeds[g.gamePk] : null
          if (g.mode === "preview") {
            if (p && (p.awayProbable || p.homeProbable))
              bits.push("Probables: " + panel.safe(p.awayProbable || "TBD", 18) +
                        " vs " + panel.safe(p.homeProbable || "TBD", 18))
            else if (g.venue) bits.push(g.venue)
          } else if (g.mode === "final") {
            if (g.winnerName) bits.push("W " + panel.safe(g.winnerName, 16))
            if (g.loserName) bits.push("L " + panel.safe(g.loserName, 16))
            if (g.saveName) bits.push("S " + panel.safe(g.saveName, 16))
            else if (g.venue) bits.push(g.venue)
          } else if (g.venue) {
            bits.push(g.venue)
          }
          return bits.join(" · ")
        }
        color: Color.popups.text
        opacity: 0.72
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }
    }
  }
}
