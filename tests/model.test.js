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
    normalizeTab, parseConfig, serialize
  };
`)()

// normalizeUrl ---------------------------------------------------------

;(function normalizeUrlAcceptsHttpAndTrims() {
  assert.strictEqual(Model.normalizeUrl("  https://example.com/list.m3u \n"), "https://example.com/list.m3u")
  assert.strictEqual(Model.normalizeUrl("http://example.com"), "http://example.com")
})()

;(function normalizeUrlRejectsNonHttpInput() {
  assert.strictEqual(Model.normalizeUrl(""), "")
  assert.strictEqual(Model.normalizeUrl(null), "")
  assert.strictEqual(Model.normalizeUrl("ftp://example.com"), "")
  assert.strictEqual(Model.normalizeUrl("javascript:alert(1)"), "")
})()

// parseM3u -------------------------------------------------------------

;(function parseM3uReadsExtInfMetadata() {
  const text = [
    "#EXTM3U",
    '#EXTINF:-1 tvg-logo="http://logo/one.png" group-title="News",Channel One',
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
    logo: "http://logo/one.png",
    group: "News",
    src: "src-a"
  })
  assert.strictEqual(channels[1].name, "No Name Channel")
  // A non-URL line drops the pending #EXTINF instead of leaking it forward.
  assert.strictEqual(channels[2].name, "https://stream.example.com/three")
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
      playlists: ["https://a.example", "not-a-url", "https://a.example"],
      favorites: [
        { url: "https://f.example", name: "Fav" },
        { url: "https://f.example" },
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
