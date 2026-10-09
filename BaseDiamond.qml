import QtQuick
import qs.Commons

// A small baseball diamond: three bases as rotated squares, filled when a
// runner is on. Pure decoration for the live focus card.
Item {
  id: diamond

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: diamond.panel && diamond.panel.hi !== undefined ? diamond.panel.hi : Color.accent
  function wash(a) { return diamond.panel && diamond.panel.wash ? diamond.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property bool on1: false
  property bool on2: false
  property bool on3: false
  property var panel: null

  implicitWidth: Style.space(26)
  implicitHeight: Style.space(26)

  // Home plate at the bottom center, bases up the left/right/top.
  Repeater {
    model: [
      { x: 0.5, y: 0.85, on: false },   // home (never "on")
      { x: 0.85, y: 0.5, on: diamond.on1 },
      { x: 0.5, y: 0.15, on: diamond.on2 },
      { x: 0.15, y: 0.5, on: diamond.on3 }
    ]
    delegate: Rectangle {
      x: modelData.x * diamond.width - width / 2
      y: modelData.y * diamond.height - height / 2
      width: Style.space(7)
      height: Style.space(7)
      rotation: 45
      radius: 1
      color: modelData.on ? diamond.hi : diamond.wash(0.16)
      border.width: 1
      border.color: modelData.on ? diamond.hi : diamond.wash(0.28)
    }
  }
}
