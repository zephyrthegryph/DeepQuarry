//Boop //New and improved, now a simple reagent sniffer.
/obj/item/boop_module
	name = "boop module"
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "nose"
	desc = "The BOOP module, a simple reagent and atmosphere scanner."
	force = 0
	throwforce = 0
	attack_verb = list("nuzzled", "nosed", "booped")
	w_class = ITEMSIZE_TINY
	flags = NOBLUDGEON //No more attack messages

CAPABILITIES(/obj/item/boop_module)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/boop_module/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if (!( istype(user.loc, /turf) ))
		return TRUE

	var/datum/gas_mixture/environment = user.loc.return_air()

	var/pressure = environment.return_pressure()
	var/total_moles = environment.total_moles()

	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, null, MSG_SELF(span_notice("You scan the air...")), MSG_OTHERS(span_notice("%U% scans the air.")))

	to_chat(user, span_boldnotice("Scan results:"))
	if(abs(pressure - ONE_ATMOSPHERE) < 10)
		to_chat(user, span_notice("Pressure: [round(pressure,0.1)] kPa"))
	else
		to_chat(user, span_warning("Pressure: [round(pressure,0.1)] kPa"))
	if(total_moles)
		// was XGM env.gas[g] iteration; under LINDA, env.gases keys are
		// /datum/gas type paths and the moles live at gases[g][MOLES].
		for(var/datum/gas/g as anything in environment.get_gases())
			var/moles = environment.get_moles(g)
			to_chat(user, span_notice("[initial(g.name)]: [round((moles / total_moles) * 100)]%"))
		var/environment_temperature = environment.return_temperature()
		to_chat(user, span_notice("Temperature: [round(environment_temperature-T0C,0.1)]&deg;C ([round(environment_temperature,0.1)]K)"))
	return TRUE

/obj/item/boop_module/afterattack(obj/O, mob/user as mob, proximity)
	if(!proximity)
		return
	if (user.stat)
		return
	if(!istype(O))
		return

	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, null, MSG_SELF(span_notice("You scan \the [O.name]...")), MSG_OTHERS(span_notice("%U% scan at \the [O.name].")))

	if(!isnull(O.reagents))
		var/dat = ""
		if(O.reagents.reagent_list.len > 0)
			for (var/datum/reagent/R in O.reagents.reagent_list)
				dat += "\n \t " + span_notice("[R]")

		if(dat)
			to_chat(user, span_notice("Your BOOP module indicates: [dat]"))
		else
			to_chat(user, span_notice("No active chemical agents detected in [O]."))
	else
		to_chat(user, span_notice("No significant chemical agents detected in [O]."))

	return

/obj/item/shockpaddles/robot/hound
	name = "paws of life"
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "defibpaddles0"
	desc = "Zappy paws. For fixing cardiac arrest."
	combat = 1
	attack_verb = list("batted", "pawed", "bopped", "whapped")
	chargecost = 500

/obj/item/shockpaddles/robot/hound/jumper
	name = "jumper paws"
	desc = "Zappy paws. For rebooting a full body prostetic."
	use_on_synthetic = 1

/obj/item/reagent_containers/borghypo/hound
	name = "MediHound hypospray"
	desc = "An advanced chemical synthesizer and injection system utilizing carrier's reserves, designed for heavy-duty medical equipment."
	var/datum/matter_synth/water = null

// More chems for Medihound
TYPE_TABLE(/obj/item/reagent_containers/borghypo/hound, borghypo_reagent_ids, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_TRICORDRAZINE, REAGENT_ID_DEXALIN, REAGENT_ID_BICARIDINE, REAGENT_ID_KELOTANE, REAGENT_ID_ANTITOXIN, REAGENT_ID_SPACEACILLIN, REAGENT_ID_TRAMADOL, REAGENT_ID_ADRANOL))

/obj/item/reagent_containers/borghypo/hound/lost
	name = "Hound hypospray"
	desc = "An advanced chemical synthesizer and injection system utilizing carrier's reserves."

TYPE_TABLE(/obj/item/reagent_containers/borghypo/hound/lost, borghypo_reagent_ids, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_INAPROVALINE, REAGENT_ID_BICARIDINE, REAGENT_ID_DEXALIN, REAGENT_ID_ANTITOXIN, REAGENT_ID_TRAMADOL, REAGENT_ID_SPACEACILLIN))

/obj/item/reagent_containers/borghypo/hound/trauma
	name = "Hound hypospray"
	desc = "An advanced chemical synthesizer and injection system utilizing carrier's reserves."

