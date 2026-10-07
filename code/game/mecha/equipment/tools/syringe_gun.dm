/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun
	name = "syringe gun"
	desc = "Exosuit-mounted chem synthesizer with syringe gun. Reagents inside are held in stasis, so no reactions will occur. (Can be attached to: Medical Exosuits)"
	mech_flags = EXOSUIT_MODULE_MEDICAL
	icon = 'icons/obj/gun.dmi'
	icon_state = "syringegun"
	var/list/syringes
	var/list/known_reagents
	var/max_syringes = 10
	var/max_volume = 75 //max reagent volume
	var/synth_speed = 5 //[num] reagent units per cycle
	energy_drain = 10
	var/mode = 0 //0 - fire syringe, 1 - analyze reagents.
	range = MECH_MELEE|RANGED
	equip_cooldown = 10
	required_type = list(/obj/mecha/medical)

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun)
	reagents(nameof(max_volume))
	owns_many(nameof(syringes), /obj/item/reagent_containers/syringe)
	interface("MechaSyringeGun")
	without("ui_open")
	op("select_reagents", ui_act("select_reagents", arg("reagents")), then(PROC_REF(ui_act_select_reagents)))
	op("purge_reagent", ui_act("purge_reagent", arg("id", schema_text(4096))), then(PROC_REF(ui_act_purge_reagent)))
	op("purge_all", ui_act("purge_all"), then(PROC_REF(ui_act_purge_all)))

/// Reagent ids selected for synthesis. Replaced whole (never mutated in place) so the setter raises.
OM_FIELD_TYPED(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, list, processed_reagents, null, CHANGE_EXPLICIT)
OM_DERIVE_FIELD(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, synthesizing, list("chassis", "processed_reagents"))
DECLARE_PERIODIC_WHILE(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, PERIODIC_FAST, "synthesizing")

/// Derived field: mounted with reagents selected for synthesis.
/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/synthesizing()
	return chassis && length(processed_reagents)

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/Initialize(mapload)
	. = ..()
	flags |= NOREACT
	rel_take_all(src, nameof(syringes))
	known_reagents = list(REAGENT_ID_INAPROVALINE=REAGENT_INAPROVALINE,REAGENT_ID_ANTITOXIN=REAGENT_ANTITOXIN)
	set_processed_reagents(list())

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/critfail()
	..()
	flags &= ~NOREACT
	return

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/get_equip_info()
	var/output = ..()
	if(output)
		return "[output] \[<a href=\"?src=\ref[src];toggle_mode=1\">[mode? "Analyze" : "Launch"]</a>\]<br />\[Syringes: [length(syringes)]/[max_syringes] | Reagents: [reagents.total_volume]/[reagents.maximum_volume]\]<br /><a href='byond://?src=\ref[src];show_reagents=1'>Reagents list</a>"
	return

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/action(atom/movable/target)
	if(!action_checks(target))
		return
	if(istype(target,/obj/item/reagent_containers/syringe))
		return load_syringe(target)
	if(istype(target,/obj/item/storage))//Loads syringes from boxes
		var/obj/item/storage/box = target
		for(var/obj/item/reagent_containers/syringe/S in box.slot_contents())
			load_syringe(S)
		return
	if(mode)
		return analyze_reagents(target)
	if(!length(syringes))
		occupant_message(span_warning("No syringes loaded."))
		return
	if(reagents.total_volume<=0)
		occupant_message(span_warning("No available reagents to load syringe with."))
		return
	set_ready_state(FALSE)
	chassis.use_power(energy_drain)
	var/turf/trg = get_turf(target)
	var/obj/item/reagent_containers/syringe/S = syringes[1]
	S.forceMove(get_turf(chassis))
	reagents.trans_to_obj(S, min(S.volume, reagents.total_volume))
	own_take_member(src, nameof(syringes), S)
	S.icon = 'icons/obj/chemical.dmi'
	S.icon_state = "syringeproj"
	play_sfx(src, SFX_ITEMS_SYRINGEPROJ)
	src.mecha_log_message("Launched [S] from [src], targeting [target].")
	S.mech_syringe_flight(trg, 6) // the syringe's own clock: it flies on if the gun is deleted
	do_after_cooldown()
	return 1


