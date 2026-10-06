/datum/song/ui_title(mob/user)
	return parent().name

/datum/song/tgui_host(mob/user)
	return parent()

/datum/song/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["id"] = id
	data["note_shift"] = note_shift
	data["sustain_mode"] = sustain_mode
	data["volume"] = volume
	data["volume_dropoff_threshold"] = sustain_dropoff_volume
	data["sustain_indefinitely"] = full_sustain_held_note
	data["playing"] = playing
	data["repeat"] = repeat
	var/list/merged_1 = ui_data_datum_song(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/song's window data.
/datum/song/proc/ui_data_datum_song(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["using_instrument"] = using_instrument()?.name || "No instrument loaded!"
	data["octaves"] = round(note_shift / 12, 0.01)
	switch(sustain_mode)
		if(SUSTAIN_LINEAR)
			data["sustain_mode_button"] = "Linear Sustain Duration (in seconds)"
			data["sustain_mode_duration"] = sustain_linear_duration / 10
			data["sustain_mode_min"] = INSTRUMENT_MIN_TOTAL_SUSTAIN
			data["sustain_mode_max"] = INSTRUMENT_MAX_TOTAL_SUSTAIN
		if(SUSTAIN_EXPONENTIAL)
			data["sustain_mode_button"] = "Exponential Falloff Factor (% per decisecond)"
			data["sustain_mode_duration"] = sustain_exponential_dropoff
			data["sustain_mode_min"] = INSTRUMENT_EXP_FALLOFF_MIN
			data["sustain_mode_max"] = INSTRUMENT_EXP_FALLOFF_MAX
	data["instrument_ready"] = using_instrument()?.ready()
	data["bpm"] = round(60 SECONDS / tempo)
	data["lines"] = list()
	var/linecount
	for(var/line in lines)
		linecount++
		data["lines"] += list(list(
			"line_count" = linecount,
			"line_text" = line,
		))
	return data

/datum/song/tgui_static_data(mob/user)
	var/list/data = ..()
	data["can_switch_instrument"] = (length(allowed_instrument_ids) > 1)
	data["possible_instruments"] = list()
	for(var/instrument in allowed_instrument_ids)
		UNTYPED_LIST_ADD(data["possible_instruments"], list("name" = SSinstruments.ready().instrument_data[instrument], "id" = instrument))
	data["sustain_modes"] = SSinstruments.ready().note_sustain_modes
	data["max_repeats"] = max_repeats
	data["min_volume"] = min_volume
	data["max_volume"] = max_volume
	data["note_shift_min"] = note_shift_min
	data["note_shift_max"] = note_shift_max
	data["max_line_chars"] = MUSIC_MAXLINECHARS
	data["max_lines"] = MUSIC_MAXLINES
	return data

/datum/song/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!istype(user))
		return FALSE
	return TRUE

/datum/song/proc/ui_act_play_music(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!playing)
		start_playing(user)
	else
		stop_playing()
	return TRUE

/datum/song/proc/ui_act_set_instrument_id(datum/act/op/A, id_arg)
	if(!ui_gate(A))
		return FALSE
	var/new_id = reject_bad_name(LOWER_TEXT(id_arg), max_length = 20, allow_numbers = TRUE, cap_after_symbols = FALSE)
	if(new_id)
		id = new_id
	return TRUE

/datum/song/proc/ui_act_change_instrument(datum/act/op/A, new_instrument_arg)
	if(!ui_gate(A))
		return FALSE
	var/new_instrument = new_instrument_arg
	//only one instrument, so no need to bother changing it.
	if(!length(allowed_instrument_ids))
		return FALSE
	if(!(new_instrument in allowed_instrument_ids))
		return FALSE
	set_instrument(new_instrument)
	return TRUE

/datum/song/proc/ui_act_tempo(datum/act/op/A, tempo_change)
	if(!ui_gate(A))
		return FALSE
	var/move_direction = tempo_change
	var/tempo_diff
	if(move_direction == "increase_speed")
		tempo_diff = world.tick_lag
	else
		tempo_diff = -world.tick_lag
	tempo = sanitize_tempo(tempo + tempo_diff)
	return TRUE

//SONG MAKING

/datum/song/proc/song_title(datum/act/op/A)
	return name

/datum/song/proc/instrument_title(datum/act/op/A)
	return parent()?.name

/// An import as long as the editor holds asks whether to keep editing it (a "Yes" to one over the limit ends the import: press it again to paste anew).
/datum/song/proc/import_too_long(datum/act/op/A)
	return length_char(A.step_value("song")) >= MUSIC_MAXLINES * MUSIC_MAXLINECHARS

/datum/song/proc/ui_act_import_song(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/song_text = A.step_value("song")
	if(A.step_value("too_long") == "Yes" && length_char(song_text) > MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
		return TRUE // keep editing: the import ends unparsed
	if(!in_range(parent(), A.actor))
		return FALSE
	ParseSong(A.actor, song_text)
	return TRUE

/datum/prompt/text/song_import
	question = "Please paste the entire song, formatted:"
	max_len = MUSIC_MAXLINES * MUSIC_MAXLINECHARS
	multiline = TRUE
	timeout = 0

/datum/prompt/text/song_import/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/song_import_continue
	question = "Your message is too long! Would you like to continue editing it?"
	title = "Warning"
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0

/datum/song/proc/ui_act_start_new_song(datum/act/op/A)
	name = ""
	lines = new()
	tempo = sanitize_tempo(5) // default 120 BPM
	return OP_OK

/datum/song/proc/ui_act_add_new_line(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/value = A.step_value("line")
	if(!value || lines.len > MUSIC_MAXLINES || !in_range(parent(), A.actor))
		return FALSE
	append_answered_line(value)
	return TRUE

/datum/song/proc/ui_act_delete_line(datum/act/op/A, line_deleted)
	if(!ui_gate(A))
		return FALSE
	var/line_to_delete = line_deleted
	if(line_to_delete > lines.len || line_to_delete < 1)
		return FALSE
	lines.Cut(line_to_delete, line_to_delete + 1)
	return TRUE

/// The line a modify button names is one of the song's.
/datum/song/proc/line_exists(datum/act/op/A)
	var/line = A.args["line_editing"]
	return isnum(line) && line >= 1 && line <= length(lines) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/datum/song/proc/edited_line(datum/act/op/A)
	return lines[A.args["line_editing"]]

/datum/song/proc/ui_act_modify_line(datum/act/op/A, line_editing)
	if(!ui_gate(A))
		return FALSE
	if(line_editing > lines.len || line_editing < 1 || !in_range(parent(), A.actor))
		return FALSE
	lines[line_editing] = A.step_value("line")
	return TRUE

//MODE STUFF

/datum/song/proc/ui_act_set_sustain_mode(datum/act/op/A, new_mode_arg)
	if(!ui_gate(A))
		return FALSE
	var/new_mode = new_mode_arg
	if(isnull(new_mode) || !(new_mode in SSinstruments.ready().note_sustain_modes))
		return FALSE
	sustain_mode = new_mode
	return TRUE

/datum/song/proc/ui_act_set_note_shift(datum/act/op/A, amount_arg)
	if(!ui_gate(A))
		return FALSE
	var/amount = amount_arg
	if(!isnum(amount))
		return FALSE
	note_shift = clamp(amount, note_shift_min, note_shift_max)
	return TRUE

/datum/song/proc/ui_act_set_volume(datum/act/op/A, amount)
	if(!ui_gate(A))
		return FALSE
	var/new_volume = amount
	if(!isnum(new_volume))
		return FALSE
	set_volume(new_volume)
	return TRUE

/datum/song/proc/ui_act_set_dropoff_volume(datum/act/op/A, amount)
	if(!ui_gate(A))
		return FALSE
	var/dropoff_threshold = amount
	if(!isnum(dropoff_threshold))
		return FALSE
	set_dropoff_volume(dropoff_threshold)
	return TRUE

/datum/song/proc/ui_act_toggle_sustain_hold_indefinitely(datum/act/op/A)
	full_sustain_held_note = !full_sustain_held_note
	return OP_OK

/datum/song/proc/ui_act_set_repeat_amount(datum/act/op/A, amount)
	if(!ui_gate(A))
		return FALSE
	if(playing)
		return
	var/repeat_amount = amount
	if(!isnum(repeat_amount))
		return FALSE
	set_repeats(repeat_amount)
	return TRUE

/datum/song/proc/ui_act_edit_sustain_mode(datum/act/op/A, amount)
	if(!ui_gate(A))
		return FALSE
	var/sustain_amount = amount
	if(isnull(sustain_amount) || !isnum(sustain_amount))
		return
	switch(sustain_mode)
		if(SUSTAIN_LINEAR)
			set_linear_falloff_duration(sustain_amount)
		if(SUSTAIN_EXPONENTIAL)
			set_exponential_drop_rate(sustain_amount)

/**
 * Parses a song the user has input into lines and stores them.
 */
/datum/song/proc/ParseSong(mob/user, new_song)
	//split into lines
	lines = islist(new_song) ? new_song : splittext(new_song, "\n")
	if(lines.len)
		var/bpm_string = "BPM: "
		if(findtext(lines[1], bpm_string, 1, length(bpm_string) + 1))
			var/divisor = text2num(copytext(lines[1], length(bpm_string) + 1)) || 120 // default
			tempo = sanitize_tempo(BPM_TO_TEMPO_SETTING(divisor))
			lines.Cut(1, 2)
		else
			tempo = sanitize_tempo(5) // default 120 BPM
		if(lines.len > MUSIC_MAXLINES)
			if(user)
				to_chat(user, "Too many lines!")
			lines.Cut(MUSIC_MAXLINES + 1)
		var/linenum = 1
		for(var/l in lines)
			if(length_char(l) > MUSIC_MAXLINECHARS)
				if(user)
					to_chat(user, "Line [linenum] too long!")
				lines.Remove(l)
			else
				linenum++

/datum/song/proc/append_answered_line(value)
	if(length(value) > MUSIC_MAXLINECHARS)
		value = copytext(value, 1, MUSIC_MAXLINECHARS)
	lines.Add(value)

/datum/prompt/text/song_line
	max_len = MUSIC_MAXLINECHARS
	timeout = 0

/datum/prompt/text/song_line/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/song_line/add
	question = "Enter your line"

/datum/prompt/text/song_line/modify
	question = "Enter your line "
