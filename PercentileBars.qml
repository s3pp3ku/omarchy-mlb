import QtQuick
import qs.Commons
import "mlb.js" as Mlb

// Baseball Savant's percentile sliders: a label, a track, and a bubble at
// the player's percentile, blue (poor) through grey to red (elite). Bars are
// [{label, pct}] from Mlb.percentileBars; higher is always better.
Column {
  id: bars

  // Plugin color scheme (Panel.qml): highlight + card wash follow the
  // Omarchy theme, MLB navy/red, or classic, independent of the shell accent.
  readonly property color hi: bars.panel && bars.panel.hi !== undefined ? bars.panel.hi : Color.accent
  function wash(a) { return bars.panel && bars.panel.wash ? bars.panel.wash(a) : Util.alpha(Color.popups.text, a) }
  property var model: []
  property var panel: null          // for theme slider colors (Panel.pctColor)
  property real labelWidth: Style.space(92)
  spacing: Style.space(3)

  Repeater {
    model: bars.model
    delegate: Item {
      required property var modelData
      width: bars.width
      height: Style.space(17)
      readonly property color tint: bars.panel ? bars.panel.pctColor(modelData.pct)
                                               : Mlb.percentileColor(modelData.pct)

      Text {
        id: lbl
        width: bars.labelWidth
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: modelData.label
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
      }

      Item {
        id: track
        anchors.left: lbl.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(9)
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        readonly property real at: Math.max(0, Math.min(1, modelData.pct / 100)) * width

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Style.space(3)
          radius: height / 2
          color: bars.wash(0.10)
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: track.at
          height: Style.space(3)
          radius: height / 2
          color: tint
          Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        }
        Rectangle {
          width: Style.space(18)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          x: track.at - width / 2
          color: tint
          border.width: 1
          border.color: bars.wash(0.35)
          Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(modelData.pct)
            color: "#FFFFFF"
            font.family: Style.font.family
            font.pixelSize: Style.space(9)
            font.bold: true
          }
        }
      }
    }
  }
}
