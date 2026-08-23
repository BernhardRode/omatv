# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
