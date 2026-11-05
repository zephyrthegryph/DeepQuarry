// The examine icon cache: an atom's last examine icon, kept for a while so examining it again does not redraw it (lazy state atom_misc, the storage contract).
// It names the state, so it lives in content; the host layer below the engine may not.
/proc/set_cached_examine_icon(atom/A, icon/I, expiry = 20 MINUTES)
	if(!A)
		return
	STATE_SET(A, atom_misc, examine_icon_snapshot, I)
	if(expiry && !after_pending(A, "examine_icon_expiry"))
		after(A, expiry, TYPE_PROC_REF(/atom, uncache_examine_icon), key = "examine_icon_expiry")

/proc/get_cached_examine_icon(atom/A)
	return STATE_PEEK(A, atom_misc, examine_icon_snapshot)

/atom/proc/uncache_examine_icon()
	STATE_SET(src, atom_misc, examine_icon_snapshot, null)

