/*
 * Source-held alpha for mobs: the stat alpha_mult.
 *
 * A handful of visual effects (underwater stealth, cult ambush, the robotic cloak module, creature cloaks) each fade the
 * mob's icon out while active. Historically each wrote `alpha` directly and reset it to a hardcoded 255 or initial(alpha) on
 * expiry, so two concurrent effects stomped each other. Each effect holds alpha_mult (PRODUCT, base 1) under its own source
 * (SRC_ALPHA_*); the mob's alpha is 255 times the product, so two half-transparent effects stack towards more transparent and
 * one ending never snaps the mob opaque under the other. A source holding again replaces its own value.
 */

STAT(/mob/living, alpha_mult, PRODUCT, base = 1, reapply = REAPPLY_REPLACE, virtual = TRUE)
SOURCE_DEF(alpha_underwater_stealth)
SOURCE_DEF(alpha_ambush)
SOURCE_DEF(alpha_robot_cloak)
SOURCE_DEF(alpha_creature_cloak)

/// Adds (or updates) this mob's opacity contribution from `source` (an SRC_ALPHA_* id or a datum): `multiplier` of full
/// opacity, 0..1. `animate_time` animates to the new combined alpha.
/mob/living/proc/set_alpha_source(source, multiplier, animate_time = 0)
	hold(src, STAT_ALPHA_MULT, clamp(multiplier, 0, 1), source)
	apply_combined_alpha(animate_time)

/// Removes `source`'s contribution; the mob shows whatever the rest combine to.
/mob/living/proc/clear_alpha_source(source, animate_time = 0)
	release(src, STAT_ALPHA_MULT, source)
	apply_combined_alpha(animate_time)

/// Applies 255 x the combined alpha_mult (255 once the last source releases).
/mob/living/proc/apply_combined_alpha(animate_time = 0)
	var/target_alpha = round(255 * stat_value(src, STAT_ALPHA_MULT))
	if(animate_time)
		animate(src, alpha = target_alpha, time = animate_time)
	else
		alpha = target_alpha
