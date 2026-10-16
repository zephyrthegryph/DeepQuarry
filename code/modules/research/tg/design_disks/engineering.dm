/obj/item/disk/design_disk/rapid_construction
	name = "rapid fabricator design disk"
	desc = "A disk containing several rapid fabrication devices."

CAPABILITIES(/obj/item/disk/design_disk/rapid_construction)
	after_init(0, then(PROC_REF(load_designs)))

/obj/item/disk/design_disk/rapid_construction/proc/load_designs(datum/act/timer/A)
	add_blueprints(SSresearch.techweb_design_by_id(/datum/design_techweb/rcd_loaded::id))
	add_blueprints(SSresearch.techweb_design_by_id(/datum/design_techweb/rcd_ammo::id))
	add_blueprints(SSresearch.techweb_design_by_id(/datum/design_techweb/rpd::id))
	add_blueprints(SSresearch.techweb_design_by_id(/datum/design_techweb/rms::id))
	add_blueprints(SSresearch.techweb_design_by_id(/datum/design_techweb/rsf::id)) // may as well
