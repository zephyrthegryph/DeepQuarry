// Client lighting, piece 3: the gameplay light level. With client lighting on there are no lighting corners, so a turf's
// light level (get_lumcount(), and through it stealth, plants, cameras, darkness checks) is worked out when someone asks:
// the glowing lights near the turf (the shadow masks' chunk index) whose reach covers it, each with the same distance falloff
// the corner engine uses (LUM_FALLOFF: height LIGHTING_HEIGHT, divisor the light's range), at the tile centre. Nothing is
// stored or updated per tick.

/// Cumulative reads (benchmarks).
GLOBAL_VAR_INIT(client_light_level_reads, 0)

/// The raw light on `T` from glowing lights (the corner engine's lum_r + lum_g + lum_b averaged per channel), occluded by each
/// light's reach.
/proc/client_light_level(turf/T)
	GLOB.client_light_level_reads++
	. = 0
	var/cx = round((T.x - 1) / CLIENT_GLOW_CHUNK)
	var/cy = round((T.y - 1) / CLIENT_GLOW_CHUNK)
	var/span = CEILING(CLIENT_GLOW_MAX_RANGE / CLIENT_GLOW_CHUNK, 1)
	for(var/ddx = -span, ddx <= span, ddx++)
		for(var/ddy = -span, ddy <= span, ddy++)
			for(var/datum/light_source/L as anything in GLOB.client_glow_chunks["[T.z],[cx + ddx],[cy + ddy]"])
				if(QDELETED(L) || !L.glow_reach)
					continue
				var/turf/S = L.source_turf
				var/dx = T.x - S.x
				var/dy = T.y - S.y
				if(!L.glow_reach["[dx],[dy]"])
					continue
				var/falloff = 1 - CLAMP01(sqrt(dx * dx + dy * dy + LIGHTING_HEIGHT) / max(1, L.light_range))
				if(falloff <= 0)
					continue
				. += falloff * L.light_power * (L.lum_r + L.lum_g + L.lum_b) / 3
