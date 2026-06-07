// Smooth 2D noise field for biome assignment.
//
// DM has no native Perlin/Simplex, so we roll a cheap value-noise
// function: hash a coarse-cell grid to per-corner random values in
// [0,1], then bilinear-blend at sample time. Coarse cells default to
// 16 tiles wide — small enough that biome blobs are coherent on a
// 256x256 layer (gives ~16x16 = 256 random values), large enough
// that biome regions are big enough to walk through.
//
// Sample produces values in [0,1]. Callers bucket the value into
// biome indices weighted by each biome's presence weight on the
// layer (see _quarry_pick_biome_for_value).

#define QUARRY_NOISE_CELL_SIZE 16


/// Hash an integer pair to a stable pseudo-random value in [0,1].
/// Uses an integer mix that scrambles each input before combining,
/// then folds into a 16-bit range so DM's 24-bit float precision
/// handles the final % cleanly. The original "x*73 + y*179" mix
/// produced near-zero values for small (x, y) coarse cells, which
/// meant every layer mapped to the first biome in the roster.
/proc/_quarry_noise_hash(seed, x, y)
	// Scramble each input independently before combining. DM has no
	// native bitwise XOR (^ is exponentiation), so we use modular
	// additive mixing with primes. All intermediates kept under
	// 2^23 = 8388608 to fit DM's 24-bit float precision.
	// Inputs (x, y) are in [1, 16] for a 256-wide layer with cell
	// size 16, so (x+1031)*2017 stays under ~2.1M.
	var/sx = ((x + 1031) * 2017) % 1009
	var/sy = ((y + 2053) * 3593) % 1009
	var/ss = ((seed + 4099) * 6151) % 1009
	// Combine: sx*sy max ~1M which is safe; mod into a smaller
	// range to scramble further; final mix adds the three streams.
	var/m = (sx * sy + ss * 257) % 1009
	var/n = (sx * 13 + sy * 37 + ss * 89 + m * 211) % 1009
	if(n < 0)
		n += 1009
	return n / 1009


/// Bilinear sample of the noise field at (x, y).
/proc/_quarry_noise_sample(seed, x, y)
	var/cx = round(x / QUARRY_NOISE_CELL_SIZE)
	var/cy = round(y / QUARRY_NOISE_CELL_SIZE)
	var/fx = (x - cx * QUARRY_NOISE_CELL_SIZE) / QUARRY_NOISE_CELL_SIZE
	var/fy = (y - cy * QUARRY_NOISE_CELL_SIZE) / QUARRY_NOISE_CELL_SIZE

	var/v00 = _quarry_noise_hash(seed, cx, cy)
	var/v10 = _quarry_noise_hash(seed, cx + 1, cy)
	var/v01 = _quarry_noise_hash(seed, cx, cy + 1)
	var/v11 = _quarry_noise_hash(seed, cx + 1, cy + 1)

	// Smoothstep on the fractional parts to soften boundaries.
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)

	var/top = v00 * (1 - fx) + v10 * fx
	var/bot = v01 * (1 - fx) + v11 * fx
	return top * (1 - fy) + bot * fy
