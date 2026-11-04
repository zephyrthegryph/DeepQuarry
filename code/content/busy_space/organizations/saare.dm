//replaced the edgy blackstar group with polaris-canon SAARE
/datum/lore/organization/mil/saare
	name = "Stealth Assault Enterprises"
	short_name = "SAARE"
	acronym = "SAARE"
	desc = "SAARE consistently have the worst reputation of any paramilitary group. This is because they specialize in deniability and secrecy. Although publically they work in asset recovery, they have a substantiated reputation for info-theft and piracy that has lead to them butting heads with the law on more than one occasion. Nonetheless, they are an invaluable part of the Solar economy, and other TSCs and small colonial governments keep them in business.\
	<br><br>\
	For the purposes of plausible deniability, SAARE designates their ships using a series of rotating identifiers, with ships on a specific operation or in a particular area all using the same initial designation (<i>e.g.</i> 'Sledgehammer') and having a different numerical identifier, with the most important ships involved bearing a unique additional codename (such as 'Actual' for Command & Control ships). As ships are shuffled in and out of operating areas, it can be difficult to pin down exactly which ship in SAARE's fleet was responsible for which act. SAARE's misdirection is multilayered, including elements such as extensive use of repainting, false IFFs, bribes, forged documents, intimidation, camouflage, and all manner of other underhanded tactics."
	history = ""
	work = "mercenary contractors"
	headquarters = ""
	motto = "Aut Neca Aut Necare"
	autogenerate_destination_names = TRUE

	org_type = "military"
	ship_prefixes = list("SAARE" = "a classified")
	ship_names = list()
	destination_names = list(
			"SAARE Command",
			"a SAARE training site",
			"a SAARE logistical depot",
			"a SAARE-held shipyard"
			)

/datum/lore/organization/mil/saare/New()
	..()
	var/i = 20 //give us twenty random names, saare uses tacticool designations
	var/list/letters = list(
			"King",
			"Queen",
			"Duke",
			"Cipher",
			"Monarch",
			"Marshal",
			"Magnum",
			"Longbow",
			"Jupiter",
			"Excalibur",
			"Charon",
			"Bloodhound",
			"Daybreak",
			"Tomahawk",
			"Raptor",
			"Cerberus",
			"Apollo",
			"Firebird",
			"Outlaw",
			"Outrider",
			"Vector",
			"Spearhead",
			"Sledgehammer",
			"Typhon",
			"Sundown",
			"Zodiac",
			"Colossus",
			"Jackhammer",
			"Kodiak",
			"Phalanx",
			"Rainmaker",
			"Shockwave",
			"Warhammer",
			"Crusader",
			"Maverick",
			"Nighthawk",
			"Foxbat",
			"Redshift",
			"Challenger",
			"Starlight",
			"Sunray",
			"Ironside",
			"Holdfast",
			"Foxhound",
			"Zerstorer",
			"Skyhawk",
			"Thunderhead"
			)
	var/list/numbersone = list(
			"Zero",
			"One",
			"Two",
			"Three",
			"Four",
			"Five",
			"Six",
			"Seven",
			"Eight",
			"Nine"
			)
	var/list/numberstwo = list(
			"Zero",
			"One",
			"Two",
			"Three",
			"Four",
			"Five",
			"Six",
			"Seven",
			"Eight",
			"Niner"
			)
	while(i)
		ship_names.Add("[pick(letters)] [pick(40;"Actual","[pick(numbersone)]-[pick(numberstwo)]")]")
		i--

	//ex: "Phalanx One-Niner", "Sledgehammer Actual" (CO/VIP), "Kodiak Seven-Four", "Tomahawk Two-Zero"
	//probably a more elegant (read: fancier) way to do the second part but fuck it, this works just fine
