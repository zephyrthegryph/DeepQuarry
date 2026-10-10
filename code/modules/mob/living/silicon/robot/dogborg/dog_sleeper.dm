#define SLEEPER_INJECT_COST 600 // Note that this has unlimited supply unlike a borg hypo, so should be balanced accordingly
/// Longest gap (in baseline belly ticks) one digestion pass catches up on.
#define DOGBORG_DIGEST_MAX_CATCHUP 3

//Sleeper
/obj/item/dogborg/sleeper
	name = "Sleeper Belly"
	desc = "A mounted sleeper that stabilizes patients and can inject reagents in the borg's reserves."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "sleeper"
	w_class = ITEMSIZE_TINY
	var/mob/living/carbon/patient = null
	var/mob/living/silicon/robot/hound = null
	var/inject_amount = 10
	/// Below this vitality the patient is too unstable for anything but inaprovaline.
	var/min_vitality = 0
	var/cleaning = 0
	var/working = FALSE
	var/patient_laststat = null
	var/eject_port = "ingestion"
	/// Things in our contents spared from digestion.
	var/list/items_preserved
	var/stabilizer = TRUE
	var/compactor = FALSE
	var/analyzer = FALSE
	var/decompiler = FALSE
	var/delivery = FALSE
	var/delivery_tag = "Fuel"
	var/list/list/deliverylists = list() // ALLOW(instance_list): d: nested per-slot lists created with the sleeper and edited in place
	var/list/deliveryslot_1
	var/list/deliveryslot_2
	var/list/deliveryslot_3
	var/synced = FALSE
	var/startdrain = 500
	var/max_item_count = 1
	var/upgraded_capacity = FALSE
	var/gulpsound = SFX_VORE_GULP
	var/datum/matter_synth/metal/metal = null
	var/datum/matter_synth/glass/glass = null
	var/datum/matter_synth/wood/wood = null
	var/datum/matter_synth/plastic/plastic = null
	var/datum/matter_synth/water = null
	var/digest_brute = 2
	/// world.time of the last digestion pass (0: none yet).
	EXPIRY_TMP_DECLARE(last_digest_time)
	var/digest_burn = 3
	var/digest_multiplier = 1
	var/recycles = FALSE
	var/medsensor = TRUE //Does belly sprite come with patient ok/dead light?
	var/obj/item/healthanalyzer/med_analyzer = null
	var/ore_storage = FALSE
	var/obj/item/ore_bag/sleeper/ore_bag //Used by supply compactor
	flags = NOBLUDGEON

/// The sleeper has something to look after (a patient, a clean cycle or a last look for one): its step runs every two seconds while it holds.
TRACKED(/obj/item/dogborg/sleeper, working)

MSG_DEF_SELF(sleeper/full, "Your sleeper is full. Eject or process contents to continue.")
MSG_DEF_SELF(sleeper/blacklisted, "You are hard-wired to not ingest this item.")
MSG_DEF_SELF(sleeper/too_large, "%T% is too large to fit into your sleeper.")
MSG_DEF_SELF(sleeper/occupied, "Your sleeper is already occupied.")
MSG_DEF_SELF(sleeper/buckled, "%T% is buckled and can not be put into your sleeper.")

