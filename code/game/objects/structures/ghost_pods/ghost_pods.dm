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

TRACKED(/obj/structure/ghost_pod, used)
TRACKED(/obj/structure/ghost_pod, busy)

CAPABILITIES(/obj/structure/ghost_pod)
	ref_one(nameof(opening_actor))
	owns_one(nameof(Q), /datum/ghost_query)

/// Why `user`'s ghost may not take a ghost role here, or null: the ghost-role ban, then the OOC notes (the old not_has_ooc_text() check, as a reason).
/proc/ghost_role_refusal(mob/observer/dead/user, ban_reason = "You cannot inhabit this creature because you are banned from playing ghost roles.")
	READS_FROM() // bans, config and preferences are not round state an op could watch
	if(jobban_isbanned(user, JOB_GHOSTROLES))
		return ban_reason
	if(CONFIG_GET(flag/allow_metadata) && length(user.client?.prefs?.read_preference(/datum/preference/text/living/ooc_notes)) < 15)
		return "Please set informative OOC notes related to RP/ERP preferences. Set them using the 'OOC Notes' button on the 'General' tab in character setup."
	return null

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
	set_busy(TRUE)
	rel_set(src, nameof(Q), new ghost_query_type())
	observe(Q, /datum/notice/ghost_query_complete, src, then(PROC_REF(get_winner)))
	Q.query()

