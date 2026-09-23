//
//Robotic Component Analyser, basically a health analyser for robots
//
/obj/item/robotanalyzer
	name = "cyborg analyzer"
	icon = 'icons/obj/device.dmi'
	icon_state = "robotanalyzer"
	item_state = "analyzer"
	desc = "A hand-held scanner able to diagnose robotic injuries."
	description_info = "Alt-click to toggle between robot analysis and robot module scan mode."
	slot_flags = SLOT_BELT
	throwforce = 3
	w_class = ITEMSIZE_SMALL
	throw_speed = 5
	throw_range = 10
	matter = list(MAT_STEEL = 500, MAT_GLASS = 200)
	var/mode = 1;
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/robotanalyzer/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	do_scan(M, user)
	return ITEM_INTERACT_SUCCESS

/obj/item/robotanalyzer/click_alt(mob/user)
	mode = !mode
	user.show_message(span_blue("[mode ? "Toggled to cyborg analyzing mode." : "Toggled to cyborg upgrade scan mode."]"), 1)

/obj/item/robotanalyzer/proc/do_scan(mob/living/M, mob/living/user)
	if(CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_red("You try to analyze the floor's vitals!"))
		for(var/mob/O in viewers(M, null))
			O.show_message(span_red(text("[user] has analyzed the floor's vitals!")), 1)
		user.show_message(span_blue("Cyborg analyzer results for the floor: no components detected."), 1)
		return

	var/scan_type
	if(isrobot(M))
		scan_type = "robot"
	else if(ishuman(M))
		scan_type = "prosthetics"
	else if(istype(M, /obj/mecha))
		scan_type = "mecha"
	else
		to_chat(user, span_red("You can't analyze non-robotic things!"))
		return

	user.visible_message(span_notice("\The [user] has analyzed [M]'s components."),span_notice("You have analyzed [M]'s components."))
	switch(scan_type)
		if("robot")
			if(mode)
				var/mob/living/silicon/robot/R = M
				render_diagnosis(R, user)
				var/obj/item/cell/cell = R.get_cell()
				if(cell)
					var/cell_charge = round(cell.percent())
					var/cell_text
					if(cell_charge > 60)
						cell_text = span_green("[cell_charge]")
					else if (cell_charge > 30)
						cell_text = span_yellow("[cell_charge]")
					else if (cell_charge > 10)
						cell_text = span_orange("[cell_charge]")
					else if (cell_charge > 1)
						cell_text = span_red("[cell_charge]")
					else
						cell_text = span_red(span_bold("[cell_charge]"))
					user.show_message("\t Power Cell Status: [span_blue("[capitalize(cell.name)]")] at [cell_text]% charge")
				if(R.emagged && prob(5))
					user.show_message(span_red("\t ERROR: INTERNAL SYSTEMS COMPROMISED"),1)
			else
				var/mob/living/silicon/robot/R = M
				var/obj/item/cell/cell = R.get_cell()
				user.show_message(span_blue("Upgrade Analyzing Results for [M]:"))
				if(cell)
					user.show_message("\t Power Cell Details: [span_blue("[capitalize(cell.name)]")] with a capacity of [cell.maxcharge] at [round(cell.percent())]% charge")
				var/show_title = TRUE
				for(var/datum/design_techweb/prosfab/robot_upgrade/utility/upgrade in SSresearch.techweb_designs)
					var/obj/item/borg/upgrade/utility/upgrade_type = initial(upgrade.build_path)
					var/needs_module = initial(upgrade_type.require_module)
					if((!R.module && needs_module) || !initial(upgrade.name) || (R.stat != DEAD && (upgrade_type == /obj/item/borg/upgrade/utility/restart)) || (isshell(R) && (upgrade_type == /obj/item/borg/upgrade/utility/rename)))
						continue
					if(show_title)
						user.show_message("\t Utility Modules, used for modifying purposes:")
						show_title = FALSE
					if(R.stat == DEAD)
						if(initial(upgrade.name) == "Emergency Restart Module")
							user.show_message(span_blue("\t\t [capitalize(initial(upgrade.name))]: [span_green("Usable")]"))
					else
						user.show_message(span_blue("\t\t [capitalize(initial(upgrade.name))]: [span_green("Usable")]"))
				show_title = TRUE
				for(var/datum/design_techweb/prosfab/robot_upgrade/basic/upgrade in SSresearch.techweb_designs)
					var/obj/item/borg/upgrade/basic/upgrade_type = initial(upgrade.build_path)
					var/needs_module = initial(upgrade_type.require_module)
					if((!R.module && needs_module) || !initial(upgrade.name) || R.stat == DEAD)
						continue
					if(show_title)
						user.show_message("\t Basic Modules, used for direct upgrade purposes:")
						show_title = FALSE
					show_upgrade_line(user, R, initial(upgrade.build_path), initial(upgrade.name))
				show_title = TRUE
				for(var/datum/design_techweb/prosfab/robot_upgrade/advanced/upgrade in SSresearch.techweb_designs)
					var/obj/item/borg/upgrade/advanced/upgrade_type = initial(upgrade.build_path)
					var/needs_module = initial(upgrade_type.require_module)
					if((!R.module && needs_module) || !initial(upgrade.name) || R.stat == DEAD)
						continue
					if(show_title)
						user.show_message("\t Advanced Modules, used for module upgrade purposes:")
						show_title = FALSE
					show_upgrade_line(user, R, initial(upgrade.build_path), initial(upgrade.name))
				show_title = TRUE
				for(var/datum/design_techweb/prosfab/robot_upgrade/restricted/upgrade in SSresearch.techweb_designs)
					var/obj/item/borg/upgrade/restricted/upgrade_type = initial(upgrade.build_path)
					var/needs_module = initial(upgrade_type.require_module)
					if((!R.module && needs_module) || !initial(upgrade.name) || !R.supports_upgrade(initial(upgrade.build_path)) || R.stat == DEAD)
						continue
					if(show_title)
						user.show_message("\t Restricted Modules, used for module upgrade purposes on specific chassis:")
						show_title = FALSE
					show_upgrade_line(user, R, initial(upgrade.build_path), initial(upgrade.name))
				show_title = TRUE
		if("prosthetics")

			render_diagnosis(M, user)

		if("mecha")

			var/obj/mecha/Mecha = M

			var/integrity = Mecha.get_integrity()/Mecha.max_integrity*100
			var/cell_charge = Mecha.get_charge()
			var/tank_pressure = Mecha.internal_tank ? round(Mecha.internal_tank.return_pressure(),0.01) : "None"
			var/tank_temperature = Mecha.internal_tank ? Mecha.internal_tank.return_temperature() : "Unknown"
			var/cabin_pressure = round(Mecha.return_pressure(),0.01)

			var/output = span_notice("Analyzing Results for \the [Mecha]:") + {"<br>
				<b>Chassis Integrity: </b> [integrity]%<br>
				<b>Powercell charge: </b>[isnull(cell_charge)?"No powercell installed":"[capitalize(initial(Mecha.cell.name))] at [Mecha.cell.percent()]%"]<br>
				<b>Air source: </b>[Mecha.use_internal_tank?"Internal Airtank":"Environment"]<br>
				<b>Airtank pressure: </b>[tank_pressure]kPa<br>
				<b>Airtank temperature: </b>[tank_temperature]K|[tank_temperature - T0C]&deg;C<br>
				<b>Cabin pressure: </b>[cabin_pressure>WARNING_HIGH_PRESSURE ? span_red("[cabin_pressure]"): cabin_pressure]kPa<br>
				<b>Cabin temperature: </b> [Mecha.return_temperature()]K|[Mecha.return_temperature() - T0C]&deg;C<br>
				<b>DNA Lock: </b> [Mecha.dna?"Mecha.dna":"Not Found"]<br>
				"}

			to_chat(user, output)
			to_chat(user, "<hr>")
			to_chat(user, span_notice("Internal Diagnostics:"))
			for(var/slot in Mecha.internal_components)
				var/obj/item/mecha_parts/component/MC = Mecha.internal_components[slot]
				to_chat(user, "[MC? ("[slot]: [MC] " + span_notice("[round((MC.get_integrity() / MC.max_integrity) * 100, 0.1)]%") + " integrity. [MC.get_efficiency() * 100] Operational capacity.") : span_warning("[slot]: Component Not Found")]")

			to_chat(user, "<hr>")
			to_chat(user, span_notice("General Statistics:"))
			to_chat(user, span_notice("Movement Weight: [Mecha.get_step_delay()]") + "<br>")

	src.add_fingerprint(user)
	return

/// Diagnose `M` through the synthetic diagnostic bus (nanite telemetry for
/// nanoform bodies) and print the report.
/obj/item/robotanalyzer/proc/render_diagnosis(mob/living/M, mob/user)
	var/profile = istype(M.body, /datum/body/humanoid/nanoform) ? /datum/diagnostic_profile/nanite : /datum/diagnostic_profile/robot_analyzer
	var/datum/diagnosis/D = M.diagnose(profile)
	if(!D)
		return
	user.show_message(D.render_chat(), 1)
	log_diagnosis(user, M, D)
	qdel(D)

/// One upgrade line of the upgrade scan, from the upgrade's own detection.
/obj/item/robotanalyzer/proc/show_upgrade_line(mob/user, mob/living/silicon/robot/R, upgrade_type, upgrade_name)
	var/obj/item/borg/upgrade/proto = robot_upgrade_prototype(upgrade_type)
	if(!proto)
		return
	if(proto.host_missing(R))
		user.show_message(span_blue("\t\t [capitalize(upgrade_name)]: [span_red(span_bold("ERROR"))]"))
		return
	user.show_message(span_blue("\t\t [capitalize(upgrade_name)]: [proto.is_installed(R) ? span_green("Installed") : span_red("Missing")]"))
