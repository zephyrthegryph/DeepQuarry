/datum/lore/organization/tsc/morpheus
	name = "Morpheus Cyberkinetics"
	short_name = "Morpheus"
	acronym = "MC"
	desc = "The only large corporation run by positronic intelligences, Morpheus caters almost exclusively to their sensibilities \
	and needs. A product of the synthetic colony of Shelf, Morpheus eschews traditional advertising to keep their prices low and \
	relied on word of mouth among positronics to reach their current economic dominance. Morpheus in exchange lobbies heavily for \
	positronic rights, sponsors positronics through their Jans-Fhriede test, and tends to other positronic concerns to earn them \
	the good-will of the positronics, and the ire of those who wish to exploit them. \
	<br><br> \
	Morpheus' fleet bears the names of periodic elements. They initially wanted to go with complex compounds, but realized that \
	such designations would be unwieldy and inefficient for regular usage. In the event that multiple ships are working together, \
	they may use the periodic element as their flotilla designation, and a numerical identifier that corresponds with an isotope \
	of that element for individual ships."
	history = ""
	work = "cybernetics manufacturer"
	headquarters = "Shelf flotilla"
	motto = ""

	org_type = "neutral" //disables slogans for morpheus as they don't advertise, per the description above
	/*
	slogans = list()
	*/
	ship_prefixes = list("MCV" = "a general operations", "MTV" = "a freight", "MDV" = "a market protection", "MSV" = "an outreach")
	//periodic elements; something 'unusual' for the posibrain TSC without being full on 'quirky' culture ship names (much as I love them, they're done to death)
	append_ship_names = TRUE
	added_ship_names = list(
			"Hydrogen",
			"Helium",
			"Lithium",
			"Beryllium",
			"Boron",
			"Carbon",
			"Nitrogen",
			"Oxygen",
			"Fluorine",
			"Neon",
			"Sodium",
			"Magnesium",
			"Aluminium",
			"Silicon",
			"Phosphorus",
			"Sulfur",
			"Chlorine",
			"Argon",
			"Potassium",
			"Calcium",
			"Scandium",
			"Titanium",
			"Vanadium",
			"Chromium",
			"Manganese",
			"Iron",
			"Cobalt",
			"Nickel",
			"Copper",
			"Zinc",
			"Gallium",
			"Germanium",
			"Arsenic",
			"Selenium",
			"Bromine",
			"Krypton",
			"Rubidium",
			"Strontium",
			"Yttrium",
			"Zirconium",
			"Niobium",
			"Molybdenum",
			"Technetium",
			"Ruthenium",
			"Rhodium",
			"Palladium",
			"Silver",
			"Cadmium",
			"Indium",
			"Tin",
			"Antimony",
			"Tellurium",
			"Iodine",
			"Xenon",
			"Caesium",
			"Barium"
			)
	//some hebrew alphabet destinations for a little extra unusualness
	destination_names = list(
			"our headquarters, the Shelf flotilla",
			"one of our factory complexes on Root",
			"research outpost Aleph",
			"logistics depot Dalet",
			"research installation Zayin",
			"research base Tsadi",
			"manufacturing facility Samekh"
		)
