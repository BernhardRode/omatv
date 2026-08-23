.pragma library

// --- Security policy ------------------------------------------------------
// Playlist content is untrusted remote input: it supplies channel names,
// logo URLs (fetched by Qt's image loader) and stream URLs (handed to mpv),
// and playlist URLs themselves are followed across redirects by curl.
// Every remote URL that survives parsing must therefore be HTTPS *and*
// point at a public host -- no loopback/private/link-local targets, which
// would turn channel lists into an SSRF vector against the user's LAN
// (routers, metadata endpoints, ...). DNS-level rebinding is out of scope
// here (curl resolves independently); this is the URL-layer policy.
//
// Producer caps keep a hostile or oversized playlist from ballooning
// memory/model size: bytes buffered per fetch, channels per playlist, and
// characters per text field are all bounded below.

var DEFAULT_PLAYLIST = "https://iptv-org.github.io/iptv/index.m3u"

var MAX_PLAYLIST_BYTES = 8 * 1024 * 1024 // per fetched playlist body
var MAX_CHANNELS = 20000 // entries kept per playlist
var MAX_FIELD_CHARS = 256 // per parsed #EXTINF name/logo/group value
var MAX_REDIRECT_HOPS = 5 // enforced again per-hop by Service.qml's curl calls
var MAX_CONFIG_CHARS = 256 * 1024 // config.json read boundary

