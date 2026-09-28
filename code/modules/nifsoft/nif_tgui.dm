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

/**
 * Small helper datum to manage the HUD icon.
 * Owned by the NIF through `menu_ref`; hooks the implanted mob and goes away with it.
 */
/datum/nif_menu
	var/mob/owner
	var/atom/movable/screen/nif/screen_icon

DECLARE_REF(/datum/nif_menu, "screen_icon", OWNED, null)
DECLARE_REF(/datum/nif_menu, "owner", BACK, null)

/datum/nif_menu/New(mob/M)
	..()
	if(!ismob(M))
		log_runtime("nif_menu created without a mob owner ([M]).")
		return
	owner = M
	om_hook(owner, /datum/om/event/mob_client_login, src, PROC_REF(on_client_login))
	om_hook(owner, /datum/om/event/qdeleting, src, PROC_REF(on_owner_qdeleting))
	if(owner.client)
		create_mob_button(owner)

// takes the NIF verb back from its owner. Hooks, the screen icon (owned; it
// leaves client screens in its own teardown) and the owner ref are core work.
/datum/nif_menu/on_destroy(force)
	if(ishuman(owner))
		remove_verb(owner, /mob/living/carbon/human/proc/nif_menu)
	..()

/datum/nif_menu/proc/on_owner_qdeleting(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	qdel(src)

/datum/nif_menu/proc/on_client_login(datum/source, datum/om/event/mob_client_login/event)
	EVENT_HANDLER
	create_mob_button(source)

/datum/nif_menu/proc/create_mob_button(mob/user)
	var/datum/hud/HUD = user.hud_used
	if(!screen_icon)
		screen_icon = new()
		om_hook(screen_icon, /datum/om/event/click, src, PROC_REF(nif_menu_click))
	screen_icon.icon = HUD.ui_style
	screen_icon.color = HUD.ui_color
	screen_icon.alpha = HUD.ui_alpha
	LAZYADD(HUD.other_important, screen_icon)
	user.client?.screen += screen_icon

	add_verb(user, /mob/living/carbon/human/proc/nif_menu)

/datum/nif_menu/proc/nif_menu_click(datum/source, datum/om/event/click/event)
	EVENT_HANDLER
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
	set category = "IC.NIF"
	set desc = "Open the NIF user interface."

	var/obj/item/nif/N = nif
	if(istype(N))
		N.tgui_interact(src)

/**
 * The NIF State ensures that only our authorized implanted user can touch us.
 */
/obj/item/nif/tgui_state(mob/user)
	return GLOB.tgui_nif_main_state

/**
 * Standard TGUI stub to open the NIF.js template.
 */
/obj/item/nif/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui)
	if(!ishuman(user))
		return FALSE
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "NIF", name)
		ui.open()

/**
 * tgui_data gives the UI any relevant data it needs.
 * In our case, that's basically everything from our statpanel.
 */
/obj/item/nif/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["valid_themes"] = valid_ui_themes
	data["theme"] = save_data["ui_theme"]
	data["last_notification"] = last_notification

	// Random biometric information
	data["nutrition"] = human.nutrition
	data["isSynthetic"] = HAS_SYNTHETIC_BIOLOGY(human)

	data["nif_percent"] = round((durability/initial(durability))*100)
	data["nif_stat"] = stat

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
/obj/item/nif/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("setTheme")
			if((params["theme"] in valid_ui_themes) || params["theme"] == null)
				save_data["ui_theme"] = params["theme"]
			return TRUE
		if("toggle_module")
			var/datum/nifsoft/NS = locate_in_list(nifsofts, params["module"])
			if(!istype(NS))
				return
			if(NS.activates)
				if(NS.active)
					NS.deactivate()
				else
					NS.activate()
			return TRUE
		if("uninstall")
			var/datum/nifsoft/NS = locate_in_list(nifsofts, params["module"])
			if(!istype(NS))
				return
			NS.uninstall()
			return TRUE
		if("dismissNotification")
			last_notification = null
			return TRUE

/// The NIF's HUD menu helper, owned by the NIF (created on implant, deleted on unimplant or with the NIF).
/obj/item/nif/proc/menu() as /datum/nif_menu
	return QDELETED(menu_ref) ? null : menu_ref

DECLARE_REF(/obj/item/nif, "menu_ref", OWNED, null)
