/*
//Commenting out the Ue-Katish and Vox Marauders for now, to dial down the implications of rampant piracy
/datum/lore/organization/other/uekatish
	name = "Ue-Katish Pirates"
	short_name = ""
	acronym = "UEK"
	desc = "Contrasting with the Qerr-Glia is a vibrant community of Ue-Katish pirates, who live in cargo flotillas on the edge of Skrellian space (especially on the Human-Skrell border). Ue-Katish ships have no caste system even for the truecaste Skrell and aliens who live there, although they are regimented by rank and role in the ship's functioning. Ue-Katish ships are floating black markets where everything is available for the right price, including some of the galaxy's most well-connected information brokers and most skilled guns-for-hire. The Ue-Katish present the greatest Skrellian counterculture and feature heavily in romanticized human media, although at their hearts they are still bandits and criminals, and the black markets are filled with goods plundered from human and Skrellian trade ships. Many of the Ue-Katish ships themselves bear the scars of the battle that brought them under the pirate flag.\
	<br><br> \
	Ue-Katish pirate culture is somewhat similar to many human countercultures, gleefully reclaiming slurs and subverting expectations for the sheer shock value. Nonetheless, Ue-Katish are still Skrell, and still organize in neat hierarchies under each ship's Captain. The Captain's word is absolute, and unlike the Qerr-Katish they lack any sort of anti-corruption institutions."
	history = ""
	work = ""
	motto = ""
	autogenerate_destination_names = TRUE

	org_type = "pirate"
	ship_prefixes = list("Ue-Katish pirate" = "a raiding", "Ue-Katish bandit" = "a raiding", "Ue-Katish raider" = "a raiding", "Ue-Katish enforcer" = "an enforcement")
	ship_names = list()

/datum/lore/organization/other/uekatish/New()
	..()
	var/i = 20 //give us twenty random names
	var/list/first_names = file2list('config/names/first_name_skrell.txt')
	var/list/words = list(
			"Prize",
			"Bounty",
			"Treasure",
			"Pearl",
			"Star",
			"Mercy",
			"Compass",
			"Greed",
			"Slave",
			"Madness",
			"Pride",
			"Disgrace",
			"Judgement",
			"Wrath",
			"Hatred",
			"Vengeance",
			"Fury",
			"Thunder",
			"Scream",
			"Dagger",
			"Saber",
			"Lance",
			"Blade"
			)
	while(i)
		ship_names.Add("[pick(first_names)]'s [pick(words)]")
		i--

/datum/lore/organization/other/marauders
	name = "Vox Marauders"
	short_name = "" //whitespace hack again
	acronym = "VOX"
	desc = "Whilst rarely as directly threatening as 'common' pirates, the phoron-breathing vox nevertheless pose a constant nuisance for shipping; as far as vox are concerned, only vox and vox matters matter, and everyone else is a 'treeless dusthuffer'. Unlike sometimes over-confident pirates, the vox rarely engage in direct, open combat, preferring to make their profits by either stealth or gunboat diplomacy that tends to be more bluster than true brute force: vox raiders will only commit to an attack if they're confident that they can quickly overwhelm and subdue their victims, then get away with the spoils before any reinforcements can arrive.\
	<br><br>\
	As Vox ship names are generally impossible for the vast majority of other species to pronounce, System Defense tends to tag marauders with a designation based on the ancient NATO Phonetic Alphabet."
	history = "Unknown"
	work = "Looting and raiding"
	headquarters = "Nowhere"
	motto = "(unintelligible screeching)"
	autogenerate_destination_names = TRUE //the events we get called for don't fire a destination, but we need *some* entries to avoid runtimes.

	org_type = "pirate"
	ship_prefixes = list("vox marauder" = "a marauding", "vox raider" = "a raiding", "vox ravager" = "a raiding", "vox corsair" = "a raiding") //as assigned by control, second part shouldn't even come up
	//blank out our shipnames for redesignation
	ship_names = list()

/datum/lore/organization/other/marauders/New()
	..()
	var/i = 20 //give us twenty random names, marauders get tactical designations from SDF
	var/list/letters = list(
			"Alpha",
			"Bravo",
			"Charlie",
			"Delta",
			"Echo",
			"Foxtrot",
			"Golf",
			"Hotel",
			"India",
			"Juliett",
			"Kilo",
			"Lima",
			"Mike",
			"November",
			"Oscar",
			"Papa",
			"Quebec",
			"Romeo",
			"Sierra",
			"Tango",
			"Uniform",
			"Victor",
			"Whiskey",
			"X-Ray",
			"Yankee",
			"Zulu"
			)
	var/list/numbers = list(
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
	while(i)
		ship_names.Add("[pick(letters)]-[pick(numbers)]")
		i--
*/
//////////////////////////////////////////////////////////////////////////////////

