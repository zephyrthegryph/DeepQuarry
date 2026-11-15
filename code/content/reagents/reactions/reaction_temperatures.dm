// The temperature of every chemistry recipe, in one place (the rules that read it: code/domains/world_model/reagents/chem_temperature.dm).
//
// A recipe is filed under a class; a class is a working range and an ideal band inside it, in kelvin: list(range low, ideal low, ideal high, range high).
//   * ideal band       clean product;
//   * range, off band  product and contaminants (cold: organic residue; hot: reactive impurity and some of the product lost), scaled by the distance;
//   * outside range    no reaction.
// A catalyst in the beaker widens band and range on both sides. Only the recipes of the instant regime are classed (the distilling regime names its own
// temperatures in each rule); a recipe nothing below names is GENTLE.
//
// The classes (Celsius):                   range        ideal
//   AMBIENT   drinks, food, paint, carpet, virology: they keep working at the bar, in the kitchen, in the cold                -30 .. 120     -10 .. 60
//   GENTLE    ordinary medicine and lab chemistry: room temperature is right                                                    0 ..  75      15 .. 40
//   WARM      the touchier drugs and poisons: a warm bath                                                                      25 ..  95      45 .. 65
//   HOT       acids, mutagens, fire starters: a hot plate                                                                      55 .. 150      85 .. 110
//   VIOLENT   explosives and their kin: a hot plate set high, and care                                                         85 .. 220     130 .. 170

/// class => list(range low, ideal low, ideal high, range high), kelvin.
GLOBAL_LIST_INIT(reaction_temperature_classes, list(
	REACTION_TEMP_AMBIENT = list(T0C - 30, T0C - 10, T0C + 60, T0C + 120),
	REACTION_TEMP_GENTLE = list(T0C, T0C + 15, T0C + 40, T0C + 75),
	REACTION_TEMP_WARM = list(T0C + 25, T0C + 45, T0C + 65, T0C + 95),
	REACTION_TEMP_HOT = list(T0C + 55, T0C + 85, T0C + 110, T0C + 150),
	REACTION_TEMP_VIOLENT = list(T0C + 85, T0C + 130, T0C + 170, T0C + 220),
))

/// class => the recipes filed under it: a rule type, which takes its subtypes with it. The first class naming a type (or one above it) wins.
GLOBAL_LIST_INIT(reaction_temperature_assignments, list(
	REACTION_TEMP_VIOLENT = list(
		/transformation/chem/instant/explosion_potassium,
		/transformation/chem/instant/flash_powder,
		/transformation/chem/instant/nitroglycerin,
		/transformation/chem/instant/emp_pulse,
		/transformation/chem/instant/napalm,
		/transformation/chem/instant/neoliquidfire,
	),
	REACTION_TEMP_HOT = list(
		/transformation/chem/instant/pacid,
		/transformation/chem/instant/thermite,
		/transformation/chem/instant/mutagen,
		/transformation/chem/instant/neurotoxin,
		/transformation/chem/instant/zombiepowder,
		/transformation/chem/instant/titanium_oxidation,
		/transformation/chem/instant/hydrophoron,
		/transformation/chem/instant/deuterium,
	),
	REACTION_TEMP_WARM = list(
		/transformation/chem/instant/mortiferin,
		/transformation/chem/instant/chloralhydrate,
		/transformation/chem/instant/soporific,
		/transformation/chem/instant/mindbreaker,
		/transformation/chem/instant/bliss,
		/transformation/chem/instant/carpotoxin,
		/transformation/chem/instant/left4zed,
	),
	REACTION_TEMP_AMBIENT = list(
		/transformation/chem/instant/drinks,
		/transformation/chem/instant/food,
		/transformation/chem/instant/water,
		/transformation/chem/instant/lube,
		/transformation/chem/instant/soapification,
		/transformation/chem/instant/glucose,
		/transformation/chem/instant/sorbitol,
		/transformation/chem/instant/unsorbitol,
		/transformation/chem/instant/nutrient,
		/transformation/chem/instant/artificial_sustenance,
		/transformation/chem/instant/meatcolony,
		/transformation/chem/instant/plantcolony,
		/transformation/chem/instant/antibodies,
		/transformation/chem/instant/neuter_virus,
		/transformation/chem/instant/falter_virus,
		/transformation/chem/instant/mix_virus,
	),
))

/// Recipes whose type path holds one of these words are AMBIENT too: the paints, the carpets and dyes, the virus foods (dozens of siblings, no common parent).
GLOBAL_LIST_INIT(reaction_temperature_ambient_words, list("_paint", "carpet", "virus_food"))

/// The class a rule type is filed under.
/proc/reaction_temperature_class(rule_type)
	for(var/class in GLOB.reaction_temperature_assignments)
		for(var/assigned_type in GLOB.reaction_temperature_assignments[class])
			if(ispath(rule_type, assigned_type))
				return class
	var/path_text = "[rule_type]"
	for(var/word in GLOB.reaction_temperature_ambient_words)
		if(findtext(path_text, word))
			return REACTION_TEMP_AMBIENT
	return REACTION_TEMP_GENTLE

/// The rule type => its band (list(range low, ideal low, ideal high, range high), K): every instant chemistry rule that exists.
/proc/build_reaction_temperature_table()
	static_entries_ensure("build_reaction_temperature_table")
	var/list/table = list()
	for(var/datum/xform/X as anything in GLOB.xform_rules)
		if(X.medium == MEDIUM_REAGENTS && X.regime == REGIME_INSTANT && ispath(X.rule_type, /transformation/chem))
			table[X.rule_type] = GLOB.reaction_temperature_classes[reaction_temperature_class(X.rule_type)]
	return table

GLOBAL_TABLE(reaction_temperature_table, GLOBAL_PROC_REF(build_reaction_temperature_table))

/// The band of a chemistry rule: list(range low, ideal low, ideal high, range high) in kelvin, or null (a rule that is not an instant chemistry recipe).
/proc/reaction_temperature_profile(rule_type)
	var/list/table = GLOBAL_TABLE_GET(reaction_temperature_table)
	return table[rule_type]
