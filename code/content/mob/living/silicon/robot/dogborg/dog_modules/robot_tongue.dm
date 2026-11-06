//Tongue stuff
/obj/item/robot_tongue
	name = "synthetic tongue"
	desc = "Useful for slurping mess off the floor before affectionately licking the crew members in the face."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "synthtongue"
	var/emagged = 0
	var/datum/matter_synth/water = null // readds water
	flags = NOBLUDGEON //No more attack messages

MSG_DEF(tongue/drink, span_notice("You begin to lap up water from %T%."), span_filter_notice("%U% begins to lap up water from %T%."))
MSG_DEF_SELF(tongue/full, span_notice("You refrain from lapping water from %T% with your reserves filled."))
MSG_DEF_SELF(tongue/dry, span_notice("Your mouth feels dry. You should drink up some water ."))
MSG_DEF(tongue/lick_up, span_notice("You begin to lick off %T%..."), span_filter_notice("%U% begins to lick off %T%."))
MSG_DEF(tongue/nibble, span_notice("You begin to nibble away at %T%..."), span_filter_notice("%U% nibbles away at %T%."))
MSG_DEF(tongue/cram, span_notice("You begin cramming %T% down your throat..."), span_filter_notice("%U% begins cramming %T% down its throat."))
MSG_DEF(tongue/lick_clean, span_notice("You begin to lick %T% clean..."), span_filter_notice("%U% begins to lick %T% clean..."))

CAPABILITIES(/obj/item/robot_tongue)
	ref_one(nameof(water), /datum/matter_synth)
	configure(item_sounds(hit = SFX_EFFECTS_ATTACKBLOB))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	// a lick of anything but a person is five seconds of standing still; a person's face is instant (afterattack)
	op("tongue_drink_sink", at_target(/obj/structure/sink), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_thirsty), silent = TRUE)), starts(PROC_REF(tongue_started)), begins(MSG(tongue/drink)), wait(5 SECONDS), then(PROC_REF(tongue_drank)))
	op("tongue_drink_toilet", at_target(/obj/structure/toilet), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_thirsty), because = MSG(tongue/full))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/drink)), wait(5 SECONDS), then(PROC_REF(tongue_drank)))
	op("tongue_lick_up", at_target(/obj/effect/decal/cleanable), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/lick_up)), wait(5 SECONDS), then(PROC_REF(tongue_licked_up)))
	op("tongue_eat_trash", at_target(/obj/item/trash), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/nibble)), wait(5 SECONDS), then(PROC_REF(tongue_ate_trash)))
	op("tongue_eat_food", at_target(/obj/item/reagent_containers/food), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/nibble)), wait(5 SECONDS), then(PROC_REF(tongue_ate_food)))
	op("tongue_eat_cell", at_target(/obj/item/cell), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/cram)), wait(5 SECONDS), then(PROC_REF(tongue_ate_cell)))
	op("tongue_clean_item", at_target(/obj/item), priority(OP_PRIORITY_NORMAL), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/lick_clean)), wait(5 SECONDS), then(PROC_REF(tongue_cleaned_item)))
	op("tongue_clean_other", at_target(), priority(OP_PRIORITY_DEFAULT), answers(INTENT_USE, INTENT_ATTACK), when(PROC_REF(not_a_person)), needs(req(PROC_REF(tongue_wet))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/lick_clean)), wait(5 SECONDS), then(PROC_REF(tongue_cleaned_other)))

/// Old attack_self.
/obj/item/robot_tongue/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = user
	if(R.emagged || R.emag_items)
		emagged = !emagged
		if(emagged)
			name = "hacked tongue of doom"
			desc = "Your tongue has been upgraded successfully. Congratulations."
			set_icon('icons/mob/dogborg_vr.dmi')
			set_icon_state("syndietongue")
		else
			name = "synthetic tongue"
			desc = "Useful for slurping mess off the floor before affectionately licking the crew members in the face."
			set_icon('icons/mob/dogborg_vr.dmi')
			set_icon_state("synthtongue")
	return TRUE

/obj/item/robot_tongue/afterattack(atom/target, mob/user, proximity)
	if(!proximity)
		return
	// everything but a person is a tongue_* op (its CAPABILITIES block)
	if(!ishuman(target))
		return

	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(user.client && (target in user.client.screen))
		to_chat(user, span_warning("You need to take \the [target.name] off before cleaning it!"))
	if(water.energy < 5)
		to_chat(user, span_notice("Your mouth feels dry. You should drink up some water ."))
		return
	if(src.emagged)
		var/mob/living/silicon/robot/R = user
		var/mob/living/L = target
		if(!R.draw_power(ROBOT_CELL_JOULES(666), src, ROBOT_CELL_JOULES(100)))
			to_chat(user, span_warning("Warning, low power detected. Aborting action."))
			return
		L.status_at_least(STAT_STUNNED, 1)
		L.status_at_least(STAT_WEAKENED, 1)
		L.apply_effect(STUTTER, 1)
		act_message(L, user, MSG_SELF(span_userdanger("%T% has shocked you with its tongue! You can feel the betrayal.")), \
			MSG_OTHERS(span_danger("%T% has shocked %U% with its tongue!")))
		play_sfx(src, SFX_WEAPONS_EGLOVES)
	else
		act_message(user, target, MSG_SELF(span_notice("You affectionately lick all over %T%'s face!")), \
			MSG_OTHERS(span_notice("%U% affectionately licks all over %T%'s face!")))
		play_sfx(src, SFX_EFFECTS_ATTACKBLOB)
		water.use_charge(5)
		var/mob/living/carbon/human/H = target
		if(H.species.lightweight == 1)
			H.status_at_least(STAT_WEAKENED, 3)