function normalizeUrl(value) {
  var url = String(value || "").trim()
  if (!/^https:\/\//i.test(url)) return ""
  return url
}

function capField(value, maxChars) {
  var capped = String(value == null ? "" : value)
  if (capped.length > maxChars) capped = capped.substring(0, maxChars)
  return capped
}

function channelKey(url) {
  return String(url || "").trim()
}

// True when the host is a loopback/private/link-local/otherwise reserved
// target that must never be fetched or streamed to. Handles IPv4 and IPv6
// literals plus the usual localhost spellings; hostnames are checked at the
// URL layer only (see the caveat above about DNS).
function isPrivateHost(host) {
  var value = String(host || "").trim().toLowerCase()
  if (!value) return true
  while (value.charAt(value.length - 1) === ".") value = value.substring(0, value.length - 1)

  // [::1] style bracketed IPv6.
  if (value.charAt(0) === "[" && value.charAt(value.length - 1) === "]")
    value = value.substring(1, value.length - 1)

  if (value === "localhost" || value === "localhost.localdomain" || value.indexOf(".localhost") !== -1 || value.indexOf(".local") !== -1 || value.indexOf(".internal") !== -1)
    return true

  // Dotted-quad IPv4 literal (also catches IPv6 IPv4-mapped tails later).
  var octets = value.split(".")
  if (octets.length === 4 && /^\d+$/.test(octets[0])) {
    for (var i = 0; i < 4; i++) {
      if (!/^\d+$/.test(octets[i]) || octets[i].length > 3) return true // malformed -> treat as hostile
      var n = parseInt(octets[i], 10)
      if (isNaN(n) || n > 255) return true
    }
    var a = parseInt(octets[0], 10), b = parseInt(octets[1], 10)
    if (a === 0 || a === 10 || a === 127) return true
    if (a === 169 && b === 254) return true // link-local incl. cloud metadata
    if (a === 172 && b >= 16 && b <= 31) return true
    if (a === 192 && b === 168) return true
    if (a === 100 && b >= 64 && b <= 127) return true // CGNAT
    if (a >= 224) return true // multicast + reserved
    return false
  }

  // IPv6 literal: block loopback/unspecified, ULA (fc00::/7), link-local
  // (fe80::/10) and IPv4-mapped forms (::ffff:10.0.0.1).
  if (value.indexOf(":") !== -1) {
    var lower = value.toLowerCase()
    if (lower === "::" || lower === "::1") return true
    var mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(lower)
      || /^::ffff:0:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(lower)
    if (mapped) return isPrivateHost(mapped[1])
    if (/^f[cd][0-9a-f]{2}:/i.test(lower)) return true // fc00::/7 unique local
    if (/^fe[89ab][0-9a-f]:/i.test(lower)) return true // fe80::/10 link-local
    if (/^::(ffff:)?(10\.|127\.|192\.168\.|169\.254\.)/i.test(lower)) return true
    return false
  }

  return false
}

// The single gatekeeper for every remote URL we act on: fetching playlists,
// loading logos, handing streams to mpv, and each redirect hop along the
// way. Returns "" (and callers drop the URL) unless the address is HTTPS on
// a public host.
function isPublicHttpsUrl(value) {
  var raw = String(value || "").trim()
  if (!raw || raw.length > 2048) return ""
  if (!/^https:\/\//i.test(raw)) return ""

  // Strip control characters and whitespace outright -- none of them can
  // appear in a legitimate URL and all of them are smuggling tricks.
  if (/[\s\u0000-\u001f\u007f]/.test(raw)) return ""

  var authority = raw.substring(8)
  var pathAt = authority.search(/[/?#]/)
  if (pathAt !== -1) authority = authority.substring(0, pathAt)
  if (!authority) return ""

  // Userinfo (@ before host) is never legitimate for our endpoints and is
  // a classic parser-confusion trick: user@public-host could be read as
  // host=public-host by one parser and user=... by another.
  var atIndex = authority.lastIndexOf("@")
  if (atIndex !== -1) return ""

  var host = authority
  var port = ""
  var colon = host.lastIndexOf(":")
  if (colon !== -1 && host.indexOf("]") < colon) {
    port = host.substring(colon + 1)
    host = host.substring(0, colon)
  }
  if (port !== "") {
    if (!/^\d{1,5}$/.test(port)) return ""
    var portNum = parseInt(port, 10)
    if (portNum < 1 || portNum > 65535) return ""
  }

  if (isPrivateHost(host)) return ""
  return raw
}

// Resolve a possibly-relative Location header against the URL it came from,
// then run it through the same public-HTTPS gate.
function resolveRedirect(base, location) {
  var loc = String(location || "").trim()
  if (!loc || loc.length > 2048) return ""
  if (/^https?:\/\//i.test(loc)) return isPublicHttpsUrl(loc)
  // Protocol-relative must be tested before root-relative.
  if (loc.substring(0, 2) === "//") return isPublicHttpsUrl("https:" + loc)

  var baseStr = String(base || "")
  var schemeMatch = /^https:\/\/[^/?#]+/.exec(baseStr)
  if (!schemeMatch) return ""
  if (loc.charAt(0) === "/") return isPublicHttpsUrl(schemeMatch[0] + loc)

  var basePath = baseStr.substring(schemeMatch[0].length).split("?")[0].split("#")[0]
  var dir = basePath.substring(0, basePath.lastIndexOf("/") + 1)
  return isPublicHttpsUrl(schemeMatch[0] + dir + loc)
}

function parseExtInfAttributes(line) {
  var attrs = {}
  var attrPattern = /([A-Za-z0-9_-]+)="([^"]*)"/g
  var match
  while ((match = attrPattern.exec(line)) !== null) attrs[match[1]] = match[2]
  return attrs
}

// Parse an m3u document under the producer caps: input is truncated to
// maxBytes, at most maxChannels entries survive, every text field is
// length-capped, and both stream and logo URLs must pass isPublicHttpsUrl
// (logos go straight into Qt's image loader, so a file:// or private
// network logo URL would be just as much an SSRF/local-read as the
// playlists themselves).
function parseM3u(text, src, options) {
  var opts = options || {}
  var maxBytes = opts.maxBytes || MAX_PLAYLIST_BYTES
  var maxChannels = opts.maxChannels || MAX_CHANNELS

  var channels = []
  if (!text) return channels

  var body = String(text)
  if (body.length > maxBytes) body = body.substring(0, maxBytes)

  var lines = body.split(/\r?\n/)
  var pending = null

  for (var i = 0; i < lines.length; i++) {
    if (channels.length >= maxChannels) break

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

    var url = isPublicHttpsUrl(line)
    if (!url) { pending = null; continue }

    var logo = pending ? isPublicHttpsUrl(pending.logo) : ""
    channels.push({
      name: capField(pending && pending.name ? pending.name : url, MAX_FIELD_CHARS),
      url: url,
      logo: logo ? capField(logo, MAX_FIELD_CHARS) : "",
      group: capField(pending ? pending.group : "", MAX_FIELD_CHARS),
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

// The config file lives under the user's own config dir, but it aggregates
// data that started life as untrusted playlist content (favorite names,
// logos, stream URLs), so the same caps and public-HTTPS gate apply here.
function parseConfig(text, defaults) {
  var raw = {}
  try {
    if (text && String(text).length > MAX_CONFIG_CHARS) text = "" // oversized: treat as corrupt, fall back to defaults
    raw = text ? JSON.parse(text) : {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) raw = {}
  } catch (exception) {
    raw = {}
  }

  var playlists = []
  if (Array.isArray(raw.playlists)) {
    for (var p = 0; p < raw.playlists.length && playlists.length < 20; p++) {
      var url = isPublicHttpsUrl(raw.playlists[p])
      if (url && playlists.indexOf(url) === -1) playlists.push(url)
    }
  }
  if (playlists.length === 0) playlists = [defaults.defaultPlaylist]

  var favorites = []
  var seen = {}
  if (Array.isArray(raw.favorites)) {
    for (var f = 0; f < raw.favorites.length && favorites.length < 500; f++) {
      var entry = raw.favorites[f]
      if (!entry || typeof entry !== "object") continue
      var favUrl = isPublicHttpsUrl(entry.url)
      if (!favUrl || seen[favUrl]) continue
      seen[favUrl] = true
      favorites.push({
        name: capField(entry.name || favUrl, MAX_FIELD_CHARS),
        url: favUrl,
        logo: isPublicHttpsUrl(entry.logo) ? capField(isPublicHttpsUrl(entry.logo), MAX_FIELD_CHARS) : "",
        group: capField(entry.group || "", MAX_FIELD_CHARS)
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
