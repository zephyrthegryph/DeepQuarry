/************************************************************************\
 * This module controls everything to do with the NIF's tgui interface. *
\************************************************************************/
/**
 * Etc variables on the NIF to keep this self contained
 */
/obj/item/nif
	var/static/list/valid_ui_themes = list(
		"abductor",
		"cardtable",
		"hackerman",
		"malfunction",
		"ntos",
		"paper",
		"retro",
		"syndicate"
	)
	var/tmp/last_notification
	var/datum/nif_menu/menu_ref

CAPABILITIES(/obj/item/nif)
	owns_one(nameof(comm), on_destroy = ON_DESTROY_DELETE)
	links(/obj/item/nif::human, /mob/living/carbon/human::nif)
	owns_many(nameof(nifsofts), /datum/nifsoft)
	owns_one(nameof(menu_ref), /datum/nif_menu)
	interface("NIF", state = nameof(GLOB.tgui_nif_main_state))
	without("ui_open")
	op("setTheme", ui_act("setTheme", arg("theme")), then(PROC_REF(ui_act_settheme)))
	op("toggle_module", ui_act("toggle_module", arg("module", schema_ref(/datum/nifsoft))), then(PROC_REF(ui_act_toggle_module)))
	op("uninstall", ui_act("uninstall", arg("module", schema_ref(/datum/nifsoft))), then(PROC_REF(ui_act_uninstall)))
	op("dismissNotification", ui_act("dismissNotification"), then(PROC_REF(ui_act_dismissnotification)))
	param(nameof(wear_at_make), pos = 1)
	param(nameof(load_data_at_make), pos = 2)
	op("rewire", stack(/obj/item/stack/cable_coil, 3), label("Replace the wiring"), when(PROC_REF(needs_rewiring)), wait(6 SECONDS), then(PROC_REF(rewire_done)), says(MSG(nif/rewired)))
	op("rewire_intact", stack(/obj/item/stack/cable_coil, 3), when(PROC_REF(wiring_intact)), priority(OP_PRIORITY_PART + 1), wait(0), then(PROC_REF(wiring_checked)), says(MSG(nif/wiring_intact)))
	op("pry_open", tool(TOOL_SCREWDRIVER), label("Pry open"), when(req_is(nameof(open), 0)), wait(4 SECONDS), then(PROC_REF(pry_open_done)), says(MSG(nif/pried_open)))
	op("reseal", tool(TOOL_SCREWDRIVER), label("Re-seal"), when(req_is(nameof(open), 3)), priority(OP_PRIORITY_PART + 1), wait(3 SECONDS), then(PROC_REF(reseal_done)), says(MSG(nif/resealed)))
	// the legacy screwdriver_act / multitool_act refused every other state and ended the click: so do these (a screwdriver does not fall through to a hit)
	op("screwdriver_blocked", tool(TOOL_SCREWDRIVER), when(PROC_REF(screwdriver_blocked)), priority(OP_PRIORITY_PART + 2), needs(req(PROC_REF(never), silent = TRUE)))
	op("multitool_blocked", tool(TOOL_MULTITOOL), when(PROC_REF(multitool_blocked)), priority(OP_PRIORITY_PART + 1), needs(req(PROC_REF(never), silent = TRUE)))
	op("reset_circuits", tool(TOOL_MULTITOOL), label("Reset the circuits"), when(req_is(nameof(open), 2)), wait(8 SECONDS), then(PROC_REF(reset_circuits_done)), says(MSG(nif/reset)))
	// Special Promethean surgery: a NIF stuffed into another slime body's chest.
	op("stuff_in", at_target(/mob/living/carbon/human), when(PROC_REF(stuffable)), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Stuff it in"),
		needs(req_adjacent(), req(PROC_REF(stuff_in_unclothed)), req(PROC_REF(stuff_in_torso))),
		begins(PROC_REF(stuffing_text)), wait(20 SECONDS), then(PROC_REF(stuff_in_done)))

/**
 * Small helper datum to manage the HUD icon.
 * Owned by the NIF through `menu_ref`; hooks the implanted mob and goes away with it.
 */
/datum/nif_menu
	var/mob/owner
	var/atom/movable/screen/nif/screen_icon


/datum/nif_menu/New(mob/M)
	..()
	if(!ismob(M))
		log_runtime("nif_menu created without a mob owner ([M]).")
		return
	rel_set(src, nameof(owner), M)
	observe(owner, /datum/notice/mob_client_login, src, then(PROC_REF(on_client_login)))
	observe(owner, /datum/notice/qdeleting, src, then(PROC_REF(on_owner_qdeleting)))
	if(owner.client)
		create_mob_button(owner)

// The NIF verb is granted with this menu as source, so its deletion takes the verb back.
// Deletes its button from the hud that owns it. Hooks and the owner ref are core work.
/datum/nif_menu/on_destroy(force)
	if(screen_icon)
		owner?.client?.screen -= screen_icon
		var/datum/hud/button_hud = owner_of(screen_icon)
		if(istype(button_hud))
			own_remove(button_hud, nameof(button_hud.other_important), screen_icon)
	..()