CAPABILITIES(/obj/item/dogborg/sleeper)
	ref_many(nameof(items_preserved))
	// ingestion: the plain sleeper takes a person (5 seconds), the compactor an item, a mouse or a person (3 seconds)
	op("sleeper_take_patient", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_NORMAL), answers(INTENT_USE, INTENT_ATTACK), when(PROC_REF(sleeper_is_plain)), needs(req(PROC_REF(sleeper_target_free), silent = TRUE), req(PROC_REF(sleeper_has_room), because = MSG(sleeper/full)), req(PROC_REF(sleeper_target_loose), because = MSG(sleeper/buckled)), req(PROC_REF(sleeper_vacant), because = MSG(sleeper/occupied))), starts(PROC_REF(sleeper_started)), begins(PROC_REF(sleeper_ingest_text)), wait(5 SECONDS), then(PROC_REF(intake_patient_done)))
	op("sleeper_compact_item", at_target(/obj/item), at_target(/obj/effect/decal/remains), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), when(PROC_REF(sleeper_is_compactor)), needs(req(PROC_REF(sleeper_target_free), silent = TRUE), req(PROC_REF(sleeper_has_room), because = MSG(sleeper/full)), req(PROC_REF(sleeper_may_ingest), because = MSG(sleeper/blacklisted)), req(PROC_REF(sleeper_fits), because = MSG(sleeper/too_large))), starts(PROC_REF(sleeper_started)), begins(PROC_REF(sleeper_ingest_text)), wait(3 SECONDS), then(PROC_REF(sleeper_ingested_thing)))
	op("sleeper_compact_mouse", at_target(/mob/living/simple_mob/animal/passive/mouse), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), when(PROC_REF(sleeper_is_compactor)), needs(req(PROC_REF(sleeper_target_free), silent = TRUE), req(PROC_REF(sleeper_has_room), because = MSG(sleeper/full)), req(PROC_REF(sleeper_may_ingest), because = MSG(sleeper/blacklisted))), starts(PROC_REF(sleeper_started)), begins(PROC_REF(sleeper_ingest_text)), wait(3 SECONDS), then(PROC_REF(sleeper_ingested_thing)))
	op("sleeper_compact_person", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), when(PROC_REF(sleeper_is_compactor)), needs(req(PROC_REF(sleeper_target_free), silent = TRUE), req(PROC_REF(sleeper_has_room), because = MSG(sleeper/full)), req(PROC_REF(sleeper_may_ingest), because = MSG(sleeper/blacklisted)), req(PROC_REF(sleeper_vacant), because = MSG(sleeper/occupied)), req(PROC_REF(sleeper_target_loose), because = MSG(sleeper/buckled))), starts(PROC_REF(sleeper_started)), begins(PROC_REF(sleeper_ingest_text)), wait(3 SECONDS), then(PROC_REF(sleeper_ingested_person)))
	every(2 SECONDS, then(PROC_REF(sleeper_step)), when = nameof(working))
	owns_one(nameof(med_analyzer), /obj/item/healthanalyzer)
	owns_one(nameof(ore_bag), /obj/item/ore_bag/sleeper)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	interface("RobotSleeper", state = nameof(GLOB.tgui_conscious_state))
	without("ui_open")
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("clean", ui_act("clean"), then(PROC_REF(ui_act_clean)))
	op("analyze", ui_act("analyze"), then(PROC_REF(ui_act_analyze)))
	op("port", ui_act("port", arg("value", schema_text(4096))), then(PROC_REF(ui_act_port)))
	op("ingest", ui_act("ingest"), then(PROC_REF(ui_act_ingest)))
	op("deliveryslot", ui_act("deliveryslot", arg("value", schema_text(4096))), then(PROC_REF(ui_act_deliveryslot)))
	op("slot_eject", ui_act("slot_eject"), then(PROC_REF(ui_act_slot_eject)))
	op("inject", ui_act("inject", arg("value", schema_text(4096))), then(PROC_REF(ui_act_inject)))
//The borg is able to heal every damage type. As a nerf, they use 750 charge per injection.
TYPE_TABLE_DECLARE(/obj/item/dogborg/sleeper, sleeper_injection_chems, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_BICARIDINE, REAGENT_ID_KELOTANE, REAGENT_ID_ANTITOXIN, REAGENT_ID_DEXALIN, REAGENT_ID_TRICORDRAZINE, REAGENT_ID_SPACEACILLIN, REAGENT_ID_TRAMADOL))

/obj/item/dogborg/sleeper/Initialize(mapload)
	if(analyzer) //Destructive analysis
		var/static/list/destructive_events = list(
			/datum/notice/machinery_destructive_scan = TYPE_PROC_REF(/datum/experiment_handler, try_run_destructive_experiment),
		)
		new /datum/experiment_handler(src, \
			config_mode = EXPERIMENT_CONFIG_ALTCLICK, \
			allowed_experiments = list(/datum/experiment/scanning),\
			config_flags = EXPERIMENT_CONFIG_ALWAYS_ACTIVE|EXPERIMENT_CONFIG_SILENT_FAIL,\
			experiment_events = destructive_events, \
		)
	if(ore_storage)
		rel_set(src, nameof(ore_bag), new /obj/item/ore_bag/sleeper(null)) //We don't need it inside, just need a reference to it. // ALLOW(decl): kept in nullspace, conditional
	. = ..()
	rel_set(src, nameof(med_analyzer), new /obj/item/healthanalyzer) // ALLOW(decl): kept in nullspace, not in contents

