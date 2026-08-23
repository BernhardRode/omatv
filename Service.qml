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
    // Streams are handed to mpv verbatim, so they pass the same gate as
    // everything else remote: HTTPS on a public host or no playback.
    var url = Model.isPublicHttpsUrl(channel && channel.url)
    if (!url) return
    var title = String(channel.name || url).replace(/[\r\n\t]+/g, " ")
    playProcess.command = [
      "mpv",
      "--force-media-title=" + Model.capField(title, 256),
      "--really-quiet",
      url
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

  // Config read boundary: this file aggregates playlist-derived strings
  // (favorite names/logos/URLs), so everything coming out of it passes
  // through Model.parseConfig, which enforces MAX_CONFIG_CHARS -- anything
  // larger is treated as corrupt and reset to defaults rather than parsed.
  // The path itself is pinned to <config dir>/omatv/config.json.
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
  property string fetchingUrl: "" // the playlist URL as configured -- used for attribution/errors
  property string fetchHopUrl: "" // the currently validated hop being talked to
  property int fetchHops: 0
  property bool fetchDownloading: false
  property string fetchBuffer: ""
  property string fetchHeaders: ""

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
    // Redirects are followed manually, one hop at a time: blind `curl -L`
    // would happily chase a playlist's Location header into the user's LAN.
    // Each hop is probed first (status + Location only, body discarded),
    // validated through Model.resolveRedirect/isPublicHttpsUrl, and only
    // then downloaded from the final destination.
    root.fetchingUrl = root.fetchQueue.shift()
    root.fetchHopUrl = root.fetchingUrl
    root.fetchHops = 0
    root.fetchDownloading = false
    probeNextHop()
  }

  readonly property var curlBaseArgs: [
    "--proto", "=https",        // https only, including across redirects
    "--proto-redir", "=https",
    "--max-redirs", "0"         // we do the hop validation ourselves
  ]

  function probeNextHop() {
    fetchProcess.command = ["curl"].concat(root.curlBaseArgs).concat([
      "-sS", "-o", "/dev/null", "-D", "-", "--max-time", "15", root.fetchHopUrl
    ])
    fetchProcess.running = true
  }

  function downloadFinalHop() {
    root.fetchDownloading = true
    fetchProcess.command = ["curl"].concat(root.curlBaseArgs).concat([
      "-fsS", "--max-time", "30",
      "--max-filesize", String(Model.MAX_PLAYLIST_BYTES), // hard byte ceiling at the producer
      root.fetchHopUrl
    ])
    fetchProcess.running = true
  }

  function failFetch(reason) {
    root.lastError = reason + ": " + Model.shortPlaylistLabel(root.fetchingUrl)
    root.fetchBuffer = ""
    root.fetchingUrl = ""
    root.fetchHopUrl = ""
    fetchNext()
  }

  function handleFetchExit(exitCode) {
    var headers = String(root.fetchHeaders || "")
    root.fetchHeaders = ""

    if (!root.fetchDownloading) {
      if (exitCode !== 0) return failFetch("playlist failed")

      var statusMatch = /^HTTP\/[\d.]+[ \t]+(\d{3})/m.exec(headers)
      var status = statusMatch ? parseInt(statusMatch[1], 10) : 0

      if (status >= 300 && status < 400) {
        var locationMatches = headers.match(/^Location:[ \t]*(.*)$/gim)
        var location = locationMatches && locationMatches.length > 0
          ? locationMatches[locationMatches.length - 1].replace(/^Location:[ \t]*/i, "").trim() : ""
        if (location === "") return failFetch("redirect without location")
        if (root.fetchHops + 1 > Model.MAX_REDIRECT_HOPS) return failFetch("too many redirects")

        var next = Model.resolveRedirect(root.fetchHopUrl, location)
        if (!next) return failFetch("unsafe redirect blocked")
        root.fetchHops++
        root.fetchHopUrl = next
        return probeNextHop()
      }

      if (status !== 200) return failFetch("unexpected status " + (status || "none"))
      return downloadFinalHop()
    }

    var url = root.fetchingUrl
    root.fetchingUrl = ""
    root.fetchHopUrl = ""

    if (exitCode !== 0) {
      root.lastError = "playlist failed: " + Model.shortPlaylistLabel(url)
    } else {
      // Second byte ceiling client-side: parseM3u truncates to
      // MAX_PLAYLIST_BYTES even if a server ignores curl's limit.
      var parsed = Model.parseM3u(root.fetchBuffer, url)
      if (parsed.length === 0) {
        root.lastError = "empty playlist: " + Model.shortPlaylistLabel(url)
      } else {
        var next2 = root.channelGroups.slice()
        next2.push({ url: url, channels: parsed })
        root.channelGroups = next2
        revision++
      }
    }
    root.fetchBuffer = ""
    fetchNext()
  }

  property Process fetchProcess: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        // Probe phase: the dump of response headers (-D -). Download phase:
        // the playlist body itself.
        if (root.fetchDownloading) root.fetchBuffer = text
        else root.fetchHeaders = text
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") console.warn("omatv fetch:", message)
      }
    }
    onExited: function(code) { root.handleFetchExit(code) }
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
