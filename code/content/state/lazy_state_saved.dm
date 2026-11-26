// The lazy states of an object (the table-form rows of the storage contract, code/engine/declare/lazy_state.dm) used to be saved vars (doc/rewrite/proposals/base_vars.md).
// The state schema saves an object's non-tmp vars that differ from their defaults; a lazy field lives in an engine table row, so the plain ones (numbers, text, paths,
// lists) ride beside the delta instead (state_extra(), code/engine/state/schema.dm) as "lazy.feature.field", and cloning and persistence keep them as they
// kept the vars. A field at its default is not saved, and neither is a datum, an image or a weak reference (runtime only).

/obj/state_extra()
	. = ..()
	var/list/lazy = lazy_state_saved(src)
	for(var/key in lazy)
		. = . || list()
		.["lazy.[key]"] = lazy[key]

/obj/state_apply_extra(list/extra)
	..()
	var/list/lazy
	for(var/key in extra)
		if(copytext(key, 1, 6) == "lazy.")
			lazy = lazy || list()
			lazy[copytext(key, 6)] = extra[key]
	lazy_state_restore(src, lazy)
