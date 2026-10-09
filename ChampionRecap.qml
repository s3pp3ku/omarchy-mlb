import QtQuick
import qs.Commons
import qs.Ui

// Bracket tab once the World Series is decided: a champion card, the club's
// road through each round, and the Series game by game. Everything renders
// from panel.champPath (mlb.js championPath) — no fetching here.
Column {
  id: recap

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: recap.panel && recap.panel.hi !== undefined ? recap.panel.hi : Color.accent
  function wash(a) { return recap.panel && recap.panel.wash ? recap.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var panel: null
  readonly property var path: panel ? panel.champPath : null
  // Last year's title, shown while this year's field isn't set yet.
  readonly property bool defending: panel !== null && panel.bracketSeason < panel.thisYear
  readonly property bool isFav: path !== null && panel.favTeam !== "" && path.team.abbr === panel.favTeam
  readonly property color teamColor: path && panel.teamColorsOn ? path.team.color : recap.hi
  spacing: Style.space(10)

  // ---- Champion card -------------------------------------------------------
  Rectangle {
    width: parent.width
    height: hero.implicitHeight + Style.space(28)
    radius: Style.space(6)
    color: Qt.rgba(recap.teamColor.r, recap.teamColor.g, recap.teamColor.b, 0.13)
    border.width: 1
    border.color: Qt.rgba(recap.teamColor.r, recap.teamColor.g, recap.teamColor.b, 0.45)
    clip: true

    // Team-color spine down the left edge.
    Rectangle {
      width: Style.space(6)
      height: parent.height
      color: recap.teamColor
    }

    // Oversized trophy watermark.
    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: panel ? panel.trophy : ""
      color: recap.hi
      opacity: 0.85
      font.family: Style.font.family
      font.pixelSize: Style.space(54)
    }

    Column {
      id: hero
      anchors.left: parent.left
      anchors.leftMargin: Style.space(20)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(90)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: recap.path
              ? (recap.defending ? "DEFENDING CHAMPIONS · " + panel.bracketSeason
                                 : panel.bracketSeason + " WORLD SERIES CHAMPIONS")
              : ""
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
        font.bold: true
        font.letterSpacing: Style.space(2)
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: recap.path ? panel.safe(recap.path.team.name, 40) : ""
        color: recap.isFav ? recap.hi : Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(24)
        font.bold: true
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: recap.path
              ? "def. " + panel.safe(recap.path.opp.name, 30) + " " +
                recap.path.wsWon + "-" + recap.path.wsLost +
                " · postseason " + recap.path.wins + "-" + recap.path.losses
              : ""
        color: Color.popups.text
        opacity: 0.85
        font.family: Style.font.family
        font.pixelSize: Style.space(13)
      }
      Text {
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: panel && panel.wsMvp && panel.wsMvpSeason === panel.bracketSeason
              ? "World Series MVP · " + panel.safe(panel.wsMvp.name, 40) +
                (panel.wsMvp.pos ? " (" + panel.safe(panel.wsMvp.pos, 3) + ")" : "")
              : ""
        color: recap.hi
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
        font.bold: true
      }
      Text {
        visible: recap.isFav
        textFormat: Text.PlainText
        text: "Your team. Enjoy the winter."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(11)
        font.italic: true
      }
    }
  }

  // ---- Road to the title ---------------------------------------------------
  PanelSectionHeader {
    text: "ROAD TO THE TITLE"
    foreground: Color.popups.text
    font.letterSpacing: Style.space(2)
  }

  Column {
    width: parent.width
    spacing: Style.space(2)
    Repeater {
      model: recap.path ? recap.path.rounds : []
      delegate: Rectangle {
        id: roundRow
        required property var modelData
        width: parent.width
        height: Style.space(30)
        radius: Style.space(4)
        readonly property bool clickable: !modelData.bye && modelData.clinchPk > 0
        color: roundHover.containsMouse && clickable ? recap.wash(0.07) : recap.wash(0.03)

        MouseArea {
          id: roundHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: roundRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (roundRow.clickable) recap.panel.openLink(recap.panel.gamedayUrl(roundRow.modelData.clinchPk))
        }

        Text {
          id: roundName
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(150)
          textFormat: Text.PlainText
          text: modelData.name
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: true
        }

        Row {
          anchors.left: roundName.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Rectangle {
            visible: !modelData.bye && recap.panel.teamColorsOn
            width: Style.space(4)
            height: Style.space(16)
            radius: 1
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.bye ? "transparent" : modelData.opp.color
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.bye ? "First-round bye" : "def. " + recap.panel.safe(modelData.opp.name, 30)
            color: modelData.bye ? Color.muted : Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
            font.italic: modelData.bye
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          visible: !modelData.bye
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          // A sweep earns its name.
          text: modelData.bye ? "" : modelData.won + "-" + modelData.lost +
                (modelData.lost === 0 ? "  sweep" : "")
          color: recap.hi
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
          font.bold: true
        }
      }
    }
  }

  // ---- World Series, game by game ------------------------------------------
  PanelSectionHeader {
    text: "WORLD SERIES"
    foreground: Color.popups.text
    font.letterSpacing: Style.space(2)
  }

  Column {
    width: parent.width
    spacing: Style.space(2)
    Repeater {
      model: recap.path ? recap.path.wsGames : []
      delegate: Rectangle {
        id: gameRow
        required property var modelData
        width: parent.width
        height: Style.space(28)
        radius: Style.space(4)
        color: gameHover.containsMouse ? recap.wash(0.07)
             : modelData.clincher ? Qt.rgba(recap.teamColor.r, recap.teamColor.g, recap.teamColor.b, 0.10)
             : "transparent"

        MouseArea {
          id: gameHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: recap.panel.openLink(recap.panel.gamedayUrl(gameRow.modelData.gamePk))
        }

        Text {
          id: gameNo
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          textFormat: Text.PlainText
          text: "G" + modelData.n
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
          font.bold: true
        }
        Text {
          id: gameDate
          anchors.left: gameNo.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(96)
          textFormat: Text.PlainText
          text: modelData.startMs ? Qt.formatDateTime(new Date(modelData.startMs), "ddd MMM d") : ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(12)
        }

        // "TOR 11  4 LAD": away left, home right, winner bold.
        Row {
          anchors.left: gameDate.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)
          Repeater {
            model: [gameRow.modelData.away, gameRow.modelData.home]
            delegate: Row {
              required property var modelData
              required property int index
              readonly property bool won: modelData.id === gameRow.modelData.winnerId
              spacing: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                visible: index === 1
                textFormat: Text.PlainText
                text: "@"
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }
              Rectangle {
                visible: recap.panel.teamColorsOn
                width: Style.space(4)
                height: Style.space(14)
                radius: 1
                color: modelData.color
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: modelData.abbr + " " + modelData.score
                color: won ? Color.popups.text : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
                font.bold: won
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, Style.space(200))
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: modelData.clincher ? recap.panel.trophy + " clincher"
              : modelData.winnerName ? "W " + recap.panel.safe(modelData.winnerName, 24) : ""
          color: modelData.clincher ? recap.hi : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.bold: modelData.clincher
        }
      }
    }
  }

  // ---- What's next ---------------------------------------------------------
  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: {
      if (!recap.panel) return ""
      var m = recap.panel.nextMilestone()
      var head = m ? m.label + (m.year !== recap.panel.thisYear ? " " + m.year : "") + " " +
                     recap.panel.fmtLong(m.ms - recap.panel.nowMs) : ""
      if (recap.defending)
        head += (head ? " · " : "") + "the " + recap.panel.thisYear +
                " bracket appears once the field is set"
      return head
    }
    visible: text !== ""
    color: recap.hi
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
    font.bold: true
  }
}
