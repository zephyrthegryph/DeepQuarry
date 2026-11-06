////////////////////////////
//		Basic Cultist
////////////////////////////

/datum/category_item/catalogue/fauna/cultist
	name = "Cultists"
	desc = "The Galactic Awakening unlocked the psionic potential of many \
	from rim to rim. The first to notice this font of power were those who \
	were already the faithful devotees of esoteric religions. The rise of Blood \
	Cultists in service to the Geometer quickly became an intergalactic incident. \
	Although NanoTrasen and other entities have risen to combat these foes, a \
	vast array of Hermetic Orders now command frightening power."
	value = CATALOGUER_REWARD_TRIVIAL
	unlocked_by_any = list(/datum/category_item/catalogue/fauna/cultist)

// Obtained by scanning all X.
/datum/category_item/catalogue/fauna/all_cultists
	name = "Collection - Cultists"
	desc = "You have scanned a large array of different types of Cultist, \
	and therefore you have been granted a large sum of points, through this \
	entry."
	value = CATALOGUER_REWARD_SUPERHARD
	unlocked_by_all = list(
		/datum/category_item/catalogue/fauna/cultist/human,
		/datum/category_item/catalogue/fauna/cultist/tesh,
		/datum/category_item/catalogue/fauna/cultist/lizard,
		/datum/category_item/catalogue/fauna/cultist/caster,
		/datum/category_item/catalogue/fauna/cultist/initiate,
		/datum/category_item/catalogue/fauna/cultist/castertesh,
		/datum/category_item/catalogue/fauna/cultist/elite,
		/datum/category_item/catalogue/fauna/cultist/magus,
		/datum/category_item/catalogue/fauna/cultist/hunter
		)

/datum/category_item/catalogue/fauna/cultist/human
	name = "Cultists - Human"
	desc = "The first wave of zealots faced by many on the Frontier were \
	human. For a short while it was assumed that humans were somehow more \
	susecptible to Paracausal influence. Although this belief has long since \
	been disproven, the large Human population on the Frontier has ensured \
	that the species is overrepresented amongst the ranks of Cult aggressors."
	value = CATALOGUER_REWARD_EASY

////////////////////////////
//		Teshari Cultist
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/tesh
	name = "Cultists - Teshari"
	desc = "Teshari cultists project a curiously sinister air. Perhaps \
	due to their diminutive stature, these creatures are sometimes not \
	regarded as genuine threats when compared to their more imposing companions. \
	To ignore a Teshari fanatic is a fool's errand. Fast, hard to hit, and \
	tenacious, Teshari form the vanguard of many fanatical assaults."
	value = CATALOGUER_REWARD_EASY

////////////////////////////
//		Lizard Cultist
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/lizard
	name = "Cultists - Lizard"
	desc = "The Unathi Kingdom of Moghes has stamped down heavily on the \
	heretical activities of religious sects not approved by the State. Due \
	to this, many Unathi seeking religious freedom have fled to the Frontier. \
	Unfortunately, some of those who took this path have fallen prey to true \
	evil. Possessing the zeal of the oppressed, Unathi cultists are deadly \
	fanatics, eager to shred their enemies apart in close quarters, regardless \
	of what damage they themselves incur."
	value = CATALOGUER_REWARD_EASY

////////////////////////////
//		Blood Mage
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/caster
	name = "Cultists - Blood Mage"
	desc = "For those servants of a Cult who possess enough latent ability, \
	the channelling of Paracausal power is a very real skill to be honed and \
	exploited. Blood Mages learn to fuel paranatural assaults using their own \
	life force. Necessarily short lived, these cultists believe that bleeding \
	themselves dry is a statement of faith. Able to fire beams of dark energy \
	at their foes, these fanatics should be primarily engaged by PMD response \
	teams."
	value = CATALOGUER_REWARD_MEDIUM

////////////////////////////
//		Blood Initiate
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/initiate
	name = "Cultists - Initiate"
	desc = "After the Awakening, some who thirst for power or belonging \
	saw an opportunity to have their darker desires fulfilled. These converts \
	are accepted into the ranks of Cults across the galaxy regardless of whether \
	they possess psionic potential are not. Those that do ascend through the \
	ranks, whereas those that don't may still serve as cannon fodder and sacrifices."
	value = CATALOGUER_REWARD_EASY

////////////////////////////
//		Teshari Mage
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/castertesh
	name = "Cultists - Teshari Mage"
	desc = "Similar in skill to their human counter parts, Teshari mages \
	are regarded as more ferocious combatants. Able to cast paracausal beams \
	at a rapid pace with ease, Teshari Mages are a priority target of any \
	response team, and any who discount their threat are quickly shown the \
	error of their ways."
	value = CATALOGUER_REWARD_MEDIUM

////////////////////////////
//		Elite Cultist
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/elite
	name = "Cultists - Elite"
	desc = "Cultists who preceded the Great Awakening are often regarded \
	with immense respect. Truly devoted, these adherents learned many rites \
	and rituals before they ever bore true power. As such, Elite Cultists \
	possess a working knowledge of many arcane arts, and are trusted with \
	the rare Paracausal artifacts possessed by their orders. From mirror \
	shields to arcane sets of armor, Elites command fear, and inspire the \
	fanaticism of their subordinates."
	value = CATALOGUER_REWARD_MEDIUM

////////////////////////////
//		Cult Magus
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/magus
	name = "Cultists - Blood Magus"
	desc = "The Blood Magus commands their local chapter with total authority. \
	These religious leaders possess an unparalleled knowledge of their cult's \
	secrets, rituals, and tenets. To attain the rank of Magus, a Cultist must \
	possess great psionic power. Their ability to channel Paracausal energy is \
	unparalled amongst their peers. Wielding dark gifts granted by darker gods, \
	the Magus is a priority target in any engagement."
	value = CATALOGUER_REWARD_MEDIUM

////////////////////////////
//		Blood Hunter
////////////////////////////

/datum/category_item/catalogue/fauna/cultist/hunter
	name = "Cultists - Blood Hunter"
	desc = "Whether the Blood Hunter may be considered human still remains \
	a hotly contested topic. There is further debate regarding whether every \
	instance of the Blood Hunter is the same entity, or whether this condition \
	is some manner of Paranatural affliction or status. It is speculated that \
	the Blood Hunter was once a mortal devotee of the Geometer, and has somehow \
	ascended to the rank of Paracausal Being. The Blood Hunter is a killer without \
	peer. If encountered, retreat and contact the PMD immediately."
	value = CATALOGUER_REWARD_HARD

/obj/item/shield_projector/rectangle/automatic/magus
	name = "cult shield stone"
	desc = "A stone wielded by only the most powerful of cult leaders. It projects a shield around the user."
	icon = 'icons/obj/device.dmi'
	icon_state = "implant_melted"
	max_integrity = 100
	shield_regen_delay = 10 SECONDS
	shield_regen_amount = 10
	size_x = 1
	size_y = 1
	color = "#f50202"
	high_color = "#ff0404"
	low_color = "#690000"
