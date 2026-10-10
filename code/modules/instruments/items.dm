//copy pasta of the space piano, don't hurt me -Pete
/obj/item/instrument
	name = "generic instrument"
	force = 10
	icon = 'icons/obj/musician.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_instruments.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_instruments.dmi',
	)
	abstract_type = /obj/item/instrument
	/// Our song datum.
	var/datum/song/handheld/song
	/// Our allowed list of instrument ids. This is nulled on initialize.
	var/list/allowed_instrument_ids
	/// How far away our song datum can be heard.
	var/instrument_range = 15

CAPABILITIES(/obj/item/instrument)
	owns_one(nameof(song), /datum/song/handheld, starts = PROC_REF(make_song))
	op("controls", in_hand(), label("Open instrument controls"), then(PROC_REF(instrument_controls_opened)))

/obj/item/instrument/Initialize(mapload)
	. = ..()
	allowed_instrument_ids = null //We don't need this clogging memory after its used.

/// The starting song (owns_one(starts =)).
/obj/item/instrument/proc/make_song(current)
	return new /datum/song/handheld(src, allowed_instrument_ids, instrument_range)


/obj/item/instrument/proc/can_play(atom/music_player)
	if(!ismob(music_player))
		return FALSE
	var/mob/user = music_player
	if(user.incapacitated())
		return FALSE
	if(!Adjacent(user))
		return FALSE
	return TRUE

/obj/item/instrument/proc/instrument_controls_opened(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.IsAdvancedToolUser())
		return OP_OK

	tgui_interact(user)
	return OP_OK

/obj/item/instrument/ui_redirect(mob/user)
	return song

/obj/item/instrument/violin
	name = "space violin"
	desc = "A wooden musical instrument with four strings and a bow. \"The devil went down to space, he was looking for an assistant to grief.\""
	icon_state = "violin"
	hitsound = SFX_SWING_HIT
	allowed_instrument_ids = "violin"

/obj/item/instrument/violin/golden
	name = "golden violin"
	desc = "A golden musical instrument with four strings and a bow. \"The devil went down to space, he was looking for an assistant to grief.\""
	icon_state = "golden_violin"

/obj/item/instrument/xylophone
	name = "xylophone"
	desc = "A percussion instrument consisting of a series of wooden bars graduated in length."
	icon_state = "xylophone"
	allowed_instrument_ids = "xylophone"

/obj/item/instrument/banjo
	name = "banjo"
	desc = "A 'Mura' brand banjo. It's pretty much just a drum with a neck and strings."
	icon_state = "banjo"
	attack_verb = list("scruggs-styled", "hum-diggitied", "shin-dug", "clawhammered")
	hitsound = SFX_WEAPONS_BANJOSLAP
	allowed_instrument_ids = "banjo"

/obj/item/instrument/guitar
	name = "guitar"
	desc = "It's made of wood and has bronze strings."
	icon_state = "guitar"
	attack_verb = list("played metal on", "serenaded", "crashed", "smashed")
	hitsound = SFX_WEAPONS_STRINGSMASH
	allowed_instrument_ids = list("guitar","csteelgt","cnylongt", "ccleangt", "cmutedgt")

/obj/item/instrument/eguitar
	name = "electric guitar"
	desc = "Makes all your shredding needs possible."
	icon_state = "eguitar"
	force = 12
	attack_verb = list("played metal on", "shreded", "crashed", "smashed")
	hitsound = SFX_WEAPONS_STRINGSMASH
	allowed_instrument_ids = "eguitar"

/obj/item/instrument/glockenspiel
	name = "glockenspiel"
	desc = "Smooth metal bars perfect for any marching band."
	icon_state = "glockenspiel"
	allowed_instrument_ids = list("glockenspiel","crvibr", "sgmmbox", "r3celeste")

/obj/item/instrument/accordion
	name = "accordion"
	desc = "Pun-Pun not included."
	icon_state = "accordion"
	allowed_instrument_ids = list("crack", "crtango", "accordion")

/obj/item/instrument/trumpet
	name = "trumpet"
	desc = "To announce the arrival of the king!"
	icon_state = "trumpet"
	allowed_instrument_ids = "crtrumpet"

