import QtQuick
import qs.Commons

// "Now playing" strip for the in-widget radio: bouncing level bars, the
// station, the game's score if it's on, volume - / +, and stop. Also shows
// the lookup in progress and the last note (fallback / stream dropped).
// Shared by the Radio and Live tabs; all state lives in Panel.qml.
Rectangle {
  id: np

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: np.panel && np.panel.hi !== undefined ? np.panel.hi : Color.accent
  function wash(a) { return np.panel && np.panel.wash ? np.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var panel: null
  readonly property bool playing: panel !== null && panel.radioPlaying && panel.radioNow !== null
  readonly property bool resolving: panel !== null && panel.radioResolving !== ""
  readonly property bool hasNote: panel !== null && panel.radioNote !== ""
  readonly property var game: playing && panel.radioNow.gamePk ? panel.gameByPk(panel.radioNow.gamePk) : null

  visible: playing || resolving || hasNote
  height: visible ? Style.space(playing ? 46 : 30) : 0
  radius: Style.space(6)
  color: playing ? Qt.rgba(np.hi.r, np.hi.g, np.hi.b, 0.12) : np.wash(0.04)
  border.width: 1
  border.color: playing ? np.hi : np.wash(0.12)

  // Level meter: four bars on staggered loops while audio is playing.
  Row {
    id: meter
    visible: np.playing
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
    height: Style.space(18)
    Repeater {
      model: [420, 610, 350, 520]
      delegate: Rectangle {
        required property var modelData
        width: Style.space(3)
        radius: 1
        anchors.bottom: parent.bottom
        color: np.hi
        height: Style.space(6)
        SequentialAnimation on height {
          running: np.playing && np.visible
          loops: Animation.Infinite
          NumberAnimation { to: Style.space(18); duration: modelData; easing.type: Easing.InOutSine }
          NumberAnimation { to: Style.space(5); duration: modelData; easing.type: Easing.InOutSine }
        }
      }
    }
  }

  Column {
    anchors.left: np.playing ? meter.right : parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: controls.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0
    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: {
        if (!np.panel) return ""
        if (np.playing) return "LISTENING · " + np.panel.safe(np.panel.radioNow.label, 40)
        if (np.resolving) return "Finding a stream for " + np.panel.safe(np.panel.radioResolving, 30) + "…"
        return np.panel.safe(np.panel.radioNote, 90)
      }
      color: np.playing ? np.hi : Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(np.playing ? 12 : 11)
      font.bold: np.playing
    }
    Text {
      visible: np.playing
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: {
        if (!np.playing) return ""
        var s = np.panel.radioNow.stream
        var line = np.panel.safe(s.name, 40)
        var g = np.game
        if (g && g.mode === "live")
          line = g.away.abbr + " " + (g.away.score || 0) + "-" + (g.home.score || 0) + " " + g.home.abbr +
                 (g.inning ? " " + (g.isTop ? "▲" : "▼") + g.inning : "") + "  ·  " + line
        return line + (s.bitrate ? "  ·  " + s.bitrate + " kbps" : "")
      }
      color: Color.popups.text
      opacity: 0.75
      font.family: Style.font.family
      font.pixelSize: Style.space(10)
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    component Btn: Rectangle {
      id: btn
      property string glyph: ""
      property bool show: true
      signal hit()
      visible: show
      width: Style.space(26)
      height: Style.space(24)
      radius: Style.space(5)
      color: btnMouse.containsMouse ? np.wash(0.14) : np.wash(0.05)
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: btn.glyph
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
        font.bold: true
      }
      MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.hit()
      }
    }

    Btn { show: np.playing; glyph: "−"; onHit: np.panel.setRadioVolume(np.panel.radioVolume - 10) }
    Text {
      visible: np.playing
      width: Style.space(30)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: np.panel ? String(np.panel.radioVolume) : ""
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(11)
    }
    Btn { show: np.playing; glyph: "+"; onHit: np.panel.setRadioVolume(np.panel.radioVolume + 10) }
    Btn { show: np.playing || np.resolving; glyph: "■"; onHit: np.panel.stopRadio() }
    Btn { show: !np.playing && !np.resolving && np.hasNote; glyph: "×"; onHit: np.panel.radioNote = "" }
  }
}
