/obj/item/borg/upgrade/basic/language
	name = "language module"
	desc = "Used to let cyborgs other than clerical or service speak a variety of languages."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"

/obj/item/borg/upgrade/basic/language/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		to_chat(R, span_warning("All possible languages already uploaded!"))
		to_chat(user, span_warning("The language database is up to date!"))
		return FALSE

	R.add_language(LANGUAGE_SOL_COMMON, 	1)
	R.add_language(LANGUAGE_TRADEBAND, 		1)
	R.add_language(LANGUAGE_UNATHI,			1)
	R.add_language(LANGUAGE_SIIK, 			1)
	R.add_language(LANGUAGE_AKHANI, 		1)
	R.add_language(LANGUAGE_SKRELLIAN, 		1)
	R.add_language(LANGUAGE_GUTTER, 		1)
	R.add_language(LANGUAGE_SCHECHI, 		1)
	R.add_language(LANGUAGE_ROOTLOCAL, 		1)
	R.add_language(LANGUAGE_TERMINUS, 		1)
	R.add_language(LANGUAGE_ZADDAT, 		1)
	R.add_language(LANGUAGE_BIRDSONG,		1)
	R.add_language(LANGUAGE_SAGARU,			1)
	R.add_language(LANGUAGE_CANILUNZT,		1)
	R.add_language(LANGUAGE_ECUREUILIAN,	1)
	R.add_language(LANGUAGE_DAEMON,			1)
	R.add_language(LANGUAGE_ENOCHIAN,		1)
	R.add_language(LANGUAGE_DRUDAKAR, 		1)
	R.add_language(LANGUAGE_TAVAN,			1)
	R.add_language(LANGUAGE_SIGN, 			1)
	R.add_language(LANGUAGE_VOX, 			1)
	R.add_language(LANGUAGE_ALAI, 			1)
	R.add_language(LANGUAGE_PROMETHEAN,		1)
	R.add_language(LANGUAGE_GIBBERISH, 		1)
	R.add_language(LANGUAGE_VESPINAE, 		1)
	R.add_language(LANGUAGE_SPACER, 		1)
	R.add_language(LANGUAGE_MOUSE, 			1)
	R.add_language(LANGUAGE_ANIMAL, 		1)
	R.add_language(LANGUAGE_TEPPI, 			1)
	R.add_language(LANGUAGE_SLAVIC, 		1)
	R.add_language(LANGUAGE_MARISH, 		1)
	/* Admin Stuff
	R.add_language(LANGUAGE_CULT, 			1)
	R.add_language(LANGUAGE_SWARMBOT, 		1)
	R.add_language(LANGUAGE_MINBUS, 		1)
	R.add_language(LANGUAGE_EVENT1, 		1)
	*/
	/* We don't want telepathy, but want to mark it that it's not been oversighted
	R.add_language(LANGUAGE_CHANGELING,		1)
	R.add_language(LANGUAGE_ROOTGLOBAL,		1)
	R.add_language(LANGUAGE_SHADEKIN, 		1)
	*/

	to_chat(R, span_notice("Language database updated!"))
	return TRUE
