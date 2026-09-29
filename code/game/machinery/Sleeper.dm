/obj/machinery/sleep_console
	name = "sleeper console"
	desc = "A control panel to operate a linked sleeper with."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeperconsole"
	var/obj/machinery/sleeper/sleeper
	anchored = TRUE //About time someone fixed this.
	density = TRUE
	unacidable = TRUE
	dir = 8
	use_power = USE_POWER_IDLE
	idle_power_usage = 40
	interact_offline = 1
	circuit = /obj/item/circuitboard/sleeper_console
	clicksound = SFX_MACHINES_BUTTONBEEP
	clickvol = 30

/obj/machinery/sleep_console/Initialize(mapload)
	findsleeper()
	return ..()

DECLARE_REF(/obj/machinery/sleep_console, "sleeper", PAIR, "console")

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3): the
/// sleeper's own field is the occupant's environment, same as before the
/// ledger tracked the move.
/datum/om/relation/slot/occupant/sleeper
	holder = /obj/machinery/sleeper
	slot_id = OCCUPANT_SLOT_SLEEPER
	name = "sleeper"
	// No view fields (OM relations step 3): `occupant` is still an ordinary
	// var every reader here uses, but this slot's own on_link()/on_unlink()
	// are its only writer now -- there is no generic field-link mechanism
	// left to do it for them.

/obj/machinery/sleep_console/proc/findsleeper()
	var/obj/machinery/sleeper/sleepernew = null
	for(var/direction in GLOB.cardinal) // Loop through every direction
		sleepernew = locate(/obj/machinery/sleeper, get_step(src, direction)) // Try to find a scanner in that direction
		if(sleepernew)
			sleeper = sleepernew
			sleepernew.console = src
			break


EXTEND_INTERACTIONS(/obj/machinery/sleep_console, \
	INTERACT_HAND(null, PROC_REF(sleep_console_interaction_hand), REQ_BECAUSE(REQ_PANEL(FALSE), "close the maintenance panel first")), \
	INTERACT_ITEM(null, TYPE_PROC_REF(/atom, interaction_as_touch)), \
)

/// Old attack_hand.
/obj/machinery/sleep_console/proc/sleep_console_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!sleeper)
		findsleeper()
		if(!sleeper)
			to_chat(user, span_notice("Sleeper not found!"))
			return TRUE

	if(sleeper)
		tgui_interact(user)
	return TRUE

/obj/machinery/sleep_console/screwdriver_act(mob/user, obj/item/tool)
	return deconstruct_display(user, tool)

/obj/machinery/sleep_console/power_change()
	. = ..()
	if(!operable())
		icon_state = "sleeperconsole-p"
	else
		icon_state = initial(icon_state)

/obj/machinery/sleep_console/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Sleeper", "Sleeper")
		ui.open()

/obj/machinery/sleep_console/tgui_data(mob/user)
	if(sleeper)
		return sleeper.tgui_data(user)
	return null

/obj/machinery/sleep_console/tgui_act(action, params, datum/tgui/ui, datum/tgui_state/state)
	if(sleeper)
		return sleeper.tgui_act(action, params, ui, state)
	return ..()

/obj/machinery/sleeper
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "sleeper"
	desc = "A stasis pod with built-in injectors, a dialysis machine, and a limited health scanner."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeper_0"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	flags = REMOTEVIEW_ON_ENTER
	circuit = /obj/item/circuitboard/sleeper
	var/list/available_chemicals
	var/static/list/base_chemicals = list(REAGENT_ID_INAPROVALINE = REAGENT_INAPROVALINE, REAGENT_ID_PARACETAMOL = REAGENT_PARACETAMOL, REAGENT_ID_ANTITOXIN = REAGENT_ANTITOXIN, REAGENT_ID_DEXALIN = REAGENT_DEXALIN)
	var/amounts = list(5, 10)
	var/obj/item/reagent_containers/glass/beaker = null
	var/filtering = 0
	var/pumping = 0
	// Currently never changes. On Paradise, max_chem is based on the matter bins in the sleeper.
	var/max_chem = 20
	var/initial_bin_rating = 1
	var/obj/machinery/sleep_console/console
	/// Stasis modifier (/datum/body_effect/stasis/*) applied to the occupant, or null for none.
	var/stasis_level = null
	var/static/list/stasis_choices = list("Complete (1%)" = /datum/body_effect/stasis/complete, "Deep (10%)" = /datum/body_effect/stasis/deep, "Moderate (20%)" = /datum/body_effect/stasis/moderate, "Light (50%)" = /datum/body_effect/stasis/light, "None (100%)" = null)
	var/controls_inside = FALSE
	var/auto_eject_dead = FALSE

	use_power = USE_POWER_IDLE
	idle_power_usage = 15
	active_power_usage = 200 //builtin health analyzer, dialysis machine, injectors.

