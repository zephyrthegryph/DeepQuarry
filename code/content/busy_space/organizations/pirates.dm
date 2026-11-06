/datum/lore/organization/other/pirates
	name = "Pirates"
	short_name = "" //whitespace hack again
	acronym = "IPG"
	desc = "Where there's prey, predators are sure to follow. In space, the prey are civilian merchants, and the predators are opportunistic pirates. This is about where the analogy breaks down, but the basic concept remains the same; civilian ships are usually full of valuable goods or important people, which can be sold on black markets or ransomed back for a healthy sum. Pirates seek to seize the assets of others to get rich, rather than make an honest thaler themselves.\
	<br><br>\
	Common pirates tend to be rough, practical, and brutally efficient in their work. System Defense units practice rapid response drills, and in most systems it's only a matter of minutes before The Law arrives unless the pirate is able to isolate their target and prevent them from sending a distress signal.\
	<br><br>\
	Complicating matters is the infrequent use of privateers by various minor colonial governments, mercenaries turning to piracy during hard times, and illegal salvage operations."
	history = ""
	work = ""
	headquarters = ""
	motto = "What\'s yours is mine."
	autogenerate_destination_names = TRUE //the events we get called for don't fire a destination, but we need entries to avoid runtimes.

	org_type = "pirate"
	ship_prefixes = list ("known pirate" = "a piracy", "suspected pirate" = "a piracy", "rogue privateer" = "a piracy", "Cartel enforcer" = "a piracy", "known outlaw" = "a piracy", "bandit" = "a piracy", "roving corsair" = "a piracy", "illegal salvager" = "an illegal salvage", "rogue mercenary" = "a mercenary") //as assigned by control, second part shouldn't even come up, but it exists to avoid hiccups/weirdness just in case

	ship_names = list()

/datum/lore/organization/other/pirates/New()
	..()
	var/i = 20 //give us twenty random names. as for smugglers, so for pirates. in this case I went with two-syllable b-words.
	var/list/first_word = list(
			"Bandit","Bogey","Backup","Baker","Balance","Bandwidth","Banker","Banner","Bargain","Baseball","Basket","Bathroom","Berlin","Beyond","Bidder","Bishop","Bookmark","Border","Boston","Bracelet","Brazil","Breakfast","Brian","Broadband","Brochure","Broken","Broker","Brother","Buddy","Budget","Bureau","Business"
			)
	var/list/nato_phonetic = list(
			"Alfa","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","Xray","Yankee","Zulu"
			)
	while(i)
		ship_names.Add("[pick(first_word)] [rand(1,99)]-[pick(nato_phonetic)]")
		i--