// Governments
/datum/lore/organization/gov/commonwealth
	name = "Commonwealth of Sol-Procyon"
	short_name = "SolCom"
	acronym = "CWS"
	desc = "The Commonwealth of Sol-Procyon is the evolution of the many nation states of Earth and the outlying colonies \
			having spread amongst the stars. While not quite the hegemon of all Humanity, a narrow majority of them follow \
			the flag of the Commonwealth. The constant tug and pull of government versus corporation, democracy and power \
			troubles this federation of deeply entrenched human colonies much like it did in the 21st century. Some things \
			never change. However, they are economically and culturally quite dominant, although not everyone likes that fact. \
			<br><br> \
			Ships on official CWS assignments typically carry the designations of Earth\'s largest craters, as a reminder of \
			everything the planet (and humanity itself) has endured."
	history = "" // Todo
	work = "governing polity of humanity's systems"
	headquarters = "Luna, Sol"
	motto = "Nil Mortalibus Ardui Est" // Latin, because latin.  Says 'Nothing is too steep for mortals'
	autogenerate_destination_names = TRUE

	org_type = "government"
	ship_prefixes = list("CWS-A" = "an administrative", "CWS-T" = "a transportation", "CWS-D" = "a diplomatic", "CWS-F" = "a freight", "CWS-J" = "a prisoner transfer")
	//earth's biggest impact craters
	ship_names = list(
			"Wabar",
			"Kaali",
			"Campo del Cielo",
			"Henbury",
			"Morasko",
			"Boxhole",
			"Macha",
			"Rio Cuarto",
			"Ilumetsa",
			"Tenoumer",
			"Xiuyan",
			"Lonar",
			"Agoudal",
			"Tswaing",
			"Zhamanshin",
			"Bosumtwi",
			"Elgygytgyn",
			"Bigach",
			"Karla",
			"Karakul",
			"Vredefort",
			"Chicxulub",
			"Sudbury",
			"Popigai",
			"Manicougan",
			"Acraman",
			"Morokweng",
			"Kara",
			"Beaverhead",
			"Tookoonooka",
			"Charlevoix",
			"Siljan Ring",
			"Montagnais",
			"Araguinha",
			"Chesapeake",
			"Mjolnir",
			"Puchezh-Katunki",
			"Saint Martin",
			"Woodleigh",
			"Carswell",
			"Clearwater West",
			"Clearwater East",
			"Manson",
			"Slate",
			"Yarrabubba",
			"Keurusselka",
			"Shoemaker",
			"Mistastin",
			"Kamensk",
			"Steen",
			"Strangways",
			"Tunnunik",
			"Boltysh",
			"Nordlinger Ries",
			"Presqu'ile",
			"Haughton",
			"Lappajarvi",
			"Rochechouart",
			"Gosses Bluff",
			"Amelia Creek",
			"Logancha",
			"Obolon'",
			"Nastapoka",
			"Ishim",
			"Bedout"
			)
	destination_names = list(
			"Venus",
			"Earth",
			"Luna",
			"Mars",
			"Titan",
			"Europa",
			"the Jovian subcluster",
			"a Commonwealth embassy",
			"a classified location"
			)
			// autogen will add a lot of other places as well.
