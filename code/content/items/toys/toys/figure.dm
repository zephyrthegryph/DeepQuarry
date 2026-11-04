/*
 * Action figures
 */
/obj/item/toy/figure
	name = "Non-Specific Action Figure action figure"
	desc = "A \"Space Life\" brand... wait, what the hell is this thing?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "nuketoy"
	w_class = ITEMSIZE_TINY
	var/cooldown = 0
	var/toysay = "What the fuck did you do?"

/// Every figure is described by its name (derives(), at init).
/obj/item/toy/figure/proc/space_life_desc()
	return "A \"Space Life\" brand [name]"

CAPABILITIES(/obj/item/toy/figure)
	configure(item_sounds(drop = SFX_ITEMS_DROP_ACCESSORY))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	derives(nameof(desc), PROC_REF(space_life_desc))

/// Old attack_self.
/obj/item/toy/figure/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
		user.visible_message(span_notice("The [src] says \"[toysay]\"."))
		play_sfx(src, SFX_MACHINES_CLICK, 0.4)
	return TRUE

/obj/item/toy/figure/cmo
	name = JOB_CHIEF_MEDICAL_OFFICER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHIEF_MEDICAL_OFFICER + " action figure."
	icon_state = "cmo"
	toysay = "Suit sensors!"

/obj/item/toy/figure/assistant
	name = "Assistant action figure"
	desc = "A \"Space Life\" brand Assistant action figure."
	icon_state = "assistant"
	toysay = "Grey tide station wide!"

/obj/item/toy/figure/atmos
	name = JOB_ATMOSPHERIC_TECHNICIAN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ATMOSPHERIC_TECHNICIAN + " action figure."
	icon_state = "atmos"
	toysay = "Glory to Atmosia!"

/obj/item/toy/figure/bartender
	name = JOB_BARTENDER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_BARTENDER + " action figure."
	icon_state = "bartender"
	toysay = "Where's my monkey?"

/obj/item/toy/figure/borg
	name = "Drone action figure"
	desc = "A \"Space Life\" brand Drone action figure."
	icon_state = "borg"
	toysay = "I. LIVE. AGAIN."

/obj/item/toy/figure/gardener
	name = JOB_ALT_GARDENER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ALT_GARDENER + " action figure."
	icon_state = "botanist"
	toysay = "Dude, I see colors..."

/obj/item/toy/figure/captain
	name = JOB_SITE_MANAGER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SITE_MANAGER + " action figure."
	icon_state = "captain"
	toysay = "How do I open this display case?"

/obj/item/toy/figure/cargotech
	name = JOB_CARGO_TECHNICIAN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CARGO_TECHNICIAN + " action figure."
	icon_state = "cargotech"
	toysay = "For Cargonia!"

/obj/item/toy/figure/ce
	name = JOB_CHIEF_ENGINEER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHIEF_ENGINEER + " action figure."
	icon_state = "ce"
	toysay = "Wire the solars!"

/obj/item/toy/figure/chaplain
	name = JOB_CHAPLAIN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHAPLAIN + " action figure."
	icon_state = "chaplain"
	toysay = "Gods make me a killing machine please!"

/obj/item/toy/figure/chef
	name = JOB_CHEF + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHEF + " action figure."
	icon_state = "chef"
	toysay = "I swear it's not human meat."

/obj/item/toy/figure/chemist
	name = JOB_CHEMIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHEMIST + " action figure."
	icon_state = "chemist"
	toysay = "Get your pills!"

/obj/item/toy/figure/clown
	name = JOB_CLOWN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CLOWN + " action figure."
	icon_state = "clown"
	toysay = "<font face='comic sans ms'>" + span_bold("Honk!") + "</font>"

/obj/item/toy/figure/corgi
	name = "Corgi action figure"
	desc = "A \"Space Life\" brand Corgi action figure."
	icon_state = "ian"
	toysay = "Arf!"

