// Limb variants: the species' limb families that differed only in data (a protean's, a promethean's, a xenomorph's, a crew shadekin's limbs, the
// event species' unbreakable / unseverable / indestructible sets) are rows of this table, not a subtype per limb per family. A species'
// has_limbs row names the plain limb type and the row: list("path" = /obj/item/organ/external/arm, "variant" = LIMB_VARIANT_NANO_LIMB).
// species_limb_new() builds it with the key given before init, and variants() (code/engine/lifeforms/variants.dm) sets the row's vars at preinit.
// A family whose limbs differ in behaviour (the diona's tendrils, unathi, teshari, vox) stays a set of real subtypes.

GLOBAL_LIST_INIT(dq_variants_organ_external, list(
	LIMB_VARIANT_UNBREAKABLE = list("cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_UNSEVERABLE = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE),
	LIMB_VARIANT_UNSEVERABLE_HEAD = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE, "headgib_exempt" = TRUE),
	LIMB_VARIANT_INDESTRUCTIBLE = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE, "cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_INDESTRUCTIBLE_HEAD = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE, "cannot_break" = TRUE, "dislocated" = -1, "headgib_exempt" = TRUE),

	// The swarm's own limbs: nanite, never broken.
	LIMB_VARIANT_NANO_CHEST = list("robotic" = ORGAN_NANOFORM, "encased" = FALSE, "max_damage" = 70, "min_broken_damage" = 1000, "vital" = TRUE, "model" = "protean", "cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_NANO_GROIN = list("robotic" = ORGAN_NANOFORM, "encased" = FALSE, "max_damage" = 70, "min_broken_damage" = 1000, "vital" = FALSE, "model" = "protean", "cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_NANO_HEAD = list("robotic" = ORGAN_NANOFORM, "encased" = FALSE, "max_damage" = 70, "min_broken_damage" = 1000, "vital" = FALSE, "model" = "protean", "cannot_break" = TRUE, "dislocated" = -1, "cannot_disfigure" = TRUE),
	LIMB_VARIANT_NANO_LIMB = list("robotic" = ORGAN_NANOFORM, "encased" = FALSE, "max_damage" = 40, "min_broken_damage" = 1000, "vital" = FALSE, "model" = "protean", "cannot_break" = TRUE, "dislocated" = -1),

	// Slime limbs: soft, see-through, never broken.
	LIMB_VARIANT_SLIME_CHEST = list("nonsolid" = TRUE, "transparent" = TRUE, "max_damage" = 60, "encased" = FALSE, "spread_dam" = TRUE, "cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_SLIME_GROIN = list("nonsolid" = TRUE, "transparent" = TRUE, "max_damage" = 50, "spread_dam" = TRUE, "cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_SLIME_LIMB = list("nonsolid" = TRUE, "transparent" = TRUE, "max_damage" = 35, "spread_dam" = TRUE, "cannot_break" = TRUE, "dislocated" = -1),
	LIMB_VARIANT_SLIME_HEAD = list("nonsolid" = TRUE, "transparent" = TRUE, "cannot_gib" = FALSE, "vital" = FALSE, "max_damage" = 45, "encased" = FALSE, "spread_dam" = TRUE, "cannot_break" = TRUE, "dislocated" = -1),

	// Xenomorph limbs: the chest is plain unseverable.
	LIMB_VARIANT_XENO_GROIN = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE, "encased" = TRUE),
	LIMB_VARIANT_XENO_LIMB = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE, "stapled_nerves" = TRUE, "encased" = TRUE),
	LIMB_VARIANT_XENO_HEAD = list("cannot_gib" = TRUE, "cannot_amputate" = TRUE, "headgib_exempt" = TRUE, "eye_icon" = "blank_eyes"),

	// Crew shadekin limbs: easier to break.
	LIMB_VARIANT_CREWKIN_CORE = list("min_broken_damage" = 20),
	LIMB_VARIANT_CREWKIN_LIMB = list("min_broken_damage" = 15),
	LIMB_VARIANT_CREWKIN_EXTREMITY = list("min_broken_damage" = 7),
	LIMB_VARIANT_CREWKIN_HEAD = list("min_broken_damage" = 15, "eye_icon_location" = 'icons/mob/human_face_vr.dmi', "eye_icon" = "eyes_shadekin_station"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/organ/external/proc/variant_table()
	return GLOB.dq_variants_organ_external

/// A species' limb as its has_limbs row builds it: the row's path, made with the row's variant key when it names one, placed in `H`.
/proc/species_limb_new(list/organ_data, mob/living/carbon/human/H)
	return make(organ_data["path"], at = H, variant = organ_data["variant"])

/// The eye sprite a species' head row gives: the row's variant value, else the path's own.
/proc/species_head_eye_icon(list/organ_data)
	var/obj/item/organ/external/head/head_path = organ_data?["path"]
	if(!ispath(head_path))
		return null
	var/list/row = GLOB.dq_variants_organ_external[organ_data["variant"]]
	return (row && row["eye_icon"]) || initial(head_path.eye_icon)

/// The sprite file of the eyes a species' head row gives (see species_head_eye_icon()).
/proc/species_head_eye_icon_location(list/organ_data)
	var/obj/item/organ/external/head/head_path = organ_data?["path"]
	if(!ispath(head_path))
		return null
	var/list/row = GLOB.dq_variants_organ_external[organ_data["variant"]]
	return (row && row["eye_icon_location"]) || initial(head_path.eye_icon_location)
