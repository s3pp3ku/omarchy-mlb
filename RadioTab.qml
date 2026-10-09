import QtQuick
import qs.Commons
import qs.Ui
import "mlb.js" as Mlb

// Radio tab: every game today (or the next ones on the schedule) with each
// club's radio call, the national network, and Spanish-language feeds.
// Station chips play the station right here (Radio Browser stream + mpv,
// see Panel.qml); the small arrow opens it on TuneIn instead. "MLB audio"
// opens MLB's own player. Your favorite team's game is pinned to the top.
//
// Data: game.media.stations from the schedule's broadcasts hydrate
// (Mlb.parseBroadcasts). MLB lists stations but no stream URLs, hence the
// station-directory search link.
Column {
  id: tab

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: tab.panel && tab.panel.hi !== undefined ? tab.panel.hi : Color.accent
  function wash(a) { return tab.panel && tab.panel.wash ? tab.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var panel: null
  spacing: Style.space(10)

  readonly property var games: {
    if (!panel) return []
    var list = Mlb.switcherGames(panel.schedule.games, 15)
    if (!list.length) list = (panel.schedule.upcoming || []).slice(0, 8)
    var fav = panel.favTeam
    if (!fav) return list
    var mine = [], rest = []
    for (var i = 0; i < list.length; i++) {
      var g = list[i]
      if (g.away.abbr === fav || g.home.abbr === fav) mine.push(g)
      else rest.push(g)
    }
    return mine.concat(rest)
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "Press a station to listen here (it keeps playing with the popup closed; " +
          "\u2197 opens it on TuneIn). Every flagship is free over the air in its home market; " +
          "online, some stations swap out game audio outside their market. " +
          "MLB audio opens MLB's own player (sign-in required)."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
  }

  RadioNowPlaying { panel: tab.panel; width: parent.width }

  Text {
    visible: tab.games.length === 0
    textFormat: Text.PlainText
    text: panel && panel.loadingSchedule ? "Loading the schedule…" : "No games on the schedule this week."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
  }

  Repeater {
    model: tab.games
    delegate: Rectangle {
      id: card
      required property var modelData
      readonly property var g: modelData
      readonly property var st: g.media ? g.media.stations : []
      readonly property bool fav: tab.panel.favTeam !== "" &&
        (g.away.abbr === tab.panel.favTeam || g.home.abbr === tab.panel.favTeam)
      readonly property bool live: g.mode === "live"

      function pick(side, lang, national) {
        var out = []
        for (var i = 0; i < st.length; i++) {
          var s = st[i]
          if (s.lang !== lang) continue
          if (national ? !s.national : (s.national || s.side !== side)) continue
          out.push(s)
        }
        return out
      }
      readonly property var rows: [
        { label: g.away.abbr, color: g.away.color, items: pick("away", "en", false) },
        { label: g.home.abbr, color: g.home.color, items: pick("home", "en", false) },
        { label: "NATIONAL", color: "", items: pick("", "en", true) },
        { label: "ESPAÑOL", color: "", items: pick("", "es", true).concat(pick("away", "es", false), pick("home", "es", false)) }
      ]

      width: tab.width
      height: cardCol.implicitHeight + Style.space(18)
      radius: Style.space(6)
      color: tab.wash(0.04)
      border.width: live || fav ? 2 : 1
      border.color: live ? tab.hi : fav ? tab.wash(0.35) : tab.wash(0.12)

      Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(9)
        spacing: Style.space(5)

        // Header: matchup + state, MLB audio link on the right.
        Item {
          width: parent.width
          height: Style.space(20)
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Rectangle {
              visible: card.live
              width: Style.space(7); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: tab.panel.cLive
              SequentialAnimation on opacity {
                running: card.live && card.visible
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.3; duration: 900 }
                NumberAnimation { from: 0.3; to: 1; duration: 900 }
              }
            }
            Text {
              textFormat: Text.PlainText
              text: card.g.away.abbr + " @ " + card.g.home.abbr
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(14)
              font.bold: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var g = card.g
                if (g.mode === "live")
                  return (g.away.score || 0) + "-" + (g.home.score || 0) +
                         (g.inning ? " · " + (g.isTop ? "▲" : "▼") + g.inning : "")
                if (g.mode === "final") return "Final " + g.away.score + "-" + g.home.score
                return tab.panel.dayWord(g.startMs) + " " + tab.panel.fmtTime(g.startMs)
              }
              color: card.live ? tab.hi : Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: card.live
            }
            Text {
              visible: card.fav
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "YOUR TEAM"
              color: tab.hi
              font.family: Style.font.family
              font.pixelSize: Style.space(9)
              font.bold: true
              font.letterSpacing: Style.space(1)
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "MLB audio ↗"
            color: tab.hi
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
            font.underline: audioMouse.containsMouse
            MouseArea {
              id: audioMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: tab.panel.openLink(tab.panel.mlbAudioUrl(card.g.gamePk))
            }
          }
        }

        Text {
          visible: card.st.length === 0
          textFormat: Text.PlainText
          text: "No radio listings posted yet."
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.italic: true
        }

        Repeater {
          model: card.rows
          delegate: Row {
            id: row
            required property var modelData
            visible: modelData.items.length > 0
            width: cardCol.width
            spacing: Style.space(8)

            Row {
              width: Style.space(76)
              spacing: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              Rectangle {
                visible: row.modelData.color !== "" && tab.panel.teamColorsOn
                width: Style.space(4); height: Style.space(14); radius: 1
                anchors.verticalCenter: parent.verticalCenter
                color: row.modelData.color || "transparent"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.modelData.color !== "" ? Color.popups.text : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.space(row.modelData.color !== "" ? 12 : 9)
                font.bold: true
                font.letterSpacing: row.modelData.color !== "" ? 0 : Style.space(1)
              }
            }

            Flow {
              width: cardCol.width - Style.space(84)
              spacing: Style.space(5)
              Repeater {
                model: row.modelData.items
                delegate: Rectangle {
                  id: stChip
                  required property var modelData
                  readonly property bool playing: tab.panel.radioPlaying && tab.panel.radioNow !== null &&
                                                  tab.panel.radioNow.query === modelData.query
                  readonly property bool busy: tab.panel.radioResolving === modelData.query
                  readonly property bool missing: tab.panel.streamCache[modelData.query] === false
                  width: stText.implicitWidth + extLink.width + Style.space(26)
                  height: Style.space(24)
                  radius: Style.space(12)
                  color: playing ? Qt.rgba(tab.hi.r, tab.hi.g, tab.hi.b, 0.22)
                       : stMouse.containsMouse ? tab.wash(0.12) : tab.wash(0.05)
                  border.width: playing ? 2 : 1
                  border.color: playing || stMouse.containsMouse ? tab.hi : tab.wash(0.14)
                  Text {
                    id: stText
                    x: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: (stChip.playing ? "\u25A0 " : stChip.busy ? "\u2026 " : stChip.missing ? "\u2197 " : "\u25B6 ") +
                          tab.panel.safe(stChip.modelData.name, 34)
                    color: stChip.playing || stMouse.containsMouse ? tab.hi : Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                    font.bold: stChip.playing
                  }
                  MouseArea {
                    id: stMouse
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: extLink.left
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tab.panel.toggleStation(stChip.modelData, card.g.gamePk)
                  }
                  // Open on TuneIn instead of playing here.
                  Text {
                    id: extLink
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "\u2197"
                    color: extMouse.containsMouse ? tab.hi : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                    MouseArea {
                      id: extMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: tab.panel.openLink(tab.panel.radioUrl(stChip.modelData.query))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
