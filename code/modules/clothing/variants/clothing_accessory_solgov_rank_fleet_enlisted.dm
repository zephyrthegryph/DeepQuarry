// Auto-generated. 12 variants of /obj/item/clothing/accessory/solgov/rank/fleet/enlisted.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_fleet_enlisted, list(
	"e2" = list("name" = "ranks (E-2 crewman apprentice)", "desc" = "Insignia denoting the rank of Crewman Apprentice."),
	"e3" = list("name" = "ranks (E-3 crewman)", "desc" = "Insignia denoting the rank of Crewman."),
	"e4" = list("name" = "ranks (E-4 petty officer third class)", "desc" = "Insignia denoting the rank of Petty Officer Third Class."),
	"e5" = list("name" = "ranks (E-5 petty officer second class)", "desc" = "Insignia denoting the rank of Petty Officer Second Class."),
	"e6" = list("name" = "ranks (E-6 petty officer first class)", "desc" = "Insignia denoting the rank of Petty Officer First Class."),
	"e7" = list("name" = "ranks (E-7 chief petty officer)", "desc" = "Insignia denoting the rank of Chief Petty Officer."),
	"e8" = list("name" = "ranks (E-8 senior chief petty officer)", "desc" = "Insignia denoting the rank of Senior Chief Petty Officer."),
	"e9" = list("name" = "ranks (E-9 master chief petty officer)", "desc" = "Insignia denoting the rank of Master Chief Petty Officer."),
	"e9_alt1" = list("name" = "ranks (E-9 command master chief petty officer)", "desc" = "Insignia denoting the rank of Command Master Chief Petty Officer."),
	"e9_alt2" = list("name" = "ranks (E-9 fleet master chief petty officer)", "desc" = "Insignia denoting the rank of Fleet Master Chief Petty Officer."),
	"e9_alt3" = list("name" = "ranks (E-9 force master chief petty officer)", "desc" = "Insignia denoting the rank of Force Master Chief Petty Officer."),
	"e9_alt4" = list("name" = "ranks (E-9 master chief petty officer of the Fleet)", "desc" = "Insignia denoting the rank of Master Chief Petty Officer of the Fleet."),
))

CAPABILITIES(/obj/item/clothing/accessory/solgov/rank/fleet/enlisted)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/solgov/rank/fleet/enlisted/proc/variant_table()
	return GLOB.dq_variants_accessory_solgov_rank_fleet_enlisted
