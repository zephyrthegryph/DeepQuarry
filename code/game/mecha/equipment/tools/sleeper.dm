/obj/item/mecha_parts/mecha_equipment/tool/sleeper
	name = "mounted sleeper"
	desc = "A sleeper. Mountable to an exosuit. (Can be attached to: Medical Exosuits)"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeper_0"
	energy_drain = 20
	range = MECH_MELEE
	equip_cooldown = 30
	mech_flags = EXOSUIT_MODULE_MEDICAL
	var/inject_amount = 5
	required_type = list(/obj/mecha/medical)
	salvageable = 0
	allow_duplicate = TRUE

/// Life support is engaged on a loaded occupant.
OM_FIELD(/obj/item/mecha_parts/mecha_equipment/tool/sleeper, sustaining, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/mecha_parts/mecha_equipment/tool/sleeper, PERIODIC_SECOND, "sustaining")

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/mecha_sleeper
	holder = /obj/item/mecha_parts/mecha_equipment/tool/sleeper
	slot_id = OCCUPANT_SLOT_MECHA_SLEEPER
	name = "mounted sleeper"


/obj/item/mecha_parts/mecha_equipment/tool/sleeper/Exit(atom/movable/O)
	return 0

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/action(mob/living/carbon/human/target)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!action_checks(target))
		return
	if(!istype(target))
		return
	if(target?.buckled_to())
		occupant_message(span_infoplain("[target] will not fit into the sleeper because they are buckled to [target?.buckled_to()]."))
		return
	if(occupant)
		occupant_message(span_warning("The sleeper is already occupied"))
		return
	if(target.has_buckled_mobs())
		occupant_message(span_warning("\The [target] has other entities attached to it. Remove them first."))
		return
	occupant_message(span_infoplain("You start putting [target] into [src]."))
	chassis.visible_message(span_infoplain("[chassis] starts putting [target] into the [src]."))
	var/C = chassis.loc
	var/T = target.loc
	if(do_after_cooldown(target))
		if(chassis.loc!=C || target.loc!=T)
			return
		if(occupant)
			occupant_message(span_boldwarning("The sleeper is already occupied!"))
			return
		if(!move_into(src, OCCUPANT_SLOT_MECHA_SLEEPER, target))
			return
		occupant.set_stasis(/datum/body_effect/stasis/moderate, src)
		set_ready_state(FALSE)
		set_sustaining(TRUE)
		occupant_message(span_notice("[target] successfully loaded into [src]. Life support functions engaged."))
		chassis.visible_message(span_infoplain("[chassis] loads [target] into [src]."))
		src.mecha_log_message("[target] loaded. Life support functions engaged.")
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/go_out()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!occupant)
		return
	occupant_message(span_infoplain("[occupant] ejected. Life support functions disabled."))
	src.mecha_log_message("[occupant] ejected. Life support functions disabled.")
	occupant.set_stasis(null, src)
	slot_remove(occupant, get_turf(src))
	set_sustaining(FALSE)
	set_ready_state(TRUE)
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/detach()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(occupant)
		occupant_message(span_infoplain("Unable to detach [src] - equipment occupied."))
		return
	return ..()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/get_equip_info()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	var/output = ..()
	if(output)
		var/temp = ""
		if(occupant)
			temp = "<br />\[Occupant: [occupant] (Health: [round(occupant.vitality()*100)]%)\]<br /><a href='byond://?src=\ref[src];view_stats=1'>View stats</a>|<a href='byond://?src=\ref[src];eject=1'>Eject</a>"
		return "[output] [temp]"
	return

// TGUI migration. The view_stats sub-window (formerly
// browse()) now opens MechaSleeper.tsx; inject/eject move to tgui_act.
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/sleeper, "eject", PROC_REF(topic_eject))
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/sleeper, "view_stats", PROC_REF(topic_view_stats))
TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/sleeper, "inject", PROC_REF(topic_inject), TOPIC_REF("inject", /datum/reagent, PROC_REF(topic_injectable_pool)), TOPIC_REF("source", /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, PROC_REF(topic_chassis_equipment)))

