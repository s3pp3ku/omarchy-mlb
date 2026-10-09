import QtQuick
import qs.Commons
import "mlb.js" as Mlb

// Catcher's-eye strike zone for one plate appearance. Pitch locations come
// from the feed in feet: pX across from the middle of the plate, pZ up from
// the ground; the zone's top and bottom are set per batter. Dots are filled
// with the pitch type's color, balls drawn translucent, balls in play ringed,
// and the newest pitch pulses. The batter stands on his side of the plate.
Item {
  id: zone

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: zone.panel && zone.panel.hi !== undefined ? zone.panel.hi : Color.accent
  function wash(a) { return zone.panel && zone.panel.wash ? zone.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var pitches: []
  property string bats: ""          // "R" | "L" | "S"
  property var panel: null          // for theme pitch colors (Panel.pitchColor)
  function pc(code) { return panel ? panel.pitchColor(code) : Mlb.pitchColor(code) }

  // Visible window in feet: 3.4 ft wide centered on the plate, 0.7-4.3 ft up.
  readonly property real xMin: -1.7
  readonly property real xMax: 1.7
  readonly property real zMin: 0.7
  readonly property real zMax: 4.3
  readonly property real halfPlate: 0.708   // 17 in / 2
  readonly property real ppf: width / (xMax - xMin)  // pixels per foot

  // The zone height follows the latest pitch's batter-specific top/bottom.
  readonly property var latest: pitches && pitches.length ? pitches[pitches.length - 1] : null
  readonly property real szTop: latest ? latest.szTop : 3.4
  readonly property real szBot: latest ? latest.szBot : 1.6

  function px(x) { return (x - xMin) * ppf }
  function pz(z) { return height - Style.space(26) - (z - zMin) * ((height - Style.space(26)) / (zMax - zMin)) }

  implicitWidth: Style.space(220)
  implicitHeight: Style.space(262)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(6)
    color: zone.wash(0.03)
    border.width: 1
    border.color: zone.wash(0.08)
  }

  // Batter's box on the hitter's side (catcher view: a righty stands left).
  Rectangle {
    visible: zone.bats === "R" || zone.bats === "L"
    width: Style.space(18)
    height: zone.pz(zone.szBot) - zone.pz(zone.szTop) + Style.space(60)
    y: zone.pz(zone.szTop) - Style.space(30)
    x: zone.bats === "R" ? Style.space(8) : zone.width - width - Style.space(8)
    radius: Style.space(4)
    color: "transparent"
    border.width: 1
    border.color: zone.wash(0.14)
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: zone.bats === "R" ? "R" : "L"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.space(10)
      font.bold: true
    }
  }

  // The zone itself, with a faint 3x3 grid.
  Rectangle {
    id: box
    x: zone.px(-zone.halfPlate)
    y: zone.pz(zone.szTop)
    width: zone.px(zone.halfPlate) - x
    height: zone.pz(zone.szBot) - y
    color: zone.wash(0.04)
    border.width: Style.space(2)
    border.color: zone.wash(0.55)
    Repeater {
      model: 2
      Rectangle {
        required property int index
        x: box.width * (index + 1) / 3
        width: 1
        height: box.height
        color: zone.wash(0.14)
      }
    }
    Repeater {
      model: 2
      Rectangle {
        required property int index
        y: box.height * (index + 1) / 3
        height: 1
        width: box.width
        color: zone.wash(0.14)
      }
    }
  }

  // Home plate, seen from behind: a flat pentagon under the zone.
  Canvas {
    id: plate
    x: zone.px(-zone.halfPlate)
    width: zone.px(zone.halfPlate) - x
    y: zone.height - Style.space(20)
    height: Style.space(12)
    onWidthChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      c.fillStyle = "rgba(255,255,255,0.5)"
      c.beginPath()
      c.moveTo(0, 0)
      c.lineTo(width, 0)
      c.lineTo(width, height * 0.45)
      c.lineTo(width / 2, height)
      c.lineTo(0, height * 0.45)
      c.closePath()
      c.fill()
    }
  }

  Repeater {
    model: zone.pitches
    delegate: Item {
      id: dot
      required property var modelData
      required property int index
      readonly property bool newest: index === zone.pitches.length - 1
      visible: modelData.px !== null && modelData.pz !== null
      readonly property real d: Style.space(newest ? 22 : 19)
      width: d
      height: d
      // Clamp to the window so wild pitches still show at the edge.
      x: Math.max(0, Math.min(zone.width - d, zone.px(modelData.px || 0) - d / 2))
      y: Math.max(0, Math.min(zone.height - Style.space(26) - d, zone.pz(modelData.pz || 0) - d / 2))
      z: index

      // Newest pitch: an expanding ring so the eye finds it.
      Rectangle {
        visible: dot.newest
        anchors.centerIn: parent
        width: dot.d
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: zone.pc(dot.modelData.code)
        SequentialAnimation on scale {
          running: dot.newest && dot.visible
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 1.9; duration: 1100; easing.type: Easing.OutCubic }
          PauseAnimation { duration: 500 }
        }
        SequentialAnimation on opacity {
          running: dot.newest && dot.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0.9; to: 0.0; duration: 1100; easing.type: Easing.OutCubic }
          PauseAnimation { duration: 500 }
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: zone.pc(dot.modelData.code)
        opacity: dot.modelData.isBall ? 0.55 : 1.0
        border.width: dot.modelData.inPlay ? 2 : (dot.newest ? 2 : 1)
        border.color: dot.modelData.inPlay || dot.newest ? "#FFFFFF" : Qt.rgba(0, 0, 0, 0.45)
      }
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(dot.modelData.n)
        color: "#FFFFFF"
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
      }
    }
  }
}
