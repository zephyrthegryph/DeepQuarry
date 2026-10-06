// The sleeper and its console (doc/rewrite/final_api.html sections 16.1 and 16.4, doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list each. The sleeper is a machine (machine_basics()) and an occupant pod (occupant_pod(): a person is dragged or grabbed in after a
// two-second wait, climbs in from the menu, is let out from the menu or by moving; tools and part swaps wait for an empty sleeper; entering needs it
// working, asked again when the wait ends). While it works, its stasis setting holds the occupant's biological clock (a while_slotted() contribution
// to STAT_CLOCK_RATE_BIO, gated on STAT_OPERABLE: an unpowered sleeper holds nobody, and nobody releases anything by hand). Its beaker sits in a bay
// (beaker_bay()); dialysis and the stomach pump drain the occupant into it every machine interval while it works and is occupied. An EMP throws the
// occupant out. Its window is worked from the console beside it (the console's window forwards to it), by a silicon remotely, or from inside when the
// sleeper has controls inside.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits read through machine_basics()'s bridge, set_use_power(),
// RefreshParts() with the board and its parts, and maintenance_flags (the panel and the crowbar).

MSG_DEF_SELF(sleeper/dead_occupant, "This person has no life to preserve anymore. Take them to a department capable of reanimating them.")
MSG_DEF_SELF(sleeper/too_far_gone, "This person is not in good enough condition for sleepers to be effective! Use another means of treatment, such as cryogenics!")
MSG_DEF_SELF(sleeper/needs_beaker, "There is no beaker to drain into.")

/// Units of blood chemistry dialysis draws per chemical present, per machine interval (and as much blood as chemicals plus one).
#define SLEEPER_DIALYSIS_UNITS 3
/// Units of stomach contents the pump draws per chemical present, per machine interval.
#define SLEEPER_PUMP_UNITS 3
/// How close to an overdose the window warns (units of the chemical the next press could add).
#define SLEEPER_OVERDOSE_CAUTION 10
/// The top of the window's temperature bar, in kelvin (a burning vox armalis in a sleeper still fits).
#define SLEEPER_TEMPERATURE_BAR_MAX 1000

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

CAPABILITIES(/obj/machinery/sleep_console)
	machine_basics(repair = NONE)
	paired_console(/obj/machinery/sleeper, nameof(sleeper))
	links(/obj/machinery/sleep_console::sleeper, /obj/machinery/sleeper::console)
	space(SPACE_PANEL, door = nameof(panel_open))
	// The console's window is its sleeper's panel: every button goes to the sleeper, and it shows the sleeper's data.
	interface("Sleeper", title = "Sleeper", forwards = nameof(sleeper))
	extend("ui_open", binds(item(/obj/item)), needs(req_paired(nameof(sleeper)), req_closed(SPACE_PANEL)))

/// Dark while it has no power.
/obj/machinery/sleep_console/draw(datum/look/look)
	..()
	look.state(operable() ? "sleeperconsole" : "sleeperconsole-p")

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
	/// The doses a chemical button gives.
	var/static/list/amounts = list(5, 10)
	var/obj/item/reagent_containers/glass/beaker = null
	/// Dialysis runs: the occupant's blood chemistry drains into the beaker.
	var/filtering = FALSE
	/// The stomach pump runs: what the occupant swallowed drains into the beaker.
	var/pumping = FALSE
	// Currently never changes. On Paradise, max_chem is based on the matter bins in the sleeper.
	var/max_chem = 20
	var/obj/machinery/sleep_console/console
	/// The share of normal speed the occupant's biology runs at while the sleeper works (1: no stasis). The window's stasis choice sets it.
	var/stasis_rate = 1
	var/static/list/stasis_choices = list("Complete (1%)" = 0.01, "Deep (10%)" = 0.1, "Moderate (20%)" = 0.2, "Light (50%)" = 0.5, "None (100%)" = 1)
	/// The occupant can work the window from inside.
	var/controls_inside = FALSE
	var/auto_eject_dead = FALSE

	use_power = USE_POWER_IDLE
	idle_power_usage = 15
	active_power_usage = 200 //builtin health analyzer, dialysis machine, injectors.

TRACKED(/obj/machinery/sleeper, filtering)
TRACKED(/obj/machinery/sleeper, pumping)
TRACKED(/obj/machinery/sleeper, stasis_rate)
TRACKED(/obj/machinery/sleeper, auto_eject_dead)

