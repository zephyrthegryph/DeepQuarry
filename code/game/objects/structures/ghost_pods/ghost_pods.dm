// These are used to spawn a specific mob when triggered, with the mob controlled by a player pulled from the ghost pool, hense its name.
/obj/structure/ghost_pod
	name = "Base Ghost Pod"
	desc = "If you can read me, someone don goofed."
	icon = 'icons/obj/structures.dmi'
	var/ghost_query_type = null
	var/icon_state_opened = null	// Icon to switch to when 'used'.
	var/used = FALSE
	var/busy = FALSE // Don't spam ghosts by spamclicking.
	var/needscharger //For drone pods that want their pod to turn into a charger.
	var/datum/ghost_query/Q //This is used so we can unregister ourself.
	unacidable = TRUE
	var/delay_to_self_open = 0 // How long to wait for first attempt.  Note that the timer by default starts when the pod is created.
	var/delay_to_try_again = 0 // How long to wait if first attempt fails.  Set to 0 to never try again.

// Call this to get a ghost volunteer.
/obj/structure/ghost_pod/proc/trigger(mob/user, alert, adminalert)
	if(!ghost_query_type)
		return FALSE
	if(busy)
		return FALSE

	if(alert)
		visible_message(alert)
	if(adminalert)
		log_and_message_admins(adminalert)
	busy = TRUE
	Q = new ghost_query_type()
	RegisterSignal(Q, COMSIG_GHOST_QUERY_COMPLETE, PROC_REF(get_winner))
	Q.query()

/obj/structure/ghost_pod/proc/get_winner()
	SIGNAL_HANDLER
	busy = FALSE
	if(length(Q.candidates))
		var/mob/observer/dead/D = Q.candidates[1]
		UnregisterSignal(Q, COMSIG_GHOST_QUERY_COMPLETE)
		QDEL_NULL(Q) //get rid of the query
		create_occupant(D)
		return

	if(delay_to_try_again)
		om_after(src, delay_to_try_again, PROC_REF(trigger))
	UnregisterSignal(Q, COMSIG_GHOST_QUERY_COMPLETE)
	QDEL_NULL(Q) //get rid of the query

// Override this to create whatever mob you need. Be sure to call ..() if you don't want it to make infinite mobs.
/obj/structure/ghost_pod/proc/create_occupant(mob/M)
	open_pod()

/// Marks the pod used and opened (and swaps it for a charger if it needs one).
/obj/structure/ghost_pod/proc/open_pod()
	used = TRUE
	icon_state = icon_state_opened
	registry_leave(REGISTRY_GHOST_PODS, src)
	if(needscharger)
		replace_with(src, /obj/machinery/recharge_station/ghost_pod_recharger)

// This type is triggered manually by a player discovering the pod and deciding to open it.
/obj/structure/ghost_pod/manual
	var/confirm_before_open = FALSE // Recommended to be TRUE if the pod contains a surprise.

/obj/structure/ghost_pod/manual/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/ghost_pod_open,
	)
	..()

/// Old attack_hand: open the pod.
/datum/interaction/entry_hand/ghost_pod_open
	id = "ghost_pod_open"
	name = "Open"
	effect = /obj/structure/ghost_pod/manual/proc/interaction_open

/obj/structure/ghost_pod/manual/proc/interaction_open(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!used)
		if(confirm_before_open)
			om_prompt(src, user, list("message" = "Are you sure you want to touch \the [src]?", "title" = "Confirm", "choices" = list("No", "Yes"), "requires" = PROMPT_ADJACENT), PROC_REF(touch_confirmed))
			return TRUE
		touch_confirmed(user, "Yes")
	return TRUE

/obj/structure/ghost_pod/manual/attack_ai(mob/living/silicon/user)
	if(Adjacent(user))
		attack_hand(user) // Borgs can open pods.

// This type is triggered on a timer, as opposed to needing another player to 'open' the pod.  Good for away missions.
/obj/structure/ghost_pod/automatic
	delay_to_self_open = 10 MINUTES
	delay_to_try_again = 20 MINUTES

/obj/structure/ghost_pod/automatic/Initialize(mapload)
	. = ..()
	om_after(src, delay_to_self_open, PROC_REF(trigger))

/obj/structure/ghost_pod/automatic/trigger(mob/user)
	. = ..()
	if(. == FALSE) // If we failed to get a volunteer, try again later if allowed to.
		if(delay_to_try_again)
			om_after(src, delay_to_try_again, PROC_REF(trigger))

// This type is triggered by a ghost clicking on it, as opposed to a living player.  A ghost query type isn't needed.
/obj/structure/ghost_pod/ghost_activated
	description_info = "A ghost can click on this to return to the round as whatever is contained inside this object."

