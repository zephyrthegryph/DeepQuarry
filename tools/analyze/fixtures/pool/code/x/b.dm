/proc/f()
	new /datum/foo
	new /datum/foo/child
	new /datum/foobar
	new   /datum/decl(1)
	new /datum/commented
	new /datum/baz
	var/s = "new /datum/foo"
	// new /datum/foo
	new /datum/foo // ALLOW(pool): kept
	// ALLOW(pool): above is not honoured
	new /datum/bar
	new /datum/notype
	x = new /datum/foo + new /datum/decl
	new /datum/foo/a/b
	new /datum/
	renew /datum/foo
	new/datum/foo
