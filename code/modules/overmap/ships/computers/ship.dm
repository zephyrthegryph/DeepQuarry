/*
While these computers can be placed anywhere, they will only function if placed on either a non-space, non-shuttle turf
with an /obj/effect/overmap/visitable/ship present elsewhere on that z level, or else placed in a shuttle area with an /obj/effect/overmap/visitable/ship
somewhere on that shuttle. Subtypes of these can be then used to perform ship overmap movement functions.
*/
/obj/machinery/computer/ship
	var/obj/effect/overmap/visitable/ship/linked
	var/list/viewers // Weakrefs to mobs in direct-view mode.
	var/extra_view = 0 // how much the view is increased by when the mob is in overmap mode.
	/// Whether AI/silicon mobs are permitted to interact with this console. Subtypes may override to FALSE.
	var/ai_control = TRUE

// A late init operation called in SSshuttles, used to attach the thing to the right ship.
/obj/machinery/computer/ship/proc/attempt_hook_up(obj/effect/overmap/visitable/ship/sector)
	if(!istype(sector))
		return
	if(sector.check_ownership(src))
		linked = sector
		return 1

/obj/machinery/computer/ship/proc/sync_linked(user = null)
	var/obj/effect/overmap/visitable/ship/sector = get_overmap_sector(z)
	if(!sector)
		return
	. = attempt_hook_up_recursive(sector)
	if(. && linked && user)
		to_chat(user, span_notice("[src] reconnected to [linked]"))
		// reconnect dialog is TGUI now; close via SStgui
		SStgui.close_uis(src)

/obj/machinery/computer/ship/proc/attempt_hook_up_recursive(obj/effect/overmap/visitable/ship/sector)
	if(attempt_hook_up(sector))
		return sector
	for(var/obj/effect/overmap/visitable/ship/candidate in sector)
		if((. = .(candidate)))
			return

/obj/machinery/computer/ship/proc/display_reconnect_dialog(mob/user, flavor)
	if(viewing_overmap(user))
		user.reset_perspective()
	// was an admin_log_show error popup; now a tgui_alert with a single Reconnect choice.
	if(tgui_alert(user, "Unable to connect to [flavor].", "[src]", list("Reconnect", "Close")) == "Reconnect")
		if(sync_linked(user))
			interface_interact(user)

/obj/machinery/computer/ship/Topic(href, href_list)
	if(..())
		return TRUE
	if(href_list["sync"])
		if(sync_linked(usr))
			interface_interact(usr)
		return TRUE

/// Opens the TGUI for this console. Return TRUE if handled.
/// Direct interactions inside this proc must perform their own CanInteract checks.
/obj/machinery/computer/ship/proc/interface_interact(mob/user)
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/ship/attack_ai(mob/user)
	if(!ai_control && issilicon(user))
		to_chat(user, span_warning("Access Denied."))
		return
	if(tgui_status(user, tgui_state()) > STATUS_CLOSE)
		return interface_interact(user)

/obj/machinery/computer/ship/attack_ghost(mob/user)
	interface_interact(user)

/obj/machinery/computer/ship/attack_hand(mob/user)
	if((. = ..()))
		return
	if(!ai_control && issilicon(user))
		to_chat(user, span_warning("Access Denied."))
		return TRUE
	if(!allowed(user))
		to_chat(user, span_warning("Access Denied."))
		return TRUE
	if(tgui_status(user, tgui_state()) > STATUS_CLOSE)
		return interface_interact(user)

/obj/machinery/computer/ship/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	switch(action)
		if("sync")
			sync_linked(ui.user)
			return TRUE
		if("close")
			ui.user.reset_perspective()
			return TRUE
	return FALSE

// Management of mob view displacement. look to shift view to the ship on the overmap; unlook to shift back.

/obj/machinery/computer/ship/look(mob/user)
	if(linked && linked.real_appearance)
		user.client?.images += linked.real_appearance
	user.set_viewsize(world.view + extra_view)

/obj/machinery/computer/ship/unlook(mob/user)
	if(linked && linked.real_appearance && user.client)
		user.client.images -= linked.real_appearance
	user.set_viewsize() // reset to default

/obj/machinery/computer/ship/proc/viewing_overmap(mob/user)
	return (WEAKREF(user) in viewers)

/obj/machinery/computer/ship/tgui_close(mob/user)
	. = ..()
	user.reset_perspective()

/obj/machinery/computer/ship/sensors/Destroy()
	sensors = null
	. = ..()


// === merged from ship_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/*
Ships can now be hijacked!
*/
/obj/machinery/computer/ship
	var/hacked = 0   // Has been emagged, no access restrictions.

/obj/machinery/computer/ship/emag_act(remaining_charges, mob/user)
	if (!hacked)
		req_access = list()
		req_one_access = list()
		hacked = 1
		to_chat(user, "You short out the console's ID checking system. It's now available to everyone!")
		return 1
