// Checks if user can use this object. Set use_flags to customize what checks are done.
// Returns 0 if they can use it, a value representing why they can't if not.
// Flags are in `code/defines/content/misc.dm`
#define NOT_FLAG(flag) (!(flag & use_flags))
#define HAS_FLAG(flag) (flag & use_flags)
/atom/proc/use_check(mob/user, use_flags = 0, show_messages = FALSE)
	. = 0
	if (NOT_FLAG(USE_ALLOW_NONLIVING) && !isliving(user))
		// No message for ghosts.
		return USE_FAIL_NONLIVING

	if (NOT_FLAG(USE_ALLOW_NON_ADJACENT) && !Adjacent(user))
		if (show_messages)
			to_chat(user, span_notice("You're too far away from [src] to do that."))
		return USE_FAIL_NON_ADJACENT

	if (NOT_FLAG(USE_ALLOW_DEAD) && user.stat == DEAD)
		if (show_messages)
			to_chat(user, span_notice("You can't do that when you're dead."))
		return USE_FAIL_DEAD

	if (NOT_FLAG(USE_ALLOW_INCAPACITATED) && (user.incapacitated()))
		if (show_messages)
			to_chat(user, span_notice("You cannot do that in your current state."))
		return USE_FAIL_INCAPACITATED

	if (NOT_FLAG(USE_ALLOW_NON_ADV_TOOL_USR) && !user.IsAdvancedToolUser())
		if (show_messages)
			to_chat(user, span_notice("You don't know how to operate [src]."))
		return USE_FAIL_NON_ADV_TOOL_USR

	if (HAS_FLAG(USE_FORCE_SRC_IN_USER) && !(src in user))
		if (show_messages)
			to_chat(user, span_notice("You need to be holding [src] to do that."))
		return USE_FAIL_NOT_IN_USER

#undef NOT_FLAG
#undef HAS_FLAG
