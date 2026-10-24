// Sparse slots that used to be saved vars (doc/rewrite/proposals/base_vars.md, wave 2). The state schema saves an object's non-tmp vars that differ
// from their defaults; a slot lives in the tmp sparse_slots list, so these ride beside the delta instead (state_extra(), code/engine/state/schema.dm)
// and latent collapse, cloning and persistence keep them as they kept the vars. name = the value that slot reads as when unset; a slot at that
// value is not saved, as a var at its default was not.

GLOBAL_LIST_INIT(state_sparse_saved, list(
	"burn_overlay" = null,
	"burn_particle_type" = null,
	"burn_fuel" = 0,
	"burn_ended_by" = null,
	"economic_department" = null,
	"economic_export_value" = 0,
	"economic_producer_account" = 0,
	"economic_sale_invoice_id" = 0,
	"mat_luminescence" = 0,
	"mat_radioactivity" = 0,
	"mat_toxicity" = 0,
	"d_mult_old" = 1,
	"digest_stage" = null,
	"cleanname" = null,
	"cleandesc" = null,
	"oldname" = null,
	"item_tf_spawn_allowed" = FALSE,
	"trash_eatable" = TRUE,
	"worn_layer" = null,
	"tether_path" = null,
	"tf_scale_x" = null,
	"tf_scale_y" = null,
	"tf_rotation" = null,
	"tf_offset_x" = null,
	"tf_offset_y" = null,
	"swarm_offset_x" = 0,
	"swarm_offset_y" = 0,
	"is_swarming" = FALSE,
	"blocks_light" = FALSE,
	"ckeys_allowed_itemspawn" = null,
))

/obj/state_extra()
	. = ..()
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
	for(var/name in GLOB.state_sparse_saved)
		_sparse_set(src, name, extra?["slot.[name]"])
