/*
 * Source-keyed alpha for mobs (rewrite/mobsrc, on the OM contribution store).
 *
 * A handful of visual effects (underwater stealth, cult ambush, the robotic cloak module)
 * each fade the mob's icon out while active. Historically each wrote `alpha` directly and
 * reset it to a hardcoded 255 or initial(alpha) on expiry, so two concurrent effects stomped
 * each other. Each effect now holds EFFECT_ALPHA_MULT (COMBINE_MULTIPLY, default 1) on the
 * mob under its own ALPHA_SOURCE_* key; the mob's alpha is 255 times the product, so two
 * half-transparent effects stack towards more transparent and one ending never snaps the mob
 * opaque under the other.
 */

/// Adds (or updates) this mob's opacity contribution from `source_key`: `multiplier` of full
/// opacity, 0..1. `animate_time` animates to the new combined alpha.
/mob/living/proc/set_alpha_source(source_key, multiplier, animate_time = 0)
	om_hold(src, EFFECT_ALPHA_MULT, src, clamp(multiplier, 0, 1), source_key)
	apply_combined_alpha(animate_time)

/// Removes `source_key`'s contribution; the mob shows whatever the rest combine to.
/mob/living/proc/clear_alpha_source(source_key, animate_time = 0)
	om_release(src, EFFECT_ALPHA_MULT, src, source_key)
	apply_combined_alpha(animate_time)

/// Applies 255 x the combined EFFECT_ALPHA_MULT (255 once the last source releases).
/mob/living/proc/apply_combined_alpha(animate_time = 0)
	var/target_alpha = round(255 * om_value_of(src, EFFECT_ALPHA_MULT))
	if(animate_time)
		animate(src, alpha = target_alpha, time = animate_time)
	else
		alpha = target_alpha
