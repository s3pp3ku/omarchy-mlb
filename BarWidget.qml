import QtQuick
import qs.Commons
import qs.Ui

// Bar pill for the MLB widget: a baseball glyph plus either a live score, the
// next first pitch, or an offseason countdown. All fetching and the popup live
// in Panel.qml; this file is the bar-slot button and the popout-identity shim
// the bar expects from a widget that owns a panel.
BarWidget {
  id: root
  moduleName: "s3pp3ku.mlb"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing: the bar identifies a
  // panel by the widget mounted in its slot (this file), so open/close/opened
  // have to live here and forward to the nested Panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The score/label strings vary in width ("SD 2 MIL 3" vs "OPENS 174d"), so
  // measure the actual text and size the slot to match, exactly as the
  // Formula 1 pill does — BarIconButton's single-glyph slot would otherwise
  // clip or overhang its neighbours.
  TextMetrics {
    id: pillMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: button.text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Fallback glyph so the pill isn't blank before the first fetch lands.
    text: panelLoader.item ? panelLoader.item.label : "\uED5C"
    slotSize: Math.max(Style.bar.statusSlot,
                       Math.ceil(pillMetrics.width) + Style.space(9))
    opticalSize: slotSize
    tooltipText: panelLoader.item ? panelLoader.item.tooltip : "MLB"
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