TYPE_TABLE(/obj/item/reagent_containers/borghypo/hound/trauma, borghypo_reagent_ids, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_INAPROVALINE, REAGENT_ID_OXYCODONE, REAGENT_ID_DEXALIN ,REAGENT_ID_SPACEACILLIN))

//Tongue stuff
/obj/item/robot_tongue
	name = "synthetic tongue"
	desc = "Useful for slurping mess off the floor before affectionately licking the crew members in the face."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "synthtongue"
	hitsound = SFX_EFFECTS_ATTACKBLOB
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
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	// a lick of anything but a person is five seconds of standing still; a person's face is instant (afterattack)
	op("tongue_drink_sink", at_target(/obj/structure/sink), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_thirsty), silent = TRUE)), starts(PROC_REF(tongue_started)), begins(MSG(tongue/drink)), wait(5 SECONDS), then(PROC_REF(tongue_drank)))
	op("tongue_drink_toilet", at_target(/obj/structure/toilet), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_thirsty), because = MSG(tongue/full))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/drink)), wait(5 SECONDS), then(PROC_REF(tongue_drank)))
	op("tongue_lick_up", at_target(/obj/effect/decal/cleanable), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet), because = MSG(tongue/dry))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/lick_up)), wait(5 SECONDS), then(PROC_REF(tongue_licked_up)))
	op("tongue_eat_trash", at_target(/obj/item/trash), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet), because = MSG(tongue/dry))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/nibble)), wait(5 SECONDS), then(PROC_REF(tongue_ate_trash)))
	op("tongue_eat_food", at_target(/obj/item/reagent_containers/food), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet), because = MSG(tongue/dry))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/nibble)), wait(5 SECONDS), then(PROC_REF(tongue_ate_food)))
	op("tongue_eat_cell", at_target(/obj/item/cell), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet), because = MSG(tongue/dry))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/cram)), wait(5 SECONDS), then(PROC_REF(tongue_ate_cell)))
	op("tongue_clean_item", at_target(/obj/item), priority(OP_PRIORITY_NORMAL), answers(INTENT_USE, INTENT_ATTACK), needs(req(PROC_REF(tongue_wet), because = MSG(tongue/dry))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/lick_clean)), wait(5 SECONDS), then(PROC_REF(tongue_cleaned_item)))
	op("tongue_clean_other", at_target(), priority(OP_PRIORITY_DEFAULT), answers(INTENT_USE, INTENT_ATTACK), when(PROC_REF(not_a_person)), needs(req(PROC_REF(tongue_wet), because = MSG(tongue/dry))), starts(PROC_REF(tongue_started)), begins(MSG(tongue/lick_clean)), wait(5 SECONDS), then(PROC_REF(tongue_cleaned_other)))

/// Old attack_self.
/obj/item/robot_tongue/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = user
	if(R.emagged || R.emag_items)
		emagged = !emagged
		if(emagged)
			name = "hacked tongue of doom"
			desc = "Your tongue has been upgraded successfully. Congratulations."
			icon = 'icons/mob/dogborg_vr.dmi'
			icon_state = "syndietongue"
		else
			name = "synthetic tongue"
			desc = "Useful for slurping mess off the floor before affectionately licking the crew members in the face."
			icon = 'icons/mob/dogborg_vr.dmi'
			icon_state = "synthtongue"
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
	return read_once(water.energy >= 5)

/// A sink is lapped from while the reserve has room.
/obj/item/robot_tongue/proc/tongue_thirsty(datum/act/op/A)
	return read_once(water.energy < water.max_energy)

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

/obj/item/pupscrubber
	name = "floor scrubber"
	desc = "Toggles floor scrubbing."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "scrub0"
	var/enabled = FALSE
	flags = NOBLUDGEON

CAPABILITIES(/obj/item/pupscrubber)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/pupscrubber/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = user
	if(!enabled)
		R.scrubbing = TRUE
		enabled = TRUE
		icon_state = "scrub1"
	else
		R.scrubbing = FALSE
		enabled = FALSE
		icon_state = "scrub0"
	return TRUE

/obj/item/lightreplacer/dogborg
	name = "light replacer"
	desc = "A device to automatically replace lights. This version is capable to produce a few replacements using your internal matter reserves."
	max_uses = 16
	uses = 10
	var/datum/matter_synth/glass = null
	special_handling = TRUE

