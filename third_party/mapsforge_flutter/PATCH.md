# Vendored + patched `mapsforge_flutter` 4.0.0

This is an unmodified copy of `mapsforge_flutter` 4.0.0 from pub.dev **except** for
one bug fix, applied via `dependency_overrides` in the root `pubspec.yaml`.

## Why

On a GPS-follow map (we call `MapModel.setPosition()` once per 1 Hz GPS fix), the
map tiles did **not** pan with the position. The current-location marker and the
recorded track (rendered by `MarkerDatastoreOverlay`, which re-projects against the
*live* position) followed correctly, but the street tiles stayed frozen and only
jumped ~one tile (~hundreds of metres) at a time. Visually: the marker sat pinned
at screen-centre while the streets underneath were stuck, then snapped to catch up.

## Root cause

`lib/src/tile/tile_job_queue.dart` emits a `TileSet` stamped with the **render's**
`MapPosition`. `TransformWidget` shifts tiles by
`tileSet.center - tileSet.mapPosition.getCenter()`, so a tileset carrying an old
center produces a zero/stale shift. Two paths kept the old center:

1. While a render was still in flight (`!_done`), incoming positions whose tiles were
   already "contained" were **dropped** (`return`) — the map couldn't follow until the
   (slow, on the emulator) render finished.
2. Completed renders re-emitted the tileset with their original center.

## Fix (only `lib/src/tile/tile_job_queue.dart`)

- `_emitTileSetBatched()` now re-stamps the emitted tileset with
  `mapModel.lastPosition` (same zoom level only), so the already-loaded tiles are
  shifted to the **latest** requested center every time they're emitted. This is a
  cheap re-projection of the same images and is the single choke-point for all emits
  (including the per-tile emits of an in-flight render).
- The "render still running" branch now re-emits the tiles loaded so far (when any)
  instead of dropping the position, so follow stays smooth during a slow render.

Search for `PATCH (cycle)` in that file for the exact diffs.

## Removing this

Delete the `dependency_overrides: mapsforge_flutter` block in the root `pubspec.yaml`
and this directory once the fix (or an equivalent) lands upstream
(https://github.com/mikes222/mapsforge_flutter).
