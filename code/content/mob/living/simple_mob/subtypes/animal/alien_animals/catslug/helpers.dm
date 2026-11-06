// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//No relation to slugcat :)

/datum/category_item/catalogue/fauna/catslug
	name = "Alien Wildlife - Catslug"
	desc = "The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_MEDIUM

/datum/say_list/catslug	//Quiet quiet, no noise! We speak in sign so only people with sign will understand our questions.
	speak = list("Have any porl?", "What is that?", "Where is this?", "What are you doing?", "How did you get here?", "Don't go into the rain.")
	emote_see = list("turns their head.", "looks at you.", "watches something unseen.", "sways its tail.", "flicks its ears.", "stares at you.", "gestures an unintelligible message.", "points into the distance!")

/obj/item/holder/catslug
	icon = 'icons/mob/alienanimals_x32.dmi'
	item_state = "catslug"

/obj/item/holder/catslug/take_held(mob/held)
	..()
	if(held)
		set_color(held.color)

/datum/category_item/catalogue/fauna/catslug/custom/spaceslug
	name = "Alien Wildlife - Catslug - Miros"
	desc = "This catslug serves as the Fuel Depots resident attendant,\
	despite the facility being fully automated and self-serve. - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_MEDIUM	//Should offer a measure of incentive for people to visit the depot more often.

/datum/say_list/catslug/custom/spaceslug
	speak = list("Have any porl?", "What is that?", "What kind of ship is that?", "What are you doing?", "How did you get here?", "Don't take off your helmet.", "SPAAAAAACE!", "WAOW!", "Nice weather we're having, isn't it?")

/obj/item/holder/catslug/custom/spaceslug
	item_state = "spaceslug"

//Engineer catslug
/datum/category_item/catalogue/fauna/catslug/custom/engislug
	name = "Alien Wildlife - Catslug - Engineer O'Brimn"
	desc = "A resident worker at the NSB Rascal's Pass, Engineer O'Brimn \
	keeps the facilities pipework and machinery maintained between shifts, as \
	well as \"fixing\" the engine back to it's original configuration. \
	Reportedly the cause for numerous phoron-based conflagrations. - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL	//Local catslugs worth less than rarer ones

/datum/say_list/catslug/custom/engislug
	speak = list("Have any porl?", "What is that?", "Phoroncheck!", "Thump is mean work fine!", "What are you doing?", "How did you get here?", "Don't breathe in the spicy purple.", "Zap-zap ball bad.", "WAOW!", "The pipes make sense.")

/obj/item/holder/catslug/custom/engislug
	item_state = "engislug"

//Security catslug
/datum/category_item/catalogue/fauna/catslug/custom/gatslug
	name = "Alien Wildlife - Catslug - Officer Gatslug"
	desc = "A resident worker at the NSB Rascal's Pass, Officer Gatslug \
	served with distinction during upheaval at the NSB Adephagia in 2321. \
	After their recovery from the wreckage afterwards, they were awarded \
	several commendations and an offer to serve aboard the latest NT venture \
	in the Virgo-Erigone system. - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL	//Local catslugs worth less than rarer ones

/datum/say_list/catslug/custom/gatslug
	speak = list("Have any flashbangs?", "Valids!", "Heard spiders?", "What is that?", "Freeze!", "What are you doing?", "How did you get here?", "Red alert means big bangsticks.", "No being naughty now.", "WAOW!", "Who ate all the donuts?")

/obj/item/holder/catslug/custom/gatslug
	item_state = "gatslug"

//Medical catslug
/datum/category_item/catalogue/fauna/catslug/custom/medislug
	name = "Alien Wildlife - Catslug - Doctor Mlemulon"
	desc = "A resident worker at the NSB Rascal's Pass, Doctor Mlemulon \
	works hard to drink and eat all the remaining medicine stocks in \
	the smartfridge after the end of a shift. Rumour has it they have \
	a side business of trading advanced surgical tools for \"tasty yummers\" too. - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL	//Local catslugs worth less than rarer ones

