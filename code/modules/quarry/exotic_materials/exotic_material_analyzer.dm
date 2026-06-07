// Exotic material analyzer machine.
//
// Accepts /obj/item/exotic_material_sample items and reveals the
// /datum/material/dynamic's full profile — eleven core stats grouped
// by category, plus any behavior components (luminescent / radioactive
// / toxic) attached to it. Tracks which materials have been scanned
// this round on a per-machine basis.

/obj/machinery/exotic_material_analyzer
	name = "exotic material analyzer"
	desc = "A bench-mounted spectrometer for cataloguing the strange minerals brought up from deeper layers. Insert a sample and run an analysis."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "mixer0"
	density = TRUE
	anchored = TRUE
	idle_power_usage = 20
	active_power_usage = 200

	/// The sample currently loaded.
	var/obj/item/exotic_material_sample/loaded_sample = null
	/// Round-ids of materials that have been scanned at this machine.
	var/list/known_material_ids = list()


/obj/machinery/exotic_material_analyzer/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/exotic_material_sample))
		if(loaded_sample)
			to_chat(user, span_warning("\The [src] already has a sample loaded. Eject it first."))
			return
		if(!user.unEquip(W))
			return
		W.forceMove(src)
		loaded_sample = W
		to_chat(user, span_notice("You slot \the [W] into \the [src]."))
		update_icon()
		SStgui.update_uis(src)
		return
	return ..()


/obj/machinery/exotic_material_analyzer/attack_hand(mob/user)
	if(..())
		return
	tgui_interact(user)


/obj/machinery/exotic_material_analyzer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DQExoticAnalyzer", name)
		ui.open()


/obj/machinery/exotic_material_analyzer/tgui_data(mob/user)
	var/list/data = list()
	data["loaded"] = _serialize_loaded()
	data["catalogue"] = _serialize_catalogue()
	return data


/obj/machinery/exotic_material_analyzer/proc/_serialize_loaded()
	if(!loaded_sample)
		return null
	var/datum/material/dynamic/M = SSquarry?.get_exotic_material(loaded_sample.material_id)
	if(!M)
		return list(
			"id" = 0,
			"name" = "Indeterminate Sample",
			"color" = "#888888",
			"band" = 0,
			"scanned" = FALSE,
			"mechanical" = list(),
			"thermal" = list(),
			"electrical" = list(),
			"chemical" = list(),
			"behaviors" = list(),
			"traits" = list(),
		)
	var/scanned = ("[loaded_sample.material_id]" in known_material_ids)
	return _build_material_payload(M, loaded_sample.material_id, scanned)


/obj/machinery/exotic_material_analyzer/proc/_serialize_catalogue()
	var/list/out = list()
	if(!SSquarry)
		return out
	for(var/key in known_material_ids)
		var/datum/material/dynamic/M = SSquarry.get_exotic_material(text2num(key))
		if(!M)
			continue
		out += list(_build_material_payload(M, text2num(key), TRUE))
	return out


/obj/machinery/exotic_material_analyzer/proc/_build_material_payload(datum/material/dynamic/M, id, include_stats)
	. = list(
		"id" = id,
		"name" = M.pretty_name,
		"color" = M.color,
		"band" = M.band,
		"rarity" = M.rarity,
		"material_class" = M.material_class,
		"scanned" = include_stats,
		"mechanical" = list(),
		"thermal" = list(),
		"electrical" = list(),
		"chemical" = list(),
		"behaviors" = list(),
		"traits" = list(),
	)
	if(!include_stats)
		return
	.["mechanical"] = list(
		list("name" = "Hardness",     "magnitude" = M.hardness),
		list("name" = "Density",      "magnitude" = M.density),
		list("name" = "Integrity",    "magnitude" = M.integrity),
		list("name" = "Elasticity",   "magnitude" = M.elasticity),
		list("name" = "Brittleness",  "magnitude" = M.brittleness, "debuff" = TRUE),
	)
	.["thermal"] = list(
		list("name" = "Heat Resistance",    "magnitude" = M.heat_resistance),
		list("name" = "Thermal Insulation", "magnitude" = M.thermal_insulation),
	)
	.["electrical"] = list(
		list("name" = "Conductivity", "magnitude" = M.conductivity),
		list("name" = "Magnetism",    "magnitude" = M.magnetism),
	)
	.["chemical"] = list(
		list("name" = "Reactivity",           "magnitude" = M.reactivity),
		list("name" = "Corrosion Resistance", "magnitude" = M.corrosion_resistance),
	)
	var/lum = dq_material_luminescence(M)
	var/rad = dq_material_radioactivity(M)
	var/tox = dq_material_toxicity(M)
	if(lum)
		.["behaviors"] += list(list("name" = "Luminescent", "magnitude" = lum, "debuff" = FALSE))
	if(rad)
		.["behaviors"] += list(list("name" = "Radioactive", "magnitude" = rad, "debuff" = TRUE))
	if(tox)
		.["behaviors"] += list(list("name" = "Toxic", "magnitude" = tox, "debuff" = TRUE))
	// Traits — qualitative tags. Surfaced separately from numeric stats.
	var/list/traits = dq_material_traits(M)
	.["traits"] = list()
	if(islist(traits))
		for(var/datum/component/material_trait/T as anything in traits)
			.["traits"] += list(list(
				"name" = T.trait_name,
				"description" = T.trait_description,
				"debuff" = T.debuff,
			))


/obj/machinery/exotic_material_analyzer/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	switch(action)
		if("scan")
			return _act_scan(usr)
		if("eject")
			return _act_eject(usr)
	return FALSE


/obj/machinery/exotic_material_analyzer/proc/_act_scan(mob/user)
	if(!loaded_sample)
		return TRUE
	if(stat & (NOPOWER|BROKEN))
		to_chat(user, span_warning("\The [src] has no power."))
		return TRUE
	var/datum/material/dynamic/M = SSquarry?.get_exotic_material(loaded_sample.material_id)
	if(!M)
		to_chat(user, span_warning("The sample reads as inert. The analyzer can't latch onto it."))
		return TRUE
	use_power(active_power_usage)
	visible_message(span_notice("\The [src] hums as it spins up its scan head."))
	if(!("[loaded_sample.material_id]" in known_material_ids))
		known_material_ids += "[loaded_sample.material_id]"
		to_chat(user, span_notice("New material catalogued: <b>[M.pretty_name]</b>."))
	else
		to_chat(user, span_notice("[M.pretty_name] re-confirmed. No new properties."))
	SStgui.update_uis(src)
	return TRUE


/obj/machinery/exotic_material_analyzer/proc/_act_eject(mob/user)
	if(!loaded_sample)
		return TRUE
	loaded_sample.forceMove(get_turf(src))
	if(user && Adjacent(user))
		user.put_in_hands(loaded_sample)
	loaded_sample = null
	update_icon()
	SStgui.update_uis(src)
	return TRUE


/obj/machinery/exotic_material_analyzer/examine(mob/user)
	. = ..()
	if(loaded_sample)
		. += span_notice("It's loaded with \the [loaded_sample].")
	else
		. += span_notice("Its sample tray is empty.")


/obj/machinery/exotic_material_analyzer/Destroy()
	if(loaded_sample)
		loaded_sample.forceMove(get_turf(src))
		loaded_sample = null
	return ..()
