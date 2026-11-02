/datum/test_fx/reactions()
	. += on_notice(/datum/notice/test_only, PROC_REF(x))

/datum/test_fx/proc/go()
	PUBLISH_LEGACY(src, /datum/notice/test_only)
