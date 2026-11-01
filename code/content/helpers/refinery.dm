// Grinding as transformations (doc/rewrite/proposals/transformations.md, wave 3): a grinder breaks an item down into reagents. A rule is a type under
// /transformation/grinding that takes one item (stack_term for a sheet, item_term for an ore) and makes a list of reagent terms: the list is shared out evenly
// (a reagent named twice is two terms, so it gets two shares), and a sheet or ore of exactly that type is what the rule fits (grinding_rule_for()).

/transformation/grinding

CAPABILITIES(/transformation/grinding)
	transformation(medium = MEDIUM_CONTENTS, regime = REGIME_GRINDING)

/// The grinding rule for an item of exactly this type, or null.
/proc/grinding_rule_for(item_type)
	RETURN_TYPE(/datum/xform)
	var/list/candidates = xform_candidates(MEDIUM_CONTENTS, REGIME_GRINDING, item_type)
	return candidates?[1]

/// The rule for a sheet (a stack) of exactly this type, or null.
/proc/grinding_sheet_rule_for(item_type)
	RETURN_TYPE(/datum/xform)
	var/datum/xform/rule = grinding_rule_for(item_type)
	return (rule && rule.takes[1][1] == XCUR_STACK) ? rule : null

/// The rule for an ore of exactly this type, or null.
/proc/grinding_ore_rule_for(item_type)
	RETURN_TYPE(/datum/xform)
	var/datum/xform/rule = grinding_rule_for(item_type)
	return (rule && rule.takes[1][1] == XCUR_ITEM) ? rule : null

/// The reagent ids a grinding rule makes, in order, a reagent named twice twice.
/datum/xform/proc/grind_ids()
	RETURN_TYPE(/list)
	. = list()
	for(var/list/row as anything in makes)
		. += row[2]

/transformation/grinding/stack_material_plastic
CAPABILITIES(/transformation/grinding/stack_material_plastic)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/plastic, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_SULFUR, 1))))

/transformation/grinding/stack_material_copper
CAPABILITIES(/transformation/grinding/stack_material_copper)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/copper, 1)),
		makes = list(reagent(REAGENT_ID_COPPER, 1))))

/transformation/grinding/stack_material_graphite
CAPABILITIES(/transformation/grinding/stack_material_graphite)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/graphite, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1))))

/transformation/grinding/stack_material_aluminium
CAPABILITIES(/transformation/grinding/stack_material_aluminium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/aluminium, 1)),
		makes = list(reagent(REAGENT_ID_ALUMINIUM, 1))))

/transformation/grinding/stack_material_diamond
CAPABILITIES(/transformation/grinding/stack_material_diamond)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/diamond, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1))))

/transformation/grinding/stack_material_durasteel
CAPABILITIES(/transformation/grinding/stack_material_durasteel)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/durasteel, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/grinding/stack_material_wax
CAPABILITIES(/transformation/grinding/stack_material_wax)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/wax, 1)),
		makes = list(reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_TRIGLYCERIDE, 1))))

/transformation/grinding/stack_material_iron
CAPABILITIES(/transformation/grinding/stack_material_iron)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/iron, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1))))

/transformation/grinding/stack_material_phoron
CAPABILITIES(/transformation/grinding/stack_material_phoron)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/phoron, 1)),
		makes = list(reagent(REAGENT_ID_PHORON, 1))))

/transformation/grinding/stack_material_gold
CAPABILITIES(/transformation/grinding/stack_material_gold)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/gold, 1)),
		makes = list(reagent(REAGENT_ID_GOLD, 1))))

/transformation/grinding/stack_material_silver
CAPABILITIES(/transformation/grinding/stack_material_silver)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/silver, 1)),
		makes = list(reagent(REAGENT_ID_SILVER, 1))))

/transformation/grinding/stack_material_platinum
CAPABILITIES(/transformation/grinding/stack_material_platinum)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/platinum, 1)),
		makes = list(reagent(REAGENT_ID_PLATINUM, 1))))

