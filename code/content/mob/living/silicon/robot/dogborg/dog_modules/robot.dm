/obj/item/mining_scanner/robot
	name = "integrated deep scan device"

/obj/item/mining_scanner/robot/proc/upgrade(mob/user)
	desc = "An advanced device used to locate ore deep underground."
	set_scan_time(0.5 SECONDS)
	set_exact(TRUE)

CAPABILITIES(/obj/item/mining_scanner/robot)
	op("set_range", hand(), gesture(GESTURE_ALT), label("Set Scanner Range"), when(nameof(exact)), needs(carried()),
		asks(/datum/prompt/choice, keeps = 0, fields = list("timeout" = 0, "question" = "Scanner Range", "title" = "Pick a range to scan. ", "choices" = list(0,1,2,3,4,5,6,7))), then(PROC_REF(range_picked)))

/obj/item/mining_scanner/robot/proc/range_picked(datum/act/op/A)
	var/datum/prompt/choice/picked = A.answer
	// Unlike the advanced handheld, the integrated scanner accepts zero.
	set_range(picked.value)
	to_chat(A.actor, span_notice("Scanner will now look up to [range] tile(s) away."))
	return OP_OK
