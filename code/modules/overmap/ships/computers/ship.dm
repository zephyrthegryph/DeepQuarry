/*
While these computers can be placed anywhere, they will only function if placed on either a non-space, non-shuttle turf
with an /obj/effect/overmap/visitable/ship present elsewhere on that z level, or else placed in a shuttle area with an /obj/effect/overmap/visitable/ship
somewhere on that shuttle. Subtypes of these can be then used to perform ship overmap movement functions.
*/
/obj/machinery/computer/ship
	var/tmp/obj/effect/overmap/visitable/ship/linked
	var/list/viewers // Mobs in direct-view mode (relation list, filled by /datum/remote_view/viewer_managed)
	var/extra_view = 0 // how much the view is increased by when the mob is in overmap mode.
	/// Whether AI/silicon mobs are permitted to interact with this console. Subtypes may override to FALSE.
	var/ai_control = TRUE


// A late init operation called in SSshuttles, used to attach the thing to the right ship.
/obj/machinery/computer/ship/proc/attempt_hook_up(obj/effect/overmap/visitable/ship/sector)
	if(!istype(sector))
		return
	if(sector.check_ownership(src))
		rel_set(src, nameof(linked), sector)
		return 1

/obj/machinery/computer/ship/proc/sync_linked(user = null)
	var/obj/effect/overmap/visitable/ship/sector = get_overmap_sector(z)
	if(!sector)
		return
	. = attempt_hook_up_recursive(sector)
	if(. && linked() && user)
		to_chat(user, span_notice("[src] reconnected to [linked()]"))
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
	open_request(src, /datum/prompt/choice/ship_reconnect, PROC_REF(reconnect_answered), answerer = user, question = "Unable to connect to [flavor].", title = "[src]")

/obj/machinery/computer/ship/proc/reconnect_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/mob/user = context.answer.answerer
	if(viewing_overmap(user))
		user.reset_perspective()
	if(context.answer.value == "Reconnect")
		if(sync_linked(user))
			interface_interact(user)
	if(!QDELETED(src))
		SStgui.update_uis(src)

TOPIC_ACTION(/obj/machinery/computer/ship, "sync", PROC_REF(topic_sync))

/obj/machinery/computer/ship/proc/topic_sync(mob/user, list/args)
	if(sync_linked(user))
		interface_interact(user)
	return TRUE

/// Opens the TGUI for this console. Return TRUE if handled.
/// Direct interactions inside this proc must perform their own CanInteract checks.
/obj/machinery/computer/ship/proc/interface_interact(mob/user)
	tgui_interact(user)
	return TRUE

/// Old attack_ai: open the interface if silicon control is allowed. Never fell through.
/obj/machinery/computer/ship/proc/ship_silicon_use(datum/act/op/A)
	var/mob/user = A.actor
	if(tgui_status(user, tgui_state()) > STATUS_CLOSE)
		interface_interact(user)
	return OP_OK

/// Old attack_ghost: open the interface.
/obj/machinery/computer/ship/proc/ship_ghost_view(datum/act/op/A)
	interface_interact(A.actor)
	return OP_OK

MSG_DEF_SELF(ship/ai_denied, "Access Denied.")
MSG_DEF_SELF(ship/access_denied, "access denied")

TRACKED(/obj/machinery/computer/ship, ai_control)

/// Requirement (old attack_hand): ID access.
/obj/machinery/computer/ship/proc/ship_access_holds(datum/act/op/A)
	return !!allowed(A.actor)

/// Old attack_hand: opens the interface if it isn't already.
/obj/machinery/computer/ship/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(tgui_status(user, tgui_state()) > STATUS_CLOSE)
		interface_interact(user)
	return OP_OK

// The buttons every ship console's window has (declared in its CAPABILITIES, code/modules/flight_operations/flight_console.dm).
/// The guard every button of a ship console asks first (a console type overrides it).
/obj/machinery/computer/ship/proc/ui_gate(datum/act/op/A)
	return TRUE

/obj/machinery/computer/ship/proc/ui_act_sync(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	sync_linked(A.actor)
	return TRUE

/obj/machinery/computer/ship/proc/ui_act_close(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/mob/user = A.actor
	user.reset_perspective()
	return TRUE

// Management of mob view displacement. look to shift view to the ship on the overmap; unlook to shift back.

/obj/machinery/computer/ship/look(mob/user)
	if(linked() && linked().real_appearance)
		user.client?.images += linked().real_appearance
	user.set_viewsize(world.view + extra_view)

/obj/machinery/computer/ship/unlook(mob/user)
	if(linked() && linked().real_appearance && user.client)
		user.client.images -= linked().real_appearance
	user.set_viewsize() // reset to default

/obj/machinery/computer/ship/proc/viewing_overmap(mob/user)
	return (user in viewers)

/obj/machinery/computer/ship/tgui_close(mob/user)
	. = ..()
	user.reset_perspective()

/*
Ships can now be hijacked!
*/
/obj/machinery/computer/ship
	var/hacked = 0   // Has been emagged, no access restrictions.

/obj/machinery/computer/ship/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if (!hacked)
		req_access = list()
		req_one_access = list()
		hacked = 1
		to_chat(user, "You short out the console's ID checking system. It's now available to everyone!")
		return OP_OK
	return OP_DECLINE

/// Accessor for the linked var.
/obj/machinery/computer/ship/proc/linked() as /obj/effect/overmap/visitable/ship
	return linked

/datum/prompt/choice/ship_reconnect
	choices = list("Reconnect", "Close")
	buttons = TRUE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/ship_reconnect/recheck_extra()
	var/mob/user = answerer
	return !istype(user) || QDELETED(user) ? "gone" : null
