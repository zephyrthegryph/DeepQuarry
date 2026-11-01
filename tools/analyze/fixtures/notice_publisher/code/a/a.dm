ACTION(fall)
ACTION(jump, notice = /datum/notice/jumped_far)
ACTION(sing)

/datum/notice/dead
/datum/notice/legacy
/datum/notice/parent
/datum/notice/parent/child
/datum/notice/from_data
/datum/notice/test_only

/datum/fx/reactions()
	. += on_notice(/datum/notice/legacy, PROC_REF(x))
	. += on_notice(/datum/notice/parent, PROC_REF(x))
	. += on_notice(/datum/notice/from_data, PROC_REF(x))
	. += on_notice(/datum/notice/fell, PROC_REF(x))
	. += on_notice(/datum/notice/jumped_far, PROC_REF(x))
	. += on_notice(/datum/notice/dead, PROC_REF(x))
	. += on_notice(/datum/notice/sang, PROC_REF(x))
	observe(src, /datum/notice/test_only, src, then(PROC_REF(x)))

/datum/fx/proc/go()
	PUBLISH_LEGACY(src, /datum/notice/legacy)
	publish(src, take_notice(/datum/notice/parent/child))
	var/notice_type = /datum/notice/from_data
	act_fall(src)
	ACT_ATTEMPT(src, jump)
