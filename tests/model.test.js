const assert = require("assert")
const fs = require("fs")

// Model.js is a QML .pragma library: strip the pragma line and evaluate it in
// a function scope so its top-level functions become reachable.
const source = fs
  .readFileSync(require.resolve("../Model.js"), "utf8")
  .replace(/^\.pragma library.*$/m, "")
const Model = new Function(`
  ${source};
  return {
    normalizeUrl, channelKey, parseExtInfAttributes, parseM3u,
    shortPlaylistLabel, fold, fuzzyScore, filterChannels,
    normalizeTab, parseConfig, serialize,
    isPrivateHost, isPublicHttpsUrl, resolveRedirect,
    capField, MAX_PLAYLIST_BYTES, MAX_CHANNELS, MAX_FIELD_CHARS,
    MAX_REDIRECT_HOPS, MAX_CONFIG_CHARS
  };
`)()

// URL security gate ------------------------------------------------------

;(function normalizeUrlAcceptsHttpsAndTrims() {
  assert.strictEqual(Model.normalizeUrl("  https://example.com/list.m3u \n"), "https://example.com/list.m3u")
})()

;(function normalizeUrlRejectsPlainHttpAndNonHttpInput() {
  // Plain HTTP would downgrade every fetch and stream; non-http schemes were
  // always rejected.
  assert.strictEqual(Model.normalizeUrl("http://example.com"), "")
  assert.strictEqual(Model.normalizeUrl("ftp://example.com"), "")
  assert.strictEqual(Model.normalizeUrl(""), "")
  assert.strictEqual(Model.normalizeUrl(null), "")
})()

;(function publicHttpsGateAllowsPublicHosts() {
  assert.strictEqual(Model.isPublicHttpsUrl("https://example.com/a.m3u"), "https://example.com/a.m3u")
  assert.strictEqual(Model.isPublicHttpsUrl("https://example.com:8443/a.m3u"), "https://example.com:8443/a.m3u")
  assert.ok(Model.isPublicHttpsUrl("https://8.8.8.8/x")) // public IP literals are fine
  assert.ok(Model.isPublicHttpsUrl("https://2001:4860:4860::8888/x"))
})()

