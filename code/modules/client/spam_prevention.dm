// Based on Aurora's anti-spam system.
/client/
	EXPIRY_DECLARE(last_message_time)
	var/spam_alert = 0

/client/proc/handle_spam_prevention(mute_type = MUTE_ALL, spam_delay = 0.5 SECONDS)
	if(ELAPSED_SINCE(src, last_message_time, CLOCK_WORLD) < spam_delay)
		spam_alert++
		if(spam_alert > 5)
			cmd_admin_mute(src.mob, mute_type, TRUE)
	else
		spam_alert = max(0, spam_alert - 1)
	EXPIRY_STAMP(src, last_message_time, CLOCK_WORLD)
