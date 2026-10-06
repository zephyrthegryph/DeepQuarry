MATERIAL_MIX(/obj/item/taperecorder, list(MAT_STEEL = 60,MAT_GLASS = 30))
/obj/item/taperecorder
	name = "universal recorder"
	desc = "A device that can record to cassette tapes, and play them. It automatically translates the content in playback."
	icon = 'icons/obj/device.dmi'
	icon_state = "taperecorder_empty"
	item_state = "analyzer"
	w_class = ITEMSIZE_SMALL


	var/emagged = 0.0
	var/playing = 0.0
	var/playsleepseconds = 0.0
	var/obj/item/rectape/mytape = /obj/item/rectape/random
	COOLDOWN_DECLARE(canprint)
	slot_flags = SLOT_BELT
	throwforce = 2
	throw_speed = 4
	throw_range = 20
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/taperecorder)
	owns_one(nameof(mytape), /obj/item/rectape, starts = nameof(mytape))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/obj/item/taperecorder/empty
	mytape = null

OM_FIELD(/obj/item/taperecorder, recording, 0, CHANGE_EXPLICIT)
// The tape fills one second at a time while recording.
DECLARE_REPEAT(/obj/item/taperecorder, 1 SECOND, record_tick, "recording")

/// A recorder hears what is said around it (the listening registry).
/obj/item/taperecorder/capabilities()
	. = ..()
	. += membership(joins = REGISTRY_LISTENING_OBJECTS)

DECLARE_INTERACTIONS(/obj/item/taperecorder, \
	INTERACT_INSERT(/obj/item/rectape, PROC_REF(interaction_item), "Insert tape", REQ_BECAUSE(REQ_FIELD_NOT("mytape"), "there's already a tape inside")), \
	INTERACT_HAND(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_hand_eject)), \
	INTERACT_USE(null, PROC_REF(interaction_self), REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_use_self)), \
)

// Requirements (side-effect free; TRUE, or why not). An incapacitated user passes: the effects decline silently.

/// Taking the tape out from the other hand.
/obj/item/taperecorder/proc/can_hand_eject(mob/user, atom/target, obj/item/held)
	if(user.get_inactive_hand() != src || !mytape)
		return TRUE // not an eject: falls through to the ordinary hand
	return can_eject(user, target, held)

/// Self-use stops playback/recording, or starts recording.
/obj/item/taperecorder/proc/can_use_self(mob/user, atom/target, obj/item/held)
	if(recording || playing)
		return TRUE
	return can_record(user, target, held)

/obj/item/taperecorder/proc/can_eject(mob/user, atom/target, obj/item/held)
	if(user.incapacitated())
		return TRUE
	if(!mytape)
		return "there's no tape in it"
	if(emagged)
		return "the tape seems to be stuck inside"
	return TRUE

/obj/item/taperecorder/proc/can_record(mob/user, atom/target, obj/item/held)
	if(user.incapacitated())
		return TRUE
	if(!mytape)
		return "there's no tape"
	if(mytape.ruined || emagged)
		return "the tape recorder makes a scratchy noise"
	if(recording)
		return "you're already recording"
	if(playing)
		return "you can't record when playing"
	return TRUE

/obj/item/taperecorder/proc/can_wipe(mob/user, atom/target, obj/item/held)
	if(user.incapacitated())
		return TRUE
	if(!mytape)
		return "there's no tape"
	if(emagged || mytape.ruined)
		return "the tape recorder makes a scratchy noise"
	if(recording || playing)
		return "you can't wipe the tape while playing or recording"
	return TRUE

/obj/item/taperecorder/proc/can_playback(mob/user, atom/target, obj/item/held)
	if(user.incapacitated())
		return TRUE
	if(!mytape)
		return "there's no tape"
	if(mytape.ruined)
		return "the tape recorder makes a scratchy noise"
	if(recording)
		return "you can't playback when recording"
	if(playing)
		return "you're already playing"
	return TRUE

