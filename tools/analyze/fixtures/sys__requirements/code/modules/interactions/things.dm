DECLARE_INTERACTIONS(/obj/thing, INTERACT_USE("Open", PROC_REF(do_open)), INTERACT_USE("Close", PROC_REF(do_close)))
EXTEND_INTERACTIONS(/obj/thing/sub, \
	INTERACT_USE("Lock", PROC_REF(do_lock)), \
	INTERACT_USE("Unlock", TYPE_PROC_REF(/obj/thing, do_unlock)), \
	INTERACT_USE("Legacy", .proc/do_legacy))
DECLARE_INTERACTIONS(/obj/other, INTERACT_USE(null, PROC_REF(other_effect)))

/obj/thing/proc/do_open(mob/user)
	if(locked)
		to_chat(user, "It is locked.")
		return
	do_the_open()

/obj/thing/proc/do_close(mob/user)
	var/x = 5
	SHOULD_NOT_SLEEP(TRUE)
	if(!anchored) return to_chat(user, "Bolt it down.")
	if(broken) { to_chat(user, "Broken."); return }
	if(foo)
		balloon_alert(user, "no")
		playsound(src, 'x.ogg', 50)
		return FALSE
	do_the_close()

/obj/thing/proc/do_lock(mob/user)
	if(prob(50))
		to_chat(user, "You fumble.")
		return
	if(use(1) == 0)
		to_chat(user, "Out of charge.")
		return
	if(locked)
		visible_message("The lock rattles.")
		return
	else
		do_it()
	do_the_lock()

/obj/thing/sub/proc/do_unlock(mob/user)
	if(!locked)
		to_chat(user, "Already unlocked")
		return
	if(maybe)
		do_other_thing()
		return
	if(never)
		to_chat(user, "never")
		return
	do_the_unlock()

/obj/thing/sub/do_legacy(mob/user)
	set name = "x"
	if(a) return
	if(b) return show_message("b")
	if(c)
		user.show_message("c")
		audible_message("also c")
		return 1
	if(d)
		SEND_SOUND(user, sound('x.ogg'))
		to_chat(user, "d")
		return
	if(e)
		to_chat(user, "e")
		stuff()
		return
	if(f) { stuff(); return }
	do_legacy_thing()

/obj/other/proc/other_effect(mob/user)
	var/choice = tgui_input_list(user, "Which?", "x", list("a"))
	if(!choice)
		to_chat(user, "nothing chosen")
		return
	if(locked)
		to_chat(user, "after the ask")
		return

/obj/other/proc/other_effect2(mob/user)
	if(locked)
		to_chat(user, "not an effect proc name")
		return

/obj/unrelated/proc/other_effect(mob/user)
	if(locked)
		to_chat(user, "not related type")
		return

/obj/other/child/proc/other_effect(mob/user)
	if(locked)
		to_chat(user, "related by subtype")
		return

/obj
	proc/other_effect(mob/user)
		return

/obj/other/proc/other_effect(mob/user)
	if(locked)
		// to_chat(user, "commented body line")
		return
	if(foo)
		to_chat(user, "x // not a comment") // trailing
		return
	if(bar) to_chat(user, "single quote 'x' y"); return
	if(baz)
		return to_chat(user, "z")
	if(qux)
		return
	do_x()

/obj/other/proc/other_effect(mob/user)
	// ALLOW(sys_inline_refusal): the legacy refusal stays for now
	if(locked)
		to_chat(user, "kept")
		return
	if(unlocked) // ALLOW(sys_inline_refusal): same line
		to_chat(user, "kept2")
		return
	do_x()

/obj/other/proc/other_effect(mob/user)
	if(a)
		to_chat(user, "else follows")
		return
	else
		do_x()
	do_y()

/obj/other/proc/other_effect(mob/user)
	if(a && b)
		return
	if(drop_item())
		to_chat(user, "acting cond")
		return
	if(c)
		to_chat(user, "after acting cond")
		return
	foo()
	if(d)
		to_chat(user, "after work")
		return

/obj/other/proc/other_effect(mob/user)
	var/ok = use_tool(user)
	if(a)
		to_chat(user, "after acting var")
		return

/obj/other/proc/other_effect(mob/user)
	if(a
		&& b)
		to_chat(user, "multi-line cond")
		return
	if(broken)
		to_chat(
			user,
			"multi-line message")
		return

/obj/thing/proc/helper(mob/user)
	REFUSE_IF(locked, "It is locked")
	var/x = REFUSE_IF_NOT(a)

/obj/thing/proc/helper2(mob/user)
	// REFUSE_IF(commented)
	to_chat(user, "REFUSE_IF(string) is blanked")
	REFUSE_IF (spaced)

#define REFUSE_IF(cond, msg) if(cond) return to_chat(user, msg)
#define SOMETHING_ELSE REFUSE_IF(a, b)