DECLARE_DEFAULT_CHILD(/obj/machinery/sleeper, "beaker", /obj/item/reagent_containers/glass/beaker/large)

/obj/machinery/sleeper/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()

DECLARE_REF(/obj/machinery/sleeper, "console", PAIR, "sleeper")

/obj/machinery/sleeper/RefreshParts(limited = 0)
	var/man_rating = 0
	var/cap_rating = 0

	LAZYCLEARLIST(available_chemicals)
	available_chemicals = base_chemicals.Copy()

	for(var/obj/item/stock_parts/P in component_parts)
		if(istype(P, /obj/item/stock_parts/capacitor))
			cap_rating += P.rating

	cap_rating = max(1, round(cap_rating / 2))

	update_idle_power_usage(initial(idle_power_usage) / cap_rating)
	update_active_power_usage(initial(active_power_usage) / cap_rating)

	if(!limited)
		for(var/obj/item/stock_parts/P in component_parts)
			if(istype(P, /obj/item/stock_parts/manipulator))
				man_rating += P.rating - 1

		var/list/new_chemicals = list()

		if(man_rating >= 4) // Alien tech.
			var/reag_ID = pickweight(list(
				REAGENT_ID_HEALINGNANITES = 10,
				REAGENT_ID_SHREDDINGNANITES = 5,
				REAGENT_ID_IRRADIATEDNANITES = 5,
				REAGENT_ID_NEUROPHAGENANITES = 2)
				)
			new_chemicals[reag_ID] = "Nanite"
		if(man_rating >= 3) // Anomalous tech.
			new_chemicals[REAGENT_ID_IMMUNOSUPRIZINE] = REAGENT_IMMUNOSUPRIZINE
		if(man_rating >= 2) // Tier 3.
			new_chemicals[REAGENT_ID_SPACEACILLIN] = REAGENT_SPACEACILLIN
		if(man_rating >= 1) // Tier 2.
			new_chemicals[REAGENT_ID_LEPORAZINE] = REAGENT_LEPORAZINE

		if(new_chemicals.len)
			LAZYADD(available_chemicals, new_chemicals)
		return

