/obj/item/mecha_parts/mecha_equipment/tool/sleeper
	name = "mounted sleeper"
	desc = "A sleeper. Mountable to an exosuit. (Can be attached to: Medical Exosuits)"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeper_0"
	energy_drain = 20
	range = MECH_MELEE
	equip_cooldown = 30
	mech_flags = EXOSUIT_MODULE_MEDICAL
	var/mob/living/carbon/human/occupant = null
	var/inject_amount = 5
	required_type = list(/obj/mecha/medical)
	salvageable = 0
	allow_duplicate = TRUE

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/Destroy()
	for(var/atom/movable/AM in src)
		AM.forceMove(get_turf(src))
	return ..()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/Exit(atom/movable/O)
	return 0

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/action(mob/living/carbon/human/target)
	if(!action_checks(target))
		return
	if(!istype(target))
		return
	if(target.buckled)
		occupant_message(span_infoplain("[target] will not fit into the sleeper because they are buckled to [target.buckled]."))
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
		target.forceMove(src)
		occupant = target
		occupant.Stasis(3)
		set_ready_state(FALSE)
		START_PROCESSING(SSprocessing, src)
		occupant_message(span_notice("[target] successfully loaded into [src]. Life support functions engaged."))
		chassis.visible_message(span_infoplain("[chassis] loads [target] into [src]."))
		src.mecha_log_message("[target] loaded. Life support functions engaged.")
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/go_out()
	if(!occupant)
		return
	occupant.forceMove(get_turf(src))
	occupant_message(span_infoplain("[occupant] ejected. Life support functions disabled."))
	src.mecha_log_message("[occupant] ejected. Life support functions disabled.")
	occupant.Stasis(0)
	occupant = null
	STOP_PROCESSING(SSprocessing, src)
	set_ready_state(TRUE)
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/detach()
	if(occupant)
		occupant_message(span_infoplain("Unable to detach [src] - equipment occupied."))
		return
	STOP_PROCESSING(SSprocessing, src)
	return ..()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/get_equip_info()
	var/output = ..()
	if(output)
		var/temp = ""
		if(occupant)
			temp = "<br />\[Occupant: [occupant] (Health: [occupant.health]%)\]<br /><a href='byond://?src=\ref[src];view_stats=1'>View stats</a>|<a href='byond://?src=\ref[src];eject=1'>Eject</a>"
		return "[output] [temp]"
	return

