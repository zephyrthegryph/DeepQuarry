REGISTRY_MEMBERSHIP(/turf/simulated/floor/water/digestive_enzymes/nanites, REGISTRY_NANITE_TURFS)

//half of this code is ripped from digestive enzymes themselves, with runtimes and such trimmed
/turf/simulated/floor/water/digestive_enzymes/nanites //i just wanted to map, why has it come to making such terrible crimes against humanity
	name = "nanite-infested tiles."
	desc = "This section of reinforced plating appears to host a colony of nanites between the tiles"
	icon = 'icons/turf/nanitegoo.dmi'
	icon_state = "composite"
	water_icon = 'icons/turf/nanitegoo.dmi'
	water_state = "goo_inactive"
	under_state = "reinforced"
	depth = 0
	movement_cost = 0
	mobstuff = FALSE
	footstep = FOOTSTEP_PLATING
	barefootstep = FOOTSTEP_HARD_BAREFOOT
	clawfootstep = FOOTSTEP_HARD_CLAW
	watercolor = "black"
	reagent_type = REAGENT_ID_LIQUIDPROTEAN
	oxygen		= MOLES_O2STANDARD
	nitrogen	= MOLES_N2STANDARD
	initial_temperature = T20C
	var/digesting = FALSE
	var/digest_synth = FALSE
	var/digest_robot = FALSE
	var/active = FALSE
	var/usesmes = TRUE
	/// The mob fed by the nanites: a relation view.
	var/mob/living/moblink
	var/obj/machinery/power/smes/linkedsmes //when the nanites digest something, it becomes power in an SMES (a relation view)
	var/id = null

