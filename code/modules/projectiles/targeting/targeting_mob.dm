/mob/living/var/obj/aiming_overlay/aiming
/mob/living/var/list/aimed = list()

/mob/verb/toggle_gun_mode()
	set name = "Toggle Gun Mode"
	set desc = "Begin or stop aiming."
	set category = VERB_CAT_IC_GAME

	if(isliving(src))
		var/mob/living/M = src
		if(!M.aiming)
			rel_set(M, nameof(M.aiming), new /obj/aiming_overlay(src))
		M.aiming.toggle_active()
	else
		to_chat(src, span_warning("This verb may only be used by living mobs, sorry."))
	return

/mob/living/proc/stop_aiming(obj/item/thing, no_message = 0)
	if(!aiming)
		return
	if(thing && aiming.aiming_with() != thing)
		return
	aiming.cancel_aiming(no_message)

/mob/living/update_canmove()
	..()
	if(lying)
		stop_aiming(no_message=1)

/turf/Enter(mob/living/mover)
	. = ..()
	if(istype(mover))
		if(mover.aiming && mover.aiming.aiming_at)
			mover.aiming.update_aiming()
		if(LAZYLEN(mover.aimed))
			mover.trigger_aiming(TARGET_CAN_MOVE)

/mob/living/forceMove(atom/destination, direction, movetime)
	. = ..()
	if(aiming && aiming.aiming_at)
		aiming.update_aiming()
	if(LAZYLEN(aimed))
		trigger_aiming(TARGET_CAN_MOVE)

/mob/living/proc/set_m_intent(intent)
	if (intent != I_WALK && intent != I_RUN)
		return 0
	m_intent = intent
	if(hud_used)
		if (hud_used.move_intent)
			hud_used.move_intent.icon_state = intent == I_WALK ? "walking" : "running"

