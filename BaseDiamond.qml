import QtQuick
import qs.Commons

// A small baseball diamond: three bases as rotated squares, filled when a
// runner is on. Pure decoration for the live focus card.
Item {
  id: diamond
  property bool on1: false
  property bool on2: false
  property bool on3: false

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
      color: modelData.on ? Color.accent : Qt.rgba(1, 1, 1, 0.16)
      border.width: 1
      border.color: modelData.on ? Color.accent : Qt.rgba(1, 1, 1, 0.28)
    }
  }
}
