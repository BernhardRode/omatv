# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
