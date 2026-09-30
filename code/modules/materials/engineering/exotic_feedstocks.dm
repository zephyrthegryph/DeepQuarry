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
	hardness = 52
	integrity = 48
	conductive = TRUE
	conductivity = 82
	piezoelectric_coefficient = 0.42

/datum/material/exotic_feedstock/thermic
	name = MAT_THERMIC_CERAMIC
	icon_colour = "#ff8b52"
	hardness = 46
	integrity = 62
	conductivity = 12
	heat_resistance = 88
	thermal_insulation = 58
	phase_change_temperature = T0C + 40
	phase_change_capacity = 65000

/datum/material/exotic_feedstock/kinetic
	name = MAT_KINETIC_CRYSTAL
	icon_colour = "#b7c0ce"
	hardness = 78
	integrity = 55
	brittleness = 24
	conductivity = 36
	piezoelectric_coefficient = 0.68

/datum/material/exotic_feedstock/ward
	name = MAT_WARD_METAL
	icon_colour = "#72e8b5"
	hardness = 64
	integrity = 82
	conductivity = 31
	reactive_energy_capacity = 2400

/datum/material/exotic_feedstock/spore
	name = MAT_SPORE_BIOMASS
	icon_colour = "#8fcf5a"
	hardness = 18
	integrity = 35
	conductivity = 4
	biocompatibility = 72
	hemostatic_activity = 58
	reagent_porosity = 14

/datum/material/exotic_feedstock/etching
	name = MAT_ETCHING_CERAMIC
	icon_colour = "#caff4d"
	hardness = 58
	integrity = 52
	conductivity = 8
	corrosion_resistance = 94
	catalytic_activity = 64

/datum/material/exotic_feedstock/lumen
	name = MAT_LUMEN_CRYSTAL
	icon_colour = "#fff36f"
	hardness = 48
	integrity = 45
	conductivity = 54
	luminescence = 48
	scintillation_efficiency = 0.72

/datum/material/exotic_feedstock/rift
	name = MAT_RIFT_GLASS
	icon_colour = "#a86fff"
	hardness = 62
	integrity = 42
	brittleness = 35
	conductivity = 18
	gas_sorption_capacity = 18
	reagent_porosity = 8

/obj/item/stack/material/exotic_feedstock
	name = "exotic material sample"
	icon_state = "sheet-gem"
	default_type = MAT_VOLTAIC_CRYSTAL
	apply_colour = TRUE
	no_variants = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/exotic_feedstock/random/Initialize(mapload, _amount, _material_name)
	if(!_material_name)
		_material_name = pick(
			MAT_VOLTAIC_CRYSTAL,
			MAT_THERMIC_CERAMIC,
			MAT_KINETIC_CRYSTAL,
			MAT_WARD_METAL,
			MAT_SPORE_BIOMASS,
			MAT_ETCHING_CERAMIC,
			MAT_LUMEN_CRYSTAL,
			MAT_RIFT_GLASS,
		)
	default_type = _material_name
	return ..(mapload, _amount || rand(3, 6))

/obj/item/stack/material/exotic_feedstock/examine(mob/user)
	. = ..()
	if(material)
		var/list/responses = material.material_response_summary()
		. += span_notice("This is a concrete feedstock: melt it into a batch or place it deliberately in a layered composite.")
		if(length(responses))
			. += span_notice("Measured constitutive responses: [jointext(responses, "; ")].")
