//as core click exists at the mob level
/mob/proc/trigger_aiming(trigger_type)
	return

/mob/living/trigger_aiming(trigger_type)
	if(!LAZYLEN(aimed))
		return
	for(var/obj/aiming_overlay/AO in aimed)
		if(AO.aiming_at == src)
			AO.update_aiming()
			if(AO.aiming_at == src)
				AO.trigger(trigger_type)
				AO.update_aiming_deferred()

/obj/aiming_overlay/proc/trigger(perm)
	if(!owner() || !aiming_with() || !aiming_at || !locked)
		return
	if(perm && (target_permissions & perm))
		return
	if(!owner().checkClickCooldown())
		return
	owner().setClickCooldown(5) // Spam prevention, essentially.
	// A reflex shot is not an input: the aimer's posture (combat mode) decides the safety.
	if(!owner().combat_mode && owner().client?.prefs?.read_preference(/datum/preference/toggle/safefiring))
		to_chat(owner(), span_warning("You refrain from firing \the [aiming_with()] as you are out of combat mode."))
		return
	owner().visible_message(span_danger("\The [owner()] pulls the trigger reflexively!"))
	var/obj/item/gun/G = aiming_with()
	if(istype(G))
		G.Fire(aiming_at, owner(), reflex = 1)
		set_locked(0)
		EXPIRY_SET(src, lock_time, 10, CLOCK_WORLD)
