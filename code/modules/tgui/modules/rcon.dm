#define SMES_PER_PAGE 4

/datum/tgui_module/rcon
	name = "Power RCON"

	var/list/known_SMESs = null
	var/list/known_breakers = null

	var/filtered_smeslist

	var/current_page = 1
	var/number_pages = 0

/datum/tgui_module/rcon/proc/filter_smeslist(page)
	number_pages = round((length(known_SMESs) + SMES_PER_PAGE - 1) / SMES_PER_PAGE)
	var/page_index = page - 1

	var/lower_bound = page_index * SMES_PER_PAGE + 1
	var/upper_bound = (page_index + 1) * SMES_PER_PAGE
	upper_bound = min(upper_bound, length(known_SMESs))
	filtered_smeslist = null

	for(var/index = lower_bound, index <= upper_bound, index++)
		LAZYADD(filtered_smeslist, known_SMESs[index])

CAPABILITIES(/datum/tgui_module/rcon)
	interface("RCON")
	op("set_smes_page", ui_act("set_smes_page", arg("index", num())), then(PROC_REF(ui_act_set_smes_page)))
	op("smes_in_toggle", ui_act("smes_in_toggle", arg("smes")), then(PROC_REF(ui_act_smes_in_toggle)))
	op("smes_out_toggle", ui_act("smes_out_toggle", arg("smes")), then(PROC_REF(ui_act_smes_out_toggle)))
	op("smes_in_set", ui_act("smes_in_set", arg("adjust", num()), arg("smes"), arg("target")), then(PROC_REF(ui_act_smes_in_set)))
	op("smes_out_set", ui_act("smes_out_set", arg("adjust", num()), arg("smes"), arg("target")), then(PROC_REF(ui_act_smes_out_set)))
	op("toggle_breaker", ui_act("toggle_breaker", arg("breaker", schema_text(4096))), then(PROC_REF(ui_act_toggle_breaker)))

/datum/tgui_module/rcon/ui_data(datum/act/eval/A)
	FindDevices() // Update our devices list
	var/list/data = list()
	data["pages"] = number_pages
	data["current_page"] = current_page

	filter_smeslist(current_page)

	// SMES DATA (simplified view)
	var/list/smeslist = list()
	for(var/obj/machinery/power/smes/buildable/SMES in filtered_smeslist)
		var/list/smes_data = SMES.tgui_data()
		smes_data["RCON_tag"] = SMES.RCon_tag
		smeslist.Add(list(smes_data))

	data["smes_info"] = sortByKey(smeslist, "RCON_tag")

	// BREAKER DATA (simplified view)
	var/list/breakerlist[0]
	for(var/obj/machinery/power/breakerbox/BR in known_breakers)
		breakerlist.Add(list(list(
		"RCON_tag" = BR.RCon_tag,
		"enabled" = BR.on
		)))
	data["breaker_info"] = breakerlist

	return data

/datum/tgui_module/rcon/proc/ui_act_set_smes_page(datum/act/op/A, index)
	var/page = index
	current_page = page
	. = TRUE

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
		SMES.tgui_set_io(SMES_TGUI_INPUT, target, adjust)
	. = TRUE

/datum/tgui_module/rcon/proc/ui_act_smes_out_set(datum/act/op/A, adjust, smes, target)
	var/obj/machinery/power/smes/buildable/SMES = GetSMESByTag(smes)
	if(SMES)
		SMES.tgui_set_io(SMES_TGUI_OUTPUT, target, adjust)
	. = TRUE

/datum/tgui_module/rcon/proc/ui_act_toggle_breaker(datum/act/op/A, breaker_tag)
	var/mob/user = A.actor
	var/obj/machinery/power/breakerbox/toggle = null
	for(var/obj/machinery/power/breakerbox/breaker in known_breakers)
		if(breaker.RCon_tag == breaker_tag)
			toggle = breaker
	if(toggle)
		if(toggle.update_locked)
			to_chat(user, "The breaker box was recently toggled. Please wait before toggling it again.")
		else
			toggle.auto_toggle()
	. = TRUE

// Proc: GetSMESByTag()
// Parameters: 1 (tag - RCON tag of SMES we want to look up)
// Description: Looks up and returns SMES which has matching RCON tag
/datum/tgui_module/rcon/proc/GetSMESByTag(tag)
	if(!tag)
		return

	for(var/obj/machinery/power/smes/buildable/S in known_SMESs)
		if(S.RCon_tag == tag)
			return S

// Proc: FindDevices()
// Parameters: None
// Description: Refreshes local list of known devices.
/datum/tgui_module/rcon/proc/FindDevices()
	rel_clear(src, nameof(known_SMESs))

	var/z = get_z(tgui_host())
	var/list/map_levels = using_map.get_map_levels(z)

	for(var/obj/machinery/power/smes/buildable/SMES in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(!(SMES.z in map_levels))
			continue
		if(SMES.RCon_tag && (SMES.RCon_tag != "NO_TAG") && SMES.RCon)
			rel_add(src, nameof(known_SMESs), SMES)

	rel_clear(src, nameof(known_breakers))
	for(var/obj/machinery/power/breakerbox/breaker in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!(breaker.z in map_levels))
			continue
		if(breaker.RCon_tag != "NO_TAG")
			rel_add(src, nameof(known_breakers), breaker)

/datum/tgui_module/rcon/ntos
	ntos = TRUE

/datum/tgui_module/rcon/robot
DECLARE_UI_STATE(/datum/tgui_module/rcon/robot, GLOB.tgui_self_state)

#undef SMES_PER_PAGE
