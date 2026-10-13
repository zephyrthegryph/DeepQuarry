/obj/item/instrument/piano_synth
	name = "synthesizer"
	desc = "An advanced electronic synthesizer that can be used as various instruments."
	icon_state = "synth"
	allowed_instrument_ids = "piano"

CAPABILITIES(/obj/item/instrument/piano_synth)
	after_init(0, then(PROC_REF(allow_synth_instruments)))

/obj/item/instrument/piano_synth/proc/allow_synth_instruments(datum/act/timer/A)
	song.allowed_instrument_ids = SSinstruments.ready().synthesizer_instrument_ids

/obj/item/instrument/piano_synth/headphones
	name = "headphones"
	desc = "Unce unce unce unce. Boop!"
	icon_state = "headphones"
	w_class = ITEMSIZE_SMALL
	instrument_range = 1

CAPABILITIES(/obj/item/instrument/piano_synth/headphones)
	configure(item_worn(slots = SLOT_EARS | SLOT_HEAD))
	configure(item_combat(force = 0))
	on_notice(/datum/notice/instrument_start, then(PROC_REF(start_playing)))
	on_notice(/datum/notice/instrument_end, then(PROC_REF(stop_playing)))

/**
 * Called by a component signal when our song starts playing.
 */
/obj/item/instrument/piano_synth/headphones/proc/start_playing(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)

	icon_state = "[initial(icon_state)]_on"
	changed(src) // the wearer watches its headphones

/**
 * Called by a component signal when our song stops playing.
 */
/obj/item/instrument/piano_synth/headphones/proc/stop_playing(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)

	icon_state = "[initial(icon_state)]"
	changed(src) // the wearer watches its headphones


/obj/item/instrument/piano_synth/headphones/spacepods
	name = "\improper Nanotrasen space pods"
	desc = "Flex your money, AND ignore what everyone else says, all at once!"
	icon_state = "spacepods"
	//strip_delay = 100 //air pods don't fall out
	instrument_range = 0 //you're paying for quality here

CAPABILITIES(/obj/item/instrument/piano_synth/headphones/spacepods)
	configure(item_worn(slots = SLOT_EARS))
