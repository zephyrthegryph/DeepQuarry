// BYOND built-ins that hold references, written through the engine (doc/rewrite/proposals/relations.md D11).
//
// vis_contents, client.screen and client.images keep atoms and images alive where the collector cannot see. Content writes them only through
// these verbs (the native_ref_write lint counts the raw writes that are left), so the engine owns the one write path: the declared relation
// ends with native storage, their reverse index and their teardown are added here, not at every call site. Today the verbs write the
// built-in (null-safe, a deleted thing is refused); a dying movable already leaves every vis_contents that shows it (atoms_movable.dm) and a
// client's screen is released with the client.

/// Shows `thing` (an atom, or a list of them) through `holder`'s vis_contents.
/proc/vis_add(atom/holder, thing)
	if(!holder || isnull(thing) || (isdatum(thing) && QDELETED(thing)))
		return
	holder.vis_contents += thing

/// Stops showing `thing` (an atom, or a list) through `holder`.
/proc/vis_remove(atom/holder, thing)
	if(!holder || isnull(thing))
		return
	holder.vis_contents -= thing

/// Puts `thing` (a screen object, or a list) on client `C`'s screen.
/proc/client_screen_add(client/C, thing)
	if(!C || isnull(thing) || (isdatum(thing) && QDELETED(thing)))
		return
	C.screen += thing

/// Takes `thing` (or a list) off client `C`'s screen.
/proc/client_screen_remove(client/C, thing)
	if(!C || isnull(thing))
		return
	C.screen -= thing

/// Shows image `thing` (or a list) to client `C`.
/proc/client_images_add(client/C, thing)
	if(!C || isnull(thing))
		return
	C.images += thing

/// Stops showing image `thing` (or a list) to client `C`.
/proc/client_images_remove(client/C, thing)
	if(!C || isnull(thing))
		return
	C.images -= thing
