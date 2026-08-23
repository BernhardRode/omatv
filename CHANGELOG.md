# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0](https://github.com/BernhardRode/omatv/compare/omatv-v1.2.0...omatv-v1.3.0) (2026-08-23)


### Features

* add bar widget launcher ([3626765](https://github.com/BernhardRode/omatv/commit/3626765792d559fa535e58888570a101288a60fe))
* add fullscreen fuzzy-search overlay player ([3dd8e4c](https://github.com/BernhardRode/omatv/commit/3dd8e4c658171cc47c0b24d46bd04b6f1f29b8af))
* add playlist service with mpv playback and config persistence ([98bb2ba](https://github.com/BernhardRode/omatv/commit/98bb2bae46d72ff744dd7b2b5578124eb97fd44a))
* bootstrap OMATV plugin manifest and license ([50791a5](https://github.com/BernhardRode/omatv/commit/50791a5e0391ee59b92c87f9694cae1aa621238b))
* parse m3u playlists with subsequence fuzzy channel search ([92b9d98](https://github.com/BernhardRode/omatv/commit/92b9d98c7945ee02ab4e42a3e4170d3558c414a7))


### Bug Fixes

* **security:** enforce the url gate across fetch, redirects, playback and rendering ([06d0c34](https://github.com/BernhardRode/omatv/commit/06d0c348ab169442c4f2572f20bebd4182956bb1))
* **security:** route all remote urls through a public-https policy with producer caps ([986cc79](https://github.com/BernhardRode/omatv/commit/986cc797af3c69285f06d9056b92c49c5d6cc2fc))

## [1.2.0] - 2026-08-23

### Security

- Every remote URL (playlists, redirects, logos, streams) must be HTTPS on a public host; private-network, link-local and metadata targets are blocked.
- Playlist redirects are followed hop-by-hop with per-destination validation instead of blind `curl -L`, with byte ceilings at both curl and parser level.
- Producer caps: 8MB per playlist, 20k channels, 256 chars per field, 20 playlists / 500 favorites, 256KB config read boundary.
- Channel names render as plain text; mpv playback refuses URLs failing the gate.

### Changed

- Plain-HTTP playlist URLs are no longer accepted; migrate saved entries to HTTPS.

## [1.1.1] - 2026-08-23

### Changed

- README now embeds the demo recording as a playable video instead of a bare link.

## [1.0.0] - 2026-08-23

### Added

- Fullscreen IPTV browser: fuzzy-search combined m3u playlists and play channels in mpv.
- Bar widget entry point with configurable display name and section.
- Favorites with drag-free reordering, multi-playlist support, and persisted config.
- Pure-JS model (`Model.js`) for m3u parsing, URL normalization, and subsequence fuzzy scoring.
- Zero-dependency test suite (`node tests/model.test.js`).
- CI: test workflow plus automated releases via release-please.