// This should be fixed someday
/transformation/grinding/stack_material_osmium
CAPABILITIES(/transformation/grinding/stack_material_osmium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/osmium, 1)),
		makes = list(reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/grinding/stack_material_steel
CAPABILITIES(/transformation/grinding/stack_material_steel)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/steel, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1))))

//8 iron, 8 carbon, 4 platinum,
/transformation/grinding/stack_material_plasteel
CAPABILITIES(/transformation/grinding/stack_material_plasteel)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/plasteel, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/grinding/stack_material_sandstone
CAPABILITIES(/transformation/grinding/stack_material_sandstone)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/sandstone, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_OXYGEN, 1))))

/transformation/grinding/stack_material_marble
CAPABILITIES(/transformation/grinding/stack_material_marble)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/marble, 1)),
		makes = list(reagent(REAGENT_ID_CALCIUM, 1))))

/transformation/grinding/stack_material_titanium
CAPABILITIES(/transformation/grinding/stack_material_titanium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/titanium, 1)),
		makes = list(reagent(REAGENT_ID_ALUMINIUM, 1))))

/transformation/grinding/stack_material_lead
CAPABILITIES(/transformation/grinding/stack_material_lead)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/lead, 1)),
		makes = list(reagent(REAGENT_ID_LEAD, 1))))

// Nuclear
/transformation/grinding/stack_material_mhydrogen
CAPABILITIES(/transformation/grinding/stack_material_mhydrogen)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/mhydrogen, 1)),
		makes = list(reagent(REAGENT_ID_HYDROGEN, 1))))

/transformation/grinding/stack_material_deuterium
CAPABILITIES(/transformation/grinding/stack_material_deuterium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/deuterium, 1)),
		makes = list(reagent(REAGENT_ID_HYDROGEN, 1))))

/transformation/grinding/stack_material_tritium
CAPABILITIES(/transformation/grinding/stack_material_tritium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/tritium, 1)),
		makes = list(reagent(REAGENT_ID_HYDROGEN, 1))))

/transformation/grinding/stack_material_uranium
CAPABILITIES(/transformation/grinding/stack_material_uranium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/uranium, 1)),
		makes = list(reagent(REAGENT_ID_URANIUM, 1))))

/transformation/grinding/stack_material_supermatter
CAPABILITIES(/transformation/grinding/stack_material_supermatter)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/supermatter, 1)),
		makes = list(reagent(REAGENT_ID_SUPERMATTER, 1))))

// Misc
/transformation/grinding/stack_material_snow
CAPABILITIES(/transformation/grinding/stack_material_snow)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/snow, 1)),
		makes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_ICE, 1))))

/transformation/grinding/stack_tile_grass
CAPABILITIES(/transformation/grinding/stack_tile_grass)
	configure(transformation(takes = list(stack_term(/obj/item/stack/tile/grass, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_PHOSPHORUS, 1))))

/transformation/grinding/stack_material_leather
CAPABILITIES(/transformation/grinding/stack_material_leather)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/leather, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_TRIGLYCERIDE, 1))))

/transformation/grinding/stack_material_cloth
CAPABILITIES(/transformation/grinding/stack_material_cloth)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/cloth, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_fiber
CAPABILITIES(/transformation/grinding/stack_material_fiber)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/fiber, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_fur
CAPABILITIES(/transformation/grinding/stack_material_fur)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/fur, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_algae
CAPABILITIES(/transformation/grinding/stack_material_algae)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/algae, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_PHOSPHORUS, 1))))

// Just spawns with 10, is the same as normal one
/transformation/grinding/stack_material_algae_ten
CAPABILITIES(/transformation/grinding/stack_material_algae_ten)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/algae/ten, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_PHOSPHORUS, 1))))

/transformation/grinding/stack_material_concrete
CAPABILITIES(/transformation/grinding/stack_material_concrete)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/concrete, 1)),
		makes = list(reagent(REAGENT_ID_SILICATE, 1), reagent(REAGENT_ID_CALCIUM, 1))))

/transformation/grinding/stack_material_cardboard
CAPABILITIES(/transformation/grinding/stack_material_cardboard)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/cardboard, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 1))))

