// Generic lifecycle notices, independent of gameplay consumers.
/datum/notice/do_after_ended

/datum/notice/qdeleting
	var/force

/datum/notice/qdeleting/fill(force)
	src.force = force
