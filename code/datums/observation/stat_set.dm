//	Observer Pattern Implementation: Stat Set
//		Registration type: /mob/living
//
//		Raised when: A /mob/living changes stat, using the set_stat() proc
//
//		Arguments that the called proc should expect:
//			/mob/living/stat_mob: The mob whose stat changed
//			/old_stat: Status before the change.
//			/new_stat: Status after the change.
//Deprecated in favor of Comsigs

/****************
* Stat Handling *
****************/
/mob/living/set_stat(new_stat)
	var/old_stat = stat
	// Leaving DEAD is a revival, and revivals go through return_from_death() (body/revival.dm).
	if(old_stat == DEAD && new_stat != DEAD && !revival_in_progress)
		stack_trace("set_stat([new_stat]) on dead [key_name(src)] ([type]) outside return_from_death(); refused.")
		return FALSE
	. = ..()
	if(stat != old_stat)
		PUBLISH_LEGACY(src, /datum/notice/mob_statchange, new_stat, old_stat)

		if(isbelly(src.loc))
			var/obj/belly/ourbelly = src.loc
			if(!ourbelly.owner || !ourbelly.owner.client)
				return
			if(stat == CONSCIOUS)
				to_chat(ourbelly.owner, span_notice("\The [src.name] is awake."))
			else if(stat == UNCONSCIOUS)
				to_chat(ourbelly.owner, span_red("\The [src.name] has fallen unconscious!"))
