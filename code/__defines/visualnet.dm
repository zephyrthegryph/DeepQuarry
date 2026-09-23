#define CHUNK_SIZE 16

/// Chunk coordinate of a 1-based tile coordinate.
#define MOB_CHUNK_COORD(v) (FLOOR((v) - 1, CHUNK_SIZE) / CHUNK_SIZE)
/// Numeric mob-chunk key for an alist (Q12). Exact for z < 256 and maps under 4096 tiles a side.
#define MOB_CHUNK_NUMERIC_KEY(z, chunk_x, chunk_y) ((((z) * 256) + (chunk_y)) * 256 + (chunk_x))
