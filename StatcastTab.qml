import QtQuick
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// Statcast tab for the focus game: three headline tiles (hardest hit,
// longest ball, fastest pitch), a secondary strip of rate/count stats from
// the same tracking feed, then the full exit-velo and pitch-speed
// leaderboards. All of it comes from the game feed's hitData/pitchData —
// the same numbers Baseball Savant charts — plus outbound links.
Column {
  id: tab
  property var panel: null
  spacing: Style.space(8)

  readonly property var f: (panel !== null && panel.feed !== null &&
                            panel.focusGame !== null &&
                            panel.feedPk === panel.focusGame.gamePk)
    ? panel.feed : null
  readonly property bool hasFeed: f !== null

  // Tile values via guards: QML evaluates every binding regardless of
  // `visible`, so a bare `f.topHits[0]` would throw before the feed loads.
  // Surnames only in the narrow tiles ("Yelich · 105.4 mph") — full names
  // elided mid-first-name at this width.
  function last(name) {
    var parts = String(name || "").trim().split(/\s+/)
    return parts.length > 1 ? parts[parts.length - 1] : (parts[0] || "")
  }
  function hitEv() { return f && f.topHits.length ? f.topHits[0].ev.toFixed(1) : "—" }
  function hitSub() {
    if (!f || !f.topHits.length) return ""
    var h = f.topHits[0]
    return tab.last(h.player) + (h.dist > 0 ? " · " + Math.round(h.dist) + " ft" : "")
  }
  function longestFt() { return f && f.longest && f.longest.dist > 0 ? String(Math.round(f.longest.dist)) : "—" }
  function longestSub() {
    if (!f || !f.longest) return ""
    return tab.last(f.longest.player) +
           (f.longest.ev > 0 ? " · " + f.longest.ev.toFixed(1) + " mph" : "")
  }
  function fastestMph() { return f && f.fastest ? f.fastest.speed.toFixed(1) : "—" }
  function fastestSub() { return f && f.fastest ? tab.last(f.fastest.pitcher) : "" }
  // Chip band color for which team a hit/pitch belongs to, set from the play's
  // half-inning side in mlb.js. Falls back to neutral grey without a focus game.
  function sideColor(side) {
    var g = panel ? panel.focusGame : null;
    if (!g) return "#7A7A7A";
    return Mlb.colorForAbbr(side === "away" ? g.away.abbr : g.home.abbr);
  }
  function avgExit() { return f && f.avgEv > 0 ? f.avgEv.toFixed(1) + " mph" : "—" }
  function hardHits() { return f ? f.hardHits + " ≥95" : "—" }
  function pitchCount() { return f ? String(f.pitches) : "—" }
  function hrK() { return f ? f.homeRuns + " · " + f.strikeouts : "—" }

  // Game header + venue.
  Column {
    visible: panel !== null && panel.focusGame !== null
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
        var st = g.mode === "final" ? "Final" :
                 g.mode === "live" ? "Live" :
                 panel.dayWord(g.startMs) + " " + panel.fmtTime(g.startMs)
        return st + " · " + panel.safe(g.venue, 44)
      }
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
    }
  }

  // Matchup selector: today's slate (live first), so you can flip between
  // games' statcast — including ones that already ended. Click pins the
  // game; click again to return to auto-follow.
  Flow {
    visible: panel !== null && panel.focusGame !== null
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: panel !== null ? Mlb.selectorGames(panel.schedule.games, 8) : []
      delegate: Rectangle {
        required property var modelData
        width: chipText.implicitWidth + Style.space(14)
        height: Style.space(22)
        radius: Style.space(4)
        readonly property bool isFocus: panel.focusGame &&
                                        panel.focusGame.gamePk === modelData.gamePk
        readonly property bool pinned: panel.focusOverride === modelData.gamePk
        color: pinned ? Color.accent
             : isFocus ? Qt.rgba(1, 1, 1, 0.14)
             : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1)
             : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: modelData.mode === "live" && !pinned ? Color.accent
                    : pinned ? Color.accent
                    : Qt.rgba(1, 1, 1, 0.14)

        Text {
          id: chipText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: {
            var g = modelData
            var head = g.away.abbr + " \u00B7 " + g.home.abbr
            if (g.mode === "live") return head + " \u25CF"
            if (g.mode === "preview") return head
            return head + " " + (g.away.score !== null ? g.away.score : "?") +
                   "-" + (g.home.score !== null ? g.home.score : "?")
          }
          color: pinned ? Color.popups.background
               : modelData.mode === "live" ? Color.accent
               : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.bold: isFocus || modelData.mode === "live"
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            // Click the pinned chip again to release back to auto-follow.
            if (panel.focusOverride === modelData.gamePk) panel.focusGameFor(-1)
            else panel.focusGameFor(modelData.gamePk)
          }
        }
      }
    }
  }

  // When the just-ended hold is active, say so — otherwise it looks like
  // the tab simply failed to move on.
  Text {
    visible: panel !== null && panel.holdPk > 0 && panel.nowMs < panel.holdUntil &&
             panel.focusGame !== null && panel.focusGame.gamePk === panel.holdPk
    width: parent.width
    textFormat: Text.PlainText
    text: "Showing final stats \u00B7 auto-advances in " +
          panel.fmtShort(panel.holdUntil - panel.nowMs)
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
    font.italic: true
  }

  Text {
    visible: panel !== null && panel.focusGame !== null && panel.loadingFeed && !hasFeed
    textFormat: Text.PlainText
    text: "Loading statcast…"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  // Preview state: no tracking data until first pitch.
  Text {
    visible: f !== null && f.mode === "Preview"
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: f === null ? "" : (f.awayProbable || f.homeProbable)
      ? "Probables: " + panel.safe(f.awayProbable || "TBD", 24) + " vs " +
        panel.safe(f.homeProbable || "TBD", 24) + ". Statcast appears once the first pitch is thrown."
      : "Statcast appears once the first pitch is thrown."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
  }

  Text {
    visible: f !== null && f.mode !== "Preview" && f.topHits.length === 0
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "No batted-ball tracking for this game yet."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  // ---- Headline tiles -----------------------------------------------------
  Row {
    visible: f !== null && f.topHits.length > 0
    width: parent.width
    spacing: Style.space(8)

    StatTile {
      width: (parent.width - Style.space(16)) / 3
      label: "HARDEST HIT"
      value: tab.hitEv()
      unit: "mph"
      sub: tab.hitSub()
    }
    StatTile {
      width: (parent.width - Style.space(16)) / 3
      label: "LONGEST BALL"
      value: tab.longestFt()
      unit: tab.longestFt() === "—" ? "" : "ft"
      sub: tab.longestSub()
    }
    StatTile {
      width: (parent.width - Style.space(16)) / 3
      label: "FASTEST PITCH"
      value: tab.fastestMph()
      unit: tab.fastestMph() === "—" ? "" : "mph"
      sub: tab.fastestSub()
    }
  }

  // ---- Rate/count strip ---------------------------------------------------
  Row {
    visible: f !== null && f.mode !== "Preview" && f.batted > 0
    width: parent.width
    spacing: Style.space(8)

    StatChip { width: (parent.width - Style.space(24)) / 4
      label: "AVG EXIT"; value: tab.avgExit() }
    StatChip { width: (parent.width - Style.space(24)) / 4
      label: "HARD HITS"; value: tab.hardHits() }
    StatChip { width: (parent.width - Style.space(24)) / 4
      label: "PITCHES"; value: tab.pitchCount() }
    StatChip { width: (parent.width - Style.space(24)) / 4
      label: "HR · K"; value: tab.hrK() }
  }

  // ---- Exit-velo leaderboard ----------------------------------------------
  Column {
    visible: f !== null && f.topHits.length > 0
    width: parent.width
    spacing: Style.space(4)
    PanelSectionHeader {
      text: "TOP EXIT VELOCITIES"
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }
    Repeater {
      model: f !== null ? f.topHits : []
      delegate: Row {
        width: tab.width
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          width: Style.space(58)
          horizontalAlignment: Text.AlignRight
          text: modelData.ev.toFixed(1)
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(14)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: "mph"
          width: Style.space(32)
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: Style.space(3)
          height: Style.space(12)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: tab.sideColor(modelData.side)
        }
        Text {
          textFormat: Text.PlainText
          width: tab.width - Style.space(58 + 32 + 70 + 24 + 11)
          elide: Text.ElideRight
          text: panel.safe(modelData.player, 32)
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(14)
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(70)
          horizontalAlignment: Text.AlignRight
          text: modelData.dist > 0 ? Math.round(modelData.dist) + " ft" : ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
        }
      }
    }
  }

  // ---- Pitch-speed leaderboard --------------------------------------------
  Column {
    visible: f !== null && f.topPitches && f.topPitches.length > 0
    width: parent.width
    spacing: Style.space(4)
    PanelSectionHeader {
      text: "FASTEST PITCHES"
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }
    Repeater {
      model: f !== null && f.topPitches ? f.topPitches : []
      delegate: Row {
        width: tab.width
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          width: Style.space(58)
          horizontalAlignment: Text.AlignRight
          text: modelData.speed.toFixed(1)
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(14)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: "mph"
          width: Style.space(32)
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: Style.space(3)
          height: Style.space(12)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          color: tab.sideColor(modelData.side)
        }
        Text {
          textFormat: Text.PlainText
          width: tab.width - Style.space(58 + 32 + 8 + 11)
          elide: Text.ElideRight
          text: panel.safe(modelData.pitcher, 36)
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(14)
        }
      }
    }
  }

  // ---- Season sections ------------------------------------------------------
  // Full-season stats for the teams playing in the focus game and for the
  // whole league — useful when a game is on, but these sections stand alone
  // between games. Data: MLB stats API (teams/stats + stats/leaders), 2026
  // regular season.
  readonly property var focusRowAway: panel !== null && panel.focusGame !== null
                     && panel.teamStatsById[panel.focusGame.away.id] !== undefined
                     ? panel.teamStatsById[panel.focusGame.away.id] : null
  readonly property var focusRowHome: panel !== null && panel.focusGame !== null
                     && panel.teamStatsById[panel.focusGame.home.id] !== undefined
                     ? panel.teamStatsById[panel.focusGame.home.id] : null
  readonly property string statsSeasonLabel: panel !== null
    ? String(panel.thisYear) + " REGULAR SEASON"
    : String(new Date().getFullYear()) + " REGULAR SEASON"

  Column {
    visible: panel !== null && panel.teamStatsRows.length > 0 && panel.focusGame !== null
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "MATCHUP — " + tab.statsSeasonLabel
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }

    Rectangle {
      width: parent.width
      height: mCol.implicitHeight + Style.space(14)
      radius: Style.space(6)
      color: Qt.rgba(1, 1, 1, 0.04)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)

      Column {
        id: mCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(7)
        spacing: Style.space(2)

        // Header: blank label, chip+abbr for the away and home teams.
        Row {
          width: parent.width
          spacing: Style.space(8)
          Item { width: Style.space(70); height: 1 }
          Row {
            width: (parent.width - Style.space(70) - Style.space(16)) / 2
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
              font.bold: true
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
            }
          }
          Row {
            width: (parent.width - Style.space(70) - Style.space(16)) / 2
            spacing: Style.space(5)
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
              font.bold: true
              font.family: Style.font.family
              font.pixelSize: Style.space(13)
            }
          }
        }

        MatchupRow { fullWidth: parent.width; label: "RECORD"
          v1: tab.focusRowAway ? tab.focusRowAway.record : "—"
          v2: tab.focusRowHome ? tab.focusRowHome.record : "—" }
        MatchupRow { fullWidth: parent.width; label: "R/G"
          v1: tab.focusRowAway ? tab.focusRowAway.runsPer : "—"
          v2: tab.focusRowHome ? tab.focusRowHome.runsPer : "—" }
        MatchupRow { fullWidth: parent.width; label: "RA/G"
          v1: tab.focusRowAway ? tab.focusRowAway.againstPer : "—"
          v2: tab.focusRowHome ? tab.focusRowHome.againstPer : "—" }
        MatchupRow { fullWidth: parent.width; label: "AVG"
          v1: tab.focusRowAway ? tab.focusRowAway.avg : "—"
          v2: tab.focusRowHome ? tab.focusRowHome.avg : "—" }
        MatchupRow { fullWidth: parent.width; label: "HR"
          v1: tab.focusRowAway ? String(tab.focusRowAway.homeRuns) : "—"
          v2: tab.focusRowHome ? String(tab.focusRowHome.homeRuns) : "—" }
        MatchupRow { fullWidth: parent.width; label: "ERA"
          v1: tab.focusRowAway ? tab.focusRowAway.era : "—"
          v2: tab.focusRowHome ? tab.focusRowHome.era : "—" }
        MatchupRow { fullWidth: parent.width; label: "WHIP"
          v1: tab.focusRowAway ? tab.focusRowAway.whip : "—"
          v2: tab.focusRowHome ? tab.focusRowHome.whip : "—" }
        MatchupRow { fullWidth: parent.width; label: "STRIKEOUTS"
          v1: tab.focusRowAway ? String(tab.focusRowAway.strikeOuts) : "—"
          v2: tab.focusRowHome ? String(tab.focusRowHome.strikeOuts) : "—" }
      }
    }
  }

  // Full league table — every team, sortable-by-result, so there is always
  // something to slice by season rate lines between games.
  Column {
    visible: panel !== null && panel.teamStatsRows.length > 0
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "TEAM TABLE — " + tab.statsSeasonLabel
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }

    Column {
      width: parent.width
      spacing: Style.space(2)
      Row {
        id: thRow
        width: parent.width
        spacing: Style.space(6)
        Rectangle { width: Style.space(3); height: Style.space(10); color: "transparent" }
        Text { textFormat: Text.PlainText; width: Style.space(44); text: "" }
        TeamTh { value: "W-L" }
        TeamTh { value: "R/G" }
        TeamTh { value: "RA/G" }
        TeamTh { value: "AVG" }
        TeamTh { value: "HR" }
        TeamTh { value: "ERA" }
        TeamTh { value: "WHIP" }
      }
      Repeater {
        model: panel !== null ? panel.teamStatsRows : []
        delegate: Row {
          required property var modelData
          width: parent.width
          spacing: Style.space(6)
          Rectangle {
            width: Style.space(3)
            height: Style.space(12)
            radius: 1
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.color
          }
          Text {
            textFormat: Text.PlainText
            width: Style.space(44)
            text: modelData.abbr
            color: {
              var g = panel.focusGame
              return g && (g.away.id === modelData.id || g.home.id === modelData.id)
                  ? Color.accent : Color.popups.text
            }
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            font.bold: true
          }
          TeamTd { value: modelData.record }
          TeamTd { value: modelData.runsPer }
          TeamTd { value: modelData.againstPer }
          TeamTd { value: modelData.avg }
          TeamTd { value: String(modelData.homeRuns) }
          TeamTd { value: modelData.era }
          TeamTd { value: modelData.whip }
        }
      }
    }
  }

  // League leaders for the season — hitting and pitching boards.
  Column {
    visible: panel !== null && panel.leaders.length > 0
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "LEAGUE LEADERS — " + tab.statsSeasonLabel
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)

      Repeater {
        model: panel !== null ? panel.leaders : []
        delegate: Rectangle {
          required property var modelData
          width: (parent.width - Style.space(16)) / 3
          height: leadCol.implicitHeight + Style.space(12)
          radius: Style.space(6)
          color: Qt.rgba(1, 1, 1, 0.04)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)

          Column {
            id: leadCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(6)
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: modelData.label
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(9)
              font.bold: true
              font.letterSpacing: Style.space(1)
            }
            Repeater {
              model: modelData.rows
              delegate: Row {
                spacing: Style.space(4)
                Text {
                  textFormat: Text.PlainText
                  width: (parent.parent.width - Style.space(60))
                  elide: Text.ElideRight
                  text: modelData.rank + ". " + panel.safe(modelData.name, 24)
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                }
                Text {
                  textFormat: Text.PlainText
                  horizontalAlignment: Text.AlignRight
                  width: Style.space(56)
                  text: modelData.value
                  color: Color.accent
                  font.bold: true
                  font.family: Style.font.family
                  font.pixelSize: Style.space(12)
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- Outbound links to the two sources this data comes from -------------
  Row {
    visible: panel !== null && panel.focusGame !== null
    spacing: Style.space(14)
    Text {
      textFormat: Text.PlainText
      text: "MLB Gameday ↗"
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
      font.underline: linkMouse1.containsMouse
      MouseArea {
        id: linkMouse1
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.openLink(panel.gamedayUrl(panel.focusGame.gamePk))
      }
    }
    Text {
      textFormat: Text.PlainText
      text: "Baseball Savant ↗"
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
      font.underline: linkMouse2.containsMouse
      MouseArea {
        id: linkMouse2
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.openLink(panel.savantUrl(panel.focusGame.gamePk))
      }
    }
  }

  // ---- Tile components ----------------------------------------------------
  // Big number card for a headline Statcast metric.
  component StatTile: Rectangle {
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

  // Team table: bold muted header cell / plain data cell (fixed widths, right-aligned).
  component TeamTh: Text {
    property string value: ""
    text: value
    width: Style.space(46)
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(10)
    font.bold: true
  }
  component TeamTd: Text {
    property string value: ""
    text: value
    width: Style.space(46)
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
  }

  // Matchup card: label on the left, two team values centered in their columns.
  component MatchupRow: Row {
    required property string label
    required property string v1
    required property string v2
    property real fullWidth: 0
    width: parent.width
    spacing: Style.space(8)
    Text {
      textFormat: Text.PlainText
      width: Style.space(70)
      text: parent.label
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
    }
    Text {
      textFormat: Text.PlainText
      width: (parent.width - Style.space(70) - Style.space(16)) / 2
      horizontalAlignment: Text.AlignHCenter
      text: parent.v1
      color: Color.popups.text
      font.bold: true
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
    }
    Text {
      textFormat: Text.PlainText
      width: (parent.width - Style.space(70) - Style.space(16)) / 2
      horizontalAlignment: Text.AlignHCenter
      text: parent.v2
      color: Color.popups.text
      font.bold: true
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
    }
  }

  // Compact label/value chip for the secondary stat strip.
  component StatChip: Rectangle {
    property string label: ""
    property string value: ""
    height: chipCol.implicitHeight + Style.space(8)
    radius: Style.space(5)
    color: Qt.rgba(1, 1, 1, 0.03)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)

    Column {
      id: chipCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(5)
      spacing: 0
      Text {
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        text: label
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(9)
        font.bold: true
        font.letterSpacing: Style.space(1)
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        text: value
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(14)
        font.bold: true
      }
    }
  }
}
