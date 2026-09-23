//
// This is the shield effect object for the supercool shield gens.
//
/obj/effect/shield
	name = "energy shield"
	desc = "An impenetrable field of energy, capable of blocking anything as long as it's active."
	icon = 'icons/obj/machines/shielding_vr.dmi'
	icon_state = "shield"
	anchored = TRUE
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	density = TRUE
	invisibility = INVISIBILITY_NONE
	var/obj/machinery/power/shield_generator/gen = null // Owning generator
	var/disabled_for = 0
	var/diffused_for = 0
	can_atmos_pass = ATMOS_PASS_YES
	var/enabled_icon_state

/obj/effect/shield/proc/update_visuals()
	update_iconstate()
	update_color()
	update_glow()
	update_opacity()

/obj/effect/shield/proc/update_iconstate()
	if(!enabled_icon_state)
		enabled_icon_state = icon_state

	if(disabled_for || diffused_for)
		icon_state = "shield_broken"
		overlays.Cut() // Snowflake handling, avoiding SSoverlays
	else
		icon_state = enabled_icon_state
		//flags |= OVERLAY_QUEUED //Trick SSoverlays
		//SSoverlays.queue += src

/obj/effect/shield/proc/update_color()
	if(disabled_for || diffused_for)
		color = "#FFA500"
	else if(gen?.check_flag(MODEFLAG_OVERCHARGE))
		color = "#FE6666"
	else
		color = "#00AAFF"

/obj/effect/shield/proc/update_glow()
	if(density)
		set_light(3, 3, "#66FFFF")
	else
		set_light(0)

/obj/effect/shield/proc/update_opacity()
	if(gen?.check_flag(MODEFLAG_PHOTONIC) && !disabled_for && !diffused_for)
		set_opacity(1)
	else
		set_opacity(0)

// Prevents singularities and pretty much everything else from moving the field segments away.
// The only thing that is allowed to move us is the Destroy() proc.
/obj/effect/shield/forceMove(atom/destination, direction, movetime)
	if(QDELING(src))
		return ..()
	return 0

/obj/effect/shield/Destroy()
	if(can_atmos_pass != ATMOS_PASS_YES)
		update_nearby_tiles() //Force ZAS update
	. = ..()
	if(gen)
		if(src in gen.field_segments)
			LAZYREMOVE(gen.field_segments, src)
		if(src in gen.damaged_segments)
			LAZYREMOVE(gen.damaged_segments, src)
		gen = null

// Temporarily collapses this shield segment.
/obj/effect/shield/proc/fail(duration)
	if(duration <= 0)
		return

	if(gen)
		LAZYOR(gen.damaged_segments, src)
	disabled_for += duration

	set_density(0)
	update_visuals()
	update_nearby_tiles() //Force ZAS update
	update_explosion_resistance()

// Regenerates this shield segment.
/obj/effect/shield/proc/regenerate()
	if(!gen)
		return
	if(nearby_active_shield_diffuser(src))
		diffuse(5)
		return

	disabled_for = max(0, disabled_for - 1)
	diffused_for = max(0, diffused_for - 1)

	if(!disabled_for && !diffused_for)
		set_density(1)
		update_visuals()
		update_nearby_tiles() //Force ZAS update
		update_explosion_resistance()
		LAZYREMOVE(gen.damaged_segments, src)

/obj/effect/shield/proc/diffuse(duration)
	// The shield is trying to counter diffusers. Cause lasting stress on the shield.
	if(gen?.check_flag(MODEFLAG_BYPASS) && !disabled_for)
		take_damage(duration * rand(8, 12), SHIELD_DAMTYPE_EM)
		return

	diffused_for = max(duration, 0)
	LAZYOR(gen?.damaged_segments, src)

	set_density(0)
	update_visuals()
	update_nearby_tiles() //Force ZAS update
	update_explosion_resistance()

/obj/effect/shield/attack_generic(source, damage, emote)
	take_damage(damage, SHIELD_DAMTYPE_PHYSICAL)
	if(gen.check_flag(MODEFLAG_OVERCHARGE) && istype(source, /mob/living/))
		overcharge_shock(source)
	..(source, damage, emote)


// Fails shield segments in specific range. Range of 1 affects the shielded turf only.
/obj/effect/shield/proc/fail_adjacent_segments(range, hitby = null)
	if(hitby)
		visible_message(span_danger("\The [src] flashes a bit as \the [hitby] collides with it, eventually fading out in a rain of sparks!"))
	else
		visible_message(span_danger("\The [src] flashes a bit as it eventually fades out in a rain of sparks!"))
	fail(range * 2)

	for(var/obj/effect/shield/S in range(range, src))
		// Don't affect shields owned by other shield generators
		if(S.gen != src.gen)
			continue
		// The closer we are to impact site, the longer it takes for shield to come back up.
		S.fail(-(-range + get_dist(src, S)) * 2)

