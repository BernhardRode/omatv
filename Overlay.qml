import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string pluginId: "dev.ebbo.omatv"

  property bool opened: false
  property string queryText: ""
  property string tab: "all"
  property string playlistFilter: ""
  property int selectedIndex: 0
  readonly property int columns: Math.max(4, Math.floor(overlayWin.width / 240))

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  property var service: null

  readonly property var favoriteUrls: {
    var map = {}
    if (root.service) {
      for (var i = 0; i < root.service.favorites.length; i++)
        map[root.service.favorites[i].url] = true
    }
    return map
  }

  readonly property var results: {
    if (!root.service) return []
    var source
    if (root.tab === "favorites") {
      source = root.service.favorites
    } else {
      var filter = root.service.playlists.indexOf(root.playlistFilter) !== -1 ? root.playlistFilter : ""
      var all = root.service.channels
      source = []
      for (var i = 0; i < all.length; i++) {
        if (filter !== "" && all[i].src !== filter) continue
        source.push(all[i])
      }
    }
    return Model.filterChannels(source, root.queryText, 500, null)
  }

  onQueryTextChanged: root.selectedIndex = 0
  onTabChanged: {
    root.selectedIndex = 0
    if (root.service && root.service.lastTab !== root.tab) root.service.setLastTab(root.tab)
  }
  onResultsChanged: if (root.selectedIndex >= root.results.length) root.selectedIndex = 0

  property bool dragging: false
  property bool dragLock: false
  property int dragSourceIndex: -1
  property int insertIndex: -1
  property real dragX: 0
  property real dragY: 0
  property string dragGhostName: ""
  property string dragGhostLogo: ""

  function beginDrag(index) {
    if (root.tab !== "favorites") return
    var channel = root.results[index]
    if (!channel) return
    root.dragging = true
    root.dragSourceIndex = index
    root.insertIndex = index
    root.dragGhostName = channel.name
    root.dragGhostLogo = channel.logo || ""
  }

  function releaseDragLock() {
    root.dragLock = false
  }

  function updateDragGhost(x, y) {
    root.dragX = x
    root.dragY = y
  }

  function updateDropTarget(boundary) {
    root.insertIndex = boundary
  }

  function endDrag() {
    var from = root.dragSourceIndex
    var boundary = root.insertIndex
    root.dragging = false
    root.dragSourceIndex = -1
    root.insertIndex = -1
    root.dragLock = false

    if (!root.service || root.tab !== "favorites") return
    if (from < 0 || boundary < 0 || from >= root.results.length) return
    if (boundary === from || boundary === from + 1) return

    var source = root.results[from]
    if (!source) return

    var after = false
    var target = null
    if (boundary >= root.results.length) {
      target = root.results[root.results.length - 1]
      after = true
    } else {
      target = root.results[boundary]
    }
    if (target) root.service.moveFavorite(source.url, target.url, after)
  }

  function cancelDrag() {
    root.dragging = false
    root.dragSourceIndex = -1
    root.insertIndex = -1
    root.dragLock = false
  }

  function open(payloadJson) {
    root.opened = true
    root.queryText = ""
    root.tab = Model.normalizeTab(root.service ? root.service.lastTab : "all")
    root.selectedIndex = 0
    overlayWin.clearSearch()
    root.enableLayerBlur()
    Qt.callLater(function() { overlayWin.focusSearch() })
  }

  function close() {
    root.opened = false
  }

  function toggle() { root.opened ? root.close() : root.open("{}") }

  function enableLayerBlur() {
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "blur,omatv"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "ignorealpha 0,omatv"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "xray 0,omatv"])
  }

  function currentChannel() {
    if (!root.results || root.selectedIndex < 0 || root.selectedIndex >= root.results.length) return null
    return root.results[root.selectedIndex]
  }

  function selectIndex(i) {
    if (!root.results.length) return
    if (i < 0) i = 0
    if (i >= root.results.length) i = root.results.length - 1
    root.selectedIndex = i
  }

  function moveSelection(dx, dy) {
    if (!root.results.length) return
    var i = root.selectedIndex
    if (dx !== 0) i += dx
    if (dy !== 0) i += dy * root.columns
    root.selectIndex(i)
  }

  function playSelected() {
    var channel = root.currentChannel()
    if (!channel || !root.service) return
    overlayWin.clearSearch()
    Qt.callLater(root.close)
    root.service.play(channel)
  }

  function statusText() {
    if (!root.service) return "service unavailable"
    if (root.service.loading) return "loading playlists…"
    if (root.service.lastError !== "") return root.service.lastError
    return root.service.channels.length + " channels · " + root.service.playlists.length + " playlist(s)"
  }

  OverlayWindow {
    id: overlayWin
    host: root
  }
}
