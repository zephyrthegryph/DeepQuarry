/*
	AI ClickOn()

	Note currently ai restrained() returns 0 in all cases,
	therefore restrained code has been removed

	The AI can double click to move the camera (this was already true but is cleaner),
	or double click a mob to track them.

	Note that AI have no need for the adjacency proc, and so this proc is a lot cleaner.
*/
/mob/living/silicon/ai/DblClickOn(atom/A, params)
	if(client.buildmode) // comes after object.Click to allow buildmode gui objects to be clicked
		build_click(src, client.buildmode, params, A)
		return

	if(control_disabled || stat) return

	if(ismob(A))
		ai_actual_track(A)
	else
		A.move_camera_by_click(src)


// AI clicks route through the input router with the AI adapter (adapters.dm):
// its own click table, then its interactions (INTERACT_SILICON) and silicon_use.

/mob/living/silicon/ai/UnarmedAttack(atom/A)
	actor_use(/datum/input_adapter/ai, src, A)
/mob/living/silicon/ai/RangedAttack(atom/A)
	actor_use(/datum/input_adapter/ai, src, A)

/*
	The AI's modifier actions: a target's silicon hook first (silicon_* below), then
	what any mob's action does.
*/
/mob/living/silicon/ai/action_inspect(atom/A)
	if(!control_disabled && A.silicon_inspect(src))
		return
	..()

/mob/living/silicon/ai/action_pull(atom/A)
	if(!control_disabled && A.silicon_pull(src))
		return
	..()

/mob/living/silicon/ai/action_alternate(atom/A)
	if(!control_disabled && A.silicon_alternate(src))
		return
	..()

/mob/living/silicon/ai/action_swap_hands(atom/A)
	if(!control_disabled && A.silicon_swap_hands(src))
		return
	..()

/*
	Silicon action hooks: what a target does when the AI or a cyborg runs a modifier
	action on it (remote door, APC and turret controls). One hook per action, shared
	by both actors; a hook returns TRUE when it handled the action, so the actor's
	ordinary action is skipped.
*/

/// Inspect (default: shift-click).
/atom/proc/silicon_inspect(mob/living/silicon/user)
	return FALSE

/// Pull (default: ctrl-click).
/atom/proc/silicon_pull(mob/living/silicon/user)
	return FALSE

/// Alternate (default: alt-click). By default the ordinary click_alt.
/atom/proc/silicon_alternate(mob/living/silicon/user)
	return click_alt(user)

/// Swap hands (default: middle-click). The AI only; cyborgs cycle modules instead.
/atom/proc/silicon_swap_hands(mob/living/silicon/user)
	return FALSE

/// Quick (default: ctrl-shift-click). Cyborgs only; the AI uses the ordinary click_ctrl_shift.
/atom/proc/silicon_quick(mob/living/silicon/user)
	return click_ctrl_shift(user)

/// A cyborg without the airlock's access can't use its remote controls. (The AI always can.)
/obj/machinery/door/airlock/proc/silicon_denied(mob/living/silicon/user)
	return isrobot(user) && !check_access(user.idcard)

/obj/machinery/door/airlock/silicon_inspect(mob/living/silicon/user) // Opens and closes doors!
	if(silicon_denied(user))
		return TRUE
	add_fingerprint(user)
	user_toggle_open(user)
	return TRUE

/obj/machinery/door/airlock/silicon_pull(mob/living/silicon/user) // Bolts doors
	if(silicon_denied(user))
		return TRUE
	add_fingerprint(user)
	toggle_bolt(user)
	return TRUE

/obj/machinery/door/airlock/silicon_alternate(mob/living/silicon/user) // Electrifies doors.
	if(silicon_denied(user))
		return TRUE
	add_fingerprint(user)
	if(electrified_until)
		electrify(0, TRUE, user)
	else
		electrify(-1, TRUE, user)
	// Clientside only notification
	var/turf/root_turf = get_turf(src)
	var/image/client_only/electrify_notice/zap = new('icons/hud/screen_gen.dmi', root_turf, electrified_until ? "stamina_crit" : "stamina_dead", OBFUSCATION_LAYER, SOUTH)
	zap.place_from_root(root_turf)
	if(user.client)
		zap.append_client(user.client)
	return TRUE

/obj/machinery/door/airlock/silicon_quick(mob/living/silicon/user) // Nothing, for cyborgs with or without access.
	return TRUE

/obj/machinery/door/airlock/silicon_swap_hands(mob/living/silicon/user) // Toggles door bolt lights.
	add_fingerprint(user)
	if(wire_cut(WIRE_BOLT_LIGHT))
		to_chat(user, "The bolt lights wire is cut - The door bolt lights are permanently disabled.")
		return
	set_lights(!lights)
	to_chat(user, span_notice("Lights are now [lights ? "on." : "off."]"))
	changed(src) // an AI hotkey, not a dispatched call
	return TRUE

/obj/machinery/power/apc/silicon_pull(mob/living/silicon/user) // turns off/on APCs.
	if(isrobot(user) && !allowed(user))
		return TRUE
	add_fingerprint(user)
	toggle_breaker()
	return TRUE

/obj/machinery/turretid/silicon_pull(mob/living/silicon/user) //turns off/on Turrets
	if(isrobot(user) && !allowed(user))
		return TRUE
	enabled = !enabled
	updateTurrets()
	return TRUE

/obj/machinery/turretid/silicon_alternate(mob/living/silicon/user) //toggles lethal on turrets
	if(isrobot(user) && !allowed(user))
		return TRUE
	if(lethal_is_configurable)
		lethal = !lethal
		updateTurrets()
	return TRUE

//
// Override AdjacentQuick for AltClicking
//

/mob/living/silicon/ai/TurfAdjacent(turf/T)
	return (GLOB.cameranet && GLOB.cameranet.checkTurfVis(T))