// Woods
/transformation/grinding/stack_material_wood
CAPABILITIES(/transformation/grinding/stack_material_wood)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/wood, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_wood_sif
CAPABILITIES(/transformation/grinding/stack_material_wood_sif)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/wood/sif, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_wood_hard
CAPABILITIES(/transformation/grinding/stack_material_wood_hard)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/wood/hard, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

// Hull
/transformation/grinding/stack_material_steel_hull
CAPABILITIES(/transformation/grinding/stack_material_steel_hull)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/steel/hull, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1))))

/transformation/grinding/stack_material_plasteel_hull
CAPABILITIES(/transformation/grinding/stack_material_plasteel_hull)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/plasteel/hull, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/grinding/stack_material_plastitanium_hull
CAPABILITIES(/transformation/grinding/stack_material_plastitanium_hull)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/plastitanium/hull, 1)),
		makes = list(reagent(REAGENT_ID_TITANIUM, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/grinding/stack_material_durasteel_hull
CAPABILITIES(/transformation/grinding/stack_material_durasteel_hull)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/durasteel/hull, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

// Glass
/transformation/grinding/stack_material_glass
CAPABILITIES(/transformation/grinding/stack_material_glass)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/glass, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1))))

/transformation/grinding/stack_material_glass_reinforced
CAPABILITIES(/transformation/grinding/stack_material_glass_reinforced)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/glass/reinforced, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1))))

//5 platinum, 15 silicon,
/transformation/grinding/stack_material_glass_phoronglass
CAPABILITIES(/transformation/grinding/stack_material_glass_phoronglass)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/glass/phoronglass, 1)),
		makes = list(reagent(REAGENT_ID_PLATINUM, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1))))

/transformation/grinding/stack_material_glass_phoronrglass
CAPABILITIES(/transformation/grinding/stack_material_glass_phoronrglass)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/glass/phoronrglass, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_PHORON, 1))))

/transformation/grinding/stack_material_glass_titanium
CAPABILITIES(/transformation/grinding/stack_material_glass_titanium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/glass/titanium, 1)),
		makes = list(reagent(REAGENT_ID_TITANIUM, 1), reagent(REAGENT_ID_SILICON, 1))))

/transformation/grinding/stack_material_glass_plastitanium
CAPABILITIES(/transformation/grinding/stack_material_glass_plastitanium)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/glass/plastitanium, 1)),
		makes = list(reagent(REAGENT_ID_TITANIUM, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

// Rods
// 2 per sheet of steel
/transformation/grinding/stack_rods
CAPABILITIES(/transformation/grinding/stack_rods)
	configure(transformation(takes = list(stack_term(/obj/item/stack/rods, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1))))

// Only makes 1 per sheet of plasteel!
/transformation/grinding/stack_material_plasteel_rebar
CAPABILITIES(/transformation/grinding/stack_material_plasteel_rebar)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/plasteel/rebar, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PLATINUM, 1))))

// Logs
/transformation/grinding/stack_material_stick
CAPABILITIES(/transformation/grinding/stack_material_stick)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/stick, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

