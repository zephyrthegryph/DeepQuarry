// Auto-generated. 6 variants of /obj/item/clothing/accessory/solgov/rank/fleet/officer.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_fleet_officer, list(
	"wo1_monkey" = list("name" = "makeshift ranks (WO-1 warrant officer 1)", "desc" = "Insignia denoting the mythical rank of Warrant Officer. Too bad it's obviously fake."),
	"o2" = list("name" = "ranks (O-2 sub-lieutenant)", "desc" = "Insignia denoting the rank of Sub-lieutenant."),
	"o3" = list("name" = "ranks (O-3 lieutenant)", "desc" = "Insignia denoting the rank of Lieutenant."),
	"o4" = list("name" = "ranks (O-4 lieutenant commander)", "desc" = "Insignia denoting the rank of Lieutenant Commander."),
	"o5" = list("name" = "ranks (O-5 commander)", "desc" = "Insignia denoting the rank of Commander."),
	"o6" = list("name" = "ranks (O-6 captain)", "icon_state" = "fleetrank_command", "desc" = "Insignia denoting the rank of Captain."),
))

CAPABILITIES(/obj/item/clothing/accessory/solgov/rank/fleet/officer)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/solgov/rank/fleet/officer/proc/variant_table()
	return GLOB.dq_variants_accessory_solgov_rank_fleet_officer
