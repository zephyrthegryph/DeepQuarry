/obj/item/assembly_holder
	name = "Assembly"
	icon = 'icons/obj/assemblies/new_assemblies.dmi'
	icon_state = "holder"
	item_state = "assembly"
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 3
	throw_range = 10

	var/secured = 0
	var/obj/item/assembly/a_left = null
	var/obj/item/assembly/a_right = null
	var/tmp/obj/special_assembly

// Its assemblies stop naming it (ones inside go with it; ones taken out stay).

/obj/item/assembly_holder/proc/attach(obj/item/assembly/D, obj/item/assembly/D2, mob/user)
	if(!D || !D2)
		return FALSE

	if(!istype(D) || !istype(D2))
		return FALSE

	if(D.secured || D2.secured)
		return FALSE

	rel_set(D, nameof(D.holder), src)
	rel_set(D2, nameof(D2.holder), src)
	move_into(src, nameof(src.a_left), D, user)
	move_into(src, nameof(src.a_right), D2, user)
	name = "[D.name]-[D2.name] assembly"
	update_icon()
	user.put_in_hands(src)

	return TRUE

/obj/item/assembly_holder/proc/detached()
	return

DECLARE_APPEARANCE_PROC(/obj/item/assembly_holder, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/assembly_holder/appearance_overlays()
	. = list()
	if(a_left)
		. += "[a_left.icon_state]_left"
		for(var/O in a_left.attached_overlays)
			. += "[O]_l"
	if(a_right)
		. += "[a_right.icon_state]_right"
		for(var/O in a_right.attached_overlays)
			. += "[O]_r"
	if(master)
		master.update_icon()

/obj/item/assembly_holder/examine(mob/user)
	. = ..()
	if ((in_range(src, user) || src.loc == user))
		if (src.secured)
			. += "\The [src] is ready!"
		else
			. += "\The [src] can be attached!"

/obj/item/assembly_holder/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(isturf(old_loc))
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity), center = old_loc)
	if(isturf(loc))
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	if(a_left && a_right)
		a_left.holder_movement()
		a_right.holder_movement()

/obj/item/assembly_holder/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	if(a_left)
		a_left.HasProximity(T, WF, old_loc)
	if(a_right)
		a_right.HasProximity(T, WF, old_loc)

/obj/item/assembly_holder/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(a_left)
		a_left.Crossed(AM)
	if(a_right)
		a_right.Crossed(AM)

/obj/item/assembly_holder/on_found(mob/finder as mob)
	if(a_left)
		a_left.on_found(finder)
	if(a_right)
		a_right.on_found(finder)

/obj/item/assembly_holder/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/assembly_holder_hand,
		/datum/interaction/entry_self/assembly_holder_self,
	)
	..()

/// Old attack_hand: notify the parts before falling through (never handled the click itself).
/datum/interaction/entry_hand/assembly_holder_hand
	id = "assembly_holder_hand"
	name = "Use"
	effect = /obj/item/assembly_holder/proc/interaction_hand

/obj/item/assembly_holder/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)//Perhapse this should be a holder_pickup proc instead, can add if needbe I guess
	if(a_left && a_right)
		a_left.holder_movement()
		a_right.holder_movement()
	return FALSE

/obj/item/assembly_holder/screwdriver_act(mob/user, obj/item/tool)
	if(!a_left || !a_right)
		to_chat(user, span_warning(" BUG:Assembly part missing, please report this!"))
		return ITEM_INTERACT_BLOCKING
	a_left.toggle_secure()
	a_right.toggle_secure()
	secured = !secured
	to_chat(user, span_notice(secured ? "\The [src] is ready!" : "\The [src] can now be taken apart!"))
	update_icon()
	return ITEM_INTERACT_SUCCESS

/// Old attack_self: split assembly (unsecured) or use the parts (secured).
/datum/interaction/entry_self/assembly_holder_self
	id = "assembly_holder_self"
	name = "Use"
	effect = /obj/item/assembly_holder/proc/interaction_self

/obj/item/assembly_holder/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(src.secured)
		if(!a_left || !a_right)
			to_chat(user, span_warning(" BUG:Assembly part missing, please report this!"))
			return TRUE
		if(istype(a_left,a_right.type))//If they are the same type it causes issues due to window code
			var/_answer_k143 = rerun_ask(user, "k143", PROC_REF(interaction_self), args, /datum/om/prompt/choice/alert, message = "Which side would you like to use?", title = "Side", choices = list("Left","Right"))
			if(isnull(_answer_k143))
				return TRUE
			switch(_answer_k143)
				if("Left")	a_left.attack_self(user)
				if("Right")	a_right.attack_self(user)
			return TRUE
		else
			if(!istype(a_left,/obj/item/assembly/igniter))
				a_left.attack_self(user)
			if(!istype(a_right,/obj/item/assembly/igniter))
				a_right.attack_self(user)
	else
		var/turf/T = get_turf(src)
		if(!T)
			return TRUE
		if(loc?.release_refusal(src, user))
			return TRUE
		// Taken out of the holder before it is consumed (CONTAINED: they must leave its slots first).
		var/obj/item/assembly/left = rel_take(src, nameof(a_left))
		var/obj/item/assembly/right = rel_take(src, nameof(a_right))
		if(left)
			rel_clear(left, nameof(left.holder))
			left.forceMove(T)
		if(right)
			rel_clear(right, nameof(right.holder))
			right.forceMove(T)
		consume(src, user)
	return TRUE