/datum/nif_menu/proc/on_owner_qdeleting(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	ended_with(src)

/datum/nif_menu/proc/on_client_login(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	create_mob_button(source)

/datum/nif_menu/proc/create_mob_button(mob/user)
	var/datum/hud/HUD = user.hud_used
	// The hud owns the button (other_important); a new hud's button is made afresh
	// (the old hud deleted its own, which cleared this relation).
	if(!screen_icon)
		var/atom/movable/screen/nif/button = new
		rel_add(HUD, nameof(HUD.other_important), button)
		rel_set(src, nameof(screen_icon), button)
		observe(screen_icon, /datum/notice/click, src, then(PROC_REF(nif_menu_click)))
	screen_icon.icon = HUD.ui_style
	screen_icon.color = HUD.ui_color
	screen_icon.alpha = HUD.ui_alpha
	user.client?.screen += screen_icon

	grant(user, granted_verb(/mob/living/carbon/human/proc/nif_menu), src)

/datum/nif_menu/proc/nif_menu_click(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/click/event = A
	var/mob/living/carbon/human/H = event.user
	if(istype(H) && H.nif)
		INVOKE_ASYNC(H.nif, PROC_REF(tgui_interact), H) // ALLOW(scheduler): tgui_interact may block on asset/window setup

/**
 * Screen object for NIF menu access
 */
/atom/movable/screen/nif
	name = "nif menu"
	icon = 'icons/mob/screen/midnight.dmi'
	icon_state = "nif"
	screen_loc = ui_smallquad

/**
 * Verb to open the interface
 */
/mob/living/carbon/human/proc/nif_menu()
	set name = "NIF Menu"
	set category = VERB_CAT_IC_NIF
	set desc = "Open the NIF user interface."

	var/obj/item/nif/N = nif
	if(istype(N))
		N.tgui_interact(src)

/**
 * The NIF State ensures that only our authorized implanted user can touch us.
 */

/**
 * Standard TGUI stub to open the NIF.js template.
 */

/obj/item/nif/ui_prepare(mob/user, datum/tgui/ui)
	if(!ishuman(user))
		return FALSE
	return TRUE

/**
 * tgui_data gives the UI any relevant data it needs.
 * In our case, that's basically everything from our statpanel.
 */
/obj/item/nif/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["valid_themes"] = valid_ui_themes
	data["last_notification"] = last_notification
	data["nif_stat"] = stat
	var/list/merged_1 = ui_data_obj_item_nif(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/nif's window data.
/obj/item/nif/proc/ui_data_obj_item_nif(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["theme"] = save_data["ui_theme"]

	// Random biometric information
	data["nutrition"] = human.nutrition
	data["isSynthetic"] = HAS_SYNTHETIC_BIOLOGY(human)

	data["nif_percent"] = round((durability/initial(durability))*100)

	var/list/modules = list()
	if(stat == NIF_WORKING)
		for(var/nifsoft in nifsofts)
			if(!nifsoft)
				continue
			var/datum/nifsoft/NS = nifsoft
			modules.Add(list(list(
				"name" = NS.name,
				"desc" = NS.desc,
				"p_drain" = NS.p_drain,
				"a_drain" = NS.a_drain,
				"illegal" = NS.illegal,
				"wear" = NS.wear,
				"cost" = NS.cost,
				"activates" = NS.activates,
				"active" = NS.active,
				"stat_text" = NS.stat_text(),
				"ref" = REF(NS),
			)))
	data["modules"] = modules

	return data

/**
 * tgui_act handles all user input in the UI.
 */
/obj/item/nif/proc/ui_act_settheme(datum/act/op/A, theme)
	if((theme in valid_ui_themes) || theme == null)
		save_data["ui_theme"] = theme
	return TRUE

/obj/item/nif/proc/ui_act_toggle_module(datum/act/op/A, module)
	if(!isnull(module) && !(module in src.nifsofts))
		return FALSE
	var/datum/nifsoft/NS = module
	if(!istype(NS))
		return
	if(NS.activates)
		if(NS.active)
			NS.deactivate()
		else
			NS.activate()
	return TRUE

/obj/item/nif/proc/ui_act_uninstall(datum/act/op/A, module)
	if(!isnull(module) && !(module in src.nifsofts))
		return FALSE
	var/datum/nifsoft/NS = module
	if(!istype(NS))
		return
	NS.uninstall()
	return TRUE

/obj/item/nif/proc/ui_act_dismissnotification(datum/act/op/A)
	last_notification = null
	return TRUE

/// The NIF's HUD menu helper, owned by the NIF (created on implant, deleted on unimplant or with the NIF).
/obj/item/nif/proc/menu() as /datum/nif_menu
	return QDELETED(menu_ref) ? null : menu_ref

/// The NIF's case is neither sealed nor sealed-and-repaired: the screwdriver has nothing to do (and does nothing else).
/obj/item/nif/proc/screwdriver_blocked(datum/act/op/A)
	return open != 0 && open != 3

/// The circuits are not open for a reset: the multitool has nothing to do.
/obj/item/nif/proc/multitool_blocked(datum/act/op/A)
	return open != 2

/// A requirement that never holds: the blocked click is refused without a word, as the legacy tool act ended it.
/obj/item/nif/proc/never(datum/act/op/A)
	return /datum/msg/req_silent