// Small visual effect, makes the shield tiles brighten up by becoming more opaque for a moment, and spreads to nearby shields.
/obj/effect/shield/proc/flash_adjacent_segments(range)
	range = between(1, range, 10) // Sanity check
	for(var/obj/effect/shield/S in range(range, src))
		// Don't affect shields owned by other shield generators
		if(S.gen != src.gen || S == src)
			continue
		// Note: Range is a non-exact aproximation of the spread effect. If it doesn't look good
		// we'll need to switch to actually walking along the shields to get exact number of steps away.
		addtimer(CALLBACK(S, PROC_REF(impact_flash)), get_dist(src, S) * 2)
	impact_flash()

// Small visual effect, makes the shield tiles brighten up by becoming more opaque for a moment
/obj/effect/shield/proc/impact_flash()
	alpha = 100
	animate(src, alpha = initial(alpha), time = 1 SECOND)

// Just for fun
/obj/effect/shield/attack_hand(user)
	flash_adjacent_segments(3)

/obj/effect/shield/take_damage(damage, damtype, hitby)
	if(!gen)
		qdel(src)
		return

	if(!damtype)
		stack_trace("CANARY: shield.take_damage() callled without damtype.")

	if(!damage)
		return

	damage = round(damage)

	new /obj/effect/temp_visual/shield_impact_effect(get_turf(src))

	switch(gen.deal_shield_damage(damage, damtype))
		if(SHIELD_ABSORBED)
			flash_adjacent_segments(round(damage/10)) // Nice visual effect only.
			return
		if(SHIELD_BREACHED_MINOR)
			fail_adjacent_segments(rand(1, 3), hitby)
			return
		if(SHIELD_BREACHED_MAJOR)
			fail_adjacent_segments(rand(2, 5), hitby)
			return
		if(SHIELD_BREACHED_CRITICAL)
			fail_adjacent_segments(rand(4, 8), hitby)
			return
		if(SHIELD_BREACHED_FAILURE)
			fail_adjacent_segments(rand(8, 16), hitby)
			return


/// Packet sink. A segment has no integrity of its own: hits drain its
/// generator's shared energy (deal_shield_damage) by shield damage type.
/// take_damage() here keeps its (damage, SHIELD_DAMTYPE_*, hitby) form for the
/// explosion and EMP ladders (D5).
/obj/effect/shield/receive_damage(datum/damage_packet/packet)
	if(QDELETED(src) || disabled_for)
		return 0
	var/list/amounts = packet.amounts
	var/physical = amounts[DAMAGE_BLUNT] + amounts[DAMAGE_SHARP] + amounts[DAMAGE_PIERCE] + amounts[DAMAGE_BLAST]
	var/heat = amounts[DAMAGE_THERMAL] + amounts[DAMAGE_COLD]
	var/electromagnetic = amounts[DAMAGE_SHOCK] + amounts[DAMAGE_IONIC]
	if(physical > 0)
		take_damage(physical, SHIELD_DAMTYPE_PHYSICAL, packet.source)
	if(heat > 0 && !QDELETED(src))
		take_damage(heat, SHIELD_DAMTYPE_HEAT, packet.source)
	if(electromagnetic > 0 && !QDELETED(src))
		take_damage(electromagnetic, SHIELD_DAMTYPE_EM, packet.source)
	return physical + heat + electromagnetic

// As we have various shield modes, this handles whether specific things can pass or not.
/obj/effect/shield/CanPass(atom/movable/mover, turf/target)
	// Somehow we don't have a generator. This shouldn't happen. Delete the shield.
	if(!gen)
		qdel(src)
		return 1

	if(disabled_for || diffused_for)
		return 1

	if(mover)
		return mover.can_pass_shield(gen)
	return 1

/obj/effect/shield/proc/set_can_atmos_pass(new_value)
	if(new_value == can_atmos_pass)
		return
	can_atmos_pass = new_value
	update_nearby_tiles() //Force ZAS update


// EMP. It may seem weak but keep in mind that multiple shield segments are likely to be affected.
/obj/effect/shield/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || disabled_for)
		return
	take_damage(rand(30,60) / severity, SHIELD_DAMTYPE_EM)

// Explosions
/obj/effect/shield/ex_act(severity)
	if(!disabled_for)
		take_damage(rand(10,15) / severity, SHIELD_DAMTYPE_PHYSICAL)


// Fire
/obj/effect/shield/fire_act(exposed_temperature, exposed_volume)
	if(!disabled_for)
		take_damage(rand(5,10), SHIELD_DAMTYPE_HEAT)


