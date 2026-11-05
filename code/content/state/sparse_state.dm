// Sparse slots that used to be saved vars (doc/rewrite/proposals/base_vars.md, wave 2). The state schema saves an object's non-tmp vars that differ
// from their defaults; a slot lives in the tmp sparse_slots list, so these ride beside the delta instead (state_extra(), code/engine/state/schema.dm)
// and latent collapse, cloning and persistence keep them as they kept the vars. name = the value that slot reads as when unset; a slot at that
// value is not saved, as a var at its default was not.

GLOBAL_LIST_INIT(state_sparse_saved, list(
	"ckeys_allowed_itemspawn" = null,
	"atom_colours" = null,
	"surface_germs" = GERM_LEVEL_AMBIENT,
))

/obj/state_extra()
	. = ..()
	// The lazy states (the table-form rows) ride as "lazy.feature.field".
	var/list/lazy = lazy_state_saved(src)
	for(var/key in lazy)
		. = . || list()
		.["lazy.[key]"] = lazy[key]
	var/list/slots = sparse_slots
	if(!slots)
		return
	for(var/name in GLOB.state_sparse_saved)
		var/value = slots[name]
		if(isnull(value) || value == GLOB.state_sparse_saved[name])
			continue
		. = . || list()
		.["slot.[name]"] = value

/obj/state_apply_extra(list/extra)
	..()
	var/list/lazy
	for(var/key in extra)
		if(copytext(key, 1, 6) == "lazy.")
			lazy = lazy || list()
			lazy[copytext(key, 6)] = extra[key]
	lazy_state_restore(src, lazy)
	for(var/name in GLOB.state_sparse_saved)
		_sparse_set(src, name, extra?["slot.[name]"])