/datum/say_list/catslug/custom/medislug
	speak = list("Have any osteodaxon?", "What is that?", "Suit sensors!", "What are you doing?", "How did you get here?", "Put a mask on!", "No smoking!", "WAOW!", "Stop getting blood everywhere!", "WHERE IN MAINT?")

/obj/item/holder/catslug/custom/medislug
	item_state = "medislug"

//Science catslug
/datum/category_item/catalogue/fauna/catslug/custom/scienceslug
	name = "Alien Wildlife - Catslug - Professor Nubbins"
	desc = "A resident worker at the NSB Rascal's Pass, Professor Nubbins \
	is tasked with the periodic maintenance of the R&D servers. \
	Unfortunately, they take this to mean \"wipe all stored research\". - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL	//Local catslugs worth less than rarer ones

/datum/say_list/catslug/custom/scienceslug
	speak = list("Slimes, squish!", "What is that?", "Smoking in Toxins is not advised.", "What are you doing?", "How did you get here?", "Do not deconstruct the cube!", "WAOW!", "Where are our materials?", "The acid dispenser is not full of juice. Must remember that.")

/obj/item/holder/catslug/custom/scienceslug
	item_state = "scienceslug"

//Cargo catslug
/datum/category_item/catalogue/fauna/catslug/custom/cargoslug
	name = "Alien Wildlife - Catslug - Technician Nermley"
	desc = "A resident worker at the NSB Rascal's Pass, Technician Nermley \
	is something of a mystery. No one is sure where they came from, \
	local scuttlebutt is that they just turned up one day and started \
	moving crates around. - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL	//Local catslugs worth less than rarer ones

/datum/say_list/catslug/custom/cargoslug
	speak = list("Disposals is not for slip and slide.", "What is that?", "Stamp those manifests!", "What are you doing?", "How did you get here?", "Can order pizza crate?", "WAOW!", "Where are all of our materials?", "Got glubbs?")

/obj/item/holder/catslug/custom/cargoslug
	item_state = "cargoslug"

//Command catslug
/datum/category_item/catalogue/fauna/catslug/custom/capslug
	name = "Alien Wildlife - Catslug - Captain Crumsh"
	desc = "A resident worker at the NSB Rascal's Pass, Captain Crumsh \
	comes from a long line of catslug leaders, maintaining the family tradition \
	for numerous years now. After a long tenure serving at Central Command, they \
	requested transfer to a more \"front-facing\" facility, ending up shipped across \
	to the facilty recently set up on Virgo 3C. - \
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL	//Local catslugs worth less than rarer ones

/datum/say_list/catslug/custom/capslug
	speak = list("How open big glass box with shiny inside?.", "What is that?", "Respect my authority!", "What are you doing?", "How did you get here?", "Fax for yellow-shirts!", "WAOW!", "Why is that console blinking and clicking?", "Do we need to call for ERT?", "Have been called comdom before, not sure why they thought I was a balloon.")

/obj/item/holder/catslug/custom/capslug
	item_state = "capslug"

/datum/category_item/catalogue/fauna/catslug/custom/pilotslug
	name = "Alien Wildlife - Catslug - Navigator Purrverick"
	desc = "A resident at NSB Rascal's Pass, Navigator Purrverick \
	is a catslug who is known to dream big and seek the sky.\
	Purrverick has proved to be quite capable of utilizing shuttle\
	controls with excellent grace and skill. Purrverick can however\
	be rather self assured, which has on more than one occasion\
	lead to unfortunate mistakes and incidents.\
	Purrverick's provisionary piloting liscense is marked as suspended.\
	There are however still more records of the catslug's piloting escapades\
	dated afer their suspension.\
	\
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL

/datum/say_list/catslug/custom/pilotslug
	speak = list("In the pipe, five my five.","Kick the tires and light the fires!","Bogeys on my tail!","GOOSE!","I'm really good at the stick.","I'm not doing nothing.","Heh.","Can you keep up?","Can't keep the sky from me.")

/datum/category_item/catalogue/fauna/catslug/custom/royalslug
	name = "Alien Wildlife - Catslug - Ruler Purrton"
	desc = "Found in a castle beyond the redgate, Ruler Purrton\
	is a catslug who spends their days presiding over this low \
	technology town, living a life of luxury. Always seen with \
	their trademark crown and cloak, this litter critter seems \
	to just exude raw confidence and superiority. \
	\
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL

