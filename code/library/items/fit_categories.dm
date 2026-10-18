// Clothing fit categories (doc/rewrite/proposals/admission.md D3, wave 3): the one place species names are listed for fit. An item names its
// category with fits_category(FIT_X); the species it fits are listed here once, not on every item. The rule is the bodytype rule of
// dq_fits_bodytype() unchanged (an exclusive category fits every bodytype not named; the Vox/Teshari/Werebeast sprite rule still applies).


/// FIT_X -> list(bodytypes, exclusive). A static table (read while type tables compile, before globals are made).
/proc/fit_category_row(category)
	var/static/list/rows = list(
		FIT_ALTEVIAN = list(list(SPECIES_ALTEVIAN), FALSE),
		FIT_HARDSUIT = list(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_FENNEC, SPECIES_XENOHYBRID, SPECIES_ALTEVIAN, SPECIES_SHADEKIN), FALSE),
		FIT_HUMANOID_HYBRID = list(list(SPECIES_HUMAN, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_XENOCHIMERA, SPECIES_XENOMORPH_HYBRID), FALSE),
		FIT_HUMANOID_HYBRID_SKRELL = list(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_XENOCHIMERA, SPECIES_XENOMORPH_HYBRID), FALSE),
		FIT_HUMAN_PROMETHEAN = list(list(SPECIES_HUMAN, SPECIES_PROMETHEAN), FALSE),
		FIT_HUMAN_SKRELL = list(list(SPECIES_SKRELL, SPECIES_HUMAN), FALSE),
		FIT_MONKEY = list(list(SPECIES_MONKEY), FALSE),
		FIT_NO_DIONA = list(list(SPECIES_DIONA), TRUE),
		FIT_NO_DIONA_VOX = list(list(SPECIES_DIONA, SPECIES_VOX), TRUE),
		FIT_NO_DIONA_VOX_TESHARI_ALTEVIAN = list(list(SPECIES_DIONA, SPECIES_VOX, SPECIES_TESHARI, SPECIES_ALTEVIAN), TRUE),
		FIT_NO_TESHARI = list(list(SPECIES_TESHARI), TRUE),
		FIT_NO_TESHARI_VOX = list(list(SPECIES_TESHARI, SPECIES_VOX), TRUE),
		FIT_PROTEAN_HARDSUIT = list(list(SPECIES_PROTEAN, SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_XENOMORPH_HYBRID, SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW), FALSE),
		FIT_SKRELL = list(list(SPECIES_SKRELL), FALSE),
		FIT_STANDARD = list(list(SPECIES_TESHARI, SPECIES_VOX, SPECIES_DIONA), TRUE),
		FIT_TESHARI = list(list(SPECIES_TESHARI), FALSE),
		FIT_UNATHI = list(list(SPECIES_UNATHI), FALSE),
		FIT_VOX = list(list(SPECIES_VOX), FALSE),
		FIT_ZADDAT = list(list(SPECIES_ZADDAT), FALSE),
		FIT_ZADDAT_PROMETHEAN = list(list(SPECIES_ZADDAT, SPECIES_PROMETHEAN), FALSE)
	)
	return rows[category]

/// fits_category(FIT_X, because =): the wearer's bodytype fits the category (code/library/items/fit_categories.dm).
/proc/fits_category(category, because = null)
	var/list/row = fit_category_row(category)
	if(!row)
		CRASH("fits_category(): unknown fit category [category]")
	return fits(row[1], exclude = row[2], because = because)
