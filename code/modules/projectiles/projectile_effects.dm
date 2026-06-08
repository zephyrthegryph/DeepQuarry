/*
 * /datum/projectile_effects — unified effect payload for /obj/item/projectile.
 *
 * Consolidates the per-projectile var scatter (stun/weaken/paralyze/agony/
 * incendiary/flammability/modifier) behind a single datum that can be:
 *   - Declared once in a type definition and shared across all instances (static).
 *   - Composed from multiple sources at fire-time.
 *   - Extended by subtype projectiles without duplicating apply logic.
 *
 * Usage pattern (type definition):
 *   /obj/item/projectile/my_custom
 *       var/static/datum/projectile_effects/effects = new(
 *           stun = 3, weaken = 2, agony = 20
 *       )
 *
 * Usage pattern (apply in on_hit override):
 *   /obj/item/projectile/my_custom/on_hit(atom/target, blocked, def_zone)
 *       if(effects)
 *           effects.apply_to_mob(target, def_zone, blocked)
 *       return ..()
 *
 * The datum does NOT replace the base projectile vars — those remain for
 * backwards compatibility with the many call sites that set them directly.
 * The datum is an *additive* mechanism for complex projectile subtypes.
 */

/datum/projectile_effects
	/// Stun duration (deciseconds).
	var/stun = 0
	/// Weaken duration (deciseconds).
	var/weaken = 0
	/// Paralyze duration (deciseconds).
	var/paralyze = 0
	/// Irradiate amount.
	var/irradiate = 0
	/// Stutter duration (deciseconds).
	var/stutter = 0
	/// Eye-blur duration (deciseconds).
	var/eyeblur = 0
	/// Drowsy duration (deciseconds).
	var/drowsy = 0
	/// Agony (halloss damage) amount.
	var/agony = 0
	/// Incendiary level: 0 = none, 1 = ignite, 2 = trail of fire, 3 = intense fire.
	var/incendiary = 0
	/// Fire-stack amount for the above incendiary level.
	var/flammability = 0
	/// If set, apply this modifier type to struck living mobs.
	var/modifier_type_to_apply = null
	/// Duration for modifier_type_to_apply (null = permanent).
	var/modifier_duration = null
	/// Extra effects to apply to turfs struck by this projectile (turf_effect proc ref).
	var/datum/callback/turf_effect_callback = null

/datum/projectile_effects/New(
	stun = 0, weaken = 0, paralyze = 0, irradiate = 0,
	stutter = 0, eyeblur = 0, drowsy = 0, agony = 0,
	incendiary = 0, flammability = 0,
	modifier_type_to_apply = null, modifier_duration = null
)
	..()
	src.stun                  = stun
	src.weaken                = weaken
	src.paralyze              = paralyze
	src.irradiate             = irradiate
	src.stutter               = stutter
	src.eyeblur               = eyeblur
	src.drowsy                = drowsy
	src.agony                 = agony
	src.incendiary            = incendiary
	src.flammability          = flammability
	src.modifier_type_to_apply = modifier_type_to_apply
	src.modifier_duration     = modifier_duration

/datum/projectile_effects/Destroy()
	QDEL_NULL(turf_effect_callback)
	return ..()

/// Apply mob-targeted effects.  Returns TRUE if any effect was applied.
/// blocked: armor absorption percentage; >= 100 suppresses all effects.
/datum/projectile_effects/proc/apply_to_mob(mob/living/target, def_zone, blocked = 0)
	if(!isliving(target))
		return FALSE
	if(blocked >= 100)
		return FALSE
	var/mob/living/L = target
	L.apply_effects(stun, weaken, paralyze, irradiate, stutter, eyeblur, drowsy, agony, blocked, incendiary, flammability)
	if(modifier_type_to_apply)
		L.add_modifier(modifier_type_to_apply, modifier_duration)
	return TRUE

/// Apply turf-targeted effects (incendiary hotspot, etc.).
/// This is separate from the mob path so arc/mortar projectiles can affect
/// the landing tile without requiring a living target.
/datum/projectile_effects/proc/apply_to_turf(turf/T, obj/item/projectile/source)
	if(!isturf(T))
		return
	if(incendiary && source && source.damage_type == BURN)
		T.hotspot_expose(700, 5)
	if(turf_effect_callback)
		turf_effect_callback.Invoke(T, source)

/// Merge another projectile_effects datum's values additively into this one.
/// Useful when composing effects from multiple sources at fire-time.
/datum/projectile_effects/proc/merge_from(datum/projectile_effects/other)
	if(!other)
		return
	stun       += other.stun
	weaken     += other.weaken
	paralyze   += other.paralyze
	irradiate  += other.irradiate
	stutter    += other.stutter
	eyeblur    += other.eyeblur
	drowsy     += other.drowsy
	agony      += other.agony
	if(other.incendiary > incendiary)
		incendiary  = other.incendiary
		flammability = other.flammability
	else if(other.incendiary == incendiary)
		flammability += other.flammability
	// Last-writer wins for modifiers (caller should order deliberately).
	if(other.modifier_type_to_apply)
		modifier_type_to_apply = other.modifier_type_to_apply
		modifier_duration      = other.modifier_duration