// Projectiles
/obj/effect/shield/bullet_act(obj/item/projectile/proj)
	if(proj.obj_damage_type() == BURN)
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_HEAT)
	else if (proj.obj_damage_type() == BRUTE)
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_PHYSICAL)
	else //TODO - This will never happen because of get_structure_damage() only returning values for BRUTE and BURN damage types
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_EM)


// Attacks with hand tools. Blocked by Hyperkinetic flag.
/obj/effect/shield/attackby(obj/item/I as obj, mob/user as mob)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	user.do_attack_animation(src)

	if(gen.check_flag(MODEFLAG_HYPERKINETIC))
		user.visible_message(span_danger("\The [user] hits \the [src] with \the [I]!"))
		if(I.obj_damage_type() == BURN)
			take_damage(I.force, SHIELD_DAMTYPE_HEAT)
		else if (I.obj_damage_type() == BRUTE)
			take_damage(I.force, SHIELD_DAMTYPE_PHYSICAL)
		else
			take_damage(I.force, SHIELD_DAMTYPE_EM)
	else
		user.visible_message(span_danger("\The [user] tries to attack \the [src] with \the [I], but it passes through!"))


// Special treatment for meteors because they would otherwise penetrate right through the shield.
/obj/effect/shield/Bumped(atom/movable/mover)
	if(!gen)
		qdel(src)
		return 0
	mover.shield_impact(src)
	return ..()

// Meteors call this instad of Bumped for some reason
/obj/effect/shield/handle_meteor_impact(obj/effect/meteor/meteor)
	meteor.shield_impact(src)
	return !QDELETED(meteor) // If it was stopped it will have been deleted

/obj/effect/shield/proc/overcharge_shock(mob/living/M)
	M.injure(INJURY_ELECTRIC, rand(20, 40), null, src)
	M.Weaken(5)
	to_chat(M, span_danger("As you come into contact with \the [src] a surge of energy paralyses you!"))
	take_damage(10, SHIELD_DAMTYPE_EM)

// Called when a flag is toggled. Can be used to add on-toggle behavior, such as visual changes.
/obj/effect/shield/proc/flags_updated()
	if(!gen)
		qdel(src)
		return

	// Update airflow - If atmospheric we block air as long as we're enabled (density works for this)
	set_can_atmos_pass(gen.check_flag(MODEFLAG_ATMOSPHERIC) ? ATMOS_PASS_DENSITY : ATMOS_PASS_YES)
	update_visuals()
	update_explosion_resistance()

/obj/effect/shield/proc/update_explosion_resistance()
	if(gen && gen.check_flag(MODEFLAG_HYPERKINETIC))
		explosion_resistance = INFINITY
	else
		explosion_resistance = 0

//
// Visual effect of shield taking impact
//
/obj/effect/temp_visual/shield_impact_effect
	name = "shield impact"
	icon = 'icons/obj/machines/shielding_vr.dmi'
	icon_state = "shield_impact"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	duration = 2 SECONDS
	randomdir = FALSE

//
// Shield collision checks below
//

// Called only if shield is active/not destroyed etc.
/atom/movable/proc/can_pass_shield(obj/machinery/power/shield_generator/gen)
	return 1


// Other mobs
/mob/living/can_pass_shield(obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_NONHUMANS)

// Human mobs
/mob/living/carbon/human/can_pass_shield(obj/machinery/power/shield_generator/gen)
	if(isSynthetic())
		return !gen.check_flag(MODEFLAG_ANORGANIC)
	return !gen.check_flag(MODEFLAG_HUMANOIDS)

// Silicon mobs
/mob/living/silicon/can_pass_shield(obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_ANORGANIC)


// Generic objects. Also applies to bullets and meteors.
/obj/can_pass_shield(obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_HYPERKINETIC)

// Beams
/obj/item/projectile/beam/can_pass_shield(obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_PHOTONIC)


// Shield on-impact logic here. This is called only if the object is actually blocked by the field (can_pass_shield applies first)
/atom/movable/proc/shield_impact(obj/effect/shield/S)
	return

/mob/living/shield_impact(obj/effect/shield/S)
	if(!S.gen.check_flag(MODEFLAG_OVERCHARGE))
		return
	S.overcharge_shock(src)

/obj/effect/meteor/shield_impact(obj/effect/shield/S)
	if(!S.gen.check_flag(MODEFLAG_HYPERKINETIC))
		return
	S.take_damage(get_shield_damage(), SHIELD_DAMTYPE_PHYSICAL, src)
	visible_message(span_danger("\The [src] breaks into dust!"))
	make_debris()
	qdel(src)