// The synths are the module's (the owned "synths" list); the patient is in our contents.
// Things in our contents spared from digestion (a marker set; go_out() drops all contents).
// the patient is let out.
/obj/item/dogborg/sleeper/on_destroy(force)
	go_out()
	..()

/obj/item/dogborg/sleeper/Exit(atom/movable/O)
	return 0

/obj/item/dogborg/sleeper/return_air()
	return return_air_for_internal_lifeform()

/obj/item/dogborg/sleeper/return_air_for_internal_lifeform()
	var/datum/gas_mixture/belly_air/air = new(1000)
	return air

/// The cyborg carrying the sleeper is remembered as its hound when an ingestion starts.
/obj/item/dogborg/sleeper/proc/sleeper_started(datum/act/op/A)
	rel_set(src, nameof(hound), loc)

/obj/item/dogborg/sleeper/proc/sleeper_is_compactor(datum/act/op/A)
	return read_once(compactor)

/obj/item/dogborg/sleeper/proc/sleeper_is_plain(datum/act/op/A)
	return read_once(!compactor)

/// Anchored things and the cyborg's own module items are not ingested (the click is refused without a word).
/obj/item/dogborg/sleeper/proc/sleeper_target_free(datum/act/op/A)
	var/atom/movable/target = A.target
	return read_once(istype(target) && !target.anchored && !sleeper_holds_module_item(target))

/// The target is one of the carrying cyborg's own module items.
/obj/item/dogborg/sleeper/proc/sleeper_holds_module_item(atom/movable/target)
	var/mob/living/silicon/robot/R = loc
	return istype(R) && R.module && (target in R.module.modules)

/obj/item/dogborg/sleeper/proc/sleeper_has_room(datum/act/op/A)
	return read_once(contents_count(src) < max_item_count)

/obj/item/dogborg/sleeper/proc/sleeper_may_ingest(datum/act/op/A)
	return read_once(!is_type_in_list(A.target, GLOB.item_vore_blacklist))

/obj/item/dogborg/sleeper/proc/sleeper_fits(datum/act/op/A)
	var/obj/target_obj = A.target
	return read_once(target_obj.w_class <= ITEMSIZE_LARGE)

/obj/item/dogborg/sleeper/proc/sleeper_vacant(datum/act/op/A)
	return read_once(!patient)