CAPABILITIES(/obj/machinery/sleeper)
	machine_basics(repair = NONE)
	occupant_pod(OCCUPANT_SLOT_SLEEPER, enter_wait = SLEEPER_ENTER_WAIT, controls_inside = nameof(controls_inside))
	extend(TAG_POD_ENTER, needs(req_operable()))
	when(STAT_OPERABLE, while_slotted(OCCUPANT_SLOT_SLEEPER, contributes(STAT_CLOCK_RATE_BIO, nameof(stasis_rate)), on = ON_CONTENTS))
	owns_one(nameof(beaker), /obj/item/reagent_containers/glass, starts = /obj/item/reagent_containers/glass/beaker/large, on_destroy = ON_DESTROY_DELETE)
	beaker_bay(nameof(beaker), eject_button = "removebeaker")
	part_replacement()
	extend("part_replacement.replace", needs(req_is(OCCUPANT_POD_OCCUPIED, FALSE, because = MSG(occupant_pod/someone_inside))))
	space(SPACE_PANEL, door = nameof(panel_open))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(treatment_frame)), when = cond_all(STAT_OPERABLE, OCCUPANT_POD_OCCUPIED))
	on_notice(/datum/notice/pod_entered, then(PROC_REF(occupant_entered)))
	on_notice(/datum/notice/pod_left, then(PROC_REF(occupant_left)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(pulsed)))
	on_change(nameof(beaker), ANY, then(PROC_REF(beaker_changed)))
	section(window, "the sleeper's panel: its console forwards every button here; an open panel refuses them all")
	interface("Sleeper", title = "Sleeper")
	extend("ui_open", inputs(remote()))
	op("controls", inside(), label("Controls"), when(nameof(controls_inside)), opens_ui())
	extend(TAG_UI, needs(req_closed(SPACE_PANEL)), then(PROC_REF(control_touched), early = TRUE))
	op("chemical", ui_act("chemical", arg("amount", num()), arg("chemid")),
		needs(req_operable(), req_is(OCCUPANT_POD_OCCUPIED, because = MSG(occupant_pod/empty)),
			req(PROC_REF(occupant_alive), because = MSG(sleeper/dead_occupant)), req(PROC_REF(occupant_viable), because = MSG(sleeper/too_far_gone))),
		then(PROC_REF(inject_chosen)))
	op("togglefilter", ui_act("togglefilter"), needs(req_is(OCCUPANT_POD_OCCUPIED, because = MSG(occupant_pod/empty)), req_full(nameof(beaker), because = MSG(sleeper/needs_beaker))),
		toggles(nameof(filtering)))
	op("togglepump", ui_act("togglepump"), needs(req_is(OCCUPANT_POD_OCCUPIED, because = MSG(occupant_pod/empty)), req_full(nameof(beaker), because = MSG(sleeper/needs_beaker))),
		toggles(nameof(pumping)))
	op("ejectify", ui_act("ejectify"), then(PROC_REF(eject_from_window)), logs(LOG_GAME))
	op("changestasis", ui_act("changestasis"),
		asks(/datum/prompt/choice, fields = list("question" = "Levels deeper than 50% stasis level will render the patient unconscious.", "title" = "Stasis Level", "choices" = nameof(stasis_choices), "timeout" = 0), step = "stasis"),
		then(PROC_REF(set_stasis_choice)))
	op("auto_eject_dead_on", ui_act("auto_eject_dead_on"), sets(nameof(auto_eject_dead), TRUE))
	op("auto_eject_dead_off", ui_act("auto_eject_dead_off"), sets(nameof(auto_eject_dead), FALSE))
	default_parts()

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

/obj/machinery/sleeper/draw(datum/look/look)
	..()
	look.state(occupant_of(src) ? "sleeper_1" : "sleeper_0")

// ---- the occupant ----

/// Someone got in: the sleeper draws its full power and plays its music to them.
/obj/machinery/sleeper/proc/occupant_entered(datum/act/A)
	var/datum/notice/pod_entered/N = A
	var/mob/living/carbon/occupant = N.occupant
	set_use_power(USE_POWER_ACTIVE)
	if(istype(occupant))
		occupant.cozyloop?.start() // Cozy Music

/// They left (by any path): the music stops, dialysis and the pump stop with nobody to drain, the sleeper idles. Their stasis ended with the slot.
/obj/machinery/sleeper/proc/occupant_left(datum/act/A)
	var/datum/notice/pod_left/N = A
	var/mob/living/carbon/occupant = N.occupant
	if(istype(occupant))
		occupant.cozyloop?.stop() // Cozy Music
	set_filtering(FALSE)
	set_pumping(FALSE)
	set_use_power(USE_POWER_IDLE)

/// The beaker went out: there is nothing to drain into.
/obj/machinery/sleeper/proc/beaker_changed(datum/act/A)
	if(!beaker)
		set_filtering(FALSE)
		set_pumping(FALSE)

