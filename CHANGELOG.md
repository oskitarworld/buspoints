# Changelog

All notable changes to this project will be documented in this file.

## [1.3.1] - 2026-01-12
### Added
- `BusSpinner` animated waiting indicator (autobús girando) and replaced previous loading icon/dialog with it.
- PDIs are shown in Create Route screen; improved PDI querying and coordinate parsing.
- Moved locate and map-type controls into top search frame for cleaner UI.

### Changed
- Updated marker handling and performance improvements (cached BitmapDescriptors, size-aware markers).
- `pubspec.yaml` bumped to `1.3.1+11`.

### Migration/Ops
- One-off migration merged `pdi_categoris` into `pdis_v2` (external execution). No automatic deletions were performed.

### Notes
- Manual deletion of `pdi_categoris` is pending (confirm before deleting).
