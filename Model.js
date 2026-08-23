.pragma library

var DEFAULT_PLAYLIST = "https://iptv-org.github.io/iptv/index.m3u"

function normalizeUrl(value) {
  var url = String(value || "").trim()
  if (!url) return ""
  if (!/^https?:\/\//i.test(url)) return ""
  return url
}

function channelKey(url) {
  return String(url || "").trim()
}

function parseExtInfAttributes(line) {
  var attrs = {}
  var attrPattern = /([A-Za-z0-9_-]+)="([^"]*)"/g
  var match
  while ((match = attrPattern.exec(line)) !== null) attrs[match[1]] = match[2]
  return attrs
}

function parseM3u(text, src) {
  var channels = []
  if (!text) return channels

  var lines = String(text).split(/\r?\n/)
  var pending = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue

    if (line.substring(0, 7) === "#EXTINF") {
      var commaIndex = line.indexOf(",", 8)
      var name = commaIndex === -1 ? "" : line.substring(commaIndex + 1).trim()
      var attrs = parseExtInfAttributes(line)
      pending = {
        name: name,
        logo: attrs["tvg-logo"] || "",
        group: attrs["group-title"] || ""
      }
      continue
    }

    if (line.charAt(0) === "#") continue

    var url = normalizeUrl(line)
    if (!url) { pending = null; continue }

    channels.push({
      name: pending && pending.name ? pending.name : url,
      url: url,
      logo: pending ? pending.logo : "",
      group: pending ? pending.group : "",
      src: src || ""
    })
    pending = null
  }

  return channels
}

function shortPlaylistLabel(url) {
  var value = String(url || "").replace(/^https?:\/\//i, "").replace(/\/$/, "")
  var slash = value.indexOf("/")
  var host = slash === -1 ? value : value.substring(0, slash)
  var path = slash === -1 ? "" : value.substring(slash + 1)
  var label = host
  if (path && path.indexOf(".") === -1) label += "/" + path.split("/")[0]
  if (label.length > 32) label = label.substring(0, 29) + "…"
  return label
}

function fold(value) {
  return String(value || "").toLowerCase()
}

// Subsequence fuzzy match. Returns -1 when the query is not a subsequence of
// the haystack, otherwise a score where lower is better.
function fuzzyScore(query, haystack) {
  var q = fold(query)
  var h = fold(haystack)
  if (!q) return 0
  if (!h) return -1

  var exactIndex = h.indexOf(q)
  var score = 0
  var cursor = 0
  var streak = 0

  for (var i = 0; i < q.length; i++) {
    var char = q.charAt(i)

    while (cursor < h.length && h.charAt(cursor) !== char) {
      streak = 0
      cursor++
    }
    if (cursor >= h.length) return -1

    var wordStart = cursor === 0 || h.charAt(cursor - 1) === " "
    score += cursor === 0 ? 0 : Math.min(cursor, 12)
    score += wordStart ? -6 : 2
    score += streak > 0 ? -3 : 0
    streak++
    cursor++
  }

  score += Math.max(0, h.length - q.length - 40) * 0.1
  if (exactIndex !== -1) score -= 10
  return score
}

function filterChannels(channels, query, limit, excludeUrls) {
  var results = []
  var trimmed = String(query || "").trim()

  for (var i = 0; i < channels.length && results.length < limit * 4; i++) {
    var channel = channels[i]
    if (excludeUrls && excludeUrls[channel.url]) continue
    if (!trimmed) {
      results.push({ channel: channel, score: i })
      continue
    }
    var score = fuzzyScore(trimmed, channel.name)
    if (score === -1 && fuzzyScore(trimmed, channel.group) === -1) continue
    results.push({ channel: channel, score: score })
  }

  if (trimmed) results.sort(function(a, b) { return a.score - b.score })
  return results.slice(0, limit).map(function(entry) { return entry.channel })
}

function normalizeTab(value) {
  return value === "favorites" ? "favorites" : "all"
}

function parseConfig(text, defaults) {
  var raw = {}
  try {
    raw = text ? JSON.parse(text) : {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) raw = {}
  } catch (exception) {
    raw = {}
  }

  var playlists = []
  if (Array.isArray(raw.playlists)) {
    for (var p = 0; p < raw.playlists.length; p++) {
      var url = normalizeUrl(raw.playlists[p])
      if (url && playlists.indexOf(url) === -1) playlists.push(url)
    }
  }
  if (playlists.length === 0) playlists = [defaults.defaultPlaylist]

  var favorites = []
  var seen = {}
  if (Array.isArray(raw.favorites)) {
    for (var f = 0; f < raw.favorites.length; f++) {
      var entry = raw.favorites[f]
      if (!entry || typeof entry !== "object") continue
      var favUrl = normalizeUrl(entry.url)
      if (!favUrl || seen[favUrl]) continue
      seen[favUrl] = true
      favorites.push({
        name: String(entry.name || favUrl),
        url: favUrl,
        logo: String(entry.logo || ""),
        group: String(entry.group || "")
      })
    }
  }

  return { playlists: playlists, favorites: favorites, lastTab: normalizeTab(raw.lastTab) }
}

function serialize(config) {
  return JSON.stringify({
    playlists: config.playlists,
    favorites: config.favorites,
    lastTab: normalizeTab(config.lastTab)
  }, null, 2) + "\n"
}
