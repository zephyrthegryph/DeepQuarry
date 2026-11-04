//////////////////////////////////////////////////////////////////////////////////

// TSCs
/datum/lore/organization/tsc/nanotrasen
	name = "NanoTrasen Incorporated"
	short_name = "NanoTrasen"
	acronym = "NT"
	desc = "NanoTrasen is one of the foremost research and development companies in Commonwealth space. \
	Originally focused on consumer products, their swift move into the field of Phoron has lead to \
	them being the foremost experts on the substance and its uses. In the modern day, NanoTrasen prides \
	itself on being an early adopter to as many new technologies as possible, often offering the newest \
	products to their employees. In an effort to combat complaints about being 'guinea pigs', Nanotrasen \
	also offers one of the most comprehensive medical plans in Commonwealth space, up to and including cloning, \
	resleeving, and therapy.\
	<br><br>\
	NT's most well known products are its phoron based creations, especially those used in Cryotherapy. \
	It also boasts a prosthetic line, which is provided to its employees as needed, and is used as an incentive \
	for newly tested posibrains to remain with the company. \
	<br><br>\
	NT's ships are named for famous scientists."
	history = "" // To be written someday.
	work = "research giant"
	headquarters = "Luna, Sol"
	motto = ""

	org_type = "corporate"
	slogans = list(
			"NanoTrasen - Phoron Makes The Galaxy Go 'Round.",
			"NanoTrasen - Join for the Medical, stay for the Company.",
			"NanoTrasen - Advancing Humanity."
			)
	ship_prefixes = list("NTV" = "a general operations", "NEV" = "an exploration", "NGV" = "a hauling", "NRV" = "an emergency response", "NDV" = "an asset protection")
	//Scientist naming scheme
	ship_names = list(
			"Bardeen",
			"Einstein",
			"Feynman",
			"Sagan",
			"Tyson",
			"Galilei",
			"Jans",
			"Fhriede",
			"Franklin",
			"Tesla",
			"Curie",
			"Darwin",
			"Newton",
			"Pasteur",
			"Bell",
			"Mendel",
			"Kepler",
			"Edison",
			"Cavendish",
			"Nye",
			"Hawking",
			"Aristotle",
			"Kaku",
			"Oppenheimer",
			"Renwick",
			"Hubble",
			"Alcubierre",
			"Glass"
			)
	// Note that the current station being used will be pruned from this list upon being instantiated
	destination_names = list(
			"NT HQ on Luna",
			"NSS Exodus in Nyx",
			"NCS Northern Star in Vir",
			"NLS Southern Cross in Vir",
			"NAS Vir Central Command",
			"NAB Smythside Central Headquarters in Sol",
			"NAS Zeus orbiting Virgo-Prime",
			"NIB Posideon in Alpha Centauri",
			"NTB Anur on Virgo-Prime",
			"NSB Adephagia in Virgo-Erigone",
			"NSB Rascal's Pass in Virgo-Erigone",
			"NRV |Stellar Delight| in Virgo-Erigone",
			"NRV |Von Braun| in Virgo-Erigone",
			"a phoron refinery in Vilous",
			"a dockyard orbiting Virgo-Prime",
			"an asteroid orbiting Virgo 3",
			"Vir Interstellar Spaceport"
			)

/datum/lore/organization/tsc/nanotrasen/New()
	..()
	after(src, 0.1 SECONDS, PROC_REF(forget_current_map_destination)) // BYOND shenanigans means using_map is not initialized yet.  Wait a tick.

/datum/lore/organization/tsc/nanotrasen/proc/forget_current_map_destination()
	// Get rid of the current map from the list, so ships flying in don't say they're coming to the current map.
	var/string_to_test = "[using_map.station_name] in [using_map.starsys_name]"
	if(string_to_test in destination_names)
		LAZYREMOVE(destination_names, string_to_test)