/// Using it in the hand asks what to do: check the reserves (and fabricate a light from them), or change the colour of the lights it makes.
CAPABILITIES(/obj/item/lightreplacer/dogborg)
	op("choose", in_hand(), label("Reserves or colour"), priority(above("colour")),
		asks(/datum/prompt/choice, fields = list("question" = "Do you wish to check the reserves or change the color?", "title" = "Selection List", "choices" = list("Reserves", "Color"), "buttons" = TRUE)),
		then(PROC_REF(dogborg_chosen)))
	op("pick_colour", ai(), wait(0), asks(/datum/prompt/color, fields = list("question" = "Choose a color to set the light to! (Default is [LIGHT_COLOR_INCANDESCENT_TUBE])", "default" = nameof(selected_color))), then(PROC_REF(colour_asked)))
	op("fabricate", ai(), needs(req(PROC_REF(has_room), because = MSG(lightreplacer/full))), wait(5 SECONDS), then(PROC_REF(fabricated)))

/obj/item/lightreplacer/dogborg/proc/has_reserves()
	return glass && glass.energy >= 125

/// "Color" opens the picker (the replacer's colour step), "Reserves" gives (the count, then a light fabricated from the matter reserves while the borg stands still).
/obj/item/lightreplacer/dogborg/proc/dogborg_chosen(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/choice/picked = A.answer
	if(picked?.value == "Color")
		perform_op(user, src, "pick_colour", null, ORIGIN_AI, AUTH_AI)
		return OP_OK
	if(uses >= max_uses)
		to_chat(user, span_warning("[src.name] is full."))
		return OP_OK
	if(!has_reserves())
		to_chat(user, span_warning("Insufficient material reserves."))
		return OP_OK
	to_chat(user, span_filter_notice("It has [uses] lights remaining. Attempting to fabricate a replacement. Please stand still."))
	perform_op(user, src, "fabricate", null, ORIGIN_AI, AUTH_AI)
	return OP_OK

/obj/item/lightreplacer/dogborg/proc/fabricated(datum/act/op/A)
	if(!has_reserves())
		to_chat(A.actor, span_warning("Insufficient material reserves."))
		return OP_REFUSED
	glass.use_charge(125)
	add_uses(1)
	return OP_OK

/obj/item/dogborg/stasis_clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"
	var/max_clamps = 3
	var/list/clamps

/obj/item/dogborg/stasis_clamp/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return

	// /obj/machinery/clamp was a ZAS pipe-clamp tool (clamp.dm in atmoalter),
	// deleted with ZAS atmos machinery. Stasis-clamp tool reduced to a polite
	// no-op until LINDA's atmos machinery is wired in.
	if (istype(A, /obj/machinery/atmospherics/pipe))
		to_chat(user, span_warning("Pipe clamping is unavailable until LINDA's atmos machinery is wired in."))
		return

//Pounce stuff for K-9
/obj/item/dogborg/pounce
	name = "pounce"
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "pounce"
	desc = "Leap at your target to momentarily stun them."
	force = 0
	throwforce = 0
	var/bluespace = FALSE
	flags = NOBLUDGEON

CAPABILITIES(/obj/item/dogborg/pounce)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/dogborg/pounce/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/R = user
	R.leap(bluespace)
	return TRUE

/mob/living/silicon/robot/proc/leap(bluespace = FALSE)
	if(!COOLDOWN_FINISHED(src, last_special))
		to_chat(src, span_filter_notice("Your leap actuators are still recharging."))
		return

	var/minimum_power = bluespace ? 2500 : 1000
	if(!cell || cell.charge < minimum_power)
		to_chat(src, span_filter_notice("Cell charge too low to continue."))
		return

	if(src.incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, span_filter_notice("You cannot leap in your current state."))
		return

	var/list/choices = list()
	var/leap_distance = bluespace ? 5 : 3
	for(var/mob/living/M in view(leap_distance,src))
		if(!istype(M,/mob/living/silicon))
			choices += M
	choices -= src

	open_request(src, /datum/prompt/choice/robot_leap, PROC_REF(leap_target_chosen), answerer = src, ask_flags = ASK_CONSCIOUS, title = "Target Choice", question = "Who do you wish to leap at?", choices = choices, bluespace = bluespace, timeout = 0)

/// A borg's leap target. `bluespace`: the longer, costlier bluespace leap.
/datum/prompt/choice/robot_leap
	var/bluespace = FALSE

/mob/living/silicon/robot/proc/leap_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/robot_leap/leap_question = A.request
	var/mob/living/T = A.answer.value
	if(QDELETED(T))
		return
	var/bluespace = leap_question.bluespace
	var/power_cost = bluespace ? 1000 : 750
	var/minimum_power = bluespace ? 2500 : 1000
	var/leap_distance = bluespace ? 5 : 3

	if(get_dist(get_turf(T), get_turf(src)) > leap_distance) return

	if(isliving(T))
		var/mob/living/M = T
		var/datum/shadekin/SK = M.get_shadekin_state()
		if(SK && SK.in_phase)
			power_cost *= 2

	if(!draw_power(ROBOT_CELL_JOULES(power_cost), src, ROBOT_CELL_JOULES(minimum_power - power_cost)))
		to_chat(src, span_warning("Warning, low power detected. Aborting action."))
		return

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(src.incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, span_filter_notice("You cannot leap in your current state."))
		return

	COOLDOWN_START(src, last_special, 1 SECOND)
	set_status_flags(status_flags | LEAPING)
	pixel_y = pixel_y + 10

	act_message(src, T, others = span_danger("%U% leaps at %T%!"))
	/* // disable for now
	if(bluespace)
		src.forceMove(get_turf(T))
		T.hitby(src)
	else
		src.throw_at(get_step(get_turf(T),get_turf(src)), 4, 1, src)
	*/
	src.throw_at(get_step(get_turf(T),get_turf(src)), 4, 1, src) // no bluespace pounce
	play_sfx(src, SFX_MECHA_MECHSTEP2)
	pixel_y = default_pixel_y

	if(!bluespace)
		after(src, 0.5 SECONDS, PROC_REF(leap_land), with = list(T), keeps_dead = TRUE)
		return
	leap_land(T)

/mob/living/silicon/robot/proc/leap_land(mob/living/T)
	if(status_flags & LEAPING) set_status_flags(status_flags & ~LEAPING)

	if(!T || !src.Adjacent(T))
		to_chat(src, span_warning("You miss!"))
		return

	if(ishuman(T))
		var/mob/living/carbon/human/H = T
		if(H.species.lightweight == 1)
			H.status_at_least(STAT_STUNNED, 3) // Crawling made this useless. Changing to stun instead.
			H.drop_both_hands() //Stuns no longer drop items, so were forcing it >:3
			return

	var/armor_block = T.armor_against(INJURY_PAIN)
	T.injure(INJURY_PAIN, 20, null, src, flags = INJURE_ARMORED)
	if(prob(75)) //75% chance to stun for 5 seconds, really only going to be 4 bcus click cooldown+animation.
		T.apply_effect(5, STUN, armor_block)
		T.drop_both_hands() // Stuns no longer drop items

/obj/item/reagent_containers/glass/beaker/large/borg
	var/mob/living/silicon/robot/R
	var/last_robot_loc

/obj/item/reagent_containers/glass/beaker/large/borg/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(R), loc.loc)
	observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(check_loc)))