/obj/item/toy/figure/detective
	name = JOB_DETECTIVE + " action figure"
	desc = "A \"Space Life\" brand " + JOB_DETECTIVE + " action figure."
	icon_state = "detective"
	toysay = "This airlock has grey jumpsuit and insulated glove fibers on it."

/obj/item/toy/figure/dsquad
	name = "Space Commando action figure"
	desc = "A \"Space Life\" brand Space Commando action figure."
	icon_state = "dsquad"
	toysay = "Eliminate all threats!"

/obj/item/toy/figure/engineer
	name = JOB_ENGINEER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ENGINEER + " action figure."
	icon_state = "engineer"
	toysay = "Oh god, the engine is gonna go!"

/obj/item/toy/figure/geneticist
	name = JOB_GENETICIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_GENETICIST + " action figure, which was recently dicontinued."
	icon_state = "geneticist"
	toysay = "I'm not qualified for this job."

/obj/item/toy/figure/hop
	name = JOB_HEAD_OF_PERSONNEL + " action figure"
	desc = "A \"Space Life\" brand " + JOB_HEAD_OF_PERSONNEL + " action figure."
	icon_state = "hop"
	toysay = "Giving out all access!"

/obj/item/toy/figure/hos
	name = JOB_HEAD_OF_SECURITY + " action figure"
	desc = "A \"Space Life\" brand " + JOB_HEAD_OF_SECURITY + " action figure."
	icon_state = "hos"
	toysay = "I'm here to win, anything else is secondary."

/obj/item/toy/figure/qm
	name = JOB_QUARTERMASTER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_QUARTERMASTER + " action figure."
	icon_state = "qm"
	toysay = "Hail Cargonia!"

/obj/item/toy/figure/janitor
	name = JOB_JANITOR + " action figure"
	desc = "A \"Space Life\" brand " + JOB_JANITOR + " action figure."
	icon_state = "janitor"
	toysay = "Look at the signs, you idiot."

/obj/item/toy/figure/agent
	name = JOB_INTERNAL_AFFAIRS_AGENT + " action figure"
	desc = "A \"Space Life\" brand " + JOB_INTERNAL_AFFAIRS_AGENT + " action figure."
	icon_state = "agent"
	toysay = "Standard Operating Procedure says they're guilty! Hacking is proof they're an Enemy of the Corporation!"

/obj/item/toy/figure/librarian
	name = JOB_LIBRARIAN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_LIBRARIAN + " action figure."
	icon_state = "librarian"
	toysay = "One day while..."

/obj/item/toy/figure/md
	name = JOB_MEDICAL_DOCTOR + " action figure"
	desc = "A \"Space Life\" brand " + JOB_MEDICAL_DOCTOR + " action figure."
	icon_state = "md"
	toysay = "The patient is already dead!"

/obj/item/toy/figure/mime
	name = JOB_MIME + " action figure"
	desc = "A \"Space Life\" brand " + JOB_MIME + " action figure."
	icon_state = "mime"
	toysay = "..."

/obj/item/toy/figure/miner
	name = JOB_SHAFT_MINER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SHAFT_MINER + " action figure."
	icon_state = "miner"
	toysay = "Oh god, it's eating my intestines!"

/obj/item/toy/figure/ninja
	name = "Space Ninja action figure"
	desc = "A \"Space Life\" brand Space Ninja action figure."
	icon_state = "ninja"
	toysay = "Oh god! Stop shooting, I'm friendly!"

/obj/item/toy/figure/wizard
	name = JOB_WIZARD + " action figure"
	desc = "A \"Space Life\" brand " + JOB_WIZARD + " action figure."
	icon_state = "wizard"
	toysay = "Ei Nath!"

/obj/item/toy/figure/rd
	name = JOB_RESEARCH_DIRECTOR + " action figure"
	desc = "A \"Space Life\" brand " + JOB_RESEARCH_DIRECTOR + " action figure."
	icon_state = "rd"
	toysay = "Blowing all of the borgs!"

