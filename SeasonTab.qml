import QtQuick
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// Season tab: the current phase, a countdown to the next key date, and — when
// a favorite team is set — a focus card with their record/streak, their next
// games, and their full division table with them highlighted. A team picker at
// the bottom sets favoriteTeam live via `omarchy bar set`.
Column {
  id: tab
  property var panel: null
  spacing: Style.space(8)

  readonly property var favRow: panel && panel.favTeam
    ? Mlb.teamFocus(panel.standings, panel.favTeam) : null

  // Picker section: follows the favorite's league until the user switches.
  property string pickerLeague: ""
  readonly property string league: {
    if (pickerLeague === "AL" || pickerLeague === "NL") return pickerLeague
    var lg = panel ? Mlb.leagueFor(panel.favTeam) : ""
    return lg === "" ? "AL" : lg
  }
  readonly property var focusGames: panel && panel.favTeam
    ? Mlb.teamNextGames(panel.schedule.games, panel.favTeam, 4) : []
  readonly property var focusDivision: favRow
    ? Mlb.divisionTable(panel.standings, favRow.division) : []

  function ordinal(n) {
    var s = ["th", "st", "nd", "rd"], v = n % 100
    return n + (s[(v - 20) % 10] || s[v] || s[0])
  }

  // Phase + headline countdown.
  Column {
    width: parent.width
    spacing: Style.space(2)
    Text {
      textFormat: Text.PlainText
      text: panel !== null ? (panel.currentPhase() || "SEASON") : ""
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
      font.bold: true
      font.letterSpacing: Style.space(2)
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: {
        if (!panel) return ""
        var m = panel.nextMilestone()
        if (m) return m.label + " " + panel.fmtLong(m.ms - panel.nowMs)
        return "All key dates passed"
      }
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.space(18)
      font.bold: true
    }
  }

  // ---- Favorite team focus card ------------------------------------------
  Rectangle {
    visible: tab.favRow !== null
    width: parent.width
    height: focusCol.implicitHeight + Style.space(12)
    radius: Style.space(6)
    color: Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Column {
      id: focusCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(6)
      spacing: Style.space(3)

      // Row 1: chip + name + record.
      Row {
        width: parent.width
        spacing: Style.space(8)
        Rectangle {
          width: Style.space(4)
          height: Style.space(16)
          radius: 2
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.teamColorsOn
          color: tab.favRow ? tab.favRow.color : "transparent"
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width - Style.space(4 + 8 + 16 + 8) - recordText.width
          elide: Text.ElideRight
          text: tab.favRow ? tab.favRow.name : ""
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(15)
          font.bold: true
        }
        Text {
          id: recordText
          textFormat: Text.PlainText
          text: tab.favRow ? tab.favRow.wins + "-" + tab.favRow.losses : "—-—"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(15)
          font.bold: true
        }
      }

      // Row 2: division rank · GB · streak.
      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: {
          if (!tab.favRow) return ""
          var bits = []
          if (tab.favRow.division)
            bits.push((tab.favRow.rank > 0 ? tab.ordinal(tab.favRow.rank) + " in " : "") + tab.favRow.division)
          bits.push("GB " + tab.favRow.gb)
          if (tab.favRow.pct) bits.push(tab.favRow.pct)
          if (tab.favRow.streak) bits.push("Streak " + tab.favRow.streak)
          if (tab.favRow.champ) bits.push("Division champs")
          return bits.join(" · ")
        }
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
    }
  }

  // Team's next games from the schedule window.
  Column {
    visible: tab.focusGames.length > 0
    width: parent.width
    spacing: Style.space(4)
    PanelSectionHeader {
      text: "NEXT GAMES"
      foreground: Color.popups.text
      font.letterSpacing: Style.space(2)
    }
    Repeater {
      model: tab.focusGames
      delegate: Row {
        width: tab.width
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          width: Style.space(74)
          text: {
            var g = modelData
            if (g.mode === "live") return "LIVE"
            if (g.mode === "preview" && panel)
              return panel.sameDay(g.startMs) ? panel.fmtTime(g.startMs)
                   : Qt.formatDateTime(new Date(g.startMs), "ddd")
            return ""
          }
          color: modelData.mode === "live" ? Color.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: modelData.mode === "live"
        }
        Text {
          textFormat: Text.PlainText
          width: Style.space(46)
          horizontalAlignment: Text.AlignRight
          text: modelData.home.abbr === (panel ? panel.favTeam : "")
            ? "vs " + modelData.away.abbr : "@ " + modelData.home.abbr
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          width: tab.width - Style.space(74 + 46 + 16) - scoreText.width
          elide: Text.ElideRight
          text: panel ? panel.safe(Mlb.compactDesc(modelData.desc), 28) : ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }
        Text {
          id: scoreText
          textFormat: Text.PlainText
          text: {
            var g = modelData
            if (g.mode === "live" && g.away.score !== null)
              return g.away.score + "-" + g.home.score
            if (g.mode === "final") return "F"
            return ""
          }
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
        }
      }
    }
  }

  // ---- Key dates ----------------------------------------------------------
  PanelSectionHeader {
    visible: panel !== null && panel.milestones().length > 0
    text: "KEY DATES"
    foreground: Color.popups.text
    font.letterSpacing: Style.space(2)
  }

  Repeater {
    model: panel !== null ? panel.milestones() : []
    delegate: Row {
      width: tab.width
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        width: Style.space(130)
        elide: Text.ElideRight
        text: modelData.label
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(13)
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(110)
        text: Qt.formatDateTime(new Date(modelData.ms), "d MMM yyyy")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
      Text {
        textFormat: Text.PlainText
        width: tab.width - Style.space(130 + 110 + 16)
        horizontalAlignment: Text.AlignRight
        text: panel.fmtShort(modelData.ms - panel.nowMs)
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
        font.bold: true
      }
    }
  }

  // ---- Standings: focus team's division, else all division winners --------
  PanelSectionHeader {
    visible: panel !== null
    text: tab.favRow && tab.favRow.division
      ? (panel.standingsYear + " " + tab.favRow.division.toUpperCase())
      : (panel.standingsYear + " DIVISION WINNERS")
    foreground: Color.popups.text
    font.letterSpacing: Style.space(2)
  }

  Text {
    visible: panel !== null && !panel.standingsLoaded && panel.loadingStandings
    textFormat: Text.PlainText
    text: "Loading standings…"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  // Full division table when a favorite team is picked.
  Repeater {
    visible: tab.focusDivision.length > 0
    model: tab.focusDivision
    delegate: Row {
      width: tab.width
      spacing: Style.space(8)
      readonly property bool isFav: panel && panel.favTeam === modelData.abbr
      Text {
        textFormat: Text.PlainText
        width: Style.space(22)
        horizontalAlignment: Text.AlignRight
        text: modelData.rank > 0 ? String(modelData.rank) : "-"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
      Rectangle {
        width: Style.space(3)
        height: Style.space(14)
        radius: 1
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.teamColorsOn
        color: modelData.color
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(52)
        text: modelData.abbr
        color: parent.isFav ? Color.accent : Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(13)
        font.bold: parent.isFav
      }
      Text {
        textFormat: Text.PlainText
        width: tab.width - Style.space(22 + 3 + 52 + 60 + 66 + 60 + 40)
        elide: Text.ElideRight
        text: panel.safe(modelData.name, 30)
        color: parent.isFav ? Color.popups.text : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(60)
        horizontalAlignment: Text.AlignRight
        text: modelData.wins + "-" + modelData.losses
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(66)
        horizontalAlignment: Text.AlignRight
        text: modelData.gb === "-" ? "—" : modelData.gb + " GB"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(40)
        horizontalAlignment: Text.AlignRight
        text: modelData.pct
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }
    }
  }

  // No favorite team yet: division winners list.
  Repeater {
    // Repeater delegates ignore the repeater's own `visible`, so the model
    // itself has to go empty — otherwise this stacks under the division table
    // and pushes the picker off the bottom of the panel.
    model: (tab.favRow === null && panel !== null && panel.standingsLoaded)
      ? Mlb.divisionChamps(panel.standings, function(id) {
          return Mlb.teamRef(id, "").color
        })
      : []
    delegate: Row {
      width: tab.width
      spacing: Style.space(8)
      Rectangle {
        width: Style.space(3)
        height: Style.space(14)
        radius: 1
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.teamColorsOn
        color: modelData.color
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(96)
        elide: Text.ElideRight
        text: modelData.division
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(52)
        text: modelData.abbr
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(13)
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: Style.space(70)
        text: modelData.wins + "-" + modelData.losses
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(13)
      }
      Text {
        textFormat: Text.PlainText
        width: tab.width - Style.space(96 + 52 + 70 + 24)
        horizontalAlignment: Text.AlignRight
        text: modelData.pct
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }
    }
  }

  // ---- Team picker -------------------------------------------------------
  // One league at a time (15 chips) behind an AL/NL switcher: two rows of 30
  // chips ran past the bottom of the panel.
  PanelSeparator { foreground: Color.popups.text }

  PanelSectionHeader {
    text: "MY TEAM"
    foreground: Color.popups.text
    font.letterSpacing: Style.space(2)
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: panel && panel.favTeam
      ? "Picking a team replaces it. Current: " + panel.favTeam
      : "Pick a team to focus scores, standings and notifications."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    ButtonGroup {
      options: [
        { value: "AL", label: "American" },
        { value: "NL", label: "National" }
      ]
      value: tab.league
      focusable: false
      foreground: Color.popups.text
      background: Color.popups.background
      accent: Color.accent
      fontSize: Style.space(11)
      onChanged: function(v) { tab.pickerLeague = v }
    }

    // Clear chip, only when a team is set.
    Rectangle {
      visible: panel !== null && panel.favTeam !== ""
      width: clearText.implicitWidth + Style.space(14)
      height: Style.space(22)
      radius: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      color: clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.2)

      Text {
        id: clearText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "clear"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
      }

      MouseArea {
        id: clearMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.setFavorite("")
      }
    }
  }

  Flow {
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: panel ? panel.teamPicker(tab.league) : []
      delegate: Rectangle {
        required property var modelData
        width: chipText.implicitWidth + Style.space(14)
        height: Style.space(22)
        radius: Style.space(4)
        readonly property bool selected: panel && panel.favTeam === modelData.abbr
        color: selected ? Color.accent
               : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: selected ? Color.accent : Qt.rgba(1, 1, 1, 0.14)

        Rectangle {
          width: Style.space(3)
          height: parent.height - Style.space(6)
          radius: 1
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          visible: panel && panel.teamColorsOn
          color: modelData.color
        }

        Text {
          id: chipText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: modelData.abbr
          color: selected ? Color.popups.background : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.bold: selected
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.setFavorite(modelData.abbr)
        }
      }
    }
  }
}
