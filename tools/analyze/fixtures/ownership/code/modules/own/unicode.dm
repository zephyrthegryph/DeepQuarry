// Non-ASCII text on lines the checks slice and index by byte offset.
/obj/holder/proc/unicode(M)
	held = "héllo wörld ✓" // ünï
	occupant = null // 😀
	var/s = "日本語 [held]"
	M.held = null // ✓
	héld = null
	stuff += "naïve" // ALLOW(ownership): the fixture keeps this unicode write on purpose
	own_set(src, "ghøst", src)
	own_set(src, nameof(ghöst_two), src)
	var/datum/callback/cb = CALLBACK(src, PROC_REF(unicode)) // ünï
	var/h = om_handle(src) // ✓ ✓
	DECLARE_REF(thing) // 日本