/// The tongue has enough water for a lick of anything but a sink (a person's face, a mess, a meal).
/obj/item/robot_tongue/proc/tongue_wet(datum/act/op/A)
	return (read_once(water.energy >= 5)) ? null : MSG(tongue/dry)

/// A sink is lapped from while the reserve has room.
/obj/item/robot_tongue/proc/tongue_thirsty(datum/act/op/A)
	return (read_once(water.energy < water.max_energy)) ? null : MSG(tongue/full)

/obj/item/robot_tongue/proc/tongue_started(datum/act/op/A)
	var/mob/living/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)

/obj/item/robot_tongue/proc/tongue_drank(datum/act/op/A)
	water.add_charge(250)
	to_chat(A.actor, span_filter_notice("You refill some of your water reserves."))
	return OP_OK

/obj/item/robot_tongue/proc/tongue_licked_up(datum/act/op/A)
	var/atom/target = A.target
	to_chat(A.actor, span_notice("You finish licking off \the [target.name]."))
	water.use_charge(5)
	consumed(target, src)
	var/mob/living/silicon/robot/R = A.actor
	R.add_power(ROBOT_CELL_JOULES(50), src)
	return OP_OK

/obj/item/robot_tongue/proc/tongue_ate_trash(datum/act/op/A)
	var/atom/target = A.target
	var/mob/living/silicon/robot/R = A.actor
	act_message(R, null, MSG_SELF(span_notice("You finish eating \the [target.name].")), \
		MSG_OTHERS(span_filter_notice("%U% finishes eating \the [target.name].")))
	to_chat(R, span_notice("You finish off \the [target.name]."))
	consumed(target, R)
	R.add_power(ROBOT_CELL_JOULES(250), src)
	water.use_charge(5)
	return OP_OK

/obj/item/robot_tongue/proc/tongue_ate_food(datum/act/op/A)
	var/atom/target = A.target
	var/mob/living/silicon/robot/R = A.actor
	act_message(R, null, MSG_SELF(span_notice("You finish eating \the [target.name].")), MSG_OTHERS("%U% finishes eating \the [target.name]."))
	to_chat(R, span_notice("You finish off \the [target.name]."))
	consumed(target, R)
	R.add_power(ROBOT_CELL_JOULES(250), src)
	return OP_OK

/obj/item/robot_tongue/proc/tongue_ate_cell(datum/act/op/A)
	var/obj/item/cell/C = A.target
	var/mob/living/silicon/robot/R = A.actor
	act_message(R, null, MSG_SELF(span_notice("You finish swallowing \the [C.name].")), \
		MSG_OTHERS(span_filter_notice("%U% finishes gulping down \the [C.name].")))
	to_chat(R, span_notice("You finish off \the [C.name], and gain some charge!"))
	R.add_power(ROBOT_CELL_JOULES(C.charge / 3), src)
	water.use_charge(5)
	consumed(C, R)
	return OP_OK

/obj/item/robot_tongue/proc/tongue_cleaned_item(datum/act/op/A)
	var/atom/target = A.target
	to_chat(A.actor, span_notice("You clean \the [target.name]."))
	water.use_charge(5)
	var/obj/effect/decal/cleanable/C = locate_in_list(target, /obj/effect/decal/cleanable)
	consumed(C, src)
	target.wash(CLEAN_WASH)
	return OP_OK

/obj/item/robot_tongue/proc/tongue_cleaned_other(datum/act/op/A)
	var/atom/target = A.target
	to_chat(A.actor, span_notice("You clean \the [target.name]."))
	var/obj/effect/decal/cleanable/C = locate_in_list(target, /obj/effect/decal/cleanable)
	consumed(C, src)
	target.wash(CLEAN_WASH)
	water.use_charge(5)
	if(istype(target, /turf/simulated))
		var/turf/simulated/T = target
		T.dirt = 0
	return OP_OK

/// Anything the tongue can clean that is not a person: the lowest tier, behind the sink, the messes, the meals and the loose items.
/obj/item/robot_tongue/proc/not_a_person(datum/act/op/A)
	return !ishuman(A.target)

/obj/item/robot_tongue/examine(user)
	. = ..()
	if(Adjacent(user))
		if(water.energy)
			. += span_notice("[src] is wet. Just like it should be.")
		if(water.energy < 5)
			. += span_notice("[src] is dry.")


// Matter synths belong to the robot module (the owned "synths" list); tools draw on them.
