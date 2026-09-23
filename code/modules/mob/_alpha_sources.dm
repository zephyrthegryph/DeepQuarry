/*
 * Source-keyed alpha for mobs.
 *
 * A handful of visual effects (underwater stealth, cult ambush, the robotic
 * cloak module) each want to fade the mob's icon out while active and put it
 * back when they end. Historically each one did this by writing `holder.alpha`
 * directly and, on expiry, resetting it to a hardcoded 255 or `initial(alpha)`.
 * If two such effects were ever active at once, whichever one expired last
 * would stomp the other's contribution -- and any effect that expired first
 * would blow away whatever alpha the OTHER effect had set, snapping the mob
 * fully opaque (or back to some stale value) out from under it.
 *
 * This gives every such effect a small key -> multiplier slot instead. The
 * mob's actual `alpha` is the product of every active source's multiplier
 * (product, not min, so two half-transparent effects stack towards more
 * transparent rather than one silently masking the other), applied lazily
 * (only mobs that actually have an active source pay any cost).
 */

/mob/living
	/// Lazy assoc list: source key (a `#define`d string, one per effect) -> alpha
	/// multiplier in [0, 1]. Absent when no source is currently contributing.
	var/list/alpha_sources

/**
 * Adds (or updates) this mob's alpha contribution from one source.
 *
 * Arguments:
 * * source_key - A unique key identifying the effect contributing alpha (an
 *   `ALPHA_SOURCE_*` define). Re-adding the same key updates its multiplier
 *   rather than stacking a second contribution from the same source.
 * * multiplier - The fraction of full opacity (255) this source wants, from
 *   0 (fully transparent) to 1 (fully opaque, i.e. no effect).
 * * animate_time - If non-zero, animates to the new combined alpha over this
 *   duration instead of snapping to it immediately.
 */
/mob/living/proc/set_alpha_source(source_key, multiplier, animate_time = 0)
	LAZYSET(alpha_sources, source_key, clamp(multiplier, 0, 1))
	apply_combined_alpha(animate_time)

/**
 * Removes this mob's alpha contribution from one source, restoring whatever
 * the remaining sources (if any) combine to -- never a bare 255/initial().
 *
 * Arguments:
 * * source_key - The same key passed to `set_alpha_source()`.
 * * animate_time - If non-zero, animates to the new combined alpha over this
 *   duration instead of snapping to it immediately.
 */
/mob/living/proc/clear_alpha_source(source_key, animate_time = 0)
	if(!LAZYLEN(alpha_sources))
		return
	LAZYREMOVE(alpha_sources, source_key)
	if(!LAZYLEN(alpha_sources))
		alpha_sources = null
	apply_combined_alpha(animate_time)

/**
 * Recomputes `alpha` from every currently active alpha source and applies it.
 * Restores full opacity (255) once the last source clears, rather than
 * leaving `alpha` stuck at whatever the last active source left it at.
 */
/mob/living/proc/apply_combined_alpha(animate_time = 0)
	var/combined = 1
	for(var/source_key in alpha_sources)
		combined *= alpha_sources[source_key]
	var/target_alpha = round(255 * combined)
	if(animate_time)
		animate(src, alpha = target_alpha, time = animate_time)
	else
		alpha = target_alpha