EXTEND_INTERACTIONS(/obj/machinery/sleeper, \
	INTERACT_HAND_UNGATED(null, PROC_REF(sleeper_interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(sleeper_interaction_item)), \
	INTERACT_DRAG("Put inside", PROC_REF(sleeper_interaction_drag)), \
	INTERACT_VERB("Eject occupant", PROC_REF(sleeper_move_eject)), \
)

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/sleeper/proc/sleeper_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(controls_inside && user == occupant)
		tgui_interact(user)
	return TRUE

/obj/machinery/sleeper/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Sleeper", "Sleeper")
		ui.open()

/obj/machinery/sleeper/tgui_data(mob/user)
	var/mob/living/carbon/human/occupant = slot_item_real(OCCUPANT_SLOT_SLEEPER)
	var/data[0]
	data["amounts"] = amounts
	data["hasOccupant"] = occupant ? 1 : 0
	var/occupantData[0]
	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["critical"] = occupant.is_critical()
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		occupantData["diagnosis"] = D.report_data()
		qdel(D)
		occupantData["paralysis"] = occupant.status_units(EFFECT_PARALYZED)
		occupantData["hasBlood"] = 0
		occupantData["bodyTemperature"] = occupant.bodytemperature
		occupantData["maxTemp"] = 1000 // If you get a burning vox armalis into the sleeper, congratulations
		// Because we can put simple_animals in here, we need to do something tricky to get things working nice
		occupantData["temperatureSuitability"] = 0 // 0 is the baseline
		if(ishuman(occupant) && occupant.species)
			// I wanna do something where the bar gets bluer as the temperature gets lower
			// For now, I'll just use the standard format for the temperature status
			var/datum/species/sp = occupant.species
			if(occupant.bodytemperature < sp.cold_level_3)
				occupantData["temperatureSuitability"] = -3
			else if(occupant.bodytemperature < sp.cold_level_2)
				occupantData["temperatureSuitability"] = -2
			else if(occupant.bodytemperature < sp.cold_level_1)
				occupantData["temperatureSuitability"] = -1
			else if(occupant.bodytemperature > sp.heat_level_3)
				occupantData["temperatureSuitability"] = 3
			else if(occupant.bodytemperature > sp.heat_level_2)
				occupantData["temperatureSuitability"] = 2
			else if(occupant.bodytemperature > sp.heat_level_1)
				occupantData["temperatureSuitability"] = 1
		else if(isanimal(occupant))
			var/mob/living/simple_mob/silly = occupant
			if(silly.bodytemperature < silly.minbodytemp)
				occupantData["temperatureSuitability"] = -3
			else if(silly.bodytemperature > silly.maxbodytemp)
				occupantData["temperatureSuitability"] = 3
		// Blast you, imperial measurement system
		occupantData["btCelsius"] = occupant.bodytemperature - T0C
		occupantData["btFaren"] = ((occupant.bodytemperature - T0C) * (9.0/5.0))+ 32

		// I'm not sure WHY you'd want to put a simple_animal in a sleeper, but precedent is precedent
		// Runtime is aptly named, isn't she?
		if(ishuman(occupant) && !(NO_BLOOD in occupant.species.flags) && occupant.vessel)
			occupantData["pulse"] = occupant.get_pulse(GETPULSE_TOOL)
			occupantData["hasBlood"] = 1
			var/blood_volume = round(occupant.vessel.get_reagent_amount(REAGENT_ID_BLOOD))
			occupantData["bloodLevel"] = blood_volume
			occupantData["bloodMax"] = occupant.species.blood_volume
			occupantData["bloodPercent"] = round(100*(blood_volume/occupant.species.blood_volume), 0.01) //copy pasta ends here

			occupantData["bloodType"] = occupant.dna.b_type

	data["occupant"] = occupantData
	data["maxchem"] = max_chem
	data["dialysis"] = filtering
	data["stomachpumping"] = pumping
	data["auto_eject_dead"] = auto_eject_dead
	if(beaker)
		data["isBeakerLoaded"] = 1
		if(beaker.reagents)
			data["beakerMaxSpace"] = beaker.reagents.maximum_volume
			data["beakerFreeSpace"] = beaker.reagents.get_free_space()
		else
			data["beakerMaxSpace"] = 0
			data["beakerFreeSpace"] = 0
	else
		data["isBeakerLoaded"] = FALSE

	var/stasis_level_name = "Error!"
	for(var/N in stasis_choices)
		if(stasis_choices[N] == stasis_level)
			stasis_level_name = N
			break
	data["stasis"] = stasis_level_name

	var/chemicals[0]
	for(var/re in available_chemicals)
		var/datum/reagent/temp = chemistry_service().chemical_reagents[re]
		if(temp)
			var/reagent_amount = 0
			var/pretty_amount
			var/injectable = occupant ? 1 : 0
			var/overdosing = 0
			var/caution = 0 // To make things clear that you're coming close to an overdose

			if(occupant && occupant.reagents)
				reagent_amount = occupant.reagents.get_reagent_amount(temp.id)
				// If they're mashing the highest concentration, they get one warning
				if(temp.overdose && reagent_amount + 10 > (temp.overdose * occupant?.species.chemOD_threshold))
					caution = 1
				if(temp.overdose && reagent_amount > (temp.overdose * occupant?.species.chemOD_threshold))
					overdosing = 1

			pretty_amount = round(reagent_amount, 0.05)

			chemicals.Add(list(list("title" = temp.name, "id" = temp.id, "commands" = list("chemical" = temp.id), "occ_amount" = reagent_amount, "pretty_amount" = pretty_amount, "injectable" = injectable, "overdosing" = overdosing, "od_warning" = caution)))
	data["chemicals"] = chemicals
	return data

/obj/machinery/sleeper/tgui_act(action, params, datum/tgui/ui, datum/tgui_state/state)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(..())
		return TRUE
	if(!controls_inside && ui.user == occupant)
		return
	if(panel_open)
		to_chat(ui.user, span_notice("Close the maintenance panel first."))
		return

	. = TRUE
	switch(action)
		if("chemical")
			if(!occupant)
				return
			if(occupant.stat == DEAD)
				to_chat(ui.user, span_danger("This person has no life to preserve anymore. Take [occupant.p_them()] to a department capable of reanimating [occupant.p_them()]."))
				return
			var/chemical = params["chemid"]
			var/amount = text2num(params["amount"])
			if(!length(chemical) || amount <= 0)
				return
			if(occupant.vitality() > 0) //|| (chemical in emergency_chems))
				inject_chemical(ui.user, chemical, amount)
			else
				to_chat(ui.user, span_danger("This person is not in good enough condition for sleepers to be effective! Use another means of treatment, such as cryogenics!"))
		if("removebeaker")
			remove_beaker()
		if("togglefilter")
			toggle_filter()
		if("togglepump")
			toggle_pump()
		if("ejectify")
			go_out()
		if("changestasis")
			om_ask(ui.user, /datum/om/prompt/choice, PROC_REF(stasis_level_chosen), title = "Stasis Level", message = "Levels deeper than 50% stasis level will render the patient unconscious.", choices = stasis_choices, requires = PROMPT_USABLE)
		if("auto_eject_dead_on")
			auto_eject_dead = TRUE
		if("auto_eject_dead_off")
			auto_eject_dead = FALSE
		else
			return FALSE
	add_fingerprint(ui.user)

/datum/om/prompt/number/machine_ui
	requires = PROMPT_USABLE
	/// The setting being changed (the air alarm's environment and threshold).
	var/env
	var/setting

/obj/machinery/sleeper/proc/stasis_level_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/new_stasis = ask.choice
	var/mob/living/carbon/human/occupant = slot_item(OCCUPANT_SLOT_SLEEPER)
	if(new_stasis in stasis_choices)
		stasis_level = stasis_choices[new_stasis]
		log_game("STASIS: [key_name(user)] set [src] at [AREACOORD(src)] to [new_stasis] (occupant: [key_name(occupant)]).")

/obj/machinery/sleeper/machine_step()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(!operable())
		return PROCESS_KILL
	if(!occupant)
		return PROCESS_KILL
	if(occupant)
		if(auto_eject_dead && occupant.stat == DEAD)
			play_sfx(loc, SFX_MACHINES_BUZZ_SIGH, 0.8)
			go_out()
			return
		occupant.set_stasis(stasis_level, src)

		if(filtering > 0)
			if(beaker)
				if(beaker.reagents.total_volume < beaker.reagents.maximum_volume)
					var/pumped = 0
					for(var/datum/reagent/x in occupant.reagents.reagent_list)
						occupant.reagents.trans_to_obj(beaker, 3)
						pumped++
					if(ishuman(occupant))
						occupant.vessel.trans_to_obj(beaker, pumped + 1)
			else
				toggle_filter()

		if(pumping > 0)
			if(beaker)
				if(beaker.reagents.total_volume < beaker.reagents.maximum_volume)
					for(var/datum/reagent/x in occupant.ingested.reagent_list)
						occupant.ingested.trans_to_obj(beaker, 3)
			else
				toggle_pump()

/obj/machinery/sleeper/update_icon()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	icon_state = "sleeper_[occupant ? "1" : "0"]"

/// Old attackby. It never called ..(), so every item stops here.
/obj/machinery/sleeper/proc/sleeper_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	add_fingerprint(user)
	if(istype(I, /obj/item/grab))
		var/obj/item/grab/G = I
		if(G?.grab_target())
			go_in(G?.grab_target(), user)
		return TRUE
	if(istype(I, /obj/item/reagent_containers/glass))
		if(!beaker)
			beaker = I
			user.drop_item()
			I.forceMove(src)
			user.visible_message(span_infoplain(span_bold("\The [user]") + " adds \a [I] to \the [src]."), span_notice("You add \a [I] to \the [src]."))
		else
			to_chat(user, span_warning("\The [src] has a beaker already."))
		return TRUE
	if(!occupant)
		default_part_replacement(user, I)
	return TRUE

/obj/machinery/sleeper/screwdriver_act(mob/user, obj/item/tool)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	return occupant ? ITEM_INTERACT_BLOCKING : ..()

/obj/machinery/sleeper/crowbar_act(mob/user, obj/item/tool)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	return occupant ? ITEM_INTERACT_BLOCKING : ..()

/// Old verb "Eject occupant".
/obj/machinery/sleeper/proc/sleeper_move_eject(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(user == occupant)
		switch(user.stat)
			if(DEAD)
				return
			if(UNCONSCIOUS)
				to_chat(user, span_notice("You struggle through the haze to hit the eject button. This will take a couple of minutes..."))
				om_task_timed(user, 2 MINUTES, target = src, receiver = src, on_done = PROC_REF(move_eject_timed_done), done_args = list())
			if(CONSCIOUS)
				go_out()
	else
		if(user.stat != CONSCIOUS)
			return
		go_out()
	add_fingerprint(user)

/obj/machinery/sleeper/proc/move_eject_timed_done()
	go_out()

/// Old MouseDrop_T.
/obj/machinery/sleeper/proc/sleeper_interaction_drag(mob/user, mob/target, datum/interaction/interaction)
	if(!ismob(target) || user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user) || !ishuman(target))
		return FALSE
	go_in(target, user)
	return TRUE

/obj/machinery/sleeper/relaymove(mob/user)
	..()
	if(user.incapacitated())
		return
	go_out()

/obj/machinery/sleeper/emp_act(severity, recursive)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return

	if(filtering)
		toggle_filter()

	if(pumping)
		toggle_pump()

	if(!operable())
		..(severity, recursive)
		return

	if(occupant)
		go_out()

/obj/machinery/sleeper/proc/toggle_filter()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(!occupant || !beaker)
		filtering = 0
		return
	filtering = !filtering

/obj/machinery/sleeper/proc/toggle_pump()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(!occupant || !beaker)
		pumping = 0
		return
	pumping = !pumping

/obj/machinery/sleeper/proc/go_in(mob/M, mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(!M)
		return
	if(!operable())
		return
	if(M?.buckled_to())
		return
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return
	if(!ishuman(M))
		to_chat(user, span_warning("\The [src] is not designed for that organism!"))
		return
	if(M == user)
		visible_message("\The [user] starts climbing into \the [src].")
	else
		visible_message("\The [user] starts putting [M] into \the [src].")

	om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(go_in_timed_done), done_args = list(M, user))

/obj/machinery/sleeper/proc/go_in_timed_done(mob/M, mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(M?.buckled_to())
		return
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return
	M.stop_pulling()
	if(!M.move_into(src, OCCUPANT_SLOT_SLEEPER))
		return
	occupant = M
	set_use_power(USE_POWER_ACTIVE)
	MACHINE_WAKE(src)
	occupant.cozyloop.start() // Cozy Music
	update_icon()

/obj/machinery/sleeper/proc/go_out()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(!occupant || occupant.loc != src)
		occupant?.cozyloop?.stop() // Cozy Music
		return
	occupant.set_stasis(null, src)
	occupant.cozyloop.stop() // Cozy Music
	// The occupant slot is the only thing in this machine that should ever
	// leave on go_out(): everything else (beaker, circuit, parts) lives in
	// its own default slot (machine_internals) now, so the old "eject
	// everything except a hand-kept exclude list" loop -- the source of the
	// sleeper's partial-eject bug -- is gone.
	slot_remove(occupant, get_turf(src))
	set_use_power(USE_POWER_IDLE)
	update_icon()
	toggle_filter()
	toggle_pump()
	MACHINE_SLEEP(src)

/obj/machinery/sleeper/power_change()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	. = ..()
	if(. && occupant)
		MACHINE_WAKE(src)

/obj/machinery/sleeper/proc/remove_beaker()
	if(beaker)
		beaker.forceMove(get_turf(src))
		beaker = null
		toggle_filter()

/obj/machinery/sleeper/proc/inject_chemical(mob/living/user, chemical, amount)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SLEEPER)
	if(!operable())
		return
	if(!(amount in amounts))
		return
	if(!istext(chemical) || !LAZYACCESS(available_chemicals, chemical))
		log_admin("[key_name(user)] attempted to inject non-available reagent '[chemical]' via [src] at [AREACOORD(src)]")
		message_admins("[key_name_admin(user)] attempted to inject non-available reagent '[html_encode("[chemical]")]' via [src].")
		return

	if(occupant && occupant.reagents)
		if(occupant.reagents.get_reagent_amount(chemical) + amount <= max_chem)
			use_power(amount * CHEM_SYNTH_ENERGY)
			occupant.reagents.add_reagent(chemical, amount)
			to_chat(user, "Occupant now has [occupant.reagents.get_reagent_amount(chemical)] units of [LAZYACCESS(available_chemicals, chemical)] in their bloodstream.")
		else
			to_chat(user, "The subject has too many chemicals in their bloodstream.")
	else
		to_chat(user, "There's no suitable occupant in \the [src].")

//Survival/Stasis sleepers
/obj/machinery/sleeper/survival_pod
	desc = "A limited functionality sleeper, all it can do is put patients into stasis. It lacks the medication and configuration of the larger units."
	icon_state = "sleeper"
	stasis_level = /datum/body_effect/stasis/complete //Just one setting

/obj/machinery/sleeper/survival_pod/Initialize(mapload)
	. = ..()
	RefreshParts(1)

DECLARE_REF(/obj/machinery/sleeper, "beaker", HELD, null)