// The legacy reagent-selection form is gone (MechaSyringeGun.tsx selects via tgui_act).
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, "toggle_mode", PROC_REF(topic_toggle_mode))
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, "show_reagents", PROC_REF(topic_show_reagents))
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, "purge_reagent", PROC_REF(topic_purge_reagent), TOPIC_TEXT("purge_reagent", 64))
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, "purge_all", PROC_REF(topic_purge_all))

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/topic_toggle_mode(mob/user, list/args)
	mode = !mode
	update_equip_info()

// TGUI: structured reagent management UI (MechaSyringeGun.tsx).
/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/topic_show_reagents(mob/user, list/args)
	tgui_interact(user)

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/topic_purge_reagent(mob/user, list/args)
	var/reagent = args["purge_reagent"]
	if(reagent)
		reagents.del_reagent(reagent)

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/topic_purge_all(mob/user, list/args)
	reagents.clear_reagents()

// structured TGUI for syringe-gun reagent management.

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/ui_title(mob/user)
	return "[name] Reagents"

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["synth_speed"] = synth_speed
	var/list/merged_1 = ui_data_obj_item_mecha_parts_mecha_equipment_tool_syringe_gun(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun's window data.
/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/ui_data_obj_item_mecha_parts_mecha_equipment_tool_syringe_gun(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["total_volume"] = round(reagents?.total_volume || 0, 0.001)
	data["max_volume"] = reagents?.maximum_volume || 0
	var/list/known = list()
	for(var/reagent_id in known_reagents)
		known += list(list(
			"id" = reagent_id,
			"name" = known_reagents[reagent_id],
			"selected" = (reagent_id in processed_reagents),
		))
	data["known_reagents"] = known
	var/list/current = list()
	if(reagents)
		for(var/datum/reagent/R in reagents.reagent_list)
			if(R.volume > 0)
				current += list(list(
					"id" = R.id,
					"name" = "[R]",
					"volume" = round(R.volume, 0.001),
				))
	data["current_reagents"] = current
	return data

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/ui_act_select_reagents(datum/act/op/A, reagents)
	if(!isnull(reagents) && !islist(reagents))
		return FALSE
	var/list/picks = reagents
	var/list/selected = list()
	var/m = 0
	for(var/reagent_id in picks)
		if(m >= synth_speed)
			break
		if(reagent_id in known_reagents)
			selected += reagent_id
			m++
	set_processed_reagents(selected)
	if(processed_reagents.len)
		occupant_message("Reagent processing started.")
		src.mecha_log_message("Reagent processing started.")
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/ui_act_purge_reagent(datum/act/op/A, id)
	if(id)
		reagents.del_reagent(id)
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/ui_act_purge_all(datum/act/op/A)
	reagents.clear_reagents()
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/get_reagents_page()
	var/output = {"<html>
						<head>
						<title>Reagent Synthesizer</title>
						<script language='javascript' type='text/javascript'>
						[JS_BYJAX]
						</script>
						<style>
						h3 {margin-bottom:2px;font-size:14px;}
						#reagents, #reagents_form {}
						form {width: 90%; margin:10px auto; border:1px dotted #999; padding:6px;}
						#submit {margin-top:5px;}
						</style>
						</head>
						<body>
						<h3>Current reagents:</h3>
						<div id="reagents">
						[get_current_reagents()]
						</div>
						<h3>Reagents production:</h3>
						<div id="reagents_form">
						[get_reagents_form()]
						</div>
						</body>
						</html>
						"}
	return output

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/get_reagents_form()
	var/r_list = get_reagents_list()
	var/inputs
	if(r_list)
		inputs += "<input type=\"hidden\" name=\"src\" value=\"\ref[src]\">"
		inputs += "<input type=\"hidden\" name=\"select_reagents\" value=\"1\">"
		inputs += "<input id=\"submit\" type=\"submit\" value=\"Apply settings\">"
	var/output = {"<form action="byond://" method="get">
						[r_list || "No known reagents"]
						[inputs]
						</form>
						[r_list? "<span style=\"font-size:80%;\">Only the first [synth_speed] selected reagent\s will be added to production</span>" : null]
						"}
	return output

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/get_reagents_list()
	var/output
	for(var/i=1 to known_reagents.len)
		var/reagent_id = known_reagents[i]
		output += {"<input type="checkbox" value="[reagent_id]" name="reagent_[i]" [(reagent_id in processed_reagents)? "checked=\"1\"" : null]> [known_reagents[reagent_id]]<br />"}
	return output

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/get_current_reagents()
	var/output
	for(var/datum/reagent/R in reagents.reagent_list)
		if(R.volume > 0)
			output += "[R]: [round(R.volume,0.001)] - <a href=\"?src=\ref[src];purge_reagent=[R.id]\">Purge Reagent</a><br />"
	if(output)
		output += "Total: [round(reagents.total_volume,0.001)]/[reagents.maximum_volume] - <a href=\"?src=\ref[src];purge_all=1\">Purge All</a>"
	return output || "None"

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/load_syringe(obj/item/reagent_containers/syringe/S)
	if(length(syringes) < max_syringes)
		if(get_dist(src,S) >= 2)
			occupant_message("The syringe is too far away.")
			return 0
		for(var/obj/structure/D in S.loc)//Basic level check for structures in the way (Like grilles and windows)
			if(!(D.CanPass(S,src.loc)))
				occupant_message("Unable to load syringe.")
				return 0
		for(var/obj/machinery/door/D in S.loc)//Checks for doors
			if(!(D.CanPass(S,src.loc)))
				occupant_message("Unable to load syringe.")
				return 0
		S.reagents.trans_to_obj(src, S.reagents.total_volume)
		S.forceMove(src)
		own_move(S, src, nameof(syringes))
		occupant_message("Syringe loaded.")
		update_equip_info()
		return 1
	occupant_message("The [src] syringe chamber is full.")
	return 0

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/analyze_reagents(atom/A)
	if(get_dist(src,A) >= 4)
		occupant_message("The object is too far away.")
		return 0
	if(!A.reagents || istype(A,/mob))
		occupant_message(span_warning("No reagent info gained from [A]."))
		return 0
	occupant_message("Analyzing reagents...")
	// Block Edit - Start
	for(var/datum/reagent/R in A.reagents.reagent_list)
		if(R.id in known_reagents)
			occupant_message("Reagent \"[R.name]\" already present in database, skipping.")
		else if(R.reagent_state == 2 && add_known_reagent(R.id,R.name))
			occupant_message("Reagent analyzed, identified as [R.name] and added to database.")
			send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"msyringegun.browser","reagents_form",get_reagents_form())
		else
			occupant_message("Reagent \"[R.name]\" unable to be scanned, skipping.")
	//VOREstation Block Edit - End
	occupant_message("Analysis complete.")
	return 1

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/proc/add_known_reagent(r_id,r_name)
	set_ready_state(FALSE)
	do_after_cooldown()
	if(!(r_id in known_reagents))
		known_reagents += r_id
		known_reagents[r_id] = r_name
		return 1
	return 0


/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/update_equip_info()
	if(..())
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"msyringegun.browser","reagents",get_current_reagents())
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"msyringegun.browser","reagents_form",get_reagents_form())
		return 1
	return

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/on_reagent_change()
	..()
	update_equip_info()
	return

/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/periodic_step()
	if(!processed_reagents.len || reagents.total_volume >= reagents.maximum_volume || !chassis.has_charge(energy_drain))
		occupant_message(span_warning("Reagent processing stopped."))
		src.mecha_log_message("Reagent processing stopped.")
		return PROCESS_KILL
	var/amount = synth_speed / processed_reagents.len
	for(var/reagent in processed_reagents)
		reagents.add_reagent(reagent,amount)
		chassis.use_power(energy_drain)

/obj/item/mecha_parts/mecha_equipment/crisis_drone
	name = "crisis dronebay"
	desc = "A small shoulder-mounted dronebay containing a rapid response drone capable of moderately stabilizing a patient near the exosuit."
	icon_state = "mecha_dronebay"
	range = MECH_MELEE|RANGED
	equip_cooldown = 3 SECONDS
	required_type = list(/obj/mecha/medical)

	var/droid_state = "med_droid"

	var/beam_state = "medbeam"

	var/enabled = FALSE

	var/icon/drone_overlay

	var/max_distance = 3

	/// Only patients whose field triage demand for one of the drone's tags is
	/// at least this urgent (_dq_band_rank: 1 minor .. 4 critical) are treated.
	var/min_urgency = 2
	var/heal_dead = FALSE	// Does this device heal the dead?

	var/rad_heal = 0		// Radiation purged per tick while treating.
	var/bone_heal = 0	// Percent chance it will heal a broken bone. this does not mean 'make it not instantly re-break'.

	var/mob/living/Target = null
	var/datum/beam/MyBeam = null

	equip_type = EQUIP_HULL

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/crisis_drone)
	owns_one(nameof(MyBeam), /datum/beam)

/// Jammed by a critical failure: the drone stays down until it is detached (and so reset).
OM_FIELD(/obj/item/mecha_parts/mecha_equipment/crisis_drone, jammed, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE_ALL(/obj/item/mecha_parts/mecha_equipment/crisis_drone, PERIODIC_SLOW, list("chassis", "!jammed"))

/obj/item/mecha_parts/mecha_equipment/crisis_drone/Initialize(mapload)
	. = ..()
	drone_overlay = new(src.icon, icon_state = droid_state)

/obj/item/mecha_parts/mecha_equipment/crisis_drone/detach(atom/moveto=null)
	shut_down()
	. = ..(moveto)
	set_jammed(FALSE)

/obj/item/mecha_parts/mecha_equipment/crisis_drone/critfail()
	. = ..()
	set_jammed(TRUE)
	shut_down()
	if(chassis && chassis?.slot_item(MECHA_SLOT_PILOT))
		to_chat(chassis?.slot_item(MECHA_SLOT_PILOT), span_notice("\The [chassis] shudders as something jams!"))
		src.mecha_log_message("[src.name] has malfunctioned. Maintenance required.")

/// What the drone treats: TREAT_* -> amount mended per tick, applied only to
/// the tags the patient's field triage demands.
TYPE_TABLE_DECLARE(/obj/item/mecha_parts/mecha_equipment/crisis_drone, drone_treatment_tags, list( \
		TREAT_TISSUE_REPAIR = 0.5, \
		TREAT_HEMOSTATIC = 0.5, \
		TREAT_PLATING_REPAIR = 0.5, \
		TREAT_BURN_CARE = 0.5, \
		TREAT_WIRING_REPAIR = 0.5, \
		TREAT_ANTITOXIN = 0.5, \
		TREAT_OXYGENATION = 1, \
		TREAT_ANALGESIC = 0.2, \
	))

/obj/item/mecha_parts/mecha_equipment/crisis_drone/periodic_step()	// Will continually try to find the patient most urgently in need of what the drone treats, and try to heal them.
	if(chassis && enabled && chassis.has_charge(energy_drain) && (chassis?.slot_item(MECHA_SLOT_PILOT) || enable_special))
		var/target_urgency = 0

		if(!valid_target(Target))
			rel_clear(src, nameof(Target))

		if(Target)
			target_urgency = treatable_urgency(Target)

		for(var/mob/living/Potential in viewers(max_distance, chassis))
			if(!valid_target(Potential))
				continue

			var/urgency = treatable_urgency(Potential)

			if(urgency > target_urgency)
				rel_set(src, nameof(Target), Potential)
				target_urgency = urgency

		if(MyBeam && !valid_target(MyBeam.target()))
			rel_clear(src, nameof(MyBeam))

		if(Target)
			if(MyBeam && MyBeam.target() != Target)
				rel_clear(src, nameof(MyBeam))

			if(valid_target(Target))
				if(!MyBeam)
					rel_set(src, nameof(MyBeam), chassis.Beam(Target,icon='icons/effects/beam.dmi',icon_state=beam_state,time=3 SECONDS,maxdistance=max_distance,beam_type = /obj/effect/ebeam,beam_sleep_time=2))
				heal_target(Target)

	else
		shut_down()

/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/valid_target(mob/living/L)
	. = TRUE

	if(!L || !istype(L))
		return FALSE

	if(get_dist(L, src) > max_distance)
		return FALSE

	if(!(L in viewers(max_distance, chassis)))
		return FALSE

	if(!unique_patient_checks(L))
		return FALSE

	if(L.stat == DEAD && !heal_dead)
		return FALSE

	if(treatable_urgency(L) < min_urgency)
		return FALSE

/// The patient's field triage demand, as seen by the drone.
/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/patient_demand(mob/living/L)
	return L.treatment_demand(/datum/diagnostic_profile/automation/field)

/// How urgently L needs something this drone treats (_dq_band_rank, 0 = nothing).
/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/treatable_urgency(mob/living/L)
	return demand_urgency(patient_demand(L), TYPE_TABLE_GET(src, drone_treatment_tags))

/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/shut_down()
	if(enabled)
		chassis.visible_message(span_notice("\The [chassis]'s [src] buzzes as its drone returns to port."))
		toggle_drone()
	if(!isnull(Target))
		rel_clear(src, nameof(Target))
	if(MyBeam)
		rel_clear(src, nameof(MyBeam))

/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/unique_patient_checks(mob/living/L)	// Anything special for subtypes. Does it only work on Robots? Fleshies? A species?
	. = TRUE

/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/heal_target(mob/living/L)	// We've done all our special checks, just get to fixing damage.
	chassis.use_power(energy_drain)
	if(istype(L))
		var/list/demand = patient_demand(L)
		var/list/tags = TYPE_TABLE_GET(src, drone_treatment_tags)
		for(var/tag in tags)
			if(demand?[tag])
				L.mend(tag, tags[tag])
		if(rad_heal)
			L.purge_radiation(rad_heal)

		if(ishuman(L) && bone_heal)
			var/mob/living/carbon/human/H = L

			if(length(H.damaged_limbs()))
				for(var/obj/item/organ/external/E in H.damaged_limbs())
					if(prob(bone_heal))
						E.mend_fracture()

/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/toggle_drone()
	if(chassis)
		enabled = !enabled
		if(enabled)
			set_ready_state(FALSE)
			src.mecha_log_message("Activated.")
		else
			set_ready_state(TRUE)
			src.mecha_log_message("Deactivated.")

/obj/item/mecha_parts/mecha_equipment/crisis_drone/add_equip_overlay(obj/mecha/M as obj)
	..()
	if(enabled)
		M.add_overlay(drone_overlay)
	return

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/crisis_drone, "toggle_drone", PROC_REF(topic_toggle_drone))

/obj/item/mecha_parts/mecha_equipment/crisis_drone/proc/topic_toggle_drone(mob/user, list/args)
	toggle_drone()
	return

/obj/item/mecha_parts/mecha_equipment/crisis_drone/get_equip_info()
	if(!chassis) return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[src.name] - <a href='byond://?src=\ref[src];toggle_drone=1'>[enabled?"Dea":"A"]ctivate</a>"

/obj/item/mecha_parts/mecha_equipment/crisis_drone/rad
	name = "hazmat dronebay"
	desc = "A small shoulder-mounted dronebay containing a rapid response drone capable of purging a patient near the exosuit of radiation damage."
	icon_state = "mecha_dronebay_rad"

	droid_state = "rad_drone"
	beam_state = "g_beam"

	rad_heal = 5

TYPE_TABLE(/obj/item/mecha_parts/mecha_equipment/crisis_drone/rad, drone_treatment_tags, list( \
		TREAT_ANTITOXIN = 0.5, \
		TREAT_ANTIRADIATION = 1, \
		TREAT_GENETIC_REPAIR = 0.2, \
		TREAT_ANALGESIC = 0.2, \
	))

/obj/item/mecha_parts/mecha_equipment/tool/powertool/medanalyzer
	name = "mounted humanoid scanner"
	desc = "An exosuit-mounted scanning device."
	icon_state = "mecha_analyzer_health"
	equip_cooldown = 5 SECONDS
	energy_drain = 100
	range = MECH_MELEE
	equip_type = EQUIP_UTILITY
	ready_sound = SFX_WEAPONS_FLASH
	required_type = list(/obj/mecha/medical)

	tooltype = /obj/item/healthanalyzer/advanced

/// A syringe fired from an exosuit syringe gun: a step a tick toward `trg`, for up to `steps_left`
/// steps, injecting the first carbon mob it lands on.
/obj/item/reagent_containers/syringe/proc/mech_syringe_flight(turf/trg, steps_left)
	if(steps_left <= 0)
		return
	if(!step_towards(src, trg))
		icon_state = initial(icon_state)
		icon = initial(icon)
		update_icon()
		return
	var/list/mobs = list()
	for(var/mob/living/carbon/M in contents_of(loc))
		mobs += M
	var/mob/living/carbon/M = safepick(mobs)
	if(M)
		icon_state = initial(icon_state)
		icon = initial(icon)
		reagents.trans_to_mob(M, reagents.total_volume, CHEM_BLOOD)
		M.injure(INJURY_PIERCE, 2, null, src)
		visible_message(span_attack("[M] was hit by the syringe!"))
		return
	if(loc == trg)
		icon_state = initial(icon_state)
		icon = initial(icon)
		update_icon()
		return
	after(src, 0.1 SECONDS, PROC_REF(mech_syringe_flight), with = list(trg, steps_left - 1))