/obj/item/toy/figure/roboticist
	name = JOB_ROBOTICIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ROBOTICIST + " action figure."
	icon_state = "roboticist"
	toysay = "He asked to be borged!"

/obj/item/toy/figure/scientist
	name = JOB_SCIENTIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SCIENTIST + " action figure."
	icon_state = "scientist"
	toysay = "Someone else must have made those bombs!"

/obj/item/toy/figure/syndie
	name = "Doom Operative action figure"
	desc = "A \"Space Life\" brand Doom Operative action figure."
	icon_state = "syndie"
	toysay = "Get that fucking disk!"

/obj/item/toy/figure/secofficer
	name = JOB_SECURITY_OFFICER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SECURITY_OFFICER + " action figure."
	icon_state = "secofficer"
	toysay = "I am the law!"

/obj/item/toy/figure/virologist
	name = JOB_ALT_VIROLOGIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ALT_VIROLOGIST + " action figure."
	icon_state = "virologist"
	toysay = "The cure is potassium!"

/obj/item/toy/figure/warden
	name = JOB_WARDEN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_WARDEN + " action figure."
	icon_state = "warden"
	toysay = "Execute him for breaking in!"

/obj/item/toy/figure/psychologist
	name = JOB_ALT_PSYCHOLOGIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ALT_PSYCHOLOGIST + " action figure."
	icon_state = "psychologist"
	toysay = "The analyzer says you're fine!"

/obj/item/toy/figure/paramedic
	name = JOB_PARAMEDIC + " action figure"
	desc = "A \"Space Life\" brand " + JOB_PARAMEDIC + " action figure."
	icon_state = "paramedic"
	toysay = "WHERE ARE YOU??"

/obj/item/toy/figure/ert
	name = JOB_EMERGENCY_RESPONSE_TEAM + " Commander action figure"
	desc = "A \"Space Life\" brand " + JOB_EMERGENCY_RESPONSE_TEAM + " Commander action figure."
	icon_state = "ert"
	toysay = "We're probably the good guys!"

// Eris
/obj/item/toy/figure/excelsior
	name = "\"Excelsior\" figurine"
	desc = "A curiously unbranded figurine of a Space Soviet, adorned in their iconic armor. There is still a price tag on the back of the base, six-hundred credits, people collect these things? \
	\"Ever Upward!\""
	icon_state = "excelsior"

/obj/item/toy/figure/serbian
	name = "mercenary figurine"
	desc = "A curiously unbranded figurine, the olive drab a popular pick for many independent Serbian mercenary outfits. Rocket launcher not included."
	icon_state = "serbian"

/obj/item/toy/figure/acolyte
	name = "acolyte figurine"
	desc = "Church of NeoTheology \"New Faith Life\" brand figurine of an acolyte, hooded both physically and spiritually from that which would lead them astray."
	icon_state = "acolyte"

/obj/item/toy/figure/carrion
	name = "carrion figurine"
	desc = "A curiously unbranded figurine depicting a grotesque head of flesh, the Human features seem almost underdeveloped, its skull bulging outwards, mouth agape with torn flesh. \
	Whoever made this certainly knew how to thin their paints."
	icon_state = "carrion"

/obj/item/toy/figure/roach
	name = "roach figurine"
	desc = "Upon the base is an erected \"Roachman\", its arms outstretched, with more additional roach hands besides them. This is likely the one thing most universally recognized in popular media. \
	The plaque is covered in hundreds of scratch marks, eliminating any further knowledge of it or its brand."
	icon_state = "roach"

/obj/item/toy/figure/vagabond
	name = "vagabond figurine"
	desc = "An Aster's \"Space Life\" brand figurine showcasing the form of a random deplorable, wearing one of the ship's uniforms, and an orange bandana. \
	Must of been custom-made to commemorate the Eris' doomed voyage."
	icon_state = "vagabond"

