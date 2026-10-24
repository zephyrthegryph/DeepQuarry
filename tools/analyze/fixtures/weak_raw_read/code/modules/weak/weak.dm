// weak_raw_read fixture: one positive and one negative case per shape.

/mob/target
/mob/target/sub

/datum/other
	var/last_user = "plain" // a different type's var of the same name: never judged

/datum/watcher
	var/mob/target/last_user
	var/list/seen

CAPABILITIES(/datum/watcher)
	ref_one(nameof(last_user), /mob/target, weak = TRUE)
	ref_many(nameof(seen), /mob/target, weak = TRUE)

/datum/watcher/sub

/datum/watcher/proc/good(mob/target/M)
	rel_set(src, nameof(last_user), M)
	rel_add(src, nameof(/datum/watcher::seen), M)
	var/mob/target/T = last_user()
	return T

/datum/watcher/proc/bad_bare()
	var/mob/target/T = last_user
	return T

/datum/watcher/proc/bad_src()
	return src.last_user

/datum/watcher/proc/bad_write(mob/target/M)
	last_user = M

/datum/watcher/proc/bad_list()
	return length(seen)

/datum/watcher/sub/proc/bad_subtype()
	return last_user

/datum/watcher/proc/shadowed()
	var/last_user = 3
	return last_user

/proc/bad_foreign(datum/watcher/W, datum/other/O)
	var/a = W.last_user
	var/b = O.last_user
	return list(a, b)

/proc/good_foreign(datum/watcher/W)
	return W.last_user()

/proc/bad_list_foreign(datum/watcher/W)
	return W.seen
