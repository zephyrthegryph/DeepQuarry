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
	. = ..()
	if(stat != old_stat)
		om_changed(src, CHANGE_MOB_STAT)
		SEND_SIGNAL(src, COMSIG_MOB_STATCHANGE, old_stat, new_stat)

		if(isbelly(src.loc))
			var/obj/belly/ourbelly = src.loc
			if(!ourbelly.owner || !ourbelly.owner.client)
				return
			if(stat == CONSCIOUS)
				to_chat(ourbelly.owner, span_notice("\The [src.name] is awake."))
			else if(stat == UNCONSCIOUS)
				to_chat(ourbelly.owner, span_red("\The [src.name] has fallen unconscious!"))
