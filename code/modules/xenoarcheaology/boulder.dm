/obj/structure/boulder
	name = "rocky debris"
	desc = "Leftover rock from an excavation, it's been partially dug out already but there's still a lot to go."
	icon = 'icons/obj/mining.dmi'
	icon_state = "boulder1"
	density = TRUE
	opacity = 1
	anchored = TRUE
	var/excavation_level = 0
	/// Owned: the boulder's own geosample and the artifact find it took over from its mine turf.
	var/tmp/datum/geosample/geological_data_static
	var/tmp/datum/artifact_find/artifact_find_static
	COOLDOWN_DECLARE(dig_cooldown)

CAPABILITIES(/obj/structure/boulder)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	rolls(nameof(excavation_level), range_of(5, 50))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/boulder/proc/roll_icon_state(datum/roller/R)
	return "boulder[R.number(1, 4)]"

/// Old attackby.
/obj/structure/boulder/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/core_sampler))
		if(!geological_data() || !artifact_find())
			return OP_PASS
		src.geological_data().artifact_distance = rand(-100,100) / 100
		src.geological_data().artifact_id = artifact_find().artifact_id

		var/obj/item/core_sampler/C = I
		C.sample_item(src, user)
		return OP_PASS

	if(istype(I, /obj/item/depth_scanner))
		var/obj/item/depth_scanner/C = I
		C.scan_atom(user, src)
		return OP_PASS

	if(istype(I, /obj/item/xenoarch_multi_tool))
		var/obj/item/xenoarch_multi_tool/C = I
		if(C.mode) //Mode means scanning.
			C.depth_scanner.scan_atom(user, src)
			return OP_PASS
		else
			act_message(user, src, MSG_SELF(span_notice("You extend %I% over %T%, a flurry of red beams scanning %T%'s surface!")), \
				MSG_OTHERS(span_bold("%U%") + " extends %I% over %T%, a flurry of red beams scanning %T%'s surface!"), \
				item = C)
			task_timed(user, 1.5 SECONDS, src, src, PROC_REF(measure_done), list(user))
			return OP_PASS

	if(istype(I, /obj/item/measuring_tape))
		var/obj/item/measuring_tape/P = I
		act_message(user, src, MSG_SELF(span_notice("You extend %I% towards %T%.")), MSG_OTHERS(span_bold("%U%") + " extends %I% towards %T%."), item = P)
		task_timed(user, 1.5 SECONDS, src, src, PROC_REF(measure_done), list(user))
		return OP_PASS

	if(istype(I, /obj/item/pickaxe))
		var/obj/item/pickaxe/P = I

		if(!COOLDOWN_FINISHED(src, dig_cooldown))//prevents message spam
			return OP_PASS
		COOLDOWN_START(src, dig_cooldown, P.digspeed)

		to_chat(user, span_warning("You start [P.drill_verb] [src]."))
		task_timed(user, P.digspeed, src, src, PROC_REF(dig_done), list(user, P))
		return OP_PASS
	return OP_PASS

/obj/structure/boulder/proc/measure_done(mob/user)
	to_chat(user, span_notice("\The [src] has been excavated to a depth of [2 * src.excavation_level]cm."))

/obj/structure/boulder/proc/dig_done(mob/user, obj/item/pickaxe/P)
	if(loc?.release_refusal(src, user))
		return
	to_chat(user, span_notice("You finish [P.drill_verb] [src]."))
	excavation_level += P.excavation_amount

	if(prob(excavation_level))
		//success
		if(artifact_find())
			var/spawn_type = artifact_find().artifact_find_type
			var/obj/O = new spawn_type(get_turf(src))
			if(istype(O, /obj/machinery/artifact))
				var/obj/machinery/artifact/X = O
				if(X.artifact_master)
					X.artifact_master.artifact_id = artifact_find().artifact_id
			O.set_anchored(FALSE)	// Anchored finds are lame.
			src.visible_message(span_warning("\The [src] suddenly crumbles away."))
		else
			act_message(user, src, MSG_SELF(span_notice("%T% has been whittled away under your careful excavation, but there was nothing of interest inside.")), \
				MSG_OTHERS(span_warning("%T% suddenly crumbles away.")))
		consume(src, user)

/obj/structure/boulder/Bumped(AM)
	. = ..()
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		var/obj/item/pickaxe/P = H.get_inactive_hand()
		if(istype(P))
			src.attackby(P, H)

	else if(istype(AM,/mob/living/silicon/robot))
		var/mob/living/silicon/robot/R = AM
		if(istype(R.module_active,/obj/item/pickaxe))
			attackby(R.module_active,R)

	else if(istype(AM,/obj/mecha))
		var/obj/mecha/M = AM
		if(istype(M.selected,/obj/item/mecha_parts/mecha_equipment/tool/drill))
			M.selected.action(src)

/// Accessor for the owned value.
/obj/structure/boulder/proc/geological_data() as /datum/geosample
	return geological_data_static

/// Accessor for the owned value.
/obj/structure/boulder/proc/artifact_find() as /datum/artifact_find
	return artifact_find_static