/obj/item/reagent_containers/glass/beaker/large/borg/proc/check_loc(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/movable_attempted_move/event = A
	var/atom/old_loc = event.old_loc
	if(old_loc == R || old_loc == R.module)
		last_robot_loc = old_loc
	if(!istype(loc, /obj/machinery) && loc != R && loc != R.module)
		if(last_robot_loc)
			forceMove(last_robot_loc)
			last_robot_loc = null
		else
			forceMove(R)
		if(loc == R)
			hud_layerise()

/obj/item/mining_scanner/robot
	name = "integrated deep scan device"

/obj/item/mining_scanner/robot/proc/upgrade(mob/user)
	desc = "An advanced device used to locate ore deep underground."
	set_scan_time(0.5 SECONDS)
	set_exact(TRUE)

CAPABILITIES(/obj/item/mining_scanner/robot)
	op("set_range", hand(), gesture(GESTURE_ALT), label("Set Scanner Range"), when(nameof(exact)), needs(carried()),
		asks(/datum/prompt/choice, keeps = 0, fields = list("timeout" = 0, "question" = "Scanner Range", "title" = "Pick a range to scan. ", "choices" = list(0,1,2,3,4,5,6,7))), then(PROC_REF(range_picked)))

/obj/item/mining_scanner/robot/proc/range_picked(datum/act/op/A)
	var/datum/prompt/choice/picked = A.answer
	// Unlike the advanced handheld, the integrated scanner accepts zero.
	set_range(picked.value)
	to_chat(A.actor, span_notice("Scanner will now look up to [range] tile(s) away."))
	return OP_OK


/obj/item/robot_tongue/examine(user)
	. = ..()
	if(Adjacent(user))
		if(water.energy)
			. += span_notice("[src] is wet. Just like it should be.")
		if(water.energy < 5)
			. += span_notice("[src] is dry.")


// Matter synths belong to the robot module (the owned "synths" list); tools draw on them.