/obj/item/assembly_holder/proc/process_activation(obj/D, normal = 1)
	if(!D)
		return 0
	if(!secured)
		visible_message("[icon2html(src,viewers(src))] *beep* *beep*", "*beep* *beep*")
	if((normal) && (a_right) && (a_left))
		if(a_right != D)
			a_right.pulsed(0)
		if(a_left != D)
			a_left.pulsed(0)
	if(master)
		master.receive_signal()
	return 1

/obj/item/assembly_holder/hear_talk(mob/M, list/message_pieces, verb)
	if(a_right)
		a_right.hear_talk(M, message_pieces, verb)
	if(a_left)
		a_left.hear_talk(M, message_pieces, verb)

/obj/item/assembly_holder/timer_igniter
	name = "timer-igniter assembly"

/obj/item/assembly_holder/timer_igniter/Initialize(mapload)
	. = ..()

	var/obj/item/assembly/igniter/ign = new(src)
	ign.set_secured(TRUE)
	rel_set(ign, nameof(ign.holder), src)

	var/obj/item/assembly/timer/tmr = new(src)
	tmr.time = 5
	tmr.set_secured(TRUE)
	rel_set(tmr, nameof(tmr.holder), src)

	rel_set(src, nameof(a_left), tmr)
	rel_set(src, nameof(a_right), ign)
	secured = 1
	update_icon()
	name = initial(name) + " ([tmr.time] secs)"

	if(loc)
		grant(loc, granted_verb(/obj/item/assembly_holder/timer_igniter/verb/configure), src)

/obj/item/assembly_holder/timer_igniter/detached()
	if(loc)
		revoke(loc, granted_verb(/obj/item/assembly_holder/timer_igniter/verb/configure), src)
	..()

/obj/item/assembly_holder/timer_igniter/verb/configure()
	set name = "Set Timer"
	set category = VERB_CAT_OBJECT
	set src in usr

	if(!istype(src, /obj/item/grenade/chem_grenade))
		to_chat(usr, span_notice("This detonator has no timer."))
		return
	var/obj/item/grenade/chem_grenade/grenade = src
	grenade.configure_detonator_timer(usr)

/// The granted verb runs on the grenade; resolve its current detonator again on an answer.
/obj/item/grenade/chem_grenade/proc/configure_detonator_timer(mob/user, timer_answer, answer_ready = FALSE)
	if(!(user.stat || user.restrained()))
		var/obj/item/assembly_holder/holder = detonator
		if(!holder)
			to_chat(user, span_notice("This detonator has no timer."))
			return
		var/obj/item/assembly/timer/tmr = holder.a_left
		if(!istype(tmr, /obj/item/assembly/timer))
			tmr = holder.a_right
		if(!istype(tmr, /obj/item/assembly/timer))
			to_chat(user, span_notice("This detonator has no timer."))
			return
		if(tmr.timing)
			to_chat(user, span_notice("Clock is ticking already."))
		else if(!answer_ready)
			open_request(src, /datum/prompt/number/grenade_timer_configuration, PROC_REF(detonator_timer_entered), answerer = user)
		else if(timer_answer > 0 && timer_answer < 1000)
			tmr.time = timer_answer
			name = initial(name) + "([tmr.time] secs)"
			to_chat(user, span_notice("Timer set to [tmr.time] seconds."))
		else
			to_chat(user, span_notice("Timer can't be [timer_answer <= 0 ? "negative" : "more than 1000 seconds"]."))
	else
		to_chat(user, span_notice("You cannot do this while [user.stat ? "unconscious/dead" : "restrained"]."))

/obj/item/grenade/chem_grenade/proc/detonator_timer_entered(datum/act/request/A)
	if(!A.answer)
		return
	configure_detonator_timer(A.request.answerer, A.answer.value, TRUE)

/datum/prompt/number/grenade_timer_configuration
	question = "Enter desired time in seconds"
	title = "Time"
	default = 5
	min_value = 0
	max_value = 1000
	timeout = 0
	recheck_on_open = TRUE

/// Keep the legacy server answer raw; the real numeric window still rounds and bounds entries.
/datum/prompt/number/grenade_timer_configuration/recheck_extra()
	return QDELETED(owner) || QDELETED(answerer) ? "gone" : null

/datum/prompt/number/grenade_timer_configuration/normalize(given)
	return isnum(given) ? given : null

/obj/item/assembly_holder/ownership()
	. = ..()
	. += owns(nameof(a_left), policy = OWN_CONTAINED)
	. += owns(nameof(a_right), policy = OWN_CONTAINED)

/// the special_assembly this refers to (a relation view: null once it is deleted).
/obj/item/assembly_holder/proc/special_assembly() as /obj
	return special_assembly
