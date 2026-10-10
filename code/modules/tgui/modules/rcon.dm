#define SMES_PER_PAGE 4

/datum/tgui_module/rcon
	name = "Power RCON"

	/// The page of units the window shows.
	var/current_page = 1

TRACKED(/datum/tgui_module/rcon, current_page)

/// The tagged units an RCON console on the host's levels lists now (with remote control on), and the breaker boxes: read live from the
/// registries every time, so a unit that goes, or whose tag or remote wire changes, leaves the list without anything rescanning.
/datum/tgui_module/rcon/proc/known_smes()
	. = list()
	var/list/map_levels = using_map.get_map_levels(get_z(tgui_host()))
	for(var/obj/machinery/power/smes/buildable/SMES in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(!(SMES.z in map_levels))
			continue
		if(SMES.RCon_tag && (SMES.RCon_tag != "NO_TAG") && SMES.RCon)
			. += SMES

/datum/tgui_module/rcon/proc/known_breakers()
	. = list()
	var/list/map_levels = using_map.get_map_levels(get_z(tgui_host()))
	for(var/obj/machinery/power/breakerbox/breaker in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!(breaker.z in map_levels))
			continue
		if(breaker.RCon_tag != "NO_TAG")
			. += breaker

CAPABILITIES(/datum/tgui_module/rcon)
	interface("RCON")
	op("set_smes_page", ui_act("set_smes_page", arg("index", num())), then(PROC_REF(ui_act_set_smes_page)))
	op("smes_in_toggle", ui_act("smes_in_toggle", arg("smes")), then(PROC_REF(ui_act_smes_in_toggle)))
	op("smes_out_toggle", ui_act("smes_out_toggle", arg("smes")), then(PROC_REF(ui_act_smes_out_toggle)))
	op("smes_in_set", ui_act("smes_in_set", arg("adjust", num()), arg("smes"), arg("target")), then(PROC_REF(ui_act_smes_in_set)))
	op("smes_out_set", ui_act("smes_out_set", arg("adjust", num()), arg("smes"), arg("target")), then(PROC_REF(ui_act_smes_out_set)))
	op("toggle_breaker", ui_act("toggle_breaker", arg("breaker", schema_text(4096))), needs(req_bool(PROC_REF(breaker_ready), because = MSG(rcon/breaker_locked))), then(PROC_REF(ui_act_toggle_breaker)))

/// What the console shows: one page of units (their window data and tag) and every breaker box. Reads only.
/datum/tgui_module/rcon/ui_data(datum/act/eval/A)
	var/list/units = known_smes()
	var/pages = round((length(units) + SMES_PER_PAGE - 1) / SMES_PER_PAGE)
	var/page = clamp(current_page, 1, max(pages, 1))
	var/list/data = list()
	data["pages"] = pages
	data["current_page"] = page

	// SMES DATA (simplified view)
	var/list/smeslist = list()
	var/first = (page - 1) * SMES_PER_PAGE + 1
	var/last = min(page * SMES_PER_PAGE, length(units))
	for(var/index = first, index <= last, index++)
		var/obj/machinery/power/smes/buildable/SMES = units[index]
		var/list/smes_data = SMES.ui_data(A)
		smes_data["RCON_tag"] = SMES.RCon_tag
		smeslist.Add(list(smes_data))

	data["smes_info"] = sortByKey(smeslist, "RCON_tag")

	// BREAKER DATA (simplified view)
	var/list/breakerlist = list()
	for(var/obj/machinery/power/breakerbox/BR as anything in known_breakers())
		breakerlist.Add(list(list(
		"RCON_tag" = BR.RCon_tag,
		"enabled" = BR.on
		)))
	data["breaker_info"] = breakerlist

	return data

/datum/tgui_module/rcon/proc/ui_act_set_smes_page(datum/act/op/A, index)
	set_current_page(index)
	return OP_OK

/datum/tgui_module/rcon/proc/ui_act_smes_in_toggle(datum/act/op/A, smes)
	var/obj/machinery/power/smes/buildable/SMES = GetSMESByTag(smes)
	if(SMES)
		SMES.toggle_input()
	. = TRUE

/datum/tgui_module/rcon/proc/ui_act_smes_out_toggle(datum/act/op/A, smes)
	var/obj/machinery/power/smes/buildable/SMES = GetSMESByTag(smes)
	if(SMES)
		SMES.toggle_output()
	. = TRUE

/datum/tgui_module/rcon/proc/ui_act_smes_in_set(datum/act/op/A, adjust, smes, target)
	var/obj/machinery/power/smes/buildable/SMES = GetSMESByTag(smes)
	if(SMES)
		SMES.set_io_level(SMES_TGUI_INPUT, target, adjust)
	. = TRUE

/datum/tgui_module/rcon/proc/ui_act_smes_out_set(datum/act/op/A, adjust, smes, target)
	var/obj/machinery/power/smes/buildable/SMES = GetSMESByTag(smes)
	if(SMES)
		SMES.set_io_level(SMES_TGUI_OUTPUT, target, adjust)
	. = TRUE

MSG_DEF_SELF(rcon/breaker_locked, "The breaker box was recently toggled. Please wait before toggling it again.")

/// The breaker box the button names, or null.
/datum/tgui_module/rcon/proc/breaker_tagged(breaker_tag)
	for(var/obj/machinery/power/breakerbox/breaker as anything in known_breakers())
		if(breaker.RCon_tag == breaker_tag)
			return breaker
	return null

/// needs: the named breaker box is not locked by its last toggle.
/datum/tgui_module/rcon/proc/breaker_ready(datum/act/op/A)
	var/obj/machinery/power/breakerbox/toggle = breaker_tagged(A.args["breaker"])
	return !toggle?.update_locked

/datum/tgui_module/rcon/proc/ui_act_toggle_breaker(datum/act/op/A, breaker)
	var/obj/machinery/power/breakerbox/toggle = breaker_tagged(breaker)
	toggle?.auto_toggle()
	return OP_OK

// Proc: GetSMESByTag()
// Parameters: 1 (tag - RCON tag of SMES we want to look up)
// Description: Looks up and returns SMES which has matching RCON tag
/datum/tgui_module/rcon/proc/GetSMESByTag(tag)
	if(!tag)
		return

	for(var/obj/machinery/power/smes/buildable/S as anything in known_smes())
		if(S.RCon_tag == tag)
			return S

/datum/tgui_module/rcon/ntos
	ntos = TRUE

/datum/tgui_module/rcon/robot
CAPABILITIES(/datum/tgui_module/rcon/robot)
	interface("RCON", state = nameof(GLOB.tgui_self_state))

#undef SMES_PER_PAGE