/obj/item/instrument/trumpet/spectral
	name = "spectral trumpet"
	desc = "Things are about to get spooky!"
	icon_state = "spectral_trumpet"
	force = 0
	attack_verb = list("played", "jazzed", "trumpeted", "mourned", "dooted", "spooked")

/obj/item/instrument/trumpet/spectral/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	play_sfx(src, SFX_RUNTIME_INSTRUMENTS_TROMBONE_EN4)
	..()

/obj/item/instrument/saxophone
	name = "saxophone"
	desc = "This soothing sound will be sure to leave your audience in tears."
	icon_state = "saxophone"
	allowed_instrument_ids = "saxophone"

/obj/item/instrument/saxophone/spectral
	name = "spectral saxophone"
	desc = "This spooky sound will be sure to leave mortals in bones."
	icon_state = "saxophone"
	force = 0
	attack_verb = list("played", "jazzed", "saxed", "mourned", "dooted", "spooked")

/obj/item/instrument/saxophone/spectral/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	play_sfx(src, SFX_RUNTIME_INSTRUMENTS_SAXOPHONE_EN4)
	..()

/obj/item/instrument/trombone
	name = "trombone"
	desc = "How can any pool table ever hope to compete?"
	icon_state = "trombone"
	allowed_instrument_ids = list("crtrombone", "crbrass", "trombone")

/obj/item/instrument/trombone/spectral
	name = "spectral trombone"
	desc = "A skeleton's favorite instrument. Apply directly on the mortals."
	icon_state = "trombone"
	force = 0
	attack_verb = list("played", "jazzed", "tromboneed", "mourned", "dooted", "spooked")

/obj/item/instrument/trombone/spectral/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	play_sfx(src, SFX_RUNTIME_INSTRUMENTS_TROMBONE_CN4)
	..()

/obj/item/instrument/recorder
	name = "recorder"
	desc = "Just like in school, playing ability and all."
	force = 5
	icon_state = "recorder"
	allowed_instrument_ids = "recorder"

/obj/item/instrument/harmonica
	name = "harmonica"
	desc = "For when you get a bad case of the space blues."
	icon_state = "harmonica"
	allowed_instrument_ids = list("crharmony", "harmonica")
	slot_flags = SLOT_MASK
	force = 5
	w_class = ITEMSIZE_SMALL
/obj/item/instrument/bikehorn
	name = "gilded bike horn"
	desc = "An exquisitely decorated bike horn, capable of honking in a variety of notes."
	icon_state = "bike_horn"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_horns.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_horns.dmi',
	)
	allowed_instrument_ids = list("bikehorn", "honk")
	attack_verb = list("beautifully honked")
	w_class = ITEMSIZE_SMALL
	force = 0
	throw_speed = 3
	throw_range = 15
	hitsound = SFX_ITEMS_BIKEHORN

/obj/item/instrument/musicalmoth
	name = "musical moth"
	desc = "Despite its popularity, this controversial musical toy was eventually banned due to its unethically sampled sounds of moths screaming in agony."
	icon_state = "mothsician"
	allowed_instrument_ids = "mothscream"
	attack_verb = list("fluttered", "flaped")
	w_class = ITEMSIZE_SMALL
	force = 0
	hitsound = SFX_VOICE_MOTH_SCREAM_MOTH

//////////////Fluff items

/obj/item/instrument/recorder/fluff_tief
	name = "flute"
	desc = "A blue wooden flute."
	icon_state = "flute_tief"
	allowed_instrument_ids = "recorder"

/obj/item/instrument/keytar
	name = "portable keyboard"
	desc = "A keyboard, for those interested in the piano on the go! "
	icon = 'icons/obj/musician_yw.dmi'
	icon_state = "keyboard"
	item_state = "keyboard"
	attack_verb = list("smashed")
	allowed_instrument_ids = "piano"

/obj/item/instrument/xylophone
	name = "xylophone"
	desc = "A percussion instrument consisting of a series of wooden bars graduated in length."
	icon = 'icons/obj/musician_yw.dmi'
	icon_state = "xylophone"
	attack_verb = list("smashed")
	allowed_instrument_ids = "xylophone"
