/obj/structure/closet/coffin
	name = "coffin"
	desc = "It's a burial receptacle for the dearly departed."
	icon = 'icons/obj/closets/coffin.dmi'

	icon_state = "closed_unlocked"
	breakout_sound = SFX_WEAPONS_TABLEHIT1
	closet_appearance = null // Special icon for us

// A coffin is screwed shut, not welded.
CAPABILITIES(/obj/structure/closet/coffin)
	configure(weld_shut(tool = TOOL_SCREWDRIVER))

/* Graves */
/obj/structure/closet/grave
	name = "grave"
	desc = "Dirt."
	icon = 'icons/obj/closets/grave.dmi'
	icon_state = ""
	sealable = FALSE
	breakout_sound = SFX_WEAPONS_THUDSWOOSH
	anchored = TRUE
	max_closets = 1
	opened = 1
	closet_appearance = null // Special icon for us
	open_sound = SFX_EFFECTS_WOODEN_CLOSET_OPEN
	close_sound = SFX_EFFECTS_WOODEN_CLOSET_CLOSE

MSG_DEF(grave/climb_start, "You start to lower yourself into %T%.", "%U% starts to climb into %T%.")
MSG_DEF(grave/climbed, "You climb into %T%.", "%U% climbs into %T%.")
MSG_DEF(grave/fill_start, "You start to pile dirt into %T%.", "%U% piles dirt into %T%.")
MSG_DEF(grave/filled, "You finish filling in %T%.", "%U% pats down the dirt on top of %T%.")
MSG_DEF(grave/smooth_start, "You start to smoothe out the dirt of %T%.", "%U% begins to smoothe out the dirt of %T%.")
MSG_DEF(grave/smoothed, "You finish smoothing out %T%.", "%U% finishes smoothing out %T%.")
MSG_DEF(grave/dig_start, "You start to unearth %T%.", "%U% begins to unearth %T%.")
MSG_DEF(grave/dug, "You finish digging out %T%.", "%U% reaches the bottom of %T%.")

// A grave has no door to work and nothing is stuffed into it by a drag: a hand climbs into an open one (five seconds), a shovel fills one in and, on a filled one,
// unearths it (or, in combat mode, smooths it over). It holds like a sealed closet once it is filled.
CAPABILITIES(/obj/structure/closet/grave)
	without(CAP_WELD_SHUT)
	without("door")
	without("stuff")
	without("devour")
	without("strike")
	op("climb_in", hand(), label("Climb in"), at(SPACE_INTERIOR), wait(5 SECONDS), begins(MSG(grave/climb_start)), then(PROC_REF(climbed_in)), says(MSG(grave/climbed)),
		on_interrupt(PROC_REF(climb_interrupted)))
	// ALLOW(door_gates): the same shovel smooths or unearths a filled grave, and op_order reads this when() to keep the three apart
	op("fill", item(/obj/item/shovel), label("Fill in"), when(nameof(opened)), priority(OP_PRIORITY_PART), wait(4 SECONDS), begins(MSG(grave/fill_start)),
		then(PROC_REF(filled_in)), says(MSG(grave/filled)), on_interrupt(PROC_REF(fill_interrupted)))
	op("smooth_over", item(/obj/item/shovel), label("Smooth over"), when(cond_not(nameof(opened))), hostile(), priority(OP_PRIORITY_PART), wait(4 SECONDS),
		begins(MSG(grave/smooth_start)), then(PROC_REF(smoothed_over)), says(MSG(grave/smoothed)), on_interrupt(PROC_REF(smooth_interrupted)))
	op("unearth", item(/obj/item/shovel), label("Unearth"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART), wait(4 SECONDS),
		begins(MSG(grave/dig_start)), then(PROC_REF(dug_out)), says(MSG(grave/dug)), on_interrupt(PROC_REF(dig_interrupted)))

/obj/structure/closet/grave/CanPass(atom/movable/mover, turf/target)
	if(opened && ismob(mover))
		var/mob/M = mover
		add_fingerprint(M)
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.m_intent == I_WALK)
				to_chat(H, span_warning("You stop at the edge of \the [src.name]."))
				return FALSE
			else
				to_chat(H, span_warning("You fall into \the [src.name]!"))
				fall_in(H)
				return TRUE
		if(isrobot(M))
			var/mob/living/silicon/robot/R = M
			if(!R.combat_mode)
				to_chat(R, span_warning("You stop at the edge of \the [src.name]."))
				return FALSE
			else
				to_chat(R, span_warning("You enter \the [src.name]."))
				return TRUE
	return TRUE	//Everything else can move over the graves

/obj/structure/closet/grave/proc/fall_in(mob/living/L)	//Only called on humans for now, but still
	L.status_at_least(STAT_WEAKENED, 5)
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		var/limb_damage = rand(5,25)
		H.injure(INJURY_BLUNT, limb_damage, null, src)

/// The climber is let down into the grave.
/obj/structure/closet/grave/proc/climbed_in(datum/act/op/A)
	A.actor.forceMove(src.loc)
	return OP_OK

/obj/structure/closet/grave/proc/climb_interrupted(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You stop climbing into %T%.")), MSG_OTHERS(span_notice("%U% decides not to climb into %T%.")))

/// The grave is closed over what is in it.
/obj/structure/closet/grave/proc/filled_in(datum/act/op/A)
	close()
	return OP_OK

/obj/structure/closet/grave/proc/fill_interrupted(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You change your mind and stop filling in %T%.")), MSG_OTHERS(span_notice("%U% stops filling in %T%.")))

/// A grave with something in it is only hidden a little; an empty one goes away.
/obj/structure/closet/grave/proc/smoothed_over(datum/act/op/A)
	if(LAZYLEN(contents) || has_latent())
		alpha = 40	// If we've got stuff inside, like maybe a person, just make it hard to see us
	else
		consume(src, A.actor)	// Else, go away
	return OP_OK

/obj/structure/closet/grave/proc/smooth_interrupted(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You stop concealing %T%.")), MSG_OTHERS(span_notice("%U% stops concealing %T%.")))

/// The grave is dug out to the bottom: what lies in it is let out.
/obj/structure/closet/grave/proc/dug_out(datum/act/op/A)
	break_open()
	return OP_OK

/obj/structure/closet/grave/proc/dig_interrupted(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You stop digging out %T%.")), MSG_OTHERS(span_notice("%U% stops digging out %T%.")))

/obj/structure/closet/grave/close()
	..()
	if(!opened)
		set_welded(src, TRUE)

/obj/structure/closet/grave/open()
	.=..()
	alpha = 255	// Needed because of grave hiding

/obj/structure/closet/grave/bullet_act(obj/item/projectile/P)
	return PROJECTILE_CONTINUE	// It's a hole in the ground, doesn't usually stop or even care about bullets

/obj/structure/closet/grave/return_air_for_internal_lifeform(mob/living/L)
	var/gasid = GAS_CO2
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if(H.species && H.species.exhale_type)
			gasid = H.species.exhale_type
	var/datum/gas_mixture/grave_breath = new()
	var/datum/gas_mixture/above_air = return_air()
	grave_breath.adjust_gas(gasid, BREATH_MOLES)
	heat_set(grave_breath, (above_air.return_temperature()) - 30)	//Underground
	return grave_breath

/obj/structure/closet/grave/dirthole
	name = "hole"
