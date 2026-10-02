// An unbalanced apostrophe drops lines from the code view: the ALLOW lookup and the fingerprint read raw
// lines at the code view's line numbers.
/obj/thing/proc/drift()
	var/x = 'a
	spawn(0)
	var/y = b'
	sleep(1)
	spawn(1) // ALLOW(scheduler): keeps nothing when the line numbers drift
	del(src)

// Non-ASCII text around the matches.
/obj/thing/proc/unicode()
	var/s = "héllo ✓ sleep(1)" ; sleep(1) // ünï ✓
	spawn(0) // 😀 ALLOW(scheduler): the fixture keeps this unicode spawn on purpose
	var/日本 = WEAKREF(src) // 日本語
	WEAKREF(src) // ALLOW(scheduler): the fixture keeps this weakref on purpose
	ſpawn(1)
	wéakref
	WEAKREF
	weaKref
	WEAK_REF
