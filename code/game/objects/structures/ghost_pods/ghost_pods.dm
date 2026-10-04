// These are used to spawn a specific mob when triggered, with the mob controlled by a player pulled from the ghost pool, hense its name.
/obj/structure/ghost_pod
	name = "Base Ghost Pod"
	desc = "If you can read me, someone don goofed."
	icon = 'icons/obj/structures.dmi'
	var/ghost_query_type = null
	var/icon_state_opened = null	// Icon to switch to when 'used'.
	var/used = FALSE
	var/busy = FALSE // Don't spam ghosts by spamclicking.
	/// Operator who started this query, distinct from its volunteer winner.
	var/mob/opening_actor
	var/needscharger //For drone pods that want their pod to turn into a charger.
	var/datum/ghost_query/Q //This is used so we can unregister ourself.
	unacidable = TRUE
	var/delay_to_self_open = 0 // How long to wait for first attempt.  Note that the timer by default starts when the pod is created.
	var/delay_to_try_again = 0 // How long to wait if first attempt fails.  Set to 0 to never try again.

CAPABILITIES(/obj/structure/ghost_pod)
	owns_one(nameof(Q), /datum/ghost_query)

// Call this to get a ghost volunteer.
/obj/structure/ghost_pod/proc/trigger(mob/user, alert, adminalert)
	if(!ghost_query_type)
		return FALSE
	if(busy)
		return FALSE

	rel_set(src, nameof(opening_actor), user)
	if(alert)
		visible_message(alert)
	if(adminalert)
		log_and_message_admins(adminalert, user)
	busy = TRUE
	rel_set(src, nameof(Q), new ghost_query_type())
	observe(Q, /datum/notice/ghost_query_complete, src, then(PROC_REF(get_winner)))
	Q.query()

/obj/structure/ghost_pod/proc/get_winner(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	busy = FALSE
	if(length(Q.candidates))
		var/mob/observer/dead/D = Q.candidates[1]
		unobserve(Q, /datum/notice/ghost_query_complete, src)
		own_clear(src, nameof(Q), OWN_DELETE) //get rid of the query
		create_occupant(D)
		return

	// No volunteer: an automatic pod's auto_trigger() repeat tries again after delay_to_try_again.
	unobserve(Q, /datum/notice/ghost_query_complete, src)
	own_clear(src, nameof(Q), OWN_DELETE) //get rid of the query

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
	silicon_use = ROBOT_USE_HAND_ADJACENT // borgs can open pods
	var/confirm_before_open = FALSE // Recommended to be TRUE if the pod contains a surprise.

/obj/structure/ghost_pod/manual/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/ghost_pod_open,
	)
	into += dq_interaction_from_spec(type, INTERACT_OBSERVER("Inhabit", PROC_REF(ghost_pod_manual_observer_use)))
	..()

/// Old attack_hand: open the pod.
/datum/interaction/entry_hand/ghost_pod_open
	id = "ghost_pod_open"
	name = "Open"
	effect = /obj/structure/ghost_pod/manual/proc/interaction_open

