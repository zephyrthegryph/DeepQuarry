/// How a material shows itself: the card and its traits, each with the steps behind the number ("Toughness 62: base 70,
/// sulfur -12, tempered +4"). Examine, the engineering window, the wiki and the fabricator picker all read these, so a player
/// can always ask why a number is what it is. Plain materials have only a base; a processed alloy keeps its steps in stat_notes.

/// The value of card stat `stat`.
/datum/material/proc/card_value(stat)
	switch(stat)
		if(MATERIAL_STAT_STRENGTH)
			return strength
		if(MATERIAL_STAT_TOUGHNESS)
			return toughness
		if(MATERIAL_STAT_HEAT_RESISTANCE)
			return heat_resistance
		if(MATERIAL_STAT_CONDUCTIVITY)
			return conductivity
		if(MATERIAL_STAT_CORROSION_RESISTANCE)
			return corrosion_resistance
		if(MATERIAL_STAT_WEIGHT)
			return weight
	return 0

/// "base 70, sulfur -12, tempered +4" for a stat or trait id, or "" when nothing sits behind the number but its base.
/datum/material/proc/stat_breakdown(id)
	var/list/notes = LAZYACCESS(stat_notes, id)
	if(length(notes) < 2)
		return ""
	var/list/parts = list()
	for(var/list/row as anything in notes)
		var/label = row[1]
		var/delta = row[2]
		parts += label == "base" ? "base [delta]" : "[label] [delta > 0 ? "+" : ""][delta]"
	return jointext(parts, ", ")

/// The breakdown as the list a UI reads: list of list("label", "delta"), base first; empty for a plain material.
/datum/material/proc/stat_breakdown_rows(id)
	var/list/rows = list()
	for(var/list/row as anything in LAZYACCESS(stat_notes, id))
		rows += list(list("label" = row[1], "delta" = row[2]))
	return rows

/// "Strength 62: base 60, tempered +4".
/datum/material/proc/stat_line(id, value, label)
	var/breakdown = stat_breakdown(id)
	return "[label] [round(value)][breakdown ? ": [breakdown]" : ""]"

/// The six card lines.
/datum/material/proc/card_stat_lines()
	var/list/lines = list()
	for(var/stat in MATERIAL_CARD_STATS)
		lines += stat_line(stat, card_value(stat), capitalize(replacetext(stat, "_", " ")))
	return lines

/// A line for each trait the material has, and none for one it lacks.
/datum/material/proc/trait_lines()
	var/list/lines = list()
	for(var/trait_id in MATERIAL_TRAIT_IDS)
		var/strength_of_trait = trait(trait_id)
		if(strength_of_trait > 0)
			lines += stat_line(trait_id, strength_of_trait, capitalize(trait_id))
	return lines

/// The card and traits as rows a UI reads: list of list("name", "value", "breakdown" (a list of list("label", "delta"))).
/datum/material/proc/card_rows()
	var/list/rows = list()
	for(var/stat in MATERIAL_CARD_STATS)
		rows += list(list("name" = capitalize(replacetext(stat, "_", " ")), "value" = round(card_value(stat)), "breakdown" = stat_breakdown_rows(stat)))
	for(var/trait_id in MATERIAL_TRAIT_IDS)
		if(trait(trait_id) > 0)
			rows += list(list("name" = capitalize(trait_id), "value" = round(trait(trait_id)), "breakdown" = stat_breakdown_rows(trait_id)))
	return rows

/// Everything examine shows: the card, then the traits present.
/datum/material/proc/card_lines()
	return card_stat_lines() + trait_lines()
