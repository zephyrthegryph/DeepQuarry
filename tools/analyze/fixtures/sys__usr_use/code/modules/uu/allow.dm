/mob/proc/kept()
	var/a = usr // ALLOW(sys_usr_outside_verb): the fixture keeps this one on the line
	// ALLOW(sys_usr_outside_verb): the fixture keeps the next one from the comment line above
	var/b = usr
	var/c = usr // ALLOW(usr_outside_verb): the rule name without sys_ keeps nothing
	var/d = usr // ALLOW(sys_usr_outside_verb)
	var/e = usr // ALLOW(sys_sync_sql): another module's name keeps nothing
	var/f = usr // ALLOW(init, sys_usr_outside_verb): two names, one of them ours
	var/g = usr
/mob/verb/ask()
	var/h = usr // ALLOW(sys_usr_outside_verb): nothing to keep in a verb body
