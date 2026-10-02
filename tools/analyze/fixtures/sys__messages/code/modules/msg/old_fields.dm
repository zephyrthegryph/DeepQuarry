/datum/interaction/old
	message_self = "you do it"
	message_others = "someone does it"

/datum/interaction/old2/proc/run()
	start_messages(user)
	fill_message(user, "x")
	var/a = src.message_self
	var/b = foo.message_others
	var/c = my_message_self
	var/d = message_selfish
	// message_self in a comment
	var/e = "message_self" // not a comment here
	var/f = x.start_messages(1)
	var/g = start_messages (2)

/datum/interaction/old3
	message_self = "kept" // ALLOW(sys_visible_pair): migration pending
	// ALLOW(sys_visible_pair): migration pending
	message_others = "kept too"
	message_self = "marker" // ALLOW(sys_visible_pair)
	message_others = "not kept" // ALLOW(other_lint): wrong name