/// TOPIC_REF source: the equipment on the same exosuit.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/topic_chassis_equipment()
	return chassis?.equipment

/// TOPIC_REF source: the reagents held by the syringe guns on the same exosuit.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/topic_injectable_pool()
	var/list/pool = list()
	for(var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG in chassis?.equipment)
		if(SG.reagents)
			pool += SG.reagents.reagent_list
	return pool

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/topic_eject(mob/user, list/args)
	go_out()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/topic_view_stats(mob/user, list/args)
	tgui_interact(user)

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/topic_inject(mob/user, list/args)
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = args["source"]
	var/datum/reagent/R = args["inject"]
	if(!SG || !R || !(R in SG.reagents?.reagent_list))
		return
	inject_reagent(R, SG)

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/sleeper)
	interface("MechaSleeper", title = "Mounted Sleeper")
	without("ui_open")
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("inject", ui_act("inject", arg("ref", schema_ref(/datum/reagent)), arg("source", schema_ref(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun))), then(PROC_REF(ui_act_inject)))

/// /obj/item/mecha_parts/mecha_equipment/tool/sleeper's window data.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/ui_data(datum/act/eval/A)
	var/mob/living/carbon/human/occupant = slot_item_real(OCCUPANT_SLOT_MECHA_SLEEPER)
	var/list/data = list()
	data["has_occupant"] = occupant ? 1 : 0
	if(!occupant)
		data["occupant_name"] = ""
		data["status"] = ""
		data["health_percent"] = 0
		data["diagnosis"] = null
		data["body_temp_c"] = 0
		data["body_temp_f"] = 0
		data["reagents"] = list()
		data["injectables"] = list()
		return data
	data["occupant_name"] = occupant.name
	switch(occupant.stat)
		if(0)
			data["status"] = "Conscious"
		if(1)
			data["status"] = "Unconscious"
		if(2)
			data["status"] = "*dead*"
		else
			data["status"] = "Unknown"
	data["health_percent"] = round(occupant.vitality()*100)
	var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
	data["diagnosis"] = D?.report_data()
	spent(D)
	data["body_temp_c"] = round(occupant.body_temperature() - T0C, 0.1)
	data["body_temp_f"] = round(occupant.body_temperature() * 1.8 - 459.67, 0.1)
	var/list/rlist = list()
	if(occupant.reagents)
		for(var/datum/reagent/R in occupant.reagents.reagent_list)
			if(R.volume > 0)
				rlist += list(list("name" = "[R]", "volume" = round(R.volume, 0.01)))
	data["reagents"] = rlist
	var/list/inj = list()
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate_within(chassis, /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun)
	if(SG?.reagents && islist(SG.reagents.reagent_list))
		for(var/datum/reagent/R in SG.reagents.reagent_list)
			if(R.volume > 0)
				inj += list(list(
					"ref" = "\ref[R]",
					"source_ref" = "\ref[SG]",
					"name" = R.name,
				))
	data["injectables"] = inj
	return data

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/ui_act_eject(datum/act/op/A)
	go_out()
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/ui_act_inject(datum/act/op/A, ref, source)
	if(isnull(ref))
		return FALSE
	if(isnull(source))
		return FALSE
	var/datum/reagent/R = ref
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = source
	if(R && SG)
		inject_reagent(R, SG)
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_occupant_stats()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!occupant)
		return
	return {"<html>
				<head>
				<title>[occupant] statistics</title>
				<script language='javascript' type='text/javascript'>
				[JS_BYJAX]
				</script>
				<style>
				h3 {margin-bottom:2px;font-size:14px;}
				#lossinfo, #reagents, #injectwith {padding-left:15px;}
				</style>
				</head>
				<body>
				<h3>Health statistics</h3>
				<div id="lossinfo">
				[get_occupant_dam()]
				</div>
				<h3>Reagents in bloodstream</h3>
				<div id="reagents">
				[get_occupant_reagents()]
				</div>
				<div id="injectwith">
				[get_available_reagents()]
				</div>
				</body>
				</html>"}

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_occupant_dam()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	var/t1
	switch(occupant.stat)
		if(0)
			t1 = "Conscious"
		if(1)
			t1 = "Unconscious"
		if(2)
			t1 = "*dead*"
		else
			t1 = "Unknown"
	var/text = ""
	var/vitality_pct = round(occupant.vitality()*100)
	var/entry = span_bold("Health:") + " [vitality_pct]% ([t1])"
	text += vitality_pct > 50 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	var/mob/living/_tmp_occ_4 = src?.slot_item(MECHA_SLOT_PILOT)
	entry = span_bold("Core Temperature:") + " [_tmp_occ_4.body_temperature()-T0C]&deg;C ([_tmp_occ_4.body_temperature()*1.8-459.67]&deg;F)"
	text += occupant.body_temperature() > 50 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
	if(D)
		text += D.render_chat()
		text += "<br />"
		spent(D)

	return text

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_occupant_reagents()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(occupant.reagents)
		for(var/datum/reagent/R in occupant.reagents.reagent_list)
			if(R.volume > 0)
				. += "[R]: [round(R.volume,0.01)]<br />"
	return . || "None"

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_available_reagents()
	var/output
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun) in chassis.slot_contents()
	if(SG && SG.reagents && islist(SG.reagents.reagent_list))
		for(var/datum/reagent/R in SG.reagents.reagent_list)
			if(R.volume > 0)
				output += "<a href=\"?src=\ref[src];inject=\ref[R];source=\ref[SG]\">Inject [R.name]</a><br />"
	return output


