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
	owns_many(nameof(nifsofts), /datum/nifsoft)
	owns_one(nameof(menu_ref), /datum/nif_menu)

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
	EVENT_HANDLER
	qdel(src)

/datum/nif_menu/proc/on_client_login(datum/act/notice/A)
	EVENT_HANDLER
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
	EVENT_HANDLER
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
DECLARE_UI_STATE(/obj/item/nif, GLOB.tgui_nif_main_state)

/**
 * Standard TGUI stub to open the NIF.js template.
 */
DECLARE_UI(/obj/item/nif, "NIF")

/obj/item/nif/ui_prepare(mob/user, datum/tgui/ui)
	if(!ishuman(user))
		return FALSE
	return TRUE

/**
 * tgui_data gives the UI any relevant data it needs.
 * In our case, that's basically everything from our statpanel.
 */
UI_DATA(/obj/item/nif, "valid_themes=valid_ui_themes:list", "last_notification", "nif_stat=stat", "merge:ui_data_obj_item_nif{theme:unknown,nutrition:num,isSynthetic:unknown,nif_percent:num,modules:list}")

/// The computed part of /obj/item/nif's window data (declared on its UI_DATA row).
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
UI_ACT(/obj/item/nif, "setTheme", ui_act_settheme, UI_ARG_VALUE("theme"))
UI_ACT_PROC(/obj/item/nif, ui_act_settheme)
	if((params["theme"] in valid_ui_themes) || params["theme"] == null)
		save_data["ui_theme"] = params["theme"]
	return TRUE

UI_ACT(/obj/item/nif, "toggle_module", ui_act_toggle_module, UI_ARG_REF("module", "nifsofts", /datum/nifsoft))
UI_ACT_PROC(/obj/item/nif, ui_act_toggle_module)
	var/datum/nifsoft/NS = params["module"]
	if(!istype(NS))
		return
	if(NS.activates)
		if(NS.active)
			NS.deactivate()
		else
			NS.activate()
	return TRUE

UI_ACT(/obj/item/nif, "uninstall", ui_act_uninstall, UI_ARG_REF("module", "nifsofts", /datum/nifsoft))
UI_ACT_PROC(/obj/item/nif, ui_act_uninstall)
	var/datum/nifsoft/NS = params["module"]
	if(!istype(NS))
		return
	NS.uninstall()
	return TRUE

UI_ACT(/obj/item/nif, "dismissNotification", ui_act_dismissnotification)
UI_ACT_PROC(/obj/item/nif, ui_act_dismissnotification)
	last_notification = null
	return TRUE

/// The NIF's HUD menu helper, owned by the NIF (created on implant, deleted on unimplant or with the NIF).
/obj/item/nif/proc/menu() as /datum/nif_menu
	return QDELETED(menu_ref) ? null : menu_ref