;(function publicHttpsGateRejectsNonHttpsAndGarbage() {
  assert.strictEqual(Model.isPublicHttpsUrl(""), "")
  assert.strictEqual(Model.isPublicHttpsUrl(null), "")
  assert.strictEqual(Model.isPublicHttpsUrl("http://example.com"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("ftp://example.com"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("file:///etc/passwd"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("https:///no-host"), "")
  // Whitespace/control characters are smuggling tricks, never legitimate.
  assert.strictEqual(Model.isPublicHttpsUrl("https://example.com/x y"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("https://example.com/x\ty"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("https://example.com/\x01"), "")
  // Userinfo confuses URL parsers about what the host really is.
  assert.strictEqual(Model.isPublicHttpsUrl("https://user@example.com/x"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("https://user:pass@example.com/x"), "")
  assert.strictEqual(Model.isPublicHttpsUrl("https://" + "x".repeat(2100)), "")
})()

;(function publicHttpsGateRejectsPrivateTargets() {
  // Localhost spellings.
  for (const host of ["localhost", "LOCALHOST", "localhost.", "sub.localhost", "host.local", "host.internal"])
    assert.strictEqual(Model.isPublicHttpsUrl(`https://${host}/x`), "", host)
  // Private/reserved IPv4 ranges incl. link-local cloud metadata and CGNAT.
  for (const ip of [
    "127.0.0.1", "10.0.0.5", "172.16.0.1", "172.31.255.255",
    "192.168.1.1", "169.254.169.254", "0.0.0.0", "100.64.0.1",
    "224.0.0.1", "255.255.255.255"
  ])
    assert.strictEqual(Model.isPublicHttpsUrl(`https://${ip}/x`), "", ip)
  // Malformed quads are treated as hostile, not as a weird hostname.
  assert.strictEqual(Model.isPublicHttpsUrl("https://999.1.1.1/x"), "")
  // IPv6 loopback/unspecified/ULA/link-local and v4-mapped forms.
  for (const ip of ["[::1]", "[::]", "[fc00::1]", "[fd12::1]", "[fe80::1]", "[::ffff:10.0.0.1]"])
    assert.strictEqual(Model.isPublicHttpsUrl(`https://${ip}/x`), "", ip)
})()

;(function isPrivateHostClassifiesBareHosts() {
  assert.ok(Model.isPrivateHost("127.0.0.1"))
  assert.ok(Model.isPrivateHost("192.168.0.23"))
  assert.ok(Model.isPrivateHost("[::1]"))
  assert.ok(Model.isPrivateHost(""))
  assert.ok(!Model.isPrivateHost("iptv-org.github.io"))
  assert.ok(!Model.isPrivateHost("8.8.4.4"))
})()

;(function resolveRedirectValidatesAbsoluteRelativeAndProtocolRelative() {
  const base = "https://example.com/lists/index.m3u"
  assert.strictEqual(Model.resolveRedirect(base, "https://other.example.org/final.m3u"), "https://other.example.org/final.m3u")
  assert.strictEqual(Model.resolveRedirect(base, "/mirror.m3u"), "https://example.com/mirror.m3u")
  assert.strictEqual(Model.resolveRedirect(base, "deep/final.m3u"), "https://example.com/lists/deep/final.m3u")
  assert.strictEqual(Model.resolveRedirect(base, "//cdn.example.net/final.m3u"), "https://cdn.example.net/final.m3u")
  // Every resolved destination must pass the same gate.
  assert.strictEqual(Model.resolveRedirect(base, "http://other.example.org/final.m3u"), "")
  assert.strictEqual(Model.resolveRedirect(base, "https://192.168.1.1/admin"), "")
  assert.strictEqual(Model.resolveRedirect(base, "https://169.254.169.254/latest/meta-data"), "")
})()

// parseM3u -------------------------------------------------------------

;(function parseM3uReadsExtInfMetadata() {
  const text = [
    "#EXTM3U",
    '#EXTINF:-1 tvg-logo="https://logo.example/one.png" group-title="News",Channel One',
    "https://stream.example.com/one",
    "",
    "#EXTINF:-1,No Name Channel",
    "https://stream.example.com/two",
    "not-a-url",
    "https://stream.example.com/three"
  ].join("\n")

  const channels = Model.parseM3u(text, "src-a")

  assert.strictEqual(channels.length, 3)
  assert.deepStrictEqual(channels[0], {
    name: "Channel One",
    url: "https://stream.example.com/one",
    logo: "https://logo.example/one.png",
    group: "News",
    src: "src-a"
  })
  assert.strictEqual(channels[1].name, "No Name Channel")
  // A non-URL line drops the pending #EXTINF instead of leaking it forward.
  assert.strictEqual(channels[2].name, "https://stream.example.com/three")
})()

;(function parseM3uDropsNonHttpsStreamsAndUnsafeLogos() {
  const text = [
    "#EXTINF:-1 tvg-logo=\"http://logo.example/plain.png\",Http Channel",
    "http://stream.example.com/insecure", // plain-http stream: dropped
    "#EXTINF:-1 tvg-logo=\"file:///etc/passwd\",Local Logo",
    "https://stream.example.com/ok", // kept, but the file:// logo must not survive
    "#EXTINF:-1,Lan Stream",
    "https://192.168.1.10:8080/stream" // private network target: dropped
  ].join("\n")

  const channels = Model.parseM3u(text, "s")

  assert.strictEqual(channels.length, 1)
  assert.strictEqual(channels[0].name, "Local Logo")
  assert.strictEqual(channels[0].url, "https://stream.example.com/ok")
  assert.strictEqual(channels[0].logo, "") // unsafe logo stripped, channel stays usable
})()

;(function parseM3uEnforcesProducerCaps() {
  // Field cap.
  const longName = "x".repeat(1000)
  let channels = Model.parseM3u(`#EXTINF:-1,${longName}\nhttps://a.example/s`, "")
  assert.strictEqual(channels[0].name.length, Model.MAX_FIELD_CHARS)

  // Channel cap.
  let many = ""
  for (let i = 0; i < Model.MAX_CHANNELS + 50; i++) many += `https://a.example/${i}\n`
  channels = Model.parseM3u(many, "")
  assert.strictEqual(channels.length, Model.MAX_CHANNELS)

  // Byte cap: body truncated before parsing, so later entries vanish.
  channels = Model.parseM3u("x".repeat(Model.MAX_PLAYLIST_BYTES) + "\nhttps://a.example/end", "")
  assert.strictEqual(channels.length, 0)
})()

;(function parseM3uHandlesEmptyAndCrlf() {
  assert.deepStrictEqual(Model.parseM3u("", ""), [])
  assert.deepStrictEqual(Model.parseM3u(null), [])
  const channels = Model.parseM3u("#EXTINF:-1,A\r\nhttps://a.example\r\n", "s")
  assert.strictEqual(channels.length, 1)
  assert.strictEqual(channels[0].name, "A")
})()

// shortPlaylistLabel -----------------------------------------------------

;(function shortPlaylistLabelShortensUrls() {
  assert.strictEqual(Model.shortPlaylistLabel("https://iptv-org.github.io/iptv/index.m3u"), "iptv-org.github.io")
  assert.strictEqual(Model.shortPlaylistLabel("https://example.com/lists/main.m3u"), "example.com")
  assert.strictEqual(Model.shortPlaylistLabel("https://example.com/lists/"), "example.com/lists")
  assert.strictEqual(Model.shortPlaylistLabel("http://host.tld/seg/ment/ed"), "host.tld/seg")
  assert.strictEqual(Model.shortPlaylistLabel(""), "")
})()

// fuzzyScore / filterChannels --------------------------------------------

;(function fuzzyScoreRanksExactPrefixAboveScatteredMatch() {
  assert.ok(Model.fuzzyScore("cnn", "CNN") < Model.fuzzyScore("cnn", "Cartoon News Network"))
  assert.strictEqual(Model.fuzzyScore("", "anything"), 0)
  assert.strictEqual(Model.fuzzyScore("xyz", ""), -1)
  assert.strictEqual(Model.fuzzyScore("qqq", "nothing matches"), -1)
})()

;(function filterChannelsFiltersSortsAndLimits() {
  const channels = [
    { name: "CNN International", url: "https://a", group: "" },
    { name: "Cartoon Network", url: "https://b", group: "Kids" },
    { name: "CNN", url: "https://c", group: "" },
    { name: "Discovery", url: "https://d", group: "" }
  ]

  const hits = Model.filterChannels(channels, "cnn", 10)
  // "CNN", "CNN International" and (via loose subsequence) "Cartoon Network".
  assert.strictEqual(hits.length, 3)
  // Both CNN channels outrank the loose match; ties keep playlist order.
  assert.deepStrictEqual(hits.slice(0, 2).map((ch) => ch.url), ["https://a", "https://c"])
  assert.strictEqual(hits[2].url, "https://b")
  // Group matches count too.
  assert.ok(Model.filterChannels(channels, "kids", 10).some((ch) => ch.url === "https://b"))

  // limit and exclusion are honored.
  assert.strictEqual(Model.filterChannels(channels, "", 2).length, 2)
  const excluded = Model.filterChannels(channels, "", 10, { "https://a": true })
  assert.ok(excluded.every((ch) => ch.url !== "https://a"))
})()

// parseConfig / serialize --------------------------------------------------

;(function parseConfigFallsBackToDefaultsOnGarbage() {
  const defaults = { defaultPlaylist: "https://default.example/list.m3u" }
  for (const bad of [null, "", "{not json", "[1,2]", '{"playlists":"nope"}']) {
    const config = Model.parseConfig(bad, defaults)
    assert.deepStrictEqual(config.playlists, [defaults.defaultPlaylist])
    assert.deepStrictEqual(config.favorites, [])
    assert.strictEqual(config.lastTab, "all")
  }
})()

;(function parseConfigDedupesPlaylistsAndFavorites() {
  const config = Model.parseConfig(
    JSON.stringify({
      playlists: ["https://a.example", "not-a-url", "https://a.example", "http://insecure.example"],
      favorites: [
        { url: "https://f.example", name: "Fav" },
        { url: "https://f.example" },
        { url: "https://192.168.1.5/stream", logo: "file:///etc/passwd" },
        { url: "bad" },
        null
      ],
      lastTab: "favorites"
    }),
    { defaultPlaylist: "https://default.example" }
  )

  assert.deepStrictEqual(config.playlists, ["https://a.example"])
  assert.strictEqual(config.favorites.length, 1)
  assert.deepStrictEqual(config.favorites[0], { name: "Fav", url: "https://f.example", logo: "", group: "" })
  assert.strictEqual(config.lastTab, "favorites")
})()

;(function parseConfigEnforcesCountAndSizeCaps() {
  const defaults = { defaultPlaylist: "https://default.example/list.m3u" }

  // Count caps: extra playlists/favorites are dropped, not accumulated.
  const many = []
  for (let i = 0; i < 100; i++) many.push(`https://host-${i}.example`)
  let config = Model.parseConfig(JSON.stringify({ playlists: many }), defaults)
  assert.strictEqual(config.playlists.length, 20)

  const manyFavs = []
  for (let i = 0; i < 600; i++) manyFavs.push({ url: `https://fav-${i}.example` })
  config = Model.parseConfig(JSON.stringify({ playlists: ["https://a.example"], favorites: manyFavs }), defaults)
  assert.strictEqual(config.favorites.length, 500)

  // Oversized config text is treated as corrupt and falls back to defaults
  // rather than being parsed.
  const bloated = JSON.stringify({ playlists: ["https://a.example"] }) + " ".repeat(Model.MAX_CONFIG_CHARS + 1)
  config = Model.parseConfig(bloated, defaults)
  assert.deepStrictEqual(config.playlists, [defaults.defaultPlaylist])
})()

;(function serializeRoundTripsThroughParseConfig() {
  const config = {
    playlists: ["https://a.example"],
    favorites: [{ name: "Fav", url: "https://f.example", logo: "", group: "" }],
    lastTab: "favorites"
  }

  const restored = Model.parseConfig(Model.serialize(config), { defaultPlaylist: "x" })

  assert.deepStrictEqual(restored, config)
})()

console.log("omatv model tests: all passed")