/obj/item/taperecorder/proc/can_print(mob/user, atom/target, obj/item/held)
	if(user.incapacitated())
		return TRUE
	if(!mytape)
		return "there's no tape"
	if(mytape.ruined || emagged)
		return "the tape recorder makes a scratchy noise"
	if(!COOLDOWN_FINISHED(src, canprint))
		return "the recorder can't print that fast"
	if(recording || playing)
		return "you can't print the transcript while playing or recording"
	return TRUE

/obj/item/taperecorder/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(!move_into(src, nameof(src.mytape), I, user))
		return TRUE
	to_chat(user, span_notice("You insert [I] into [src]."))
	changed(src)
	return TRUE

/// Heat behaviour rule: fire ruins the tape inside.
/obj/item/taperecorder/proc/rule_ruin_tape(datum/rule/rule)
	mytape?.ruin()


/obj/item/taperecorder/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.get_inactive_hand() == src && mytape)
		taperecorder_eject_effect(user)
		return TRUE
	return FALSE

/// Callers check can_eject() first (the verb's requirement, or can_hand_eject() on the hand).
/obj/item/taperecorder/proc/taperecorder_eject_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated() || !mytape)
		return

	if(playing || recording)
		taperecorder_stop_effect(user)
	to_chat(user, span_notice("You remove [mytape] from [src]."))
	user.put_in_hands(mytape)
	rel_take(src, nameof(mytape))
	changed(src)

/obj/item/taperecorder/hear_talk(mob/M, list/message_pieces, verb)
	var/msg = multilingual_to_message(message_pieces, requires_machine_understands = TRUE, with_capitalization = TRUE)
	// START OF
	var/voice = "Unknown"
	if (M.type == /mob/living/carbon/human)
	{
		var/mob/living/carbon/human/H = M
		voice = H.voice
	}
	else
		voice = M.name
	// END OF
	if(mytape && recording)
		mytape.record_speech("[voice] [verb], \"[msg]\"")

/obj/item/taperecorder/see_emote(mob/M as mob, text, emote_type)
	if(emote_type != 2) //only hearable emotes
		return
	if(mytape && recording)
		mytape.record_speech("[strip_html_properly(text)]")

/obj/item/taperecorder/show_message(msg, type, alt, alt_type)
	var/recordedtext
	if (msg && type == 2) //must be hearable
		recordedtext = msg
	else if (alt && alt_type == 2)
		recordedtext = alt
	else
		return
	if(mytape && recording)
		mytape.record_noise("[strip_html_properly(recordedtext)]")

/obj/item/taperecorder/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(emagged == 0)
		emagged = 1
		set_recording(0)
		to_chat(user, span_warning("PZZTTPFFFT"))
		return OP_OK
	else
		to_chat(user, span_warning("It is already emagged!"))
	return OP_DECLINE

/obj/item/taperecorder/proc/explode()
	var/turf/T = get_turf(loc)
	if(ismob(loc))
		var/mob/M = loc
		to_chat(M, span_danger("\The [src] explodes!"))
	if(T)
		T.hotspot_expose(700,125)
		explosion(T, -1, -1, 0, 4)
	consume(src)
	return

/// Callers check can_record() first (the verb's requirement, or can_use_self() on self-use).
/obj/item/taperecorder/proc/taperecorder_record_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated() || !mytape || recording || playing)
		return
	if(mytape.used_capacity < mytape.max_capacity)
		to_chat(user, span_notice("Recording started."))
		set_recording(1)
		changed(src)

		mytape.record_speech("Recording started.")
		return
	else
		to_chat(user, span_notice("The tape is full."))

/// One second of recording: the tape fills up.
/obj/item/taperecorder/proc/record_tick()
	if(!mytape || mytape.used_capacity >= mytape.max_capacity)
		changed(src)
		return REPEAT_STOP
	mytape.used_capacity++
	if(mytape.used_capacity >= mytape.max_capacity)
		if(ismob(loc))
			var/mob/M = loc
			to_chat(M, span_notice("The tape is full."))
		stop_recording()
		changed(src)
		return REPEAT_STOP

/obj/item/taperecorder/proc/stop_recording()
	//Sanity checks skipped, should not be called unless actually recording
	set_recording(0)
	changed(src)
	mytape.record_speech("Recording stopped.")
	if(ismob(loc))
		var/mob/M = loc
		to_chat(M, span_notice("Recording stopped."))
	else if(isturf(loc)) // If not hidden away in a bag
		play_sfx(src, SFX_MACHINES_CLICK)
		visible_message("\The [src] clicks as it stops recording.","click")