/obj/structure/ghost_pod/manual/proc/interaction_open(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!used)
		if(confirm_before_open)
			open_request(src, /datum/prompt/yes_no, PROC_REF(touch_confirmed), valid = PROC_REF(touch_valid), answerer = user, title = "Confirm", question = "Are you sure you want to touch \the [src]?", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
			return TRUE
		touch_pod(user)
	return TRUE

// This type is triggered on a timer, as opposed to needing another player to 'open' the pod.  Good for away missions.
/obj/structure/ghost_pod/automatic
	delay_to_self_open = 10 MINUTES
	delay_to_try_again = 20 MINUTES
	/// How long until auto_trigger() next runs: delay_to_self_open first, then delay_to_try_again.
	var/next_auto_delay = 0

DECLARE_REPEAT(/obj/structure/ghost_pod/automatic, "auto_delay", auto_trigger, null)

/// The repeat's delay: delay_to_self_open until the first try, then delay_to_try_again.
/obj/structure/ghost_pod/automatic/proc/auto_delay()
	return next_auto_delay || delay_to_self_open

/// Opens itself on a timer; if that fails to get a volunteer, tries again later if allowed to.
/obj/structure/ghost_pod/automatic/proc/auto_trigger()
	if(used)
		return REPEAT_STOP
	trigger() // FALSE while a query is still out; the next run tries again
	if(!delay_to_try_again)
		return REPEAT_STOP
	next_auto_delay = delay_to_try_again

// This type is triggered by a ghost clicking on it, as opposed to a living player.  A ghost query type isn't needed.
/obj/structure/ghost_pod/ghost_activated

// Subtypes with their own ghost use override ghost_pod_observer_use() (it never fell through).
EXTEND_INTERACTIONS(/obj/structure/ghost_pod/ghost_activated, INTERACT_OBSERVER("Inhabit", PROC_REF(ghost_pod_observer_use), REQ_TARGET_STATE(/obj/structure/ghost_pod/ghost_activated/proc/can_inhabit)))

/// Requirement: TRUE, or why this ghost can't take the pod. Subtypes with their own ghost use override it.
/obj/structure/ghost_pod/ghost_activated/proc/can_inhabit(mob/observer/dead/user, atom/target, obj/item/held)
	if(jobban_isbanned(user, JOB_GHOSTROLES))
		return "you cannot inhabit this creature because you are banned from playing ghost roles"
	if(used)
		return "another spirit appears to have gotten to it before you, sorry"
	return TRUE

/// Old attack_ghost: a ghost inhabits the pod.
/obj/structure/ghost_pod/ghost_activated/proc/ghost_pod_observer_use(mob/observer/dead/user, obj/item/held, datum/interaction/interaction)
	//No OOC notes
	if (not_has_ooc_text(user))
		return TRUE

	ask_activation(user)
	return TRUE

/// A ghost confirms taking a pod. The pod is busy while it's open (manual pods): any answer or a cancel frees it.
/obj/structure/ghost_pod/proc/ask_activation(mob/user)
	return open_request(src, /datum/prompt/yes_no, PROC_REF(activation_confirmed), answerer = user, title = "Control Pod", question = "Are you certain you wish to activate this pod?", timeout = 0)

/obj/structure/ghost_pod/proc/activation_confirmed(datum/act/request/A)
	busy = FALSE
	if(!A.answer || !A.answer.answer_value)
		return
	var/mob/observer/dead/user = A.request.answerer
	if(used)
		to_chat(user, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return
	create_occupant(user)

/// Re-checked: the pod is still unused.
/obj/structure/ghost_pod/manual/proc/touch_valid(datum/request/R)
	return !used

/obj/structure/ghost_pod/manual/proc/touch_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.answer_value)
		return
	touch_pod(A.request.answerer)

/obj/structure/ghost_pod/manual/proc/touch_pod(mob/living/user)
	if(used)
		return
	trigger(user)
	if(!used)
		activated = TRUE
		ghostpod_startup(FALSE)

/// Asks a ghost which maintenance critter to become; spawn_maint_critter() makes it once confirmed.
/obj/structure/ghost_pod/proc/ask_maint_critter(mob/M, message, title)
	open_request(src, /datum/prompt/choice, PROC_REF(maint_critter_chosen), valid = PROC_REF(answerer_has_client), answerer = M, question = message, title = title, choices = assoc_to_keys(GLOB.maint_mob_pred_options), timeout = 0)

/// Re-checked: the ghost still has a client.
/obj/structure/ghost_pod/proc/answerer_has_client(datum/request/R)
	var/mob/M = R.answerer
	return istype(M) && !!M.client

/// Confirms the pick; a no asks again with the first question's text and title.
/datum/prompt/yes_no/maint_critter
	title = "Confirmation"
	var/critter
	var/first_message
	var/first_title

/obj/structure/ghost_pod/proc/maint_critter_cancelled(mob/M)
	to_chat(M, span_notice("No mob selected, cancelling."))
	reset_ghostpod()

/// A ghost picks a maintenance critter (message and title from the call). A cancel resets the pod.
/obj/structure/ghost_pod/proc/maint_critter_chosen(datum/act/request/A)
	var/datum/prompt/choice/asked = A.request
	var/mob/M = asked.answerer
	if(!A.answer)
		maint_critter_cancelled(M)
		return
	var/critter = A.answer.answer_value
	open_request(src, /datum/prompt/yes_no/maint_critter, PROC_REF(maint_critter_confirmed), answerer = M, question = "Are you sure you want to play as [critter]?", critter = critter, first_message = asked.question, first_title = asked.title, timeout = 0)

/obj/structure/ghost_pod/proc/maint_critter_confirmed(datum/act/request/A)
	var/datum/prompt/yes_no/maint_critter/R = A.request
	if(!A.answer)
		maint_critter_cancelled(R.answerer)
		return
	if(!A.answer.answer_value)
		ask_maint_critter(R.answerer, R.first_message, R.first_title)
		return
	spawn_maint_critter(R.answerer, R.critter)

/obj/structure/ghost_pod/proc/spawn_maint_critter(mob/M, choice)
	return

/// Offers the new mob's player their saved vore bellies.
/mob/living/proc/offer_load_bellies()
	open_request(src, /datum/prompt/yes_no, PROC_REF(load_bellies_answered), answerer = src, title = "Load Bellies", question = "Do you want to load the vore bellies from your current slot?", timeout = 0)

/mob/living/proc/load_bellies_answered(datum/act/request/A)
	if(!A.answer || !A.answer.answer_value)
		return
	copy_from_prefs_vr()
	if(LAZYLEN(vore_organs))
		rel_set(src, nameof(vore_selected), vore_organs[1])

/// Lets a freshly spawned character pick a new name.
/mob/living/carbon/human/proc/offer_spawn_rename()
	open_request(src, /datum/prompt/text, PROC_REF(spawn_renamed), answerer = src, title = "Name change", question = "Your mind feels foggy, and you recall your name might be [real_name]. Would you like to change your name?", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/mob/living/carbon/human/proc/spawn_renamed(datum/act/request/A)
	if(!A.answer)
		return
	var/newname = A.answer.answer_value
	if(newname)
		real_name = newname


REGISTRY_MEMBERSHIP(/obj/structure/ghost_pod, REGISTRY_GHOST_PODS)

/obj/structure/ghost_pod
	var/spawn_active = FALSE

/obj/structure/ghost_pod/manual
	var/remains_active = FALSE
	var/activated = FALSE

/// Old attack_ghost: a ghost takes over an activated pod that stays open to ghosts.
/obj/structure/ghost_pod/manual/proc/ghost_pod_manual_observer_use(mob/observer/dead/user, obj/item/held, datum/interaction/interaction)
	if(jobban_isbanned(user, JOB_GHOSTROLES))
		to_chat(user, span_warning("You cannot inhabit this creature because you are banned from playing ghost roles."))
		return TRUE

	//No OOC notes
	if (not_has_ooc_text(user))
		return TRUE

	if(!remains_active || busy)
		return TRUE

	if(!activated)
		to_chat(user, span_warning("\The [src] has not yet been activated.  Sorry."))
		return TRUE

	if(used)
		to_chat(user, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return TRUE

	busy = TRUE
	if(!ask_activation(user))
		busy = FALSE
	return TRUE

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


/obj/structure/ghost_pod/relations()
	. = ..()
	. += rel_one(nameof(opening_actor))