/turf/simulated/floor/water/digestive_enzymes/nanites/Initialize(mapload)
	. = ..()
	for(var/obj/machinery/power/smes/tolink in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(!tolink)
			continue
		if(!get_area(tolink))
			continue
		if(get_area(tolink) == get_area(src))
			rel_set(src, nameof(linkedsmes), tolink)

CAPABILITIES(/turf/simulated/floor/water/digestive_enzymes/nanites)
	ref_one(nameof(moblink), /mob/living)
	ref_one(nameof(linkedsmes), /obj/machinery/power/smes)
	op("nanites_hand", hand(), ungated(), label("Interface"), when(req(PROC_REF(hand_interface_ok))), asks(/datum/prompt/choice/nanite_state, fields = list("ask_flags" = ASK_NEAR_SUBJECT | ASK_CAPABLE), step = "state"), asks(/datum/prompt/choice/nanite_targets, fields = list("ask_flags" = ASK_NEAR_SUBJECT | ASK_CAPABLE), step = "targets", when = PROC_REF(state_is_on)), then(PROC_REF(nanites_hand_chosen)))
	op("nanites_ai", remote(), label("Interface"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), when(req(PROC_REF(ai_interface_ok))), asks(/datum/prompt/choice/nanite_state, fields = list("from_ai" = TRUE), step = "state"), asks(/datum/prompt/choice/nanite_targets, fields = list("from_ai" = TRUE), step = "targets", when = PROC_REF(state_is_on)), then(PROC_REF(nanites_ai_chosen)))

/// Old attack_hand: a protean (a human with a NIF) may interface with the pool while nobody else holds it.
/turf/simulated/floor/water/digestive_enzymes/nanites/proc/hand_interface_ok(datum/act/op/A)
	return read_once(hand_interface_open(A.actor)) // who holds the goop and who stands where is asked when the click is made

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/hand_interface_open(mob/living/user)
	var/mob/living/nutrienttarget = moblink
	var/obj/machinery/power/smes/smes = linkedsmes
	if(target_present() && (user != nutrienttarget))//prioritize this here, so mobs can turn the turf off
		return FALSE
	if(!ishuman(user))
		return FALSE
	if(smes || istype(nutrienttarget, /mob/living/silicon/ai)) // the goop's holder, not who asks
		return FALSE
	var/mob/living/carbon/human/checker = user
	return !!checker.nif //Proteans have NIFS

/// Old attack_ai. Cyborgs (shells included) never reached it: turfs send their Use to
/// attack_hand (ROBOT_USE_HAND), so they fall through to the hand op.
/turf/simulated/floor/water/digestive_enzymes/nanites/proc/ai_interface_ok(datum/act/op/A)
	return read_once(ai_interface_open(A.actor)) // who holds the goop and who stands near it is asked when the click is made

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/ai_interface_open(mob/user)
	var/mob/living/nutrienttarget = moblink
	if(target_present())
		if(istype(nutrienttarget, /mob/living/silicon/ai) && user != nutrienttarget)//first come first serve, for AI
			if(!locate_in_list(range(1, src), user))// AI can always control adjacent nanite tiles
				return FALSE
	return TRUE

/// The second question is asked only when the first answer was On.
/turf/simulated/floor/water/digestive_enzymes/nanites/proc/state_is_on(datum/act/op/A)
	return A.step_value("state") == "On"

/// Interfacing with nanite goop: on or off, then (on) what it recycles. A person must stay next
/// to it (ask_flags set at the call); an AI answers from anywhere (`from_ai`).
/datum/prompt/choice/nanite_state
	title = "Desired state"
	timeout = 0
	choices = list("On", "Off")
	var/from_ai = FALSE

/datum/prompt/choice/nanite_state/prepare(datum/act/A)
	. = ..()
	question = "Do you wish interface with \the [subject]"

/datum/prompt/choice/nanite_targets
	title = "Desired targets"
	timeout = 0
	choices = list("None", "All", "Organics and Cyborgs", "Organics and Synthetics", "Only Organics")
	var/from_ai = FALSE

/datum/prompt/choice/nanite_targets/prepare(datum/act/A)
	. = ..()
	question = "Which entities do you wish for \the [subject] to recycle?"

/datum/prompt/choice/nanite_state/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(answerer) ? "gone" : null

/datum/prompt/choice/nanite_targets/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(answerer) ? "gone" : null

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/nanites_hand_chosen(datum/act/op/A)
	check_target() // a goop whose holder is gone turns itself off before it is taken over
	nanite_interface_chosen(A.actor, A.step_value("state"), A.step_value("targets"))
	return OP_OK

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/nanites_ai_chosen(datum/act/op/A)
	check_target()
	nanite_ai_interface_chosen(A.actor, A.step_value("state"), A.step_value("targets"))
	return OP_OK

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/nanite_interface_chosen(mob/living/carbon/human/checker, state, targets)
	switch(state)
		if("On")
			if(!targets)
				return
			if(HAS_SYNTHETIC_BIOLOGY(checker))
				to_chat(checker, span_warning("With you in control, \the [src] will not attempt to recycle your body, no matter the setting you pick"))
			else
				to_chat(checker, span_warning("You realize there is no way for the simplistic [src] to ignore your form, if you set it to recycle."))
			act_message(checker, src, MSG_SELF(span_warning("You begin to interface with %T%.")), MSG_OTHERS(span_warning("%U% inspects %T%")))
			task_timed(checker, 3 SECONDS, src, src, PROC_REF(interface_on), list(checker, targets))
		if("Off")
			if(active)
				act_message(checker, src, MSG_SELF(span_warning("You begin to interface with %T%.")), MSG_OTHERS(span_warning("%U% inspects %T%")))
				task_timed(checker, 3 SECONDS, src, src, PROC_REF(toggle_all), list(FALSE))

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/interface_on(mob/user, choice2)
	rel_set(src, nameof(moblink), user)
	switch(choice2)
		if("None")
			rel_set(src, nameof(moblink), user)
			toggle_all(TRUE)
		if("All")
			rel_set(src, nameof(moblink), user)
			toggle_all(TRUE, TRUE, TRUE, TRUE)
		if("Organics and Cyborgs")
			rel_set(src, nameof(moblink), user)
			toggle_all(TRUE, TRUE, TRUE)
		if("Organics and Synthetics")
			rel_set(src, nameof(moblink), user)
			toggle_all(TRUE, TRUE, FALSE, TRUE)
		if("Only Organics")
			rel_set(src, nameof(moblink), user)
			toggle_all(TRUE, TRUE)

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/nanite_ai_interface_chosen(mob/user, state, choice2)
	switch(state)
		if("On")
			if(!choice2)
				return
			to_chat(user, span_warning("With you in control, \the [src] will not attempt to recycle your body, no matter the setting you pick"))
			switch(choice2)
				if("None")
					rel_set(src, nameof(moblink), user)
					toggle_all(TRUE)
				if("All")
					rel_set(src, nameof(moblink), user)
					toggle_all(TRUE, TRUE, TRUE, TRUE)
				if("Organics and Cyborgs")
					rel_set(src, nameof(moblink), user)
					toggle_all(TRUE, TRUE, TRUE)
				if("Organics and Synthetics")
					rel_set(src, nameof(moblink), user)
					toggle_all(TRUE, TRUE, FALSE, TRUE)
				if("Only Organics")
					rel_set(src, nameof(moblink), user)
					toggle_all(TRUE, TRUE)

		if("Off")
			if(active)
				toggle_all(FALSE)

/turf/simulated/floor/water/digestive_enzymes/nanites/can_digest(atom/movable/AM) //copypasting the entire proc because we use an SMES instead of a linked mob
	. = FALSE
	var/mob/living/nutrienttarget = moblink
	if(!active)
		return FALSE
	if(!check_target())
		return FALSE
	if(!digesting)
		return FALSE
	if(AM.loc != src)
		return FALSE
	if(isitem(AM))
		var/obj/item/targetitem = AM
		if(targetitem.unacidable || targetitem.throwing || targetitem.is_incorporeal() || !targetitem)
			return FALSE
		var/food = FALSE
		if(istype(targetitem,/obj/item/reagent_containers/food))
			food = TRUE
		if(prob(95))	//Give people a chance to pick them up
			return TRUE
		targetitem.visible_message(span_warning("\The [targetitem] sizzles..."))
		var/yum = targetitem.digest_act()	//Glorp
		if(istype(targetitem , /obj/item/card))
			yum = 0		//No, IDs do not have infinite nutrition, thank you
		if(yum)
			if(food)
				yum += 50
			give_nutrients(yum)
		return TRUE
	if(isliving(AM))
		var/mob/living/targetmob = AM
		if(targetmob.unacidable || !targetmob.digestable || targetmob?.buckled_to() || dq_get_hovering(targetmob) || targetmob.throwing || targetmob.is_incorporeal())
			return FALSE
		if(isrobot(targetmob))
			if(!digest_robot)
				return FALSE
			if(targetmob == nutrienttarget)
				return FALSE
		if(ishuman(targetmob))
			var/mob/living/carbon/human/targethuman = targetmob
			if(HAS_SYNTHETIC_BIOLOGY(targethuman))
				if(!digest_synth)
					return FALSE
				if(targetmob == nutrienttarget)
					return FALSE
			if(!targethuman.pl_suit_protected())
				return TRUE
			if(targethuman.resting && !targethuman.pl_head_protected())
				return TRUE
		return TRUE

/// The one who holds the goop while still in the area (or an AI on its SMES), or FALSE. Pure: the requirements ask it.
/turf/simulated/floor/water/digestive_enzymes/nanites/proc/target_present()
	READS_FROM() // where the owner and the goop stand now
	var/mob/living/nutrienttarget = moblink
	var/obj/machinery/power/smes/smes = linkedsmes
	if(nutrienttarget)
		if(nutrienttarget.client && !nutrienttarget.stat)
			if(smes && isAI(nutrienttarget))
				return nutrienttarget
			if(get_area(nutrienttarget))
				if(get_area(nutrienttarget) == get_area(src))
					return nutrienttarget
	return FALSE

/// target_present(); a goop whose holder is gone turns itself off.
/turf/simulated/floor/water/digestive_enzymes/nanites/proc/check_target()//check if the target is in the area, or if this is a
	. = target_present()
	if(!.)
		toggle_all(FALSE)

/turf/simulated/floor/water/digestive_enzymes/nanites/digest_stuff(atom/movable/AM)	//copypasting the entire proc because we use an SMES instead of a linked mob
	. = FALSE

	var/damage = 2
	var/list/stuff = list()
	var/nutrients = 0
	for(var/thing in contents_of(src))
		if(can_digest(thing))
			stuff |= thing
	if(!stuff.len)
		return FALSE
	var/thing = pick(stuff)	//We only think about one thing at a time, otherwise things get wacky
	. = TRUE
	if(iscarbon(thing))
		var/mob/living/carbon/targetcarbon = thing
		if(!targetcarbon)
			return
		if(targetcarbon.stat == DEAD)
			targetcarbon.unacidable = TRUE	//Don't touch this one again, we're gonna delete it in a second
			targetcarbon.release_vore_contents()
			for(var/obj/item/targetitem in targetcarbon)
				if(istype(targetitem, /obj/item/organ/internal/mmi_holder/posibrain))
					var/obj/item/organ/internal/mmi_holder/MMI = targetitem
					MMI.removed()
				if(istype(targetitem, /obj/item/organ))
					targetitem.unacidable = TRUE
					continue
				if(istype(targetitem, /obj/item/implant/backup) || istype(targetitem, /obj/item/nif))
					continue
				targetcarbon.drop_from_inventory(targetitem)
			var/how_much = targetcarbon.mob_size + targetcarbon.nutrition
			if(!targetcarbon.ckey)
				how_much = how_much / 10	//Braindead mobs are worth less
			nutrients += how_much
			targetcarbon.mind?.vore_death = TRUE
			GLOB.prey_digested_roundstat++
			targetcarbon.ghostize() //prevent runtimes
			dissolved(targetcarbon, src)	//glorp
			return
		targetcarbon.injure(INJURY_DIGESTION, damage, null, src)
		var/how_much = (damage * targetcarbon.size_multiplier) * targetcarbon.get_digestion_nutrition_modifier()
		if(!targetcarbon.ckey)
			how_much = how_much / 10	//Braindead mobs are worth less
		nutrients += how_much
		if(targetcarbon.bloodstr.get_reagent_amount(REAGENT_ID_NUMBENZYME) < 2) //best play it safe with digestion pain
			targetcarbon.bloodstr.add_reagent(REAGENT_ID_NUMBENZYME,4)
		nutrients += how_much
	else if (isliving(thing))
		var/mob/living/targetmob = thing
		if(!targetmob)
			return
		if(targetmob.stat == DEAD)
			targetmob.unacidable = TRUE	//Don't touch this one again, we're gonna delete it in a second
			targetmob.release_vore_contents()
			var/how_much = targetmob.mob_size + targetmob.nutrition
			if(!targetmob.ckey)
				how_much = how_much / 10	//Braindead mobs are worth less
			nutrients += how_much
			dissolved(targetmob, src) //gloop
			return
		targetmob.injure(INJURY_DIGESTION, damage, null, src)
		var/how_much = (damage * targetmob.size_multiplier) * targetmob.get_digestion_nutrition_modifier()
		if(!targetmob.ckey)
			how_much = how_much / 10	//Braindead mobs are worth less
		nutrients += how_much
	give_nutrients(nutrients)

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/give_nutrients(amt)
	var/mob/living/nutrienttarget = moblink
	var/obj/machinery/power/smes/smes = linkedsmes
	if(smes)
		smes.adjust_stored_charge(amt * 20)
		return
	if(nutrienttarget)
		if(ishuman(nutrienttarget))
			var/mob/living/carbon/human/targetcarbon = nutrienttarget
			if(HAS_SYNTHETIC_BIOLOGY(targetcarbon))
				targetcarbon.set_nutrition(targetcarbon.nutrition+(10 * amt * (1-min(targetcarbon.species.synthetic_food_coeff, 0.9))))
				return
	if(isrobot(nutrienttarget))
		var/mob/living/silicon/robot/targetrobot = nutrienttarget
		targetrobot.add_power(ROBOT_CELL_JOULES(amt * 20), src)
		return

/turf/simulated/floor/water/digestive_enzymes/nanites/return_air_for_internal_lifeform(mob/living/targetmob)
	if(!can_digest(targetmob))
		return return_air() //Nanites should always be nonlethal until the AI turns on digestion
	return ..()

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/toggle_all(on = TRUE, digest = FALSE, robot = FALSE, synth = FALSE)
	var/mob/living/nutrienttarget = moblink
	for(var/turf/simulated/floor/water/digestive_enzymes/nanites/nanites in REGISTRY_MEMBERS(REGISTRY_NANITE_TURFS))
		if(nanites.id == id)
			rel_clear(nanites, nameof(nanites.moblink))
			if(on)
				rel_set(nanites, nameof(nanites.moblink), nutrienttarget)
			nanites.select_state(on, digest, robot, synth)

/turf/simulated/floor/water/digestive_enzymes/nanites/proc/select_state(on = TRUE, digest = FALSE, robot = FALSE, synth = FALSE)
	if(!on)
		name = "nanite-infested tiles."
		desc = "This section of reinforced plating appears to host a colony of nanites between the tiles"
		depth = 0
		movement_cost = 0
		footstep = FOOTSTEP_PLATING
		barefootstep = FOOTSTEP_HARD_BAREFOOT
		clawfootstep = FOOTSTEP_HARD_CLAW
		set_water_state("goo_inactive")
		digesting = FALSE
		digest_synth = FALSE
		digest_robot = FALSE
		active = FALSE
		for(var/obj/structure/railing/overhang/hazard/nanite/R in turf_contents_of_type(src, /obj/structure/railing/overhang/hazard/nanite))
			R.set_icon_modifier("inactive_")
		for(var/obj/structure/dummystairs/hazardledge/stairs in turf_contents_of_type(src, /obj/structure/dummystairs/hazardledge))
			stairs.icon_state = "stair_hazard"
		return
	name = "nanite goop."
	desc = "A deep pool of pulsating, possibly deadly nanite goop."
	depth = 2
	movement_cost = 16 //twice as difficult as deep water to navigate
	footstep = FOOTSTEP_WATER
	barefootstep = FOOTSTEP_WATER
	clawfootstep = FOOTSTEP_WATER
	set_water_state("goo_active")
	digesting = digest
	digest_synth = synth
	digest_robot = robot
	active = TRUE
	for(var/obj/structure/railing/overhang/hazard/nanite/R in turf_contents_of_type(src, /obj/structure/railing/overhang/hazard/nanite))
		R.set_icon_modifier("active_")
	for(var/obj/structure/dummystairs/hazardledge/stairs in turf_contents_of_type(src, /obj/structure/dummystairs/hazardledge))
		depth = 1
		movement_cost = 8
		stairs.icon_state = "stair_hazard_nanite"
	for(var/atom/AM in turf_contents_of_type(src, /atom))
		Entered(AM)