/obj/structure/ghost_pod/ghost_activated/attack_ghost(mob/observer/dead/user)
	if(jobban_isbanned(user, JOB_GHOSTROLES))
		to_chat(user, span_warning("You cannot inhabit this creature because you are banned from playing ghost roles."))
		return

	//No OOC notes
	if (not_has_ooc_text(user))
		return

	if(used)
		to_chat(user, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return

	om_prompt(src, user, list("message" = "Are you certain you wish to activate this pod?", "title" = "Control Pod", "choices" = list("Yes", "No")), PROC_REF(activation_confirmed))

/obj/structure/ghost_pod/proc/activation_confirmed(mob/observer/dead/user, choice, datum/om/prompt/ask)
	busy = FALSE
	if(choice != "Yes")
		return
	if(used)
		to_chat(user, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return
	create_occupant(user)

/obj/structure/ghost_pod/manual/proc/touch_confirmed(mob/living/user, choice, datum/om/prompt/ask)
	if(choice != "Yes" || used)
		return
	trigger(user)
	if(!used)
		activated = TRUE
		ghostpod_startup(FALSE)

/// Asks a ghost which maintenance critter to become; spawn_maint_critter() makes it once confirmed.
/obj/structure/ghost_pod/proc/ask_maint_critter(mob/M, message, title)
	om_prompt(src, M, list("kind" = "list", "message" = message, "title" = title, "choices" = GLOB.maint_mob_pred_options, "requires" = list(/datum/om/check/has_client), "on_cancel" = PROC_REF(maint_critter_cancelled), "data" = list("message" = message, "title" = title)), PROC_REF(maint_critter_chosen))

/obj/structure/ghost_pod/proc/maint_critter_cancelled(mob/M, datum/om/prompt/ask)
	to_chat(M, span_notice("No mob selected, cancelling."))
	reset_ghostpod()

/obj/structure/ghost_pod/proc/maint_critter_chosen(mob/M, choice, datum/om/prompt/ask)
	ask.put("choice", choice)
	om_prompt_chain(ask, list("message" = "Are you sure you want to play as [choice]?", "title" = "Confirmation", "choices" = list("No", "Yes"), "on_cancel" = PROC_REF(maint_critter_cancelled)), PROC_REF(maint_critter_confirmed))

/obj/structure/ghost_pod/proc/maint_critter_confirmed(mob/M, confirm, datum/om/prompt/ask)
	if(confirm != "Yes")
		ask_maint_critter(M, ask.get("message"), ask.get("title"))
		return
	spawn_maint_critter(M, ask.get("choice"))

/obj/structure/ghost_pod/proc/spawn_maint_critter(mob/M, choice)
	return

/// Offers the new mob's player their saved vore bellies.
/mob/living/proc/offer_load_bellies()
	om_prompt(src, src, list("message" = "Do you want to load the vore bellies from your current slot?", "title" = "Load Bellies", "choices" = list("Yes", "No")), PROC_REF(load_bellies_answered))

/mob/living/proc/load_bellies_answered(mob/user, answer, datum/om/prompt/ask)
	if(answer != "Yes")
		return
	copy_from_prefs_vr()
	if(LAZYLEN(vore_organs))
		vore_selected = vore_organs[1]

/// Lets a freshly spawned character pick a new name.
/mob/living/carbon/human/proc/offer_spawn_rename()
	om_prompt(src, src, list("kind" = "text", "message" = "Your mind feels foggy, and you recall your name might be [real_name]. Would you like to change your name?", "title" = "Name change", "max_length" = MAX_NAME_LEN), PROC_REF(spawn_renamed))

/mob/living/carbon/human/proc/spawn_renamed(mob/user, newname, datum/om/prompt/ask)
	if(newname)
		real_name = newname


REGISTRY_MEMBERSHIP(/obj/structure/ghost_pod, REGISTRY_GHOST_PODS)

/obj/structure/ghost_pod
	var/spawn_active = FALSE

/obj/structure/ghost_pod/manual
	var/remains_active = FALSE
	var/activated = FALSE

/obj/structure/ghost_pod/manual/attack_ghost(mob/observer/dead/user)
	if(jobban_isbanned(user, JOB_GHOSTROLES))
		to_chat(user, span_warning("You cannot inhabit this creature because you are banned from playing ghost roles."))
		return

	//No OOC notes
	if (not_has_ooc_text(user))
		return

	if(!remains_active || busy)
		return

	if(!activated)
		to_chat(user, span_warning("\The [src] has not yet been activated.  Sorry."))
		return

	if(used)
		to_chat(user, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return

	busy = TRUE
	if(!om_prompt(src, user, list("message" = "Are you certain you wish to activate this pod?", "title" = "Control Pod", "choices" = list("Yes", "No"), "on_cancel" = PROC_REF(activation_cancelled)), PROC_REF(activation_confirmed)))
		busy = FALSE

/obj/structure/ghost_pod/proc/activation_cancelled(mob/observer/dead/user, datum/om/prompt/ask)
	busy = FALSE

/obj/structure/ghost_pod/proc/ghostpod_startup(notify = FALSE)
	registry_join(REGISTRY_GHOST_PODS, src)
	if(notify)
		trigger()

/obj/structure/ghost_pod/ghost_activated/Initialize(mapload)
	. = ..()
	if(!mapload)
		return INITIALIZE_HINT_LATELOAD

/obj/structure/ghost_pod/ghost_activated/LateInitialize()
	ghostpod_startup(spawn_active)
