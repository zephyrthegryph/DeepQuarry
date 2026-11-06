//basically just a dummy/placeholder 'org' for smuggler events
/datum/lore/organization/other/smugglers
	name = "Smugglers"
	short_name = "" //whitespace hack again
	acronym = "ISC"
	desc = "Where there's a market, there need to be merchants, and where there are buyers, there need to be suppliers. Most of all, wherever there's governments, there'll be somebody trying to control what people are and aren't allowed to do with their bodies. For those seeking goods deemed illegal (for good reasons or otherwise) they need to turn to smugglers and the fine art of sneaking things past the authorities.\
	<br><br>\
	The most common goods smuggled throughout space are narcotics, firearms, and occasionally slaves; whilst firearm ownership laws vary from location to location, most governments also take fairly hard stances on hard drugs, and slavery is consistently outlawed and punished viciously throughout the vast majority of civilized space.\
	<br><br>\
	Still, contrary to many conceptions, not all smuggling is nefarious. Entertainment media within human territories loves to paint romantic images of heroic smugglers sneaking aid supplies to refugees or even helping oppressed minorities escape the grasp of xenophobic regimes."
	history = ""
	work = ""
	headquarters = ""
	motto = ""
	autogenerate_destination_names = TRUE //the events we get called for don't fire a destination, but we need entries to avoid runtimes.

	org_type = "smuggler"
	ship_prefixes = list ("suspected smuggler" = "an illegal smuggling", "possible smuggler" = "an illegal smuggling") //as assigned by control, second part shouldn't even come up

	ship_names = list()

/datum/lore/organization/other/smugglers/New()
	..()
	var/i = 20 //give us twenty random names. for smugglers, I grabbed a bunch of two-syllable s-words, in keeping with NATO reporting names. I figured a fixed name list didn't make very much sense.
	var/list/first_word = list(
			"Smuggler","Safety","Scanner","Season","Secret","Section","Seeker","Server","Seller","Sequence","Shadow","Solar","Software","Smoker","Southwest","Spectrum","Spirit","Sponsor","Stainless","Stable","Study","Subject","Student","Surface","Symbol","Supreme","Surprise","Syntax","Sterling","Statement"
			)
	var/list/nato_phonetic = list(
			"Alfa","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","Xray","Yankee","Zulu"
			)
	while(i)
		ship_names.Add("[pick(first_word)] [rand(1,99)]-[pick(nato_phonetic)]")
		i--