/datum/say_list/catslug/custom/royalslug
	speak = list("Let them eat cake. Lots and lots of cake.", "Fetch my good cloak.", "I myself prefer my ancient eggs for breakfast!", "Have you come to pay tribute?", "How dare you intrude?", "Bring me the finest of fine finery.", "HARK!", "With great power comes great dinner.")

/datum/category_item/catalogue/fauna/catslug/custom/cryptslug
	name = "Alien Wildlife - Catslug - Keeper Sluguloth"
	desc = "Found in a deep beneath a town beyond the redgate, Sluguloth\
	is a catslug who spends their days lurking within dark dungeons \
	alongside monstrous beings of all sorts. Always seen within \
	their dark cloak, obscuring them, this litter critter seems \
	to just exude pure menance and up-to-no-goodness. \
	\
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL

/datum/say_list/catslug/custom/cryptslug
	speak = list("I have a lot of nasty friends.", "Do not test me.", "I shall rise again!", "How dare you step foot in my domain?", "Dare you indluge in dark desires?", "I am become death, one day.", "Foul creature!", "I used to think my life was a tragedy, but now I realize it's kind of okay actually.")

/datum/category_item/catalogue/fauna/catslug/custom/exploslug
	name = "Alien Wildlife - Catslug - Explorer Pawdiana"
	desc = "Found in the depths of an arugably magical jungle, Pawdiana\
	is a catslug who spends their days treking through the dense foliage \
	of the dangerous wild. Always seen within \
	their fancy explorers kit, they are always ready to brave \
	the hazards of unknown lands. \
	\
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL

/datum/say_list/catslug/custom/exploslug
	speak = list("Fortune and porls, kid. Fortune and porls.", "Lizards, why'd it have to be lizards.", "That thingy is an important artifact. It belongs in a museum!", "Everything lost is meant to be found. By me.", "I swear I've seen that stone before...", "I should have packed more jellyfishes.", "I better get back before nightfall!", "A comfy bed? Hah! I sleep under the stars!")

/datum/category_item/catalogue/fauna/catslug/custom/santaslug
	name = "Alien Wildlife - Catslug - Santa Claws"
	desc = "Found in a mysterious toyshop in a snowy wonderland, Claws\
	is a catslug who spends their days building toys and is said to, \
	once a year, hand them out to well behaved people. Always seen wearing \
	their red coat and hat, they are always ready to spread \
	festive cheer throughout the galaxy. \
	\
	The Catslug is an omnivorous terrestrial creature.\
	Exhibiting properties of both a cat and a slug (hence its name)\
	it moves somewhat awkwardly. However, the unique qualities of\
	its body make it exceedingly flexible and smooth, allowing it to\
	wiggle into and move effectively in even extremely tight spaces.\
	Additionally, it has surprisingly capable hands, and moves quite\
	well on two legs or four. Caution is advised when interacting\
	with these creatures, they are quite intelligent, and proficient\
	tool users."
	value = CATALOGUER_REWARD_TRIVIAL

/datum/say_list/catslug/custom/santaslug
	speak = list("Ho ho ho!", "Meow-ery Solstice, everybody!", "Thanks fur all the furstive cheer!", "I must get all these purresents", "What would be the pawfect gift for you?", "All I want for solstice is... Porls.", "The winter trees are more bark than bite!", "I'm just glad not to be stuck in a blizzard again!")

// The special catslugs' headsets: their channel and key.
/obj/item/radio/headset/mob_headset/capslug
	frequency = PUB_FREQ
	ks2type = /obj/item/encryptionkey/heads/captain // might not be able to speak, but the catslug can listen

/obj/item/radio/headset/mob_headset/deathslug
	frequency = DTH_FREQ

/obj/item/radio/headset/mob_headset/syndislug
	frequency = SYND_FREQ
	syndie = TRUE
	ks2type = /obj/item/encryptionkey/syndicate

/obj/item/radio/headset/mob_headset/responseslug
	frequency = ERT_FREQ
	centComm = 1
	ks2type = /obj/item/encryptionkey/ert
