import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dev.ebbo.omatv"

  readonly property string pluginId: "dev.ebbo.omatv"
  property var shell: bar && bar.shell ? bar.shell : null
  property var manifest: null
  property var pluginRegistry: null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var service: shell ? shell.serviceFor(pluginId) : null

  function refresh() {
    if (root.service) root.service.refresh()
  }

  function toggleOverlay() {
    if (root.shell && typeof root.shell.toggle === "function") {
      root.shell.toggle(root.pluginId, "{}")
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, "{}"])
  }

  IpcHandler {
    target: "dev.ebbo.omatv"

    function refresh(): void { root.refresh() }
    function toggle(): void { root.toggleOverlay() }
    function open(): void { root.toggleOverlay() }
    function close(): void {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    }
    function hide(): void { root.close() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰔂"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "OMATV — browse IPTV playlists"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton || buttonCode === Qt.RightButton)
        root.toggleOverlay()
      else if (buttonCode === Qt.MiddleButton)
        root.refresh()
    }
  }
}
