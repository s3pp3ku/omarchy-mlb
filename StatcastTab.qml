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

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: tab.panel && tab.panel.hi !== undefined ? tab.panel.hi : Color.accent
  function wash(a) { return tab.panel && tab.panel.wash ? tab.panel.wash(a) : Util.alpha(Color.popups.text, a) }
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
        color: pinned ? tab.hi
             : isFocus ? tab.wash(0.14)
             : chipMouse.containsMouse ? tab.wash(0.1)
             : tab.wash(0.05)
        border.width: 1
        border.color: modelData.mode === "live" && !pinned ? tab.hi
                    : pinned ? tab.hi
                    : tab.wash(0.14)

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
               : modelData.mode === "live" ? tab.hi
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
          color: tab.hi
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
          color: tab.hi
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
  // ---- Baseball Savant: this game -----------------------------------------
  // From Savant's Gamefeed (panel.savantGame): what the MLB feed can't say —
  // expected batting average per ball, barrels, bat speed, park-adjusted
  // homers, and each starter's arsenal with spin.
  readonly property var sv: (panel !== null && panel.savantGame !== null && panel.focusGame !== null &&
                             panel.savantGamePk === panel.focusGame.gamePk) ? panel.savantGame : null

  function xba(v) { return v === null || v === undefined ? "" : "xBA " + v.toFixed(3).replace(/^0/, "") }

  Column {
    visible: tab.sv !== null && tab.sv.batted > 0
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader {
      text: "BASEBALL SAVANT — THIS GAME"
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }

    Row {
      width: parent.width
      spacing: Style.space(8)
      StatChip { width: (parent.width - Style.space(16)) / 3
        label: "BARRELS " + (panel && panel.focusGame ? panel.focusGame.away.abbr : "")
        value: tab.sv ? String(tab.sv.barrels.away) : "—" }
      StatChip { width: (parent.width - Style.space(16)) / 3
        label: "BARRELS " + (panel && panel.focusGame ? panel.focusGame.home.abbr : "")
        value: tab.sv ? String(tab.sv.barrels.home) : "—" }
      StatChip { width: (parent.width - Style.space(16)) / 3
        label: "FASTEST SWING"
        value: tab.sv && tab.sv.swings.length ? tab.sv.swings[0].batSpeed.toFixed(1) + " mph" : "—" }
    }

    Repeater {
      model: tab.sv ? [
        { title: "TOUGHEST OUTS", hint: "best contact that still got caught", rows: tab.sv.hardOuts, kind: "xba" },
        { title: "CHEAPEST HITS", hint: "lowest expected average that fell in", rows: tab.sv.cheapHits, kind: "xba" },
        { title: "ALMOST GONE", hint: "would have been a homer in other parks", rows: tab.sv.nearHrs, kind: "parks" },
        { title: "FASTEST SWINGS", hint: "bat speed at contact", rows: tab.sv.swings, kind: "bat" }
      ] : []
      delegate: Column {
        id: svGroup
        required property var modelData
        visible: modelData.rows.length > 0
        width: tab.width
        spacing: Style.space(2)
        Row {
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            text: modelData.title
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: Style.space(1)
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.hint
            color: Color.muted
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.italic: true
          }
        }
        Repeater {
          model: modelData.rows
          delegate: Row {
            id: svRow
            required property var modelData
            readonly property string kind: svGroup.modelData.kind
            width: tab.width
            spacing: Style.space(6)
            Rectangle {
              width: Style.space(3)
              height: Style.space(14)
              radius: 1
              anchors.verticalCenter: parent.verticalCenter
              color: tab.sideColor(svRow.modelData.side)
            }
            Text {
              width: Style.space(170)
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: panel ? panel.safe(svRow.modelData.player, 28) : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
            }
            Text {
              width: tab.width - Style.space(170) - Style.space(110) - Style.space(24)
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: panel ? panel.safe(svRow.modelData.event, 16) +
                    (svRow.modelData.ev !== null ? " · " + svRow.modelData.ev.toFixed(1) + " mph" : "") +
                    (svRow.modelData.dist ? " · " + Math.round(svRow.modelData.dist) + " ft" : "") : ""
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
            }
            Text {
              width: Style.space(110)
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: svRow.kind === "parks" ? svRow.modelData.parks + "/30 parks"
                  : svRow.kind === "bat" ? (svRow.modelData.batSpeed !== null ? svRow.modelData.batSpeed.toFixed(1) + " mph" : "")
                  : tab.xba(svRow.modelData.xba)
              color: tab.hi
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
            }
          }
        }
      }
    }

    // Starters' arsenals with spin (Savant tracks spin; MLB's feed rounds it away).
    Text {
      visible: tab.sv !== null && tab.sv.arsenals.length > 0
      textFormat: Text.PlainText
      text: "STARTERS' ARSENALS"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(10)
      font.bold: true
      font.letterSpacing: Style.space(1)
    }
    Row {
      width: parent.width
      spacing: Style.space(10)
      Repeater {
        model: tab.sv ? tab.sv.arsenals : []
        delegate: Rectangle {
          id: arsCard
          required property var modelData
          width: (tab.width - Style.space(10)) / 2
          height: arsCol.implicitHeight + Style.space(14)
          radius: Style.space(6)
          color: tab.wash(0.04)
          border.width: 1
          border.color: tab.wash(0.12)
          Column {
            id: arsCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(7)
            spacing: Style.space(2)
            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: panel ? panel.safe(arsCard.modelData.pitcher, 28) + " · " + arsCard.modelData.total + " pitches" : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
            }
            Repeater {
              model: arsCard.modelData.mix.length > 6 ? arsCard.modelData.mix.slice(0, 6) : arsCard.modelData.mix
              delegate: Row {
                required property var modelData
                spacing: Style.space(5)
                Rectangle {
                  width: Style.space(8); height: width; radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: tab.panel.pitchColor(Mlb.PITCH_CODE_BY_NAME[modelData.type] || "")
                }
                Text {
                  width: Style.space(96)
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: panel ? panel.safe(Mlb.shortPitch(modelData.type), 18) : ""
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                }
                Text {
                  width: arsCol.width - Style.space(96) - Style.space(8) - Style.space(10)
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: modelData.pct + "%" +
                        (modelData.velo !== null ? " · " + modelData.velo.toFixed(1) + " mph" : "") +
                        (modelData.spin !== null ? " · " + modelData.spin + " rpm" : "")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- Starters' Savant percentiles ---------------------------------------
  Column {
    visible: panel !== null && panel.pctReady && f !== null &&
             (f.awayProbableId > 0 || f.homeProbableId > 0)
    width: parent.width
    spacing: Style.space(6)
    PanelSectionHeader {
      text: "STARTERS — SAVANT PERCENTILES " + (panel ? panel.statsYear : "")
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }
    Row {
      width: parent.width
      spacing: Style.space(14)
      Repeater {
        model: f && panel && panel.focusGame ? [
          { abbr: panel.focusGame.away.abbr, id: f.awayProbableId, name: f.awayProbable },
          { abbr: panel.focusGame.home.abbr, id: f.homeProbableId, name: f.homeProbable }
        ] : []
        delegate: Column {
          required property var modelData
          readonly property var bars: modelData.id ? Mlb.percentileBars(panel.pctPitchers[modelData.id], "pitcher") : []
          width: (tab.width - Style.space(14)) / 2
          spacing: Style.space(3)
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: modelData.abbr + " · " + (panel ? panel.safe(modelData.name || "TBD", 28) : "")
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(12)
            font.bold: true
          }
          PercentileBars {
            panel: tab.panel
            visible: parent.bars.length > 0
            width: parent.width
            labelWidth: Style.space(80)
            model: parent.bars
          }
          Text {
            visible: parent.bars.length === 0
            textFormat: Text.PlainText
            text: "Not enough innings to rank"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.italic: true
          }
        }
      }
    }
  }

  // Full-season stats for the teams playing in the focus game and for the
  // whole league — useful when a game is on, but these sections stand alone
  // between games. Data: MLB stats API (teams/stats + stats/leaders), the
  // regular season.
  readonly property var focusRowAway: panel !== null && panel.focusGame !== null
                     && panel.teamStatsById[panel.focusGame.away.id] !== undefined
                     ? panel.teamStatsById[panel.focusGame.away.id] : null
  readonly property var focusRowHome: panel !== null && panel.focusGame !== null
                     && panel.teamStatsById[panel.focusGame.home.id] !== undefined
                     ? panel.teamStatsById[panel.focusGame.home.id] : null
  readonly property string statsSeasonLabel: panel !== null
    ? String(panel.statsYear) + " REGULAR SEASON"
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
      color: tab.wash(0.04)
      border.width: 1
      border.color: tab.wash(0.12)

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
                  ? tab.hi : Color.popups.text
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
          color: tab.wash(0.04)
          border.width: 1
          border.color: tab.wash(0.12)

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
                  color: tab.hi
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

  // ---- Baseball Savant season leaderboards --------------------------------
  Column {
    visible: panel !== null && panel.savantBoards.length > 0
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "SAVANT LEADERBOARDS — " + tab.statsSeasonLabel
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)
      Repeater {
        model: panel !== null ? panel.savantBoards : []
        delegate: Rectangle {
          id: board
          required property var modelData
          width: (parent.width - Style.space(8)) / 2
          height: boardCol.implicitHeight + Style.space(12)
          radius: Style.space(6)
          color: tab.wash(0.04)
          border.width: 1
          border.color: tab.wash(0.12)
          Column {
            id: boardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(7)
            spacing: Style.space(2)
            Row {
              spacing: Style.space(6)
              Text {
                textFormat: Text.PlainText
                text: board.modelData.label
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                font.bold: true
                font.letterSpacing: Style.space(1)
              }
              Text {
                textFormat: Text.PlainText
                text: board.modelData.hint
                color: Color.muted
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                font.italic: true
              }
            }
            Repeater {
              model: board.modelData.rows
              delegate: Row {
                required property var modelData
                required property int index
                spacing: Style.space(4)
                Text {
                  width: boardCol.width - Style.space(84)
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: (index + 1) + ". " + panel.safe(modelData.name, 26) +
                        (modelData.team ? "  " + panel.safe(modelData.team, 12) : "")
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                }
                Text {
                  width: Style.space(80)
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: modelData.value
                  color: tab.hi
                  font.family: Style.font.family
                  font.pixelSize: Style.space(12)
                  font.bold: true
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
      color: tab.hi
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
      color: tab.hi
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
    color: tab.wash(0.04)
    border.width: 1
    border.color: tab.wash(0.12)

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
          color: tab.hi
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
    color: tab.wash(0.03)
    border.width: 1
    border.color: tab.wash(0.1)

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