/// An EMP stops dialysis and the pump and throws the occupant out of a working sleeper.
/obj/machinery/sleeper/proc/pulsed(datum/act/A)
	set_filtering(FALSE)
	set_pumping(FALSE)
	if(operable())
		occupant_eject(src)

/// The window's eject button.
/obj/machinery/sleeper/proc/eject_from_window(datum/act/op/A)
	if(!length(occupant_eject(src)))
		return OP_FAILED
	return OP_OK

/// Every button pressed leaves the presser's prints.
/obj/machinery/sleeper/proc/control_touched(datum/act/op/A)
	add_fingerprint(A.actor)

// ---- one machine interval of treatment, while it works and is occupied ----

/obj/machinery/sleeper/proc/treatment_frame(datum/act/timer/A)
	var/mob/living/carbon/human/occupant = occupant_of(src)
	if(!occupant)
		return
	if(auto_eject_dead && occupant.stat == DEAD)
		play_sfx(loc, SFX_MACHINES_BUZZ_SIGH, 0.8)
		occupant_eject(src)
		return
	if(filtering)
		dialyse(occupant)
	if(pumping)
		pump_stomach(occupant)

/// Dialysis: SLEEPER_DIALYSIS_UNITS of the blood chemistry for each chemical in it, in proportion (one transfer: the old per-chemical loop moved the
/// same total), and as much blood as there are chemicals plus one.
/obj/machinery/sleeper/proc/dialyse(mob/living/carbon/human/occupant)
	if(!beaker || beaker.reagents.total_volume >= beaker.reagents.maximum_volume)
		return
	var/chemicals = length(occupant.reagents.reagent_list)
	if(chemicals)
		occupant.reagents.trans_to_obj(beaker, SLEEPER_DIALYSIS_UNITS * chemicals)
	if(ishuman(occupant) && occupant.vessel)
		occupant.vessel.trans_to_obj(beaker, chemicals + 1)

/// The stomach pump: SLEEPER_PUMP_UNITS of what was swallowed for each chemical in it.
/obj/machinery/sleeper/proc/pump_stomach(mob/living/carbon/human/occupant)
	if(!beaker || beaker.reagents.total_volume >= beaker.reagents.maximum_volume)
		return
	var/chemicals = length(occupant.ingested.reagent_list)
	if(chemicals)
		occupant.ingested.trans_to_obj(beaker, SLEEPER_PUMP_UNITS * chemicals)

// ---- the window's buttons ----

/// The occupant is alive (the injectors refuse the dead).
/obj/machinery/sleeper/proc/occupant_alive(datum/act/op/A)
	var/mob/living/occupant = occupant_of(src)
	return occupant?.stat != DEAD

/// The occupant is in good enough condition for the sleeper to help.
/obj/machinery/sleeper/proc/occupant_viable(datum/act/op/A)
	var/mob/living/occupant = occupant_of(src)
	return occupant && occupant.vitality() > 0

/// A chemical button: `amount` units of `chemid` into the occupant, when it is one of the doses and one of the chemicals the sleeper lists, and the
/// occupant does not already carry max_chem of it. A chemical the sleeper does not list is a forged press: refused and told to the admins.
/obj/machinery/sleeper/proc/inject_chosen(datum/act/op/A, amount, chemid)
	var/mob/user = A.actor
	var/mob/living/carbon/human/occupant = occupant_of(src)
	if(!occupant?.reagents || !(amount in amounts))
		return OP_REFUSED
	if(!istext(chemid) || !LAZYACCESS(available_chemicals, chemid))
		log_admin("[key_name(user)] attempted to inject non-available reagent '[chemid]' via [src] at [AREACOORD(src)]")
		message_admins("[key_name_admin(user)] attempted to inject non-available reagent '[html_encode("[chemid]")]' via [src].")
		return OP_REFUSED
	if(occupant.reagents.get_reagent_amount(chemid) + amount > max_chem)
		to_chat(user, "The subject has too many chemicals in their bloodstream.")
		return OP_REFUSED
	use_power(amount * CHEM_SYNTH_ENERGY)
	occupant.reagents.add_reagent(chemid, amount)
	to_chat(user, "Occupant now has [occupant.reagents.get_reagent_amount(chemid)] units of [LAZYACCESS(available_chemicals, chemid)] in their bloodstream.")
	return OP_OK

/// The stasis choice the window asked for: the rate it names holds the occupant while the sleeper works.
/obj/machinery/sleeper/proc/set_stasis_choice(datum/act/op/A)
	var/choice = A.step_value("stasis")
	if(!(choice in stasis_choices))
		return OP_REFUSED
	set_stasis_rate(stasis_choices[choice])
	log_game("STASIS: [key_name(A.actor)] set [src] at [AREACOORD(src)] to [choice] (occupant: [key_name(occupant_of(src))]).")
	return OP_OK