/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/inject_reagent(datum/reagent/R,obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!R || !occupant || !SG || !(SG in chassis.equipment))
		return 0
	var/to_inject = min(R.volume, inject_amount)
	if(to_inject && occupant.reagents.get_reagent_amount(R.id) + to_inject > inject_amount*4)
		occupant_message(span_warning("Sleeper safeties prohibit you from injecting more than [inject_amount*4] units of [R.name]."))
	else
		occupant_message(span_notice("Injecting [occupant] with [to_inject] units of [R.name]."))
		src.mecha_log_message("Injecting [occupant] with [to_inject] units of [R.name].")
		SG.reagents.remove_reagent(R.id,to_inject)
		occupant.reagents.add_reagent(R.id,to_inject)
		update_equip_info()
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/update_equip_info()
	if(..())
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"msleeper.browser","lossinfo",get_occupant_dam())
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"msleeper.browser","reagents",get_occupant_reagents())
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"msleeper.browser","injectwith",get_available_reagents())
		return 1
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/container_resist(mob/living)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(occupant == living)
		eject()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/verb/eject()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	set name = "Sleeper Eject"
	set category = VERB_CAT_EXOSUIT_INTERFACE
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src?.slot_item(MECHA_SLOT_PILOT) || usr.stat == 2)
		return
	to_chat(usr,span_notice("Release sequence activated. This will take one minute."))
	after(src, 1 MINUTE, PROC_REF(release_sequence_done), with = list(occupant))

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/release_sequence_done(mob/living/carbon/human/occupant)
	if(occupant != src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)) //Check if someone's released/replaced/bombed him already
		return
	go_out()//and release him from the eternal prison.

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/periodic_step()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	..()
	if(!chassis)
		set_ready_state(TRUE)
		return PROCESS_KILL
	if(!chassis.has_charge(energy_drain))
		set_ready_state(TRUE)
		src.mecha_log_message("Deactivated.")
		occupant_message(span_infoplain("[src] deactivated - no power."))
		return PROCESS_KILL
	var/mob/living/carbon/M = occupant
	if(!M)
		return
	if(!M.is_critical())
		M.mend(TREAT_OXYGENATION, 1)
	M.status_adjust(EFFECT_STUNNED, -4)
	M.status_adjust(EFFECT_WEAKENED, -4)
	M.status_adjust(EFFECT_STUNNED, -4)
	M.status_at_least(EFFECT_PARALYZED, 2)
	M.status_at_least(EFFECT_WEAKENED, 2)
	M.status_at_least(EFFECT_STUNNED, 2)
	if(M.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) < 5)
		M.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 5)
	chassis.use_power(energy_drain)
	update_equip_info()
	return