// TGUI migration. The view_stats sub-window (formerly
// browse()) now opens MechaSleeper.tsx; inject/eject move to tgui_act.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/Topic(href, href_list)
	..()
	var/datum/topic_input/top_filter = new /datum/topic_input(href, href_list)
	if(top_filter.get("eject"))
		go_out()
		return
	if(top_filter.get("view_stats"))
		if(chassis?.occupant)
			tgui_interact(chassis.occupant)
		return
	if(top_filter.get("inject"))
		inject_reagent(top_filter.getType("inject", /datum/reagent), top_filter.getObj("source"))
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MechaSleeper", "Mounted Sleeper")
		ui.open()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/tgui_data(mob/user)
	var/list/data = list()
	data["has_occupant"] = occupant ? 1 : 0
	if(!occupant)
		data["occupant_name"] = ""
		data["status"] = ""
		data["health_percent"] = 0
		data["brute"] = 0
		data["oxy"] = 0
		data["tox"] = 0
		data["fire"] = 0
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
	data["health_percent"] = occupant.health
	data["brute"] = occupant.getBruteLoss()
	data["oxy"] = occupant.getOxyLoss()
	data["tox"] = occupant.getToxLoss()
	data["fire"] = occupant.getFireLoss()
	data["body_temp_c"] = round(occupant.bodytemperature - T0C, 0.1)
	data["body_temp_f"] = round(occupant.bodytemperature * 1.8 - 459.67, 0.1)
	var/list/rlist = list()
	if(occupant.reagents)
		for(var/datum/reagent/R in occupant.reagents.reagent_list)
			if(R.volume > 0)
				rlist += list(list("name" = "[R]", "volume" = round(R.volume, 0.01)))
	data["reagents"] = rlist
	var/list/inj = list()
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun) in chassis
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

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("eject")
			go_out()
			return TRUE
		if("inject")
			var/datum/reagent/R = locate(params["ref"])
			var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate(params["source"])
			if(R && SG)
				inject_reagent(R, SG)
			return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_occupant_stats()
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
	var/entry = span_bold("Health:") + " [occupant.health]% ([t1])"
	text += occupant.health > 50 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	entry = span_bold("Core Temperature:") + " [src.occupant.bodytemperature-T0C]&deg;C ([src.occupant.bodytemperature*1.8-459.67]&deg;F)"
	text += occupant.bodytemperature > 50 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	entry = span_bold("Brute Damage:") + " [occupant.getBruteLoss()]%"
	text += occupant.getBruteLoss() < 60 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	entry = span_bold("Respiratory Damage:") + " [occupant.getOxyLoss()]%"
	text += occupant.getOxyLoss() < 60 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	entry = span_bold("Toxin Content:") + " [occupant.getToxLoss()]%"
	text += occupant.getToxLoss() < 60 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	entry = span_bold("Burn Severity:") + " [occupant.getFireLoss()]%"
	text += occupant.getFireLoss() < 60 ? span_blue(entry) : span_red(entry)
	text += "<br />"

	return text

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_occupant_reagents()
	if(occupant.reagents)
		for(var/datum/reagent/R in occupant.reagents.reagent_list)
			if(R.volume > 0)
				. += "[R]: [round(R.volume,0.01)]<br />"
	return . || "None"

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/get_available_reagents()
	var/output
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun) in chassis
	if(SG && SG.reagents && islist(SG.reagents.reagent_list))
		for(var/datum/reagent/R in SG.reagents.reagent_list)
			if(R.volume > 0)
				output += "<a href=\"?src=\ref[src];inject=\ref[R];source=\ref[SG]\">Inject [R.name]</a><br />"
	return output


/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/inject_reagent(datum/reagent/R,obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG)
	if(!R || !occupant || !SG || !(SG in chassis.equipment))
		return 0
	var/to_inject = min(R.volume, inject_amount)
	if(to_inject && occupant.reagents.get_reagent_amount(R.id) + to_inject > inject_amount*4)
		occupant_message(span_warning("Sleeper safeties prohibit you from injecting more than [inject_amount*4] units of [R.name]."))
	else
		occupant_message(span_notice("Injecting [occupant] with [to_inject] units of [R.name]."))
		src.mecha_log_message("Injecting [occupant] with [to_inject] units of [R.name].")
		//SG.reagents.trans_id_to(occupant,R.id,to_inject)
		SG.reagents.remove_reagent(R.id,to_inject)
		occupant.reagents.add_reagent(R.id,to_inject)
		update_equip_info()
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/update_equip_info()
	if(..())
		send_byjax(chassis.occupant,"msleeper.browser","lossinfo",get_occupant_dam())
		send_byjax(chassis.occupant,"msleeper.browser","reagents",get_occupant_reagents())
		send_byjax(chassis.occupant,"msleeper.browser","injectwith",get_available_reagents())
		return 1
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/container_resist(mob/living)
	if(occupant == living)
		eject()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/verb/eject()
	set name = "Sleeper Eject"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant || usr.stat == 2)
		return
	to_chat(usr,span_notice("Release sequence activated. This will take one minute."))
	sleep(600)
	if(!src || !usr || !occupant || (occupant != usr)) //Check if someone's released/replaced/bombed him already
		return
	go_out()//and release him from the eternal prison.

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/process()
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
	if(M.health > 0)
		M.adjustOxyLoss(-1)
		M.updatehealth()
	M.AdjustStunned(-4)
	M.AdjustWeakened(-4)
	M.AdjustStunned(-4)
	M.Paralyse(2)
	M.Weaken(2)
	M.Stun(2)
	if(M.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) < 5)
		M.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 5)
	chassis.use_power(energy_drain)
	update_equip_info()
	return
