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

## Patch 2 — disable map rotation

`src/gesture/generic_gesture_detector.dart`: `_createDefaultHandler()` no longer
adds the `RotationHandler`, so the map is fixed north-up (a bike computer keeps
the map oriented). Re-add that one line to restore two-finger rotation.

## Patch 3 — scale-aware tile coverage (pinch-zoom-out gaps)

`src/util/tile_helper.dart` + `src/tile/tile_job_queue.dart`: tiles are scaled by
`mapPosition.scale` in the view, but `calculateTiles` sized them to the raw
`screensize` at the integer zoom — so pinching out (scale < 1, same integer zoom)
left the rendered tiles too small to cover the enlarged view, blanking the
margins progressively (roads/ways "disappearing" the further you zoom out).
`calculateTiles` now divides the half-extents by `scale`; the tile-job-queue's
"scale/rotation only" shortcut re-emits the existing tiles only while the
scale-aware tile dimension is still `contains()`-ed by what was rendered, else it
re-renders. `scale == 1` (every non-pinch state) is unchanged.

## Patch 4 — one bad marker must not abort the re-init batch

`src/marker/default_marker_datastore.dart`: `_reinitMarkers()` re-initialises the
markers in a single sequential `await` loop via `reinitOneMarker()`. If
`marker.changeZoomlevel()` threw for one marker (e.g. a degenerate zero-length
polyline), the exception propagated and aborted the loop, so every marker *after*
the bad one was left uninitialised and unpainted. Our ride track is drawn as a
gray base line plus many speed-coloured polyline segments; one bad segment made
all following segments disappear (the gray base showing through). `reinitOneMarker`
now wraps `changeZoomlevel` in try/catch and skips a marker that fails, so the
rest of the batch still paints.

## Removing this

Delete the `dependency_overrides: mapsforge_flutter` block in the root `pubspec.yaml`
and this directory once the fix (or an equivalent) lands upstream
(https://github.com/mikes222/mapsforge_flutter).