/// The window's data.
/obj/machinery/sleeper/ui_data(datum/act/eval/A)
	. = list()
	.["amounts"] = amounts
	.["maxchem"] = max_chem
	.["dialysis"] = filtering
	.["stomachpumping"] = pumping
	.["auto_eject_dead"] = auto_eject_dead
	var/list/part = ui_data_part_sleeper(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/sleeper/proc/ui_data_part_sleeper(datum/act/eval/A)
	var/mob/living/carbon/human/occupant = occupant_of(src)
	var/list/data = list()
	data["hasOccupant"] = occupant ? 1 : 0
	var/list/occupantData = list()
	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["critical"] = occupant.is_critical()
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		occupantData["diagnosis"] = D.report_data()
		spent(D)
		occupantData["paralysis"] = occupant.status_units(STAT_PARALYZED)
		occupantData["hasBlood"] = 0
		occupantData["bodyTemperature"] = occupant.body_temperature()
		occupantData["maxTemp"] = SLEEPER_TEMPERATURE_BAR_MAX
		// Because we can put simple_animals in here, we need to do something tricky to get things working nice
		occupantData["temperatureSuitability"] = 0 // 0 is the baseline
		if(ishuman(occupant) && occupant.species)
			// I wanna do something where the bar gets bluer as the temperature gets lower
			// For now, I'll just use the standard format for the temperature status
			var/datum/species/sp = occupant.species
			if(occupant.body_temperature() < sp.cold_level_3)
				occupantData["temperatureSuitability"] = -3
			else if(occupant.body_temperature() < sp.cold_level_2)
				occupantData["temperatureSuitability"] = -2
			else if(occupant.body_temperature() < sp.cold_level_1)
				occupantData["temperatureSuitability"] = -1
			else if(occupant.body_temperature() > sp.heat_level_3)
				occupantData["temperatureSuitability"] = 3
			else if(occupant.body_temperature() > sp.heat_level_2)
				occupantData["temperatureSuitability"] = 2
			else if(occupant.body_temperature() > sp.heat_level_1)
				occupantData["temperatureSuitability"] = 1
		else if(isanimal(occupant))
			var/mob/living/simple_mob/silly = occupant
			if(silly.body_temperature() < silly.minbodytemp)
				occupantData["temperatureSuitability"] = -3
			else if(silly.body_temperature() > silly.maxbodytemp)
				occupantData["temperatureSuitability"] = 3
		// Blast you, imperial measurement system
		occupantData["btCelsius"] = occupant.body_temperature() - T0C
		occupantData["btFaren"] = ((occupant.body_temperature() - T0C) * (9.0/5.0))+ 32

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
		if(stasis_choices[N] == stasis_rate)
			stasis_level_name = N
			break
	data["stasis"] = stasis_level_name

	var/list/chemicals = list()
	for(var/re in available_chemicals)
		var/datum/reagent/temp = SSchemistry.ready().chemical_reagents[re]
		if(temp)
			var/reagent_amount = 0
			var/pretty_amount
			var/injectable = occupant ? 1 : 0
			var/overdosing = 0
			var/caution = 0 // To make things clear that you're coming close to an overdose

			if(occupant && occupant.reagents)
				reagent_amount = occupant.reagents.get_reagent_amount(temp.id)
				// If they're mashing the highest concentration, they get one warning
				if(temp.overdose && reagent_amount + SLEEPER_OVERDOSE_CAUTION > (temp.overdose * occupant.species.chemOD_threshold))
					caution = 1
				if(temp.overdose && reagent_amount > (temp.overdose * occupant.species.chemOD_threshold))
					overdosing = 1

			pretty_amount = round(reagent_amount, 0.05)

			chemicals.Add(list(list("title" = temp.name, "id" = temp.id, "commands" = list("chemical" = temp.id), "occ_amount" = reagent_amount, "pretty_amount" = pretty_amount, "injectable" = injectable, "overdosing" = overdosing, "od_warning" = caution)))
	data["chemicals"] = chemicals
	return data

//Survival/Stasis sleepers
/obj/machinery/sleeper/survival_pod
	stasis_rate = 0.01 //Just one setting: complete stasis

// ALLOW(init/INSTANCE_STATE): sizes itself from the parts this pod was built with
/obj/machinery/sleeper/survival_pod/Initialize(mapload)
	. = ..()
	RefreshParts(1)

#undef SLEEPER_DIALYSIS_UNITS
#undef SLEEPER_PUMP_UNITS
#undef SLEEPER_OVERDOSE_CAUTION
#undef SLEEPER_TEMPERATURE_BAR_MAX
