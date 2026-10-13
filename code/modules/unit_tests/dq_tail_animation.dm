// Animated tails (code/modules/mob/living/carbon/human/human_look.dm): a sprite whose icon state has several
// frames is drawn with them (the picture moves in game), a still one is not. The draw once rendered every tail as the still frame.

/// The frames `state` of `file` has, from the icon's source (the .dmi.toml beside its png): 1 for a still state. A DMI does not tell
/// DM how many frames a state holds, so the source is the oracle.
/datum/unit_test/proc/dq_ta_source_frames(file, state)
	var/path = "[file]"
	var/at = findtext(path, "icons/")
	if(!at)
		return 0
	path = copytext(path, at)
	if(copytext(path, 1, 11) == "icons/gen/")
		path = "icons/[copytext(path, 11)]"
	var/list/lines = splittext(file2text("[path].toml") || "", "\n")
	var/seeking = "name = \"[state]\""
	var/found = FALSE
	for(var/line in lines)
		line = trim(line)
		if(!found)
			found = (line == seeking)
			continue
		if(copytext(line, 1, 10) == "frames = ")
			return text2num(copytext(line, 10))
		if(copytext(line, 1, 8) == "\[\[state")
			break
	return found ? 1 : 0

/// How many different pictures the first `count` frames of `state` of `file` hold.
/datum/unit_test/proc/dq_ta_distinct(file, state, count)
	var/list/seen = list()
	for(var/frame in 1 to count)
		var/icon/I = icon(file, state, SOUTH, frame)
		var/list/pixels = list("[I.Width()]x[I.Height()]")
		for(var/x in 1 to I.Width())
			for(var/y in 1 to I.Height())
				pixels += "[I.GetPixel(x, y)]"
		seen[md5(jointext(pixels, ","))] = TRUE
	return length(seen)

/// Asserts the drawn `layer` plays `state` of `file` (a multi-frame state) with every frame the source has. `drawn_state` is the state
/// the image names: a species tail names its state in the whole sheet, a coloured custom tail is a composed icon of that one state ("").
/datum/unit_test/proc/dq_ta_assert_animated(image/drawn, file, state, label, drawn_state = state)
	if(!drawn)
		return Fail("[label]: nothing was drawn", __FILE__, __LINE__)
	if((drawn.icon_state || "") != drawn_state)
		return Fail("[label]: drew state '[drawn.icon_state]', expected '[drawn_state]'", __FILE__, __LINE__)
	var/frames = dq_ta_source_frames(file, state)
	if(frames <= 1)
		return Fail("[label]: '[state]' has [frames] frames in its source, not an animated state", __FILE__, __LINE__)
	var/source = dq_ta_distinct(file, state, frames)
	var/got = dq_ta_distinct(drawn.icon, drawn_state, frames)
	if(got != source)
		return Fail("[label]: the drawn '[state]' keeps [got] of the source's [source] distinct frames", __FILE__, __LINE__)

/// Asserts the drawn `layer` is the still `state` (one frame in its source).
/datum/unit_test/proc/dq_ta_assert_still(image/drawn, file, state, label, drawn_state = state)
	if(!drawn)
		return Fail("[label]: nothing was drawn", __FILE__, __LINE__)
	if((drawn.icon_state || "") != drawn_state)
		return Fail("[label]: drew state '[drawn.icon_state]', expected '[drawn_state]'", __FILE__, __LINE__)
	var/frames = dq_ta_source_frames(file, state)
	if(frames != 1)
		return Fail("[label]: '[state]' has [frames] frames in its source, not a still state", __FILE__, __LINE__)

/datum/unit_test/dq_tail_animation_style

/datum/unit_test/dq_tail_animation_style/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_HUMAN)
	H.set_dir(SOUTH)
	var/datum/sprite_accessory/tail/style = GLOB.tail_styles_list[/datum/sprite_accessory/tail/rabbit]
	dq_hd_set(H, "tail_style", style)
	refresh_flush()
	var/image/resting = H.tail_look()[2]
	dq_ta_assert_still(resting, style.icon, style.icon_state, "rabbit tail at rest", "")
	H.toggle_tail(TRUE)
	refresh_flush()
	var/image/wagging = H.tail_look()[2]
	TEST_ASSERT(wagging != resting, "wagging draws another tail")
	dq_ta_assert_animated(wagging, style.icon, style.ani_state, "rabbit tail wagging", "")
	H.toggle_tail(FALSE)
	refresh_flush()
	TEST_ASSERT(H.tail_look()[2] == resting, "a tail that stopped wagging is the resting tail again")

/datum/unit_test/dq_tail_animation_species

/datum/unit_test/dq_tail_animation_species/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_UNATHI)
	H.set_dir(SOUTH)
	refresh_flush()
	var/file = H.species.get_tail_animation(H)
	var/tail = H.species.get_tail(H)
	var/idle = "[tail]_idle[H.tail_idle_variant()]"
	dq_ta_assert_animated(H.tail_look()[2], file, idle, "unathi tail on its own")
	H.animate_tail_stop()
	refresh_flush()
	dq_ta_assert_still(H.tail_look()[2], file, "[tail]_static", "unathi tail stopped")
	H.animate_tail_start()
	refresh_flush()
	var/image/slow = H.tail_look()[2]
	TEST_ASSERT(findtext(slow.icon_state, "[tail]_slow"), "a wagging species tail plays its slow loop, got [slow.icon_state]")
	dq_ta_assert_animated(slow, file, slow.icon_state, "unathi tail wagging")
	H.death()
	refresh_flush()
	dq_ta_assert_still(H.tail_look()[2], file, "[tail]_static", "dead unathi tail")