/obj/item/toy/figure/rooster
	name = "rooster figurine"
	desc = "\"Space Vice\" brand figurine, there is no further manufacturer information. It's a man wearing a rooster mask, and a varsity jacket with the letter \"B\" emblazoned on the front. \
	\"Do you like hurting other people?\""
	icon_state = "rooster"

/obj/item/toy/figure/barking_dog
	name = "barking dog figurine"
	desc = "A metal soldier with the mask of a hound stands upon the base, the plaque seems smeared with caked grime, but despite this you make out a rare double-quote. \
	\"A dog barks on its master's orders, lest its pack runs astray.\" \"Whatever the task, the grim dog mask would tell you that your life was done.\""
	icon_state = "barking_dog"

/obj/item/toy/figure/red_soldier
	name = "red soldier figurine"
	desc = "A curiously unbranded figurine of a red soldier fighting in the tides of war, their humanity hidden by a gas mask. \"Why do we fight? To win the war, of course.\""
	icon_state = "red_soldier"

/obj/item/toy/figure/metacat
	name = "meta-cat figurine"
	desc = "A curiously unbranded figurine depicting an anthropomorphic cat in a voidsuit, the small plaque claims this to be one of two. \"Always in silent pair, through distance or unlikelihood.\""
	icon_state = "metacat"

/obj/item/toy/figure/shitcurity
	name = "shitcurity officer figurine"
	desc = "An Aster's \"Space Life\" brand figurine of a classic redshirt of \"Nanotrasen's finest\". Their belly distends out into an obvious beer gut, revealing no form of manufacturer bias what-so-ever. \
	\"I joined just to kill people.\""
	icon_state = "shitcurity"

/obj/item/toy/figure/metro_patrolman
	name = "metro patrolman figurine"
	desc = "The plaque seems flaked with rust residue, \"London Metro\" brand it reads. The man wears some kind of enforcer's uniform, with the acronym \"VPP\" on their left shoulder and cap. \
	\"Abandoned for Escalation, the patrolman grumbles.\""
	icon_state = "metro_patrolman"

/obj/item/toy/figure/bounty_hunter
	name = "Space bounty hunter action figure"
	desc = "A \"Space Life\" brand bounty hunter action figure."
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "hunter"
	toysay = "The last greytide is in captivity. The station is at peace."

/obj/item/toy/figure/station
	name = "NLS Southern Cross action figure"
	desc = "A \"Space Life\" brand figure of the NLS Southern Cross, the station you work in."
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "station"
	toysay = "Attention! Alert level elevated to blue."

/*
 * Action figures
 */

/obj/item/toy/figure/ranger
	name = "Space Ranger action figure"
	desc = "A \"Space Life\" brand Space Ranger action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ranger"
	toysay = "To the Fontier and beyond!"

/obj/item/toy/figure/leadbandit
	name = "Bandit Leader action figure"
	desc = "A \"Space Life\" brand Bandit Leader action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bandit_lead"
	toysay = "Give us yer bluespace crystals!"

/obj/item/toy/figure/bandit
	name = "Bandit action figure"
	desc = "A \"Space Life\" brand Bandit action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bandit"
	toysay = "Stick em' up!"

/obj/item/toy/figure/abe
	name = "Action Abe action figure"
	desc = "A \"Space Life\" brand Action Abe action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "action_abe"
	toysay = "Four score and seven decades ago..."

/obj/item/toy/figure/profwho
	name = "Professor Who action figure"
	desc = "A \"Space Life\" brand Professor Who action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "prof_who"
	toysay = "Smells like... bad wolf..."

/obj/item/toy/figure/prisoner
	name = "prisoner action figure"
	desc = "A \"Space Life\" brand prisoner action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "prisoner"
	toysay = "I did not hit her! I did not!"

/obj/item/toy/figure/error
	name = "completely glitched action figure"
	desc = "A \"Space Life\" brand... wait, what the hell is this thing? It seems to be requesting the sweet release of death."
	icon = 'icons/obj/toy.dmi'
	icon_state = "glitched"
	toysay = "AaAAaAAAaAaaaAAA!!!!!"
