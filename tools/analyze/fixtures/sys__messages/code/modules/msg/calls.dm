/mob/proc/bare_pair()
	visible_message("[src] waves", "You wave")

/mob/proc/bare_self_null()
	visible_message("something happens", null)

/mob/proc/bare_one_arg()
	visible_message("something happens")

/mob/proc/bare_names_src()
	visible_message("[src] waves")

/mob/proc/bare_names_src_name()
	visible_message("[src.name] waves")

/mob/proc/bare_names_src_real()
	visible_message("[ src.real_name ] waves")

/mob/proc/bare_names_src_other()
	visible_message("[src.loc] waves")

/mob/proc/bare_exclude()
	visible_message("it waves", exclude_mobs = list(src))

/mob/proc/bare_exclude_pos()
	visible_message("it waves", exclude_x)

/mob/proc/bare_self_named()
	visible_message("it waves", self_message = "you wave")

/mob/proc/bare_self_named_null()
	visible_message("it waves", self_message = null)

/mob/proc/bare_range()
	visible_message("it waves", range = 1)

/mob/proc/bare_message_named()
	visible_message(message = "it waves", self_message = "you")

/mob/proc/bare_message_named2()
	visible_message(message = "[src] waves", range = 3)

/mob/proc/bare_blind_named()
	visible_message("x", blind_message = "[user] hears something")

/mob/proc/bare_eq()
	visible_message("x", a == b)

/obj/proc/obj_bare_pair()
	visible_message("[src] waves", "You wave")

/obj/proc/obj_names_user(mob/user)
	visible_message("[user] touches [src]")

/obj/proc/obj_names_usr()
	visible_message("[usr] touches [src]")

/obj/proc/obj_names_user_name(mob/user)
	visible_message("[user.name] touches [src]")

/obj/proc/obj_ok(mob/user)
	visible_message("[src] hums")

/obj/proc/user_recv(mob/user)
	user.visible_message("a", "b")

/obj/proc/user_recv_ok(mob/user)
	user.visible_message("a")

/obj/proc/user_recv_names(mob/user)
	user.visible_message("[user] a")

/obj/proc/usr_recv()
	usr.visible_message("a", "b")

/obj/proc/declared_recv(mob/living/M)
	M.visible_message("[M] a", "b")

/obj/proc/declared_recv_ok(mob/living/M)
	M.visible_message("a")

/obj/proc/declared_recv_names(mob/living/M)
	M.visible_message("[M] a")

/obj/proc/declared_recv_name(mob/living/M)
	M.visible_message("[M.name] a")

/obj/proc/declared_recv_nonmob(obj/O)
	O.visible_message("[O] a", "b")

/obj/proc/undeclared_recv()
	R.visible_message("[R] a", "b")

/obj/proc/declared_recv_nested(mob/living/M)
	var/obj/thing/T = M.visible_message("a", "b")
	T.visible_message("a", "b")

/obj/proc/src_recv()
	src.visible_message("[src] a", "b")

/mob/proc/src_recv_mob()
	src.visible_message("[src] a", "b")

/mob/proc/src_recv_mob_ok()
	src.visible_message("a")

/obj/proc/pair_to_chat(mob/user)
	to_chat(user, "You do it")
	user.visible_message("it happens")

/obj/proc/pair_to_chat_src()
	to_chat(src, "You do it")
	visible_message("it happens")

/obj/proc/pair_to_chat_blank_between(mob/user)
	to_chat(user, "You do it")


	user.visible_message("it happens")

/obj/proc/pair_to_chat_other(mob/user)
	to_chat(user, "You do it")
	M.visible_message("it happens")

/obj/proc/pair_to_chat_comment(mob/user)
	to_chat(user, "You do it")
	// a comment line
	user.visible_message("it happens")

/obj/proc/pair_to_chat_first_line()
	visible_message("it happens")

/obj/proc/multi_line(mob/user)
	user.visible_message(
		"it happens",
		"to you"
	)

/obj/proc/multi_line_named(mob/user)
	visible_message("x",
		self_message = "you",
		range = 2)

/obj/proc/string_commas(mob/user)
	user.visible_message("a, b, c", "d")

/obj/proc/string_brackets(mob/user)
	user.visible_message("a [list("x", "y")] b")

/obj/proc/string_brackets2(mob/user)
	user.visible_message("a [list(1, 2)] b", "c")

/obj/proc/escaped(mob/user)
	user.visible_message("a \" , b", "c")

/obj/proc/escaped2(mob/user)
	user.visible_message("a \", b")

/obj/proc/nested_calls(mob/user)
	user.visible_message("x [foo(1, 2)]", bar(3, 4))

/obj/proc/commented_call(mob/user)
	// user.visible_message("a", "b")
	user.visible_message("a") // user.visible_message("a", "b")

/obj/proc/block_call(mob/user)
	/user.visible_message("a", "b")

/obj/proc/trailing_comment_before(mob/user)
	var/x = 1 // visible_message("a", "b")

/obj/proc/receiver_split(mob/user)
	user
		.visible_message("a", "b")

/obj/proc/receiver_split2(mob/user)
	user.
	visible_message("a", "b")

/obj/proc/third_arg_names(mob/user)
	visible_message("a", null, "[user] hears")

/obj/proc/fourth_arg_names(mob/user)
	visible_message("a", null, null, "[user] hears")

/obj/proc/range_numbers(mob/user)
	visible_message("a", 1, "b")

/obj/proc/message_kw_first(mob/user)
	visible_message(range = 2, message = "[user] a")

/obj/proc/allowed_pair(mob/user)
	user.visible_message("a", "b") // ALLOW(sys_visible_pair): migration pending

/obj/proc/allowed_pair_above(mob/user)
	// ALLOW(sys_visible_pair): migration pending
	user.visible_message("a", "b")

/obj/proc/allowed_inline_marker(mob/user)
	user.visible_message("a", "b") // ALLOW(sys_visible_pair)

/obj/proc/unbalanced(mob/user)
	user.visible_message("a", "b"

/obj/proc/unbalanced2(mob/user)
	user.visible_message("a", "b"]) )

/obj/proc/brace_args(mob/user)
	user.visible_message({"a", "b"}, "c")

/mob/living/proc/living_bare()
	visible_message("[src] a", "b")

/mobile/proc/not_a_mob_type()
	visible_message("[src] a", "b")

/mob
	proc/old_style()
		visible_message("[src] a", "b")

/mob/proc/trailing_call_in_args()
	visible_message("a", "b"); visible_message("[src] c")

/obj/proc/call_one_line_two(mob/user)
	to_chat(user, "hello"); user.visible_message("it")

/obj/proc/dotted_receiver()
	owner.mob.visible_message("a", "b")
	thing.mob_ref.visible_message("a")

#define VM(x) x.visible_message("a", "b")
#define MSG(x) visible_message("[src] a")
