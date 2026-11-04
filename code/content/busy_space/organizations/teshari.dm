/datum/lore/organization/gov/teshari
	name = "Teshari Union"
	short_name = "Teshari"
	acronym = "TUV"
	desc = "Though nominally a client state of the skrell, the Teshari Union nevertheless maintain their own navy of primarily civilian ships. The fleets of the TUV are the primary source of Teshari expansion, and effectively are the nation itself. That isn't to say there aren't independent teshari colonies out there, but those that are founded under the wings of the TUV tend to be the largest and most prosperous. They're also responsible for maintaining the security of these colonies and protecting trade ships, although heavier work is done by their Skrell allies. Like the USDF (and unlike most other governmental fleets), TU vessels almost universally sport the 'TUV' designator rather than specific terms.\
	<br><br>\
	The TU's ships are named after famous teshari pioneers and explorers and the events surrounding those individuals."
	history = ""
	work = "teshari colonization and infrastructure maintenance"
	headquarters = "Qerr'balak, Qerr'valis"
	motto = ""
	autogenerate_destination_names = TRUE //big list of own holdings to come

	org_type = "government"
	//its more or less a civilian fleet of ships that have a few armed ones sprinkled in to deter pirates when needed. They call in the Skrell for anything heavier.
	ship_prefixes = list("TUV" = "a pioneering")
	//TODO: better ship names? I just took a bunch of random teshnames from the Random Name button and added a word.
	ship_names = list()
	destination_names = list(
			"an expeditionary fleet RV point",
			"an expeditionary fleet Resupply Ship",
			"an expeditionary fleet Supply Depot",
			"a newly-founded Teshari colony",
			"a prospective Teshari colony site",
			"a potential Teshari colony site",
			"a fleet hub"
			)

/datum/lore/organization/gov/teshari/New()
	..()
	var/i = 20 //give us twenty random names
	var/list/first_names = list(
			"Leniri's",
			"Tatani's",
			"Ninai's",
			"Miiescha's",
			"Ishena's",
			"Taalische's",
			"Cami's",
			"Schemisa's",
			"Shilirashi's",
			"Sanene's",
			"Aeimi's",
			"Ischica's",
			"Shasche's",
			"Leseca's",
			"Iisi's",
			"Simascha's",
			"Lisascheca's"
			)
	var/list/words = list(
			"Hope",
			"Venture",
			"Voyage",
			"Talons",
			"Fang",
			"Claw",
			"Wing",
			"Pride",
			"Glory",
			"Wit",
			"Insight",
			"Wisdom",
			"Foresight",
			"Mind",
			"Cry",
			"Howl",
			"Fury",
			"Revenge",
			"Vengeance"
			)
	while(i)
		ship_names.Add("[pick(first_names)] [pick(words)]")
		i--
