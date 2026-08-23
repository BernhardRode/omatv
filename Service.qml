import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

QtObject {
  id: root

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omatv"
  readonly property string configPath: configDir + "/config.json"

  property var playlists: [Model.DEFAULT_PLAYLIST]
  property var favorites: []
  property string lastTab: "all"
  property var channelGroups: []
  property bool loading: false
  property string lastError: ""
  property int revision: 0

  readonly property var channels: {
    var out = []
    for (var g = 0; g < root.channelGroups.length; g++) {
      var list = root.channelGroups[g].channels
      for (var c = 0; c < list.length; c++) out.push(list[c])
    }
    return out
  }

  function serviceStatus() {
    if (root.loading) return "loading"
    if (root.lastError !== "") return "error: " + root.lastError
    return root.channels.length + " channels, " + root.playlists.length + " playlist(s)"
  }

  function refresh() {
    fetchAllPlaylists()
  }

  function isFavorite(url) {
    var key = Model.channelKey(url)
    for (var i = 0; i < root.favorites.length; i++)
      if (Model.channelKey(root.favorites[i].url) === key) return true
    return false
  }

  function toggleFavorite(channel) {
    var next = []
    for (var i = 0; i < root.favorites.length; i++) {
      if (Model.channelKey(root.favorites[i].url) === Model.channelKey(channel.url)) continue
      next.push(root.favorites[i])
    }
    if (!isFavorite(channel.url))
      next.push({ name: channel.name, url: channel.url, logo: channel.logo || "", group: channel.group || "" })
    saveConfig({ favorites: next })
  }

  function moveFavorite(url, targetUrl, after) {
    var key = Model.channelKey(url)
    var targetKey = Model.channelKey(targetUrl)
    if (!key || !targetKey || key === targetKey) return false

    var moved = null
    var rest = []
    for (var i = 0; i < root.favorites.length; i++) {
      if (Model.channelKey(root.favorites[i].url) === key) { moved = root.favorites[i]; continue }
      rest.push(root.favorites[i])
    }
    if (!moved) return false

    var target = -1
    for (var j = 0; j < rest.length; j++) {
      if (Model.channelKey(rest[j].url) === targetKey) { target = j; break }
    }
    if (target === -1) return false

    rest.splice(after ? target + 1 : target, 0, moved)
    saveConfig({ favorites: rest })
    return true
  }

  function addPlaylist(url) {
    var clean = Model.normalizeUrl(url)
    if (!clean) return false
    if (root.playlists.indexOf(clean) !== -1) return true

    saveConfig({ playlists: root.playlists.concat([clean]) })
    root.lastError = ""
    root.fetchQueue.push(clean)
    if (!root.loading) {
      root.loading = true
      fetchNext()
    }
    return true
  }

  function removePlaylist(url) {
    if (root.playlists.length <= 1) return false

    var nextPlaylists = []
    var nextGroups = []
    for (var i = 0; i < root.playlists.length; i++) {
      if (root.playlists[i] === url) continue
      nextPlaylists.push(root.playlists[i])
    }
    for (var g = 0; g < root.channelGroups.length; g++) {
      if (root.channelGroups[g].url === url) continue
      nextGroups.push(root.channelGroups[g])
    }

    root.playlists = nextPlaylists
    root.channelGroups = nextGroups
    revision++
    saveConfig({ playlists: nextPlaylists })
    return true
  }

  function play(channel) {
    playProcess.command = [
      "mpv",
      "--force-media-title=" + channel.name,
      "--really-quiet",
      channel.url
    ]
    playProcess.running = true
  }

  function setLastTab(tab) {
    var normalized = Model.normalizeTab(tab)
    if (root.lastTab === normalized) return
    saveConfig({ lastTab: normalized })
  }

  function applyConfig(text) {
    var parsed = Model.parseConfig(text, { defaultPlaylist: Model.DEFAULT_PLAYLIST })
    root.playlists = parsed.playlists
    root.favorites = parsed.favorites
    root.lastTab = parsed.lastTab
    revision++
    requestFetch()
  }

  function currentConfig() {
    return { playlists: root.playlists, favorites: root.favorites, lastTab: root.lastTab }
  }

  function saveConfig(patch) {
    var config = currentConfig()
    for (var key in patch) config[key] = patch[key]

    configFile.setText(Model.serialize(config))
    applyConfigText(Model.serialize(config), config)
  }

  function applyConfigText(text, preParsed) {
    var parsed = preParsed || Model.parseConfig(text, { defaultPlaylist: Model.DEFAULT_PLAYLIST })
    root.playlists = parsed.playlists
    root.favorites = parsed.favorites
    root.lastTab = parsed.lastTab
    revision++
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  property Process configDirProcess: Process {
    command: ["mkdir", "-p", root.configDir]
    onExited: root.requestFetch()
  }

  property bool fetchPending: false
  property var fetchQueue: []
  property string fetchingUrl: ""
  property string fetchBuffer: ""

  function requestFetch() {
    if (root.fetchPending || root.loading) return
    root.fetchPending = true
    Qt.callLater(root.fetchAllPlaylists)
  }

  function fetchAllPlaylists() {
    root.fetchPending = false
    root.loading = true
    root.lastError = ""
    root.channelGroups = []
    revision++
    root.fetchQueue = []
    for (var i = 0; i < root.playlists.length; i++) root.fetchQueue.push(root.playlists[i])
    fetchNext()
  }

  function fetchNext() {
    if (root.fetchQueue.length === 0) {
      root.loading = false
      root.fetchingUrl = ""
      return
    }
    root.fetchingUrl = root.fetchQueue.shift()
    fetchProcess.command = ["curl", "-fsSL", "--max-time", "60", root.fetchingUrl]
    fetchProcess.running = true
  }

  function finishFetch(exitCode) {
    var url = root.fetchingUrl
    root.fetchingUrl = ""

    if (exitCode !== 0) {
      root.lastError = "playlist failed: " + Model.shortPlaylistLabel(url)
    } else {
      var parsed = Model.parseM3u(root.fetchBuffer, url)
      if (parsed.length === 0) {
        root.lastError = "empty playlist: " + Model.shortPlaylistLabel(url)
      } else {
        var next = root.channelGroups.slice()
        next.push({ url: url, channels: parsed })
        root.channelGroups = next
        revision++
      }
    }
    root.fetchBuffer = ""
    fetchNext()
  }

  property Process fetchProcess: Process {
    stdout: StdioCollector {
      onStreamFinished: { root.fetchBuffer = text }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") console.warn("omatv fetch:", message)
      }
    }
    onExited: function(code) { root.finishFetch(code) }
  }

  property Process playProcess: Process {
    stderr: StdioCollector {
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") console.warn("omatv mpv:", message)
      }
    }
  }

  Component.onCompleted: {
    root.configDirProcess.running = true
    root.applyConfig("")
  }
}