/obj/item/dogborg/sleeper/proc/sleeper_target_loose(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return read_once(!H.buckled_to())

/obj/item/dogborg/sleeper/proc/sleeper_ingest_text(datum/act/op/A)
	return msg_text(span_notice("You start ingesting %T% into your [name]..."), span_warning("%U% is ingesting %T% into their [name]."))

/// A person put in the plain sleeper: someone buckled or an occupied sleeper at the end loses the click.
/obj/item/dogborg/sleeper/proc/intake_patient_done(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	var/mob/living/silicon/user = A.actor
	if(H?.buckled_to())
		return OP_FAILED
	if(patient)
		return OP_FAILED //If you try to eat two people at once, you can only eat one.
	H.forceMove(src)
	update_patient()
	set_working(TRUE)
	act_message(user, src, MSG_SELF(span_notice("Your %T% lights up as [H] slips inside. Life support functions engaged.")), \
		MSG_OTHERS(span_warning("[hound.name]'s [src.name] lights up as [H.name] slips inside.")))
	log_admin("[key_name(hound)] has eaten [key_name(patient)] with a cyborg belly. ([hound ? "<a href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[hound.x];Y=[hound.y];Z=[hound.z]'>JMP</a>" : "null"])")
	playsound(src, gulpsound, vol = 100, vary = 1, falloff = 0.1, preference = /datum/preference/toggle/eating_noises)
	return OP_OK

/// A thing put in the compactor (an item, a mouse): the compartment may have filled up meanwhile.
/obj/item/dogborg/sleeper/proc/sleeper_ingested_thing(datum/act/op/A)
	var/atom/movable/target = A.target
	var/mob/living/silicon/user = A.actor
	if(!(contents_count(src) < max_item_count))
		return OP_FAILED
	target.forceMove(src)
	act_message(user, target, MSG_SELF(span_notice("Your [src.name] groans lightly as %T% slips inside.")), \
		MSG_OTHERS(span_warning("[hound.name]'s [src.name] groans lightly as [target.name] slips inside.")))
	playsound(src, gulpsound, vol = 60, vary = 1, falloff = 0.1, preference = /datum/preference/toggle/eating_noises)
	if(delivery)
		if(islist(deliverylists[delivery_tag]))
			deliverylists[delivery_tag] |= target
		to_chat(user, span_notice("\The [target.name] added to cargo compartment slot: [delivery_tag]."))
	update_patient()
	return OP_OK

/// A person put in the compactor.
/obj/item/dogborg/sleeper/proc/sleeper_ingested_person(datum/act/op/A)
	var/mob/living/carbon/human/trashman = A.target
	var/mob/living/silicon/user = A.actor
	if(!(!patient && !trashman?.buckled_to() && contents_count(src) < max_item_count))
		return OP_FAILED
	trashman.forceMove(src)
	set_working(TRUE)
	act_message(user, trashman, MSG_SELF(span_notice("Your [src.name] groans lightly as %T% slips inside.")), \
		MSG_OTHERS(span_warning("[hound.name]'s [src.name] groans lightly as %T% slips inside.")))
	log_attack("[key_name(hound)] has eaten [key_name(patient)] with a cyborg belly. ([hound ? "<a href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[hound.x];Y=[hound.y];Z=[hound.z]'>JMP</a>" : "null"])")
	playsound(src, gulpsound, vol = 100, vary = 1, falloff = 0.1, preference = /datum/preference/toggle/eating_noises)
	if(delivery)
		if(islist(deliverylists[delivery_tag]))
			deliverylists[delivery_tag] |= trashman
		to_chat(user, span_notice("\The [trashman] added to cargo compartment slot: [delivery_tag]."))
		to_chat(trashman, span_notice("[hound.name] has added you to their cargo compartment slot: [delivery_tag]."))
	update_patient()
	return OP_OK

/obj/item/dogborg/sleeper/proc/ingest_atom(atom/ingesting)
	if (!ingesting || ingesting == hound)
		return
	var/obj/belly/belly = hound.vore_selected
	if (!istype(hound) || !istype(belly) || !(belly in hound.vore_organs))
		return
	if (isliving(ingesting))
		ingest_living(ingesting, belly)
	else if (istype(ingesting, /obj/item))
		var/obj/item/to_eat = ingesting
		if (is_type_in_list(to_eat, GLOB.item_vore_blacklist))
			return
		if (istype(to_eat, /obj/item/holder)) //just in case
			var/obj/item/holder/micro = ingesting
			var/delete_holder = TRUE
			for (var/mob/living/M in contents_of(micro))
				if (!ingest_living(M, belly) || M.loc == micro)
					delete_holder = FALSE
			if (delete_holder)
				rel_clear(micro, nameof(micro.held_mob))
				consumed(micro)
			return
		if(!move_into(belly, BELLY_SLOT_INTERIOR, to_eat, hound))
			return
		log_admin("VORE: [hound] used their [src] to swallow [to_eat].")

/obj/item/dogborg/sleeper/proc/ingest_living(mob/living/victim, obj/belly/belly)
	if (victim.devourable && is_vore_predator(hound))
		belly.nom_atom(victim, hound)
		add_attack_logs(hound, victim, "Eaten via [belly.name]")
		return TRUE
	return FALSE

/obj/item/dogborg/sleeper/proc/go_out()
	rel_set(src, nameof(hound), src.loc)
	rel_clear(src, nameof(items_preserved))
	cleaning = 0
	for(var/list/dlist in deliverylists)
		dlist.Cut()
	if(contents_count(src) > 0)
		hound.visible_message(span_warning("[hound.name] empties out their contents via their [eject_port] port."), span_notice("You empty your contents via your [eject_port] port."))
		for(var/atom/movable/content in contents)
			content.forceMove(get_turf(src))
		play_sfx(src, SFX_EFFECTS_SPLAT)
	update_patient()

/obj/item/dogborg/sleeper/proc/vore_ingest_all()
	rel_set(src, nameof(hound), src.loc)
	if (!istype(hound) || contents_count(src) <= 0)
		return
	if (!hound.vore_selected)
		to_chat(hound, span_warning("You don't have a belly selected to empty the contents into!"))
		return
	for (var/C in contents)
		if (isliving(C) || isitem(C))
			ingest_atom(C)
	hound.updateVRPanel()
	update_patient()

/// Spend `amt` cell units through the robot's power ledger (never below empty).
/obj/item/dogborg/sleeper/proc/drain(amt = 3) //Slightly reduced cost (before, it was always injecting inaprov)
	var/atom/holder = loc
	if(istype(holder, /obj/item/robot_module))
		holder = holder.loc
	var/mob/living/silicon/robot/R = holder
	if(!istype(R))
		return FALSE
	rel_set(src, nameof(hound), R)
	return R.draw_power(ROBOT_CELL_JOULES(amt), src, 0, TRUE)

/// Old attack_self.
/obj/item/dogborg/sleeper/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/item/dogborg/sleeper/ui_title(mob/user)
	return "[name] Console"

/obj/item/dogborg/sleeper/tgui_static_data(mob/user)
	var/list/data = ..()

	if(!isrobot(user))
		return data

	var/mob/living/silicon/robot/robot_user = user
	var/list/robot_chems = list()
	for(var/re in TYPE_TABLE_GET(src, sleeper_injection_chems))
		var/datum/reagent/possible_reagent = SSchemistry.ready().chemical_reagents[re]
		UNTYPED_LIST_ADD(robot_chems, list("id" = possible_reagent.id, "name" = possible_reagent.name))

	data["name"] = name
	data["theme"] = robot_user.get_ui_theme()
	data["chems"] = robot_chems
	return data

/// /obj/item/dogborg/sleeper's window data.
/obj/item/dogborg/sleeper/ui_data(datum/act/eval/A)
	var/list/patient_data

	if(patient)
		var/list/ingested_reagents = list()
		if(patient.reagents.reagent_list.len)
			for(var/datum/reagent/ingested in patient.reagents.reagent_list)
				UNTYPED_LIST_ADD(ingested_reagents, list("name" = ingested.name, "volume" = ingested.volume))

		var/datum/diagnosis/D = patient.diagnose(/datum/diagnostic_profile/automation)
		var/list/findings = list()
		for(var/datum/diagnosis_finding/F as anything in D?.findings)
			UNTYPED_LIST_ADD(findings, list("name" = F.name, "band" = F.band))
		spent(D)
		patient_data = list(
			"name" = patient.name,
			"stat" = patient.stat,
			"pulse" = patient.get_pulse(GETPULSE_TOOL),
			"crit_pulse" = (patient.pulse == PULSE_NONE || patient.pulse == PULSE_THREADY),
			// Old +100..-100 readout scale, derived from vitality.
			"health" = round((2 * patient.vitality() - 1) * 100),
			"max_health" = 100,
			"findings" = findings,
			"paralysis" = patient.status_units(STAT_PARALYZED),
			"braindamage" = !!patient.injury_load(INJURY_CATEGORY_NEURAL),
			"clonedamage" = !!patient.injury_load(INJURY_CATEGORY_GENETIC),
			"ingested_reagents" = ingested_reagents
			)

	var/datum/experiment_handler/handler = get_experiment_handler()
	var/current_capacity = 0
	var/max_ore_storage = 0
	if(ore_storage)
		current_capacity = ore_bag.current_capacity
		max_ore_storage = ore_bag.max_storage_space
	var/list/data = list(
		"our_patient" = patient_data,
		"eject_port" = eject_port,
		"cleaning" = cleaning,
		"medsensor" = medsensor,
		"delivery" = delivery,
		"delivery_tag" = delivery_tag,
		"delivery_lists" = deliverylists,
		"compactor" = compactor,
		"max_item_count" = max_item_count,
		"ore_storage" = ore_storage,
		"current_capacity" = current_capacity,
		"max_ore_storage" = max_ore_storage,
		"contents" = contents,
		"deliveryslot_1" = (deliveryslot_1 || list()),
		"deliveryslot_2" = (deliveryslot_2 || list()),
		"deliveryslot_3" = (deliveryslot_3 || list()),
		"items_preserved" = items_preserved || list(),
		"has_destructive_analyzer" = analyzer,
		"techweb_name" = handler?.linked_web() ? "[handler.linked_web().id] / [handler.linked_web().organization]" : null
	)
	return data
/obj/item/dogborg/sleeper/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(user == patient)
		return FALSE
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_eject(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	go_out()
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_clean(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(cleaning)
		return FALSE
	cleaning = TRUE
	drain(startdrain)
	set_working(TRUE)
	update_patient()
	if(patient)
		to_chat(patient, span_danger("[hound.name]'s [src.name] fills with caustic enzymes around you!"))
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_analyze(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	med_analyzer.scan_mob(patient,hound)
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_port(datum/act/op/A, value)
	if(!ui_gate(A))
		return FALSE
	var/new_port = value
	if(!(new_port in list("disposal", "ingestion")))
		return FALSE
	eject_port = new_port
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_ingest(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	vore_ingest_all()
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_deliveryslot(datum/act/op/A, value)
	if(!ui_gate(A))
		return FALSE
	var/new_tag = value
	if(!(new_tag in deliverylists))
		return FALSE
	delivery_tag = new_tag
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_slot_eject(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!length(deliverylists[delivery_tag]))
		return FALSE
	hound.visible_message(span_warning("[hound.name] empties out their cargo compartment via their [eject_port] port."), span_notice("You empty your cargo compartment via your [eject_port] port."))
	for(var/atom/movable/content in deliverylists[delivery_tag])
		content.forceMove(get_turf(src))
	play_sfx(src, SFX_EFFECTS_SPLAT)
	update_patient()
	deliverylists[delivery_tag].Cut()
	return TRUE

/obj/item/dogborg/sleeper/proc/ui_act_inject(datum/act/op/A, value)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!patient || (patient.stat & DEAD))
		to_chat(user, span_notice("ERROR: Subject cannot metabolise chemicals."))
		return FALSE
	var/selected_reagent = value
	if(!(selected_reagent in TYPE_TABLE_GET(src, sleeper_injection_chems)))
		return FALSE
	if(selected_reagent == REAGENT_ID_INAPROVALINE || patient.vitality() > min_vitality)
		inject_chem(user, selected_reagent)
	else
		to_chat(user, span_notice("ERROR: Subject is not in stable condition for injections."))
	return TRUE

/obj/item/dogborg/sleeper/proc/inject_chem(mob/user, chem)
	if(patient && patient.reagents)
		if(chem in (TYPE_TABLE_GET(src, sleeper_injection_chems) + REAGENT_ID_INAPROVALINE))
			if(!hound.cell || hound.cell.charge < 800) //This is so borgs don't kill themselves with it.
				to_chat(hound, span_notice("You don't have enough power to synthesize fluids."))
				return
			else if(patient.reagents.get_reagent_amount(chem) + 10 >= 20) //Preventing people from accidentally killing themselves by trying to inject too many chemicals!
				to_chat(hound, span_notice("Your stomach is currently too full of fluids to secrete more fluids of this kind."))
			else if(patient.reagents.get_reagent_amount(chem) + 10 <= 20) //No overdoses for you
				patient.reagents.add_reagent(chem, inject_amount)
				drain(SLEEPER_INJECT_COST)
			var/units = round(patient.reagents.get_reagent_amount(chem))
			to_chat(hound, span_notice("Injecting [units] unit\s of [SSchemistry.ready().chemical_reagents[chem]] into occupant.")) //If they were immersed, the reagents wouldn't leave with them.

/// The belly light: busy (red) while cleaning, crowded or holding the dead;
/// green with a living patient. The robot only redraws when it changes.
/obj/item/dogborg/sleeper/proc/set_hound_sleeper_state(new_state)
	var/datum/robot_belly/belly = hound?.robot_belly
	belly?.set_sleeper_state(new_state)

/obj/item/dogborg/sleeper/proc/patient_light_state(mob/living/carbon/who)
	if(!medsensor || cleaning || (who.stat & DEAD))
		return SLEEPER_STATE_BUSY
	return SLEEPER_STATE_PATIENT

//For if the dogborg's existing patient uh, doesn't make it.
/obj/item/dogborg/sleeper/proc/update_patient()
	rel_set(src, nameof(hound), src.loc)
	if(!istype(hound,/mob/living/silicon/robot))
		return

	//Cleaning looks better with red on, even with nobody in it
	if(cleaning || (contents_count(src) > 10) || (decompiler && (contents_count(src) > 5)) || (analyzer && (contents_count(src) > 1)))
		set_hound_sleeper_state(SLEEPER_STATE_BUSY)
		return

	//Well, we HAD one, what happened to them?
	if(patient in contents)
		if(patient_laststat != patient.stat || !medsensor)
			set_hound_sleeper_state(patient_light_state(patient))
			patient_laststat = patient.stat
		return(patient)

	//Check for a new patient
	for(var/mob/living/carbon/human/C in contents)
		rel_set(src, nameof(patient), C)
		set_hound_sleeper_state(patient_light_state(C))
		patient_laststat = C.stat
		return(C)

	//Couldn't find anyone, and not cleaning
	patient_laststat = null
	rel_clear(src, nameof(patient))
	set_hound_sleeper_state(SLEEPER_STATE_EMPTY)
	return

//Gurgleborg process
/obj/item/dogborg/sleeper/proc/clean_cycle()

	//Sanity? Maybe not required. More like if indigestible person OOC escapes.
	for(var/I in items_preserved)
		if(!(I in contents))
			rel_remove(src, nameof(items_preserved), I)

	var/list/touchable_items = contents - items_preserved - (deliveryslot_1 + deliveryslot_2 + deliveryslot_3)

	//Belly is entirely empty
	if(!length(touchable_items))
		finish_clean_cycle()
		return

	if(prob(20))
		var/churnsound = SFX_CLASSIC_DIGESTION_SOUNDS
		playsound(src, churnsound, vol = 100, vary = 1, falloff = 0.1, ignore_walls = TRUE, preference = /datum/preference/toggle/digestion_noises)
	//If the timing is right, and there are items to be touched
	if(SSair.times_fired%3==1)
		// digest_brute / digest_burn are rates per BELLY_BASELINE_TICK, applied as
		// continuous harm for the time since the last digestion pass.
		var/delta_factor = last_digest_time ? clamp((world.time - last_digest_time) / BELLY_BASELINE_TICK, 0, DOGBORG_DIGEST_MAX_CATCHUP) : 1
		EXPIRY_STAMP(src, last_digest_time, CLOCK_WORLD)

		//Burn all the mobs or add them to the exclusion list
		for(var/mob/living/T in (touchable_items))
			touchable_items -= T //Exclude mobs from loose item picking.
			digest_occupant(T, delta_factor)

		//Pick a random item to deal with (if there are any)
		if(length(touchable_items))
			digest_loose_item(pick(touchable_items))
		update_patient()

/// The belly is empty: announce it and stop cleaning.
/obj/item/dogborg/sleeper/proc/finish_clean_cycle()
	var/finisher = SFX_CLASSIC_DEATH_SOUNDS
	playsound(src, finisher, vol = 100, vary = 1, falloff = 0.1, ignore_walls = TRUE, preference = /datum/preference/toggle/digestion_noises)
	to_chat(hound, span_notice("Your [src.name] is now clean. Ending self-cleaning cycle."))
	cleaning = 0
	update_patient()
	play_sfx(src, SFX_MACHINES_DING, 2, falloff = 0.1, ignore_walls = TRUE, preference = /datum/preference/toggle/digestion_noises)

/// One digestion pass on a living occupant; indigestible ones are preserved.
/obj/item/dogborg/sleeper/proc/digest_occupant(mob/living/T, delta_factor)
	if(in_godmode(T) || !T.digestable)
		rel_add(src, nameof(items_preserved), T)
		return
	var/damage_gain = T.injure(INJURY_DIGESTION, digest_brute * digest_multiplier * delta_factor, null, hound, flags = INJURE_CONTINUOUS)
	damage_gain += T.injure(INJURY_CORROSIVE, digest_burn * digest_multiplier * delta_factor, null, hound, flags = INJURE_CONTINUOUS)
	hound.adjust_nutrition(2.5 * damage_gain) //25*total loss as with voreorgan stats.
	if(water)
		water.add_charge(damage_gain)
	if(T.stat == DEAD)
		dissolve_occupant(T)

/// A digested occupant: release its prey and belongings, bank its volume, delete it.
/obj/item/dogborg/sleeper/proc/dissolve_occupant(mob/living/T)
	if(ishuman(T))
		log_admin("[key_name(hound)] has digested [key_name(T)] with a cyborg belly. ([hound ? "<a href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[hound.x];Y=[hound.y];Z=[hound.z]'>JMP</a>" : "null"])")
	to_chat(hound, span_notice("You feel your belly slowly churn around [T], breaking them down into a soft slurry to be used as power for your systems."))
	to_chat(T, span_notice("You feel [hound]'s belly slowly churn around your form, breaking you down into a soft slurry to be used as power for [hound]'s systems."))
	var/deathsound = SFX_CLASSIC_DEATH_SOUNDS
	playsound(src, deathsound, vol = 100, vary = 1, falloff = 0.1, ignore_walls = TRUE, preference = /datum/preference/toggle/digestion_noises)
	if(is_vore_predator(T))
		for(var/obj/belly/B as anything in T.vore_organs)
			for(var/atom/movable/thing in B)
				thing.forceMove(src)
				if(ismob(thing))
					to_chat(thing, span_filter_notice("As [T] melts away around you, you find yourself in [hound]'s [name]."))
	for(var/obj/item/I in contents_of(T))
		if(istype(I,/obj/item/organ/internal/mmi_holder/posibrain))
			var/obj/item/organ/internal/mmi_holder/MMI = I
			var/atom/movable/brain = MMI.removed()
			if(brain)
				hound.remove_from_mob(brain,src)
				brain.forceMove(src)
				rel_add(src, nameof(items_preserved), brain)
		else
			T.drop_from_inventory(I, src)
	var/volume = 0
	if(ishuman(T))
		var/mob/living/carbon/human/Prey = T
		volume = (Prey.bloodstr.total_volume + Prey.ingested.total_volume + Prey.touching.total_volume + Prey.weight) * Prey.size_multiplier
	if(water)
		water.add_charge(volume)
	if(T.reagents)
		volume = T.reagents.total_volume
		if(water)
			water.add_charge(volume)
	if(T.ckey)
		GLOB.prey_digested_roundstat++
	if(patient == T)
		patient_laststat = null
		rel_clear(src, nameof(patient))
	T.mind?.vore_death = TRUE
	dissolved(T)

/// Digest (or preserve) one loose item or remains.
/obj/item/dogborg/sleeper/proc/digest_loose_item(atom/target)
	//Handle the target being anything but a /mob/living
	var/obj/item/T = target
	if(istype(T))
		var/volume = 0
		if(T.reagents)
			volume = T.reagents.total_volume
		var/is_trash = istype(T, /obj/item/trash)
		var/digested = T.digest_act(item_storage = src)
		if(!digested)
			rel_add(src, nameof(items_preserved), T)
		else
			if(volume && water)
				water.add_charge(volume)
			var/list/item_matter = T.material_totals()
			if(recycles && length(item_matter))
				for(var/material in item_matter)
					var/total_material = item_matter[material]
					if(istype(T,/obj/item/stack))
						var/obj/item/stack/stack = T
						total_material *= stack.get_amount()
					if(material == MAT_STEEL && metal)
						metal.add_charge(total_material)
					if(material == MAT_GLASS && glass)
						glass.add_charge(total_material)
					if(decompiler)
						if(material == MAT_PLASTIC && plastic)
							plastic.add_charge(total_material)
						if(material == MAT_WOOD && wood)
							wood.add_charge(total_material)
			var/datum/experiment_handler/handler = get_experiment_handler()
			if(analyzer && handler)
				techweb_item_generate_points(T, handler.linked_web())
				PUBLISH_LEGACY(src, /datum/notice/machinery_destructive_scan, T)
			if(is_trash)
				hound.adjust_nutrition(digested)
			else
				hound.adjust_nutrition(5 * digested)  //drain(-50 * digested)
	else if(istype(target,/obj/effect/decal/remains))
		dissolved(target, src)
		hound.adjust_nutrition(10) //drain(-100)
	else
		rel_add(src, nameof(items_preserved), target)

/obj/item/dogborg/sleeper/proc/sleeper_step(datum/act/A)
	if(!istype(src.loc,/mob/living/silicon/robot))
		return

	if(cleaning) //We're cleaning, return early after calling this as we don't care about the patient.
		clean_cycle()
		return

	if(patient && stabilizer) //We're caring for the patient. Medical emergency! Or endo scene.
		update_patient()
		if(patient.is_critical())
			patient.mend(TREAT_OXYGENATION, 1) //Heal some oxygen damage if they're in critical condition
			drain()
		patient.status_adjust(STAT_STUNNED, -4)
		patient.status_adjust(STAT_WEAKENED, -4)
		drain(1)
		return

	if(!patient && !cleaning) //We think we're done working.
		if(!update_patient()) //One last try to find someone
			set_working(FALSE)
			return

/obj/item/dogborg/sleeper/proc/get_experiment_handler()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	RETURN_TYPE(/datum/experiment_handler)
	if(!analyzer)
		return null
	return experiment_handler

#undef SLEEPER_INJECT_COST
#undef DOGBORG_DIGEST_MAX_CATCHUP

/obj/item/dogborg/sleeper/muffles_death_of(mob/occupant)
	return TRUE
