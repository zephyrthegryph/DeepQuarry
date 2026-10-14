// Tests are not exempt: a seeded typo here is caught like any other.
/datum/unit_test/keys_probe
	var/note = "x"

/datum/unit_test/keys_probe/proc/run_it(mob/user)
	perform_op(user, user, "cover.open")
	perform_op(user, user, "cover.missing")
