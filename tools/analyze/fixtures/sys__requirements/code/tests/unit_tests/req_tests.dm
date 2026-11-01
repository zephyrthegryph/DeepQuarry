/obj/thing/proc/do_open(mob/user)
	if(locked)
		to_chat(user, "unit test exempt")
		return
	REFUSE_IF(a, "x")