/obj/item/taperecorder/proc/taperecorder_stop_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return
	if(recording)
		stop_recording()
		return
	else if(playing)
		playing = 0
		changed(src)
		to_chat(user, span_notice("Playback stopped."))
		return
	else
		to_chat(user, span_notice("Stop what?"))

/obj/item/taperecorder/proc/wipe_tape_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return
	if(mytape.storedinfo)	LAZYCLEARLIST(mytape.storedinfo)
	if(mytape.timestamp)	mytape.timestamp.Cut()
	mytape.used_capacity = 0
	to_chat(user, span_notice("You wipe the tape."))

/obj/item/taperecorder/proc/playback_memory_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return
	playing = 1
	changed(src)
	to_chat(user, span_notice("Playing started."))
	play_step(1)

/// Plays line `i`, then waits out the recorded gap before the next one.
/obj/item/taperecorder/proc/play_step(i)
	if(!mytape || !playing || i >= mytape.max_capacity || length(mytape.storedinfo) < i)
		play_end()
		return

	var/turf/T = get_turf(src)
	var/playedmessage = LAZYACCESS(mytape.storedinfo, i)
	if (findtextEx(playedmessage,"*",1,2)) //remove marker for action sounds
		playedmessage = copytext(playedmessage,2)
	T.audible_message(span_maroon(span_bold("Tape Recorder") + ": [playedmessage]"), runemessage = playedmessage)

	if(length(mytape.storedinfo) < i+1)
		playsleepseconds = 1
		after(src, 1 SECOND, PROC_REF(play_end_of_tape))
		return
	playsleepseconds = mytape.timestamp[i+1] - mytape.timestamp[i]

	if(playsleepseconds > 14)
		after(src, 1 SECOND, PROC_REF(play_skip_silence), with = list(i, playsleepseconds))
		return
	after(src, 10 * playsleepseconds, PROC_REF(play_step), with = list(i + 1))

/obj/item/taperecorder/proc/play_skip_silence(i, skipped)
	var/turf/T = get_turf(src)
	T.audible_message(span_maroon(span_bold("Tape Recorder") + ": Skipping [skipped] seconds of silence"), runemessage = "tape winding")
	playsleepseconds = 1
	after(src, 1 SECOND, PROC_REF(play_step), with = list(i + 1))

/obj/item/taperecorder/proc/play_end_of_tape()
	var/turf/T = get_turf(src)
	T.audible_message(span_maroon(span_bold("Tape Recorder") + ": End of recording."), runemessage = "click")
	play_end()

/obj/item/taperecorder/proc/play_end()
	playing = 0
	changed(src)

	if(emagged)
		var/turf/T = get_turf(src)
		T.audible_message(span_maroon(span_bold("Tape Recorder") + ": This tape recorder will self-destruct in... Five."), runemessage = "beep beep")
		after(src, 1 SECOND, PROC_REF(self_destruct_count), with = list(4))

/obj/item/taperecorder/proc/self_destruct_count(n)
	if(n <= 0)
		explode()
		return
	var/turf/T = get_turf(src)
	var/static/list/words = list("One", "Two", "Three", "Four")
	T.audible_message(span_maroon(span_bold("Tape Recorder") + ": [words[n]]."))
	after(src, 1 SECOND, PROC_REF(self_destruct_count), with = list(n - 1))

/obj/item/taperecorder/proc/print_transcript_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return

	to_chat(user, span_notice("Transcript printed."))
	var/obj/item/paper/P = new /obj/item/paper(get_turf(src))
	var/t1 = span_bold("Transcript:") + "<BR><BR>"
	for(var/i=1,length(mytape.storedinfo) >= i,i++)
		var/printedmessage = LAZYACCESS(mytape.storedinfo, i)
		if (findtextEx(printedmessage,"*",1,2)) //replace action sounds
			printedmessage = "\[[time2text(mytape.timestamp[i]*10,"mm:ss")]\] (Unrecognized sound)"
		t1 += "[printedmessage]<BR>"
	P.info = t1
	P.name = "Transcript"
	COOLDOWN_START(src, canprint, 30 SECONDS)