/obj/structure/ghost_pod/proc/get_winner(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	set_busy(FALSE)
	if(length(Q.candidates))
		var/mob/observer/dead/D = Q.candidates[1]
		unobserve(Q, /datum/notice/ghost_query_complete, src)
		rel_clear(src, nameof(Q)) //get rid of the query
		create_occupant(D)
		return

	// No volunteer: an automatic pod's auto_trigger() repeat tries again after delay_to_try_again.
	unobserve(Q, /datum/notice/ghost_query_complete, src)
	rel_clear(src, nameof(Q)) //get rid of the query

// Override this to create whatever mob you need. Be sure to call ..() if you don't want it to make infinite mobs.
/obj/structure/ghost_pod/proc/create_occupant(mob/M)
	open_pod()

/// Marks the pod used and opened (and swaps it for a charger if it needs one).
/obj/structure/ghost_pod/proc/open_pod()
	set_used(TRUE)
	icon_state = icon_state_opened
	registry_leave(REGISTRY_GHOST_PODS, src)
	if(needscharger)
		replace_with(src, /obj/machinery/recharge_station/ghost_pod_recharger)

// This type is triggered manually by a player discovering the pod and deciding to open it.
/obj/structure/ghost_pod/manual
	silicon_use = ROBOT_USE_HAND_ADJACENT // borgs can open pods
	var/confirm_before_open = FALSE // Recommended to be TRUE if the pod contains a surprise.

TRACKED(/obj/structure/ghost_pod/manual, confirm_before_open)

CAPABILITIES(/obj/structure/ghost_pod/manual)
	op("open", hand(), label("Open"), needs(req_is(nameof(used), FALSE, because = /datum/msg/req_silent)),
		asks(/datum/prompt/yes_no, fields = list("title" = "Confirm", "question" = computed(PROC_REF(touch_question)), "timeout" = 0), when = nameof(confirm_before_open)),
		then(PROC_REF(interaction_open)))
	// the old attack_ghost: a ghost takes over an activated pod that stays open to ghosts
	op("inhabit", observer(), label("Inhabit"), needs(req(PROC_REF(may_inhabit), because = PROC_REF(inhabit_refusal))),
		asks(/datum/prompt/yes_no, fields = list("title" = "Control Pod", "question" = "Are you certain you wish to activate this pod?", "timeout" = 0), keeps = TARGET_PRESENT),
		then(PROC_REF(inhabit_confirmed)))

/obj/structure/ghost_pod/manual/proc/touch_question(datum/act/A)
	return "Are you sure you want to touch \the [src]?"

/// Old attack_hand: open the pod (a pod with a surprise asks first).
/obj/structure/ghost_pod/manual/proc/interaction_open(datum/act/op/A)
	var/mob/living/user = A.actor
	if(confirm_before_open)
		var/datum/prompt/R = A.answer
		if(!R?.value)
			return OP_OK
	touch_pod(user)
	return OP_OK

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

/// Requirement: the ghost may take the pod. Subtypes with their own ghost use override inhabit_refusal().
/obj/structure/ghost_pod/ghost_activated/proc/can_inhabit(datum/act/op/A)
	return isnull(inhabit_refusal(A))

/// Why this ghost can't take the pod, or null.
/obj/structure/ghost_pod/ghost_activated/proc/inhabit_refusal(datum/act/op/A)
	var/why = ghost_role_refusal(A.actor)
	if(why)
		return why
	if(used)
		return MSG(ghost_pod/taken)
	return null

/// The question a ghost answers before it takes the pod: its title and text (a subtype with its own words overrides them).
/obj/structure/ghost_pod/ghost_activated/proc/inhabit_title(datum/act/A)
	return "Control Pod"

/obj/structure/ghost_pod/ghost_activated/proc/inhabit_question(datum/act/A)
	return "Are you certain you wish to activate this pod?"

/// Old attack_ghost: the ghost said yes, and takes the pod (unless another spirit got there first).
/obj/structure/ghost_pod/ghost_activated/proc/ghost_pod_observer_use(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R?.value)
		return OP_OK
	if(used)
		to_chat(A.actor, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return OP_OK
	create_occupant(A.actor)
	return OP_OK

/obj/structure/ghost_pod/manual/proc/touch_pod(mob/living/user)
	if(used)
		return
	trigger(user)
	if(!used)
		set_activated(TRUE)
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
	var/critter = A.answer.value
	open_request(src, /datum/prompt/yes_no/maint_critter, PROC_REF(maint_critter_confirmed), answerer = M, question = "Are you sure you want to play as [critter]?", critter = critter, first_message = asked.question, first_title = asked.title, timeout = 0)

/obj/structure/ghost_pod/proc/maint_critter_confirmed(datum/act/request/A)
	var/datum/prompt/yes_no/maint_critter/R = A.request
	if(!A.answer)
		maint_critter_cancelled(R.answerer)
		return
	if(!A.answer.value)
		ask_maint_critter(R.answerer, R.first_message, R.first_title)
		return
	spawn_maint_critter(R.answerer, R.critter)

/obj/structure/ghost_pod/proc/spawn_maint_critter(mob/M, choice)
	return

/// Offers the new mob's player their saved vore bellies.
/mob/living/proc/offer_load_bellies()
	open_request(src, /datum/prompt/yes_no, PROC_REF(load_bellies_answered), answerer = src, title = "Load Bellies", question = "Do you want to load the vore bellies from your current slot?", timeout = 0)

/mob/living/proc/load_bellies_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
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
	var/newname = A.answer.value
	if(newname)
		real_name = newname


REGISTRY_MEMBERSHIP(/obj/structure/ghost_pod, REGISTRY_GHOST_PODS)

/obj/structure/ghost_pod
	var/spawn_active = FALSE

/obj/structure/ghost_pod/manual
	var/remains_active = FALSE
	var/activated = FALSE

TRACKED(/obj/structure/ghost_pod/manual, remains_active)
TRACKED(/obj/structure/ghost_pod/manual, activated)

/// A ghost may take over the pod: not banned, OOC notes set, the pod stays open to ghosts, is activated and unused.
/obj/structure/ghost_pod/manual/proc/may_inhabit(datum/act/op/A)
	return isnull(inhabit_refusal(A))

/obj/structure/ghost_pod/manual/proc/inhabit_refusal(datum/act/op/A)
	var/why = ghost_role_refusal(A.actor)
	if(why)
		return why
	if(!remains_active || busy)
		return MSG(ghost_pod/closed)
	if(!activated)
		return MSG(ghost_pod/not_activated)
	if(used)
		return MSG(ghost_pod/taken)
	return null

/// The ghost said yes: it takes the pod (unless another spirit got there first).
/obj/structure/ghost_pod/manual/proc/inhabit_confirmed(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R?.value)
		return OP_OK
	if(used)
		to_chat(A.actor, span_warning("Another spirit appears to have gotten to \the [src] before you.  Sorry."))
		return OP_OK
	create_occupant(A.actor)
	return OP_OK

MSG_DEF_SELF(ghost_pod/closed, "It is not open to spirits right now.")
MSG_DEF_SELF(ghost_pod/not_activated, "It has not yet been activated.  Sorry.")
MSG_DEF_SELF(ghost_pod/taken, "Another spirit appears to have gotten to it before you.  Sorry.")

/obj/structure/ghost_pod/proc/ghostpod_startup(notify = FALSE)
	registry_join(REGISTRY_GHOST_PODS, src)
	if(notify)
		trigger()

CAPABILITIES(/obj/structure/ghost_pod/ghost_activated)
	after_init(0, then(PROC_REF(start_up_spawned)))
	// the old attack_ghost: a ghost takes the pod after a yes
	op("inhabit", observer(), label("Inhabit"), needs(req(PROC_REF(can_inhabit), because = PROC_REF(inhabit_refusal))),
		asks(/datum/prompt/yes_no, fields = list("title" = computed(PROC_REF(inhabit_title)), "question" = computed(PROC_REF(inhabit_question)), "timeout" = 0), keeps = TARGET_PRESENT),
		then(PROC_REF(ghost_pod_observer_use)))

/// A pod made during the round starts up once it exists (a mapped one waits).
/obj/structure/ghost_pod/ghost_activated/proc/start_up_spawned(datum/act/timer/A)
	if(A.mapload)
		return
	ghostpod_startup(spawn_active)
