// Variants of /obj/item/clothing/under/teshari/undercoat/jobs: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_teshari_undercoat_jobs, list(
	"atmos" = list("name" = "atmospherics undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_ATMOSPHERIC_TECHNICIAN, "icon_state" = "tesh_uniform_atmos"),
	"cap" = list("name" = "site manager undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_SITE_MANAGER, "icon_state" = "tesh_uniform_cap"),
	"cargo" = list("name" = "cargo undercoat", "desc" = "A traditional Teshari garb made for the Cargo department", "icon_state" = "tesh_uniform_car"),
	"ce" = list("name" = "chief engineer undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_CHIEF_ENGINEER, "icon_state" = "tesh_uniform_ce"),
	"chemistry" = list("name" = "chemist undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_CHEMIST, "icon_state" = "tesh_uniform_chem"),
	"cmo" = list("name" = "chief medical officer undercoat", "desc" = "A traditional Teshari garb made for the Chief Medical Officer", "icon_state" = "tesh_uniform_cmo"),
	"engineer" = list("name" = "engineering undercoat", "desc" = "A traditional Teshari garb made for the Engineering department", "icon_state" = "tesh_uniform_engie"),
	"hop" = list("name" = "head of personnel undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_HEAD_OF_PERSONNEL, "icon_state" = "tesh_uniform_hop"),
	"iaa" = list("name" = "internal affairs undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_INTERNAL_AFFAIRS_AGENT, "icon_state" = "tesh_uniform_iaa"),
	"medical" = list("name" = "medical undercoat", "desc" = "A traditional Teshari garb made for the Medical department", "icon_state" = "tesh_uniform_doc"),
	"mining" = list("name" = "mining undercoat", "desc" = "A traditional Teshari garb made for Mining", "icon_state" = "tesh_uniform_mine"),
	"para" = list("name" = "paramedic undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_PARAMEDIC, "icon_state" = "tesh_uniform_para"),
	"psych" = list("name" = "psychiatrist undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_PSYCHIATRIST, "icon_state" = "tesh_uniform_psych"),
	"qm" = list("name" = "quartermaster undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_QUARTERMASTER, "icon_state" = "tesh_uniform_qm"),
	"rd" = list("name" = "research director undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_RESEARCH_DIRECTOR, "icon_state" = "tesh_uniform_rd"),
	"robo" = list("name" = "roboticist undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_ROBOTICIST, "icon_state" = "tesh_uniform_robo"),
	"sci" = list("name" = "scientist undercoat", "desc" = "A traditional Teshari garb made for the Science department", "icon_state" = "tesh_uniform_sci"),
	"service" = list("name" = "service undercoat", "desc" = "A traditional Teshari garb made for the Service department", "icon_state" = "tesh_uniform_serv"),
	"viro" = list("name" = "virologist undercoat", "desc" = "A traditional Teshari garb made for the " + JOB_ALT_VIROLOGIST, "icon_state" = "tesh_uniform_viro"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/teshari/undercoat/jobs/proc/own_variant_table()
	return GLOB.dq_variants_teshari_undercoat_jobs

CAPABILITIES(/obj/item/clothing/under/teshari/undercoat/jobs)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's
