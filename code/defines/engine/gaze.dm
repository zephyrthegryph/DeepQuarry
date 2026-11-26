// The gaze chunk grid (code/engine/change/gaze.dm), read by the draw queue (code/engine/change/draw_queue.dm).

/// Edge of a chunk in turfs.
#define GAZE_CHUNK 16
/// How many levels of stacked open space a client's view is followed down.
#define GAZE_THROUGH_DEPTH 8
#define GAZE_CHUNK_OF(v) (round(((v) - 1) / GAZE_CHUNK))
#define GAZE_KEY(z, cx, cy) ((z) * 1048576 + (cx) * 1024 + (cy))