// Just spawns with 5, same as normal one
/transformation/grinding/stack_material_stick_fivestack
CAPABILITIES(/transformation/grinding/stack_material_stick_fivestack)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/stick/fivestack, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_log
CAPABILITIES(/transformation/grinding/stack_material_log)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/log, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_log_hard
CAPABILITIES(/transformation/grinding/stack_material_log_hard)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/log/hard, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/stack_material_log_sif
CAPABILITIES(/transformation/grinding/stack_material_log_sif)
	configure(transformation(takes = list(stack_term(/obj/item/stack/material/log/sif, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/ore_glass
CAPABILITIES(/transformation/grinding/ore_glass)
	configure(transformation(takes = list(item_term(/obj/item/ore/glass, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1))))

/transformation/grinding/ore_iron
CAPABILITIES(/transformation/grinding/ore_iron)
	configure(transformation(takes = list(item_term(/obj/item/ore/iron, 1)),
		makes = list(reagent(REAGENT_ID_IRON, 1))))

/transformation/grinding/ore_coal
CAPABILITIES(/transformation/grinding/ore_coal)
	configure(transformation(takes = list(item_term(/obj/item/ore/coal, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1))))

/transformation/grinding/ore_phoron
CAPABILITIES(/transformation/grinding/ore_phoron)
	configure(transformation(takes = list(item_term(/obj/item/ore/phoron, 1)),
		makes = list(reagent(REAGENT_ID_PHORON, 1))))

/transformation/grinding/ore_silver
CAPABILITIES(/transformation/grinding/ore_silver)
	configure(transformation(takes = list(item_term(/obj/item/ore/silver, 1)),
		makes = list(reagent(REAGENT_ID_SILVER, 1))))

/transformation/grinding/ore_gold
CAPABILITIES(/transformation/grinding/ore_gold)
	configure(transformation(takes = list(item_term(/obj/item/ore/gold, 1)),
		makes = list(reagent(REAGENT_ID_GOLD, 1))))

// Some nice variety here
/transformation/grinding/ore_marble
CAPABILITIES(/transformation/grinding/ore_marble)
	configure(transformation(takes = list(item_term(/obj/item/ore/marble, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_CALCIUM, 1))))

/transformation/grinding/ore_uranium
CAPABILITIES(/transformation/grinding/ore_uranium)
	configure(transformation(takes = list(item_term(/obj/item/ore/uranium, 1)),
		makes = list(reagent(REAGENT_ID_URANIUM, 1))))

/transformation/grinding/ore_diamond
CAPABILITIES(/transformation/grinding/ore_diamond)
	configure(transformation(takes = list(item_term(/obj/item/ore/diamond, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1))))

// should contain osmium
/transformation/grinding/ore_osmium
CAPABILITIES(/transformation/grinding/ore_osmium)
	configure(transformation(takes = list(item_term(/obj/item/ore/osmium, 1)),
		makes = list(reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/grinding/ore_lead
CAPABILITIES(/transformation/grinding/ore_lead)
	configure(transformation(takes = list(item_term(/obj/item/ore/lead, 1)),
		makes = list(reagent(REAGENT_ID_LEAD, 1))))

/transformation/grinding/ore_hydrogen
CAPABILITIES(/transformation/grinding/ore_hydrogen)
	configure(transformation(takes = list(item_term(/obj/item/ore/hydrogen, 1)),
		makes = list(reagent(REAGENT_ID_HYDROGEN, 1))))

// Some fun stuff to be useful with
/transformation/grinding/ore_verdantium
CAPABILITIES(/transformation/grinding/ore_verdantium)
	configure(transformation(takes = list(item_term(/obj/item/ore/verdantium, 1)),
		makes = list(reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_SODIUM, 1))))

/transformation/grinding/ore_rutile
CAPABILITIES(/transformation/grinding/ore_rutile)
	configure(transformation(takes = list(item_term(/obj/item/ore/rutile, 1)),
		makes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_OXYGEN, 1))))

/transformation/grinding/ore_copper
CAPABILITIES(/transformation/grinding/ore_copper)
	configure(transformation(takes = list(item_term(/obj/item/ore/copper, 1)),
		makes = list(reagent(REAGENT_ID_COPPER, 1))))

/transformation/grinding/ore_tin
CAPABILITIES(/transformation/grinding/ore_tin)
	configure(transformation(takes = list(item_term(/obj/item/ore/tin, 1)),
		makes = list(reagent(REAGENT_ID_TIN, 1))))

/transformation/grinding/ore_void_opal
CAPABILITIES(/transformation/grinding/ore_void_opal)
	configure(transformation(takes = list(item_term(/obj/item/ore/void_opal, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_WATER, 1))))

/transformation/grinding/ore_painite
CAPABILITIES(/transformation/grinding/ore_painite)
	configure(transformation(takes = list(item_term(/obj/item/ore/painite, 1)),
		makes = list(reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_OXYGEN, 1))))

/transformation/grinding/ore_quartz
CAPABILITIES(/transformation/grinding/ore_quartz)
	configure(transformation(takes = list(item_term(/obj/item/ore/quartz, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_OXYGEN, 1))))

/transformation/grinding/ore_bauxite
CAPABILITIES(/transformation/grinding/ore_bauxite)
	configure(transformation(takes = list(item_term(/obj/item/ore/bauxite, 1)),
		makes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_ALUMINIUM, 1))))

/// Grinds down various objects into their reagent components. Returns true if any reagents were gained from the attempt.
/proc/grind_items_to_reagents(list/holdingitems,datum/reagents/R)
	var/start_volume = R.total_volume

	for(var/obj/item/O in holdingitems)
		var/remaining_volume = R.maximum_volume - R.total_volume
		if(remaining_volume <= 0)
			break

		// start
		if(istype(O,/obj/item/stack/material/supermatter))
			var/regrets = 0
			for(var/obj/item/stack/material/supermatter/S in holdingitems)
				regrets += S.get_amount()
			puny_protons(regrets, R.my_atom, holdingitems)
			return
		// end

		var/datum/xform/sheet_rule = grinding_sheet_rule_for(O.type)
		var/datum/xform/ore_rule = sheet_rule ? null : grinding_ore_rule_for(O.type)
		if(sheet_rule)
			var/obj/item/stack/stack = O
			if(istype(stack))
				var/list/sheet_components = sheet_rule.grind_ids()
				// Some stacks can be made into other stacks with a multiplier. This handles that.
				var/remove_amount = stack.reagents_per_sheet()
				var/amount_to_take = max(0,min(stack.get_amount(),round(remaining_volume/remove_amount)))
				if(amount_to_take)
					stack.use(amount_to_take)
					if(QDELETED(stack))
						holdingitems -= stack
					amount_to_take = (amount_to_take/(sheet_components.len))
					for(var/i in sheet_components)
						R.add_reagent(i, (amount_to_take*remove_amount))
					continue

		else if(ore_rule)
			var/obj/item/ore/D = O
			if(istype(D))
				var/list/ore_components = ore_rule.grind_ids()
				if(remaining_volume >= REAGENTS_PER_ORE)
					holdingitems -= D
					consumed(D, R.my_atom)
					var/amount_to_take = (REAGENTS_PER_ORE/(ore_components.len))
					for(var/i in ore_components)
						R.add_reagent(i, amount_to_take)
					continue

		else if(O.reagents && O.reagents.total_volume > 0)
			O.reagents.trans_to_obj(R.my_atom, min(O.reagents.total_volume, remaining_volume))
			if(O.reagents.total_volume == 0)
				holdingitems -= O
				consumed(O, R.my_atom)
			if (R.total_volume >= R.maximum_volume)
				break

		else
			// Cronch
			holdingitems -= O
			consumed(O, R.my_atom)

	return (R.total_volume > start_volume)

// start: Repurposed coffee grinders and supermatter do not mix.
/proc/puny_protons(regrets = 0, atom/our_atom, list/holdingitems)
	set_glow(our_atom, GLOW(0, null, null))
	if(regrets > 0) // If you thought grinding supermatter would end well. Values taken from ex_act() for the supermatter stacks.
		radiation_pulse(
			source = get_turf(our_atom),
			max_range = 7,
			threshold = RAD_HEAVY_INSULATION,
			chance = 100, //Someone messed up BAD to have this happen. EVERYONE suffers.
			strength = 15 + (regrets * 4),
		)
		explosion(get_turf(our_atom), round(regrets / 12) , round(regrets / 6), round(regrets / 3), round(regrets / 25))
		destroyed(our_atom, null, "explosion")
		return

	else // If you added supermatter but didn't try grinding it, or somehow this is negative.
		for(var/obj/item/stack/material/supermatter/S in holdingitems)
			S.forceMove(our_atom.loc)
			holdingitems -= S
			regrets += S.get_amount()
		radiation_pulse(
			source = get_turf(our_atom),
			max_range = 7,
			threshold = RAD_HEAVY_INSULATION,
			chance = 100, //Someone messed up BAD to have this happen. EVERYONE suffers.
			strength = 15 + (regrets * 4),
		)
		our_atom.visible_message(span_warning("\The [our_atom] glows brightly, bursting into flames and flashing into ash."),\
		span_warning("You hear an unearthly shriek, burning heat washing over you."))
		replace_with(our_atom, /obj/effect/decal/cleanable/ash)
// end
