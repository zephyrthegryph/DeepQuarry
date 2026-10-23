// BYOND built-ins that hold references, written through the engine (doc/rewrite/proposals/relations.md D11).
//
// vis_contents, client.screen and client.images keep atoms and images alive where the collector cannot see. Content writes them only through
// these verbs (the native_ref_write lint counts the raw writes that are left), so the engine owns the one write path: the declared relation
// ends with native storage, their reverse index and their teardown are added here, not at every call site. Today the verbs write the
// built-in (null-safe, a deleted thing is refused); a dying movable already leaves every vis_contents that shows it (atoms_movable.dm) and a
// client's screen is released with the client.

/// Shows `thing` (an atom, or a list of them) through `holder`'s vis_contents.
/proc/vis_add(atom/holder, thing)
	if(!holder || isnull(thing) || datum_deleted(thing))
		return
	if(ismovable(holder))
		var/atom/movable/M = holder // typed per kind: the native compiler resolves vis_contents storage on /atom/movable and /turf, not /atom
		M.vis_contents += thing
	else if(isturf(holder))
		var/turf/T = holder
		T.vis_contents += thing

/// Stops showing `thing` (an atom, or a list) through `holder`.
/proc/vis_remove(atom/holder, thing)
	if(!holder || isnull(thing))
		return
	if(ismovable(holder))
		var/atom/movable/M = holder
		M.vis_contents -= thing
	else if(isturf(holder))
		var/turf/T = holder
		T.vis_contents -= thing

/// Shows `thing` (an atom, or a list) through `holder`'s vis_contents unless it is already there (`|=`).
/proc/vis_include(atom/holder, thing)
	if(!holder || isnull(thing) || datum_deleted(thing))
		return
	if(ismovable(holder))
		var/atom/movable/M = holder
		M.vis_contents |= thing
	else if(isturf(holder))
		var/turf/T = holder
		T.vis_contents |= thing

/// Replaces `holder`'s vis_contents with `thing` (an atom, a list, or null for none).
/proc/vis_set(atom/holder, thing)
	if(!holder)
		return
	var/list/shown = null
	if(islist(thing))
		shown = thing
	else if(!isnull(thing))
		shown = list(thing)
	if(ismovable(holder))
		var/atom/movable/M = holder
		M.vis_contents = shown
	else if(isturf(holder))
		var/turf/T = holder
		T.vis_contents = shown

/// Empties `holder`'s vis_contents.
/proc/vis_clear(atom/holder)
	if(!holder)
		return
	if(ismovable(holder))
		var/atom/movable/M = holder
		M.vis_contents.Cut()
	else if(isturf(holder))
		var/turf/T = holder
		T.vis_contents.Cut()

/// Puts `thing` (a screen object, or a list) on client `C`'s screen.
/proc/client_screen_add(client/C, thing)
	if(!C || isnull(thing) || datum_deleted(thing))
		return
	C.screen += thing

/// Puts `thing` (or a list) on client `C`'s screen unless it is already there (`|=`).
/proc/client_screen_include(client/C, thing)
	if(!C || isnull(thing) || datum_deleted(thing))
		return
	C.screen |= thing

/// Empties client `C`'s screen.
/proc/client_screen_clear(client/C)
	if(!C)
		return
	C.screen = list()

/// Takes `thing` (or a list) off client `C`'s screen.
/proc/client_screen_remove(client/C, thing)
	if(!C || isnull(thing))
		return
	C.screen -= thing

// ---- client.images: the declared end with its reverse index and teardown ----
// An image shown to a client through these verbs is indexed by the atom it rides on (image.loc) and by its viewers, so the end tears itself
// down: a dying atom takes its images off every client that sees them (client_images_drop_for(), from /atom/movable/Destroy), and a leaving
// client takes itself out of every image's viewers (client_images_client_gone(), from /client/Destroy). Images shown by a raw write are not
// indexed (the native_ref_write ratchet counts those).

GLOBAL_LIST_EMPTY(client_images_by_loc) // atom -> list of images riding on it that some client sees through client_images_add()
GLOBAL_LIST_EMPTY(client_image_viewers) // image -> list of the clients it was shown to

/// Shows image `thing` (or a list) to client `C`.
/proc/client_images_add(client/C, thing)
	if(!C || isnull(thing))
		return
	C.images += thing
	client_images_index(C, thing)

/// Records `thing` (an image or a list) as shown to `C`, by viewer and by the atom it rides on.
/proc/client_images_index(client/C, thing)
	for(var/image/I as anything in (islist(thing) ? thing : list(thing)))
		if(!istype(I))
			continue
		var/list/viewers = GLOB.client_image_viewers[I]
		if(!viewers)
			viewers = GLOB.client_image_viewers[I] = list()
		viewers |= C
		var/atom/rides = I.loc
		if(isatom(rides))
			var/list/riding = GLOB.client_images_by_loc[rides]
			if(!riding)
				riding = GLOB.client_images_by_loc[rides] = list()
			riding |= I

/// Shows image `thing` (or a list) to client `C` unless it is already shown (`|=`).
/proc/client_images_include(client/C, thing)
	if(!C || isnull(thing))
		return
	C.images |= thing
	client_images_index(C, thing)

/// Takes every image off client `C`.
/proc/client_images_clear(client/C)
	if(!C)
		return
	client_images_client_gone(C)
	C.images = null

/// Stops showing image `thing` (or a list) to client `C`.
/proc/client_images_remove(client/C, thing)
	if(!C || isnull(thing))
		return
	C.images -= thing
	for(var/image/I as anything in (islist(thing) ? thing : list(thing)))
		client_image_unview(I, C)

/// `C` no longer sees `I`: the index forgets the pair, and the image once nobody sees it.
/proc/client_image_unview(image/I, client/C)
	var/list/viewers = GLOB.client_image_viewers[I]
	if(!viewers)
		return
	viewers -= C
	if(length(viewers))
		return
	GLOB.client_image_viewers -= I
	var/atom/rides = I.loc
	var/list/riding = isatom(rides) ? GLOB.client_images_by_loc[rides] : null
	if(riding)
		riding -= I
		if(!length(riding))
			GLOB.client_images_by_loc -= rides

/// Teardown of a dying atom: every image riding on it leaves every client that sees it.
/proc/client_images_drop_for(atom/A)
	var/list/riding = GLOB.client_images_by_loc[A]
	if(!riding)
		return
	GLOB.client_images_by_loc -= A
	for(var/image/I as anything in riding)
		for(var/client/C as anything in GLOB.client_image_viewers[I])
			C.images -= I
		GLOB.client_image_viewers -= I

/// Teardown of a leaving client: it leaves the viewers of every image it was shown through the verbs.
/proc/client_images_client_gone(client/C)
	for(var/image/I as anything in C.images)
		client_image_unview(I, C)

/// TRUE when `thing` is a datum being deleted (typed for QDELETED(): `thing` may also be a list or an image).
/proc/datum_deleted(thing)
	if(!isdatum(thing))
		return FALSE
	var/datum/D = thing
	return QDELETED(D)