/obj/item/taperecorder/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(recording || playing)
		taperecorder_stop_effect(user)
	else
		taperecorder_record_effect(user)

/obj/item/taperecorder/proc/appearance_tape_state()
	if(!mytape)
		return "empty"
	if(recording)
		return "recording"
	if(playing)
		return "playing"
	return "idle"

/// The look (the draw sweep: from its template).
/obj/item/taperecorder/draw(datum/look/look)
	..()
	look.state("taperecorder_[appearance_tape_state()]")

MATERIAL_MIX(/obj/item/rectape, list(MAT_STEEL=20, MAT_GLASS=5))
/obj/item/rectape
	name = "tape"
	desc = "A magnetic tape that can hold up to ten minutes of content."
	icon = 'icons/obj/device.dmi'
	icon_state = "tape_white"
	item_state = "analyzer"
	w_class = ITEMSIZE_TINY
	force = 1
	throwforce = 0
	var/max_capacity = 1800
	var/used_capacity = 0
	var/list/storedinfo
	var/list/timestamp = new/list() // ALLOW(instance_list): d: index-parallel with storedinfo
	var/ruined = 0

/// The look (the draw sweep: from its layers).
/obj/item/rectape/draw(datum/look/look)
	..()
	if(ruined == 1)
		look.overlay("ribbonoverlay")


CAPABILITIES(/obj/item/rectape)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item/pen), label("Label"), then(PROC_REF(interaction_item)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))

/obj/item/rectape/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!ruined)
		to_chat(user, span_notice("You pull out all the tape!"))
		ruin()

/obj/item/rectape/proc/ruin()
	ruined = 1
	changed(src)

/obj/item/rectape/proc/fix()
	ruined = 0
	changed(src)

/obj/item/rectape/proc/record_speech(text)
	timestamp += used_capacity
	LAZYADD(storedinfo, "\[[time2text(used_capacity*10,"mm:ss")]\] [text]")

//shows up on the printed transcript as (Unrecognized sound)
/obj/item/rectape/proc/record_noise(text)
	timestamp += used_capacity
	LAZYADD(storedinfo, "*\[[time2text(used_capacity*10,"mm:ss")]\] [text]")


/obj/item/rectape/proc/label_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_name = sanitizeSafe(A.answer.value)
	if(new_name)
		name = "tape - '[new_name]'"
		to_chat(user, span_notice("You label the tape '[new_name]'."))
	else
		name = "tape"
		to_chat(user, span_notice("You scratch off the label."))

/obj/item/rectape/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	if(loc == user && !user.incapacitated())
		open_request(src, /datum/prompt/text, PROC_REF(label_entered), answerer = user, title = "Tape labeling", question = "What would you like to label the tape?", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/item/rectape/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!ruined)
		return OP_OK
	use_tool(user, tool, src, delay = 12 SECONDS, quality = TOOL_SCREWDRIVER, volume = 50, start_self = "You start winding the tape back in...", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	return OP_OK

/obj/item/rectape/proc/screwdriver_act_tool_done(mob/user)
	if(!(ruined))
		return
	to_chat(user, span_notice("You wound the tape back in."))
	fix()

CAPABILITIES(/obj/item/rectape/random)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/rectape/random/proc/roll_icon_state(datum/roller/R)
	return "tape_[R.choose(list("white", "blue", "red", "yellow", "purple"))]"

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/taperecorder, \
	INTERACT_VERB("Eject Tape", PROC_REF(taperecorder_eject_effect), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_eject)), \
	INTERACT_VERB("Start Recording", PROC_REF(taperecorder_record_effect), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_record)), \
	INTERACT_VERB("Stop", PROC_REF(taperecorder_stop_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Wipe Tape", PROC_REF(wipe_tape_effect), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_wipe)), \
	INTERACT_VERB("Playback Tape", PROC_REF(playback_memory_effect), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_playback)), \
	INTERACT_VERB("Print Transcript", PROC_REF(print_transcript_effect), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/taperecorder/proc/can_print)), \
)
