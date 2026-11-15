// Expedition feedstocks expressed through the concrete material property model.
// They are useful inputs, never self-contained magic payloads: geometry,
// processing history, and composite placement determine what a finished object does.

/datum/material/exotic_feedstock
	stack_type = /obj/item/stack/material/exotic_feedstock
	icon_base = "stone"
	table_icon_base = "stone"
	shard_type = SHARD_SHARD
	sheet_singular_name = "sample"
	sheet_plural_name = "samples"
	supply_conversion_value = 10

/datum/material/exotic_feedstock/voltaic
	name = MAT_VOLTAIC_CRYSTAL
	icon_colour = "#6fd0ff"
	strength = 52
	toughness = 24
	conductivity = 82
	traits = list(MT_PIEZOELECTRIC = 42)

/datum/material/exotic_feedstock/thermic
	name = MAT_THERMIC_CERAMIC
	icon_colour = "#ff8b52"
	strength = 46
	toughness = 31
	conductivity = 12
	heat_resistance = 88
	traits = list(MT_THERMAL_BUFFER = 65)

/datum/material/exotic_feedstock/kinetic
	name = MAT_KINETIC_CRYSTAL
	icon_colour = "#b7c0ce"
	strength = 78
	toughness = 27
	conductivity = 36
	traits = list(MT_PIEZOELECTRIC = 68)

/datum/material/exotic_feedstock/ward
	name = MAT_WARD_METAL
	icon_colour = "#72e8b5"
	strength = 64
	toughness = 41
	conductivity = 31
	traits = list(MT_REACTIVE = 48)

/datum/material/exotic_feedstock/spore
	name = MAT_SPORE_BIOMASS
	icon_colour = "#8fcf5a"
	strength = 18
	toughness = 18
	conductivity = 8
	traits = list(MT_HEMOSTATIC = 65, MT_SORBENT = 56)

/datum/material/exotic_feedstock/etching
	name = MAT_ETCHING_CERAMIC
	icon_colour = "#caff4d"
	strength = 58
	toughness = 26
	conductivity = 8
	corrosion_resistance = 94
	traits = list(MT_CATALYTIC = 64)

/datum/material/exotic_feedstock/lumen
	name = MAT_LUMEN_CRYSTAL
	icon_colour = "#fff36f"
	strength = 48
	toughness = 22
	conductivity = 54
	traits = list(MT_LUMINESCENT = 48)

/datum/material/exotic_feedstock/rift
	name = MAT_RIFT_GLASS
	icon_colour = "#a86fff"
	strength = 62
	toughness = 21
	conductivity = 18
	traits = list(MT_SORBENT = 72)

/obj/item/stack/material/exotic_feedstock
	name = "exotic material sample"
	icon_state = "sheet-gem"
	default_type = MAT_VOLTAIC_CRYSTAL
	apply_colour = TRUE
	no_variants = TRUE
	exotic_no_autolathe_reprint = TRUE

CAPABILITIES(/obj/item/stack/material/exotic_feedstock/random)
	param(nameof(default_type), pos = 2, default = PROC_REF(random_feedstock_material))

/// The material a random sample is made of when its creator named none (the constructor's second argument).
/obj/item/stack/material/exotic_feedstock/random/proc/random_feedstock_material()
	return pick(
		MAT_VOLTAIC_CRYSTAL,
		MAT_THERMIC_CERAMIC,
		MAT_KINETIC_CRYSTAL,
		MAT_WARD_METAL,
		MAT_SPORE_BIOMASS,
		MAT_ETCHING_CERAMIC,
		MAT_LUMEN_CRYSTAL,
		MAT_RIFT_GLASS,
	)

/obj/item/stack/material/exotic_feedstock/examine(mob/user)
	. = ..()
	if(material)
		var/list/responses = material.material_response_summary()
		. += span_notice("This is a concrete feedstock: melt it into a batch or place it deliberately in a layered composite.")
		if(length(responses))
			. += span_notice("Measured constitutive responses: [jointext(responses, "; ")].")
