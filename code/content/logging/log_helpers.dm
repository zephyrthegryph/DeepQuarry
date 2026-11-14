// The content half of code/host/helpers/logging/_logging.dm: what names content, so the layer the engine calls cannot hold it.

/**
 * Generic logging helper
 *
 * reads the type of the log
 * and writes it to the respective log file
 * unless log_globally is FALSE
 * Arguments:
 * * message - The message being logged
 * * message_type - the type of log the message is(ATTACK, SAY, etc)
 * * color - color of the log text
 * * log_globally - boolean checking whether or not we write this log to the log file
 */
/atom/proc/log_message(message, message_type, color = null, log_globally = TRUE, list/data)
	if(!log_globally)
		return

	var/log_text = "[key_name_and_tag(src)] [message] [loc_name(src)]"
	switch(message_type)
		/// ship both attack logs and victim logs to the end of round attack.log just to ensure we don't lose information
		if(LOG_ATTACK, LOG_VICTIM)
			log_attack(log_text, data)
		if(LOG_SAY)
			log_say(log_text, data)
		if(LOG_WHISPER)
			log_whisper(log_text, data)
		if(LOG_EMOTE)
			log_emote(log_text, data)
		if(LOG_PDA)
			log_pda(log_text, data)
		if(LOG_OOC)
			log_ooc(log_text, data)
		if(LOG_LOOC)
			log_looc(log_text, data)
		if(LOG_ADMIN)
			log_admin(log_text, data)
		if(LOG_ADMIN_PRIVATE)
			log_admin_private(log_text, data)
		if(LOG_ASAY)
			log_adminsay(log_text, data)
		if(LOG_GAME)
			log_game(log_text, data)
		else
			stack_trace("Invalid individual logging type: [message_type]. Defaulting to [LOG_GAME] (LOG_GAME).")
			log_game(log_text, data)

/proc/report_progress(progress_message)
	admin_notice(span_boldannounce("[progress_message]"), R_DEBUG)
	log_world(progress_message)

/* Close open log handles. This should be called as late as possible, and no logging should hapen after. */
/proc/shutdown_logging()
	log_file_flush()
	rustg_log_close_all()
	logger.shutdown_logging()

/datum/mind/key_name_fields()
	return list(key, current, name)

/client/key_name_masked()
	return admin_can(src, 0) && admin_fakekey(src)

/// fexists() for a log file, timed: it is a disk call made on the tick, and on a busy disk it blocks (LOG_WORLD_SLOW names the time it took).
/proc/log_file_exists(file)
	var/started = TICK_USAGE_REAL
	. = fexists(file)
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	GLOB.log_exists_calls++
	GLOB.log_exists_ms += ms
	GLOB.log_exists_max_ms = max(GLOB.log_exists_max_ms, ms)
