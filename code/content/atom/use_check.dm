// Checks if user can use this object. Set use_flags to customize what checks are done.
// Returns 0 if they can use it, a value representing why they can't if not.
// Flags are in `code/defines/content/misc.dm`
#define NOT_FLAG(flag) (!(flag & use_flags))
#define HAS_FLAG(flag) (flag & use_flags)
/// Why `user` can't use this (a USE_FAIL_* value), or 0. Pure: it tells the player nothing (a requirement may call it).
/atom/proc/use_check_failure(mob/user, use_flags = 0)
	. = 0
	if (NOT_FLAG(USE_ALLOW_NONLIVING) && !isliving(user))
		return USE_FAIL_NONLIVING
	if (NOT_FLAG(USE_ALLOW_NON_ADJACENT) && !Adjacent(user))
		return USE_FAIL_NON_ADJACENT
	if (NOT_FLAG(USE_ALLOW_DEAD) && user.stat == DEAD)
		return USE_FAIL_DEAD
	if (NOT_FLAG(USE_ALLOW_INCAPACITATED) && (user.incapacitated()))
		return USE_FAIL_INCAPACITATED
	if (NOT_FLAG(USE_ALLOW_NON_ADV_TOOL_USR) && !user.IsAdvancedToolUser())
		return USE_FAIL_NON_ADV_TOOL_USR
	if (HAS_FLAG(USE_FORCE_SRC_IN_USER) && !(src in user))
		return USE_FAIL_NOT_IN_USER

/atom/proc/use_check(mob/user, use_flags = 0, show_messages = FALSE)
	. = use_check_failure(user, use_flags)
	if(!. || !show_messages)
		return
	// No message for ghosts.
	switch(.)
		if(USE_FAIL_NON_ADJACENT)
			to_chat(user, span_notice("You're too far away from [src] to do that."))
		if(USE_FAIL_DEAD)
			to_chat(user, span_notice("You can't do that when you're dead."))
		if(USE_FAIL_INCAPACITATED)
			to_chat(user, span_notice("You cannot do that in your current state."))
		if(USE_FAIL_NON_ADV_TOOL_USR)
			to_chat(user, span_notice("You don't know how to operate [src]."))
		if(USE_FAIL_NOT_IN_USER)
			to_chat(user, span_notice("You need to be holding [src] to do that."))

#undef NOT_FLAG
#undef HAS_FLAG
