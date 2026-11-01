/// Logs a dialog line to the database: a write on the I/O lane (io_job), so nothing waits.
/proc/db_log_insert(mob/log_target, message, type, color)
	if(!ismob(log_target))
		return
	if(!SSdbcore.IsConnected())
		return
	io_job(null, /datum/io_backend/sql, "INSERT INTO erro_dialog (mid, time, ckey, mob, area, type, color, message) VALUES (null, NOW(), :sender_ckey, :sender_mob, :message_area, :message_type, :message_color, :message_content)",
		list("sender_ckey" = log_target.ckey, "sender_mob" = log_target.real_name, "message_area" = "[loc_name(log_target)]", "message_type" = "[type]", "message_color" = color, "message_content" = message),
		/proc/db_log_insert_done)

/proc/db_log_insert_done(list/result, error)
	if(error)
		log_sql("Error during logging: [error]")
