/// Game log files are written by a verdigris writer thread: a call here queues the line and returns, so a stalled disk
/// never stalls the tick. Lines land in the order of the calls; log_file_flush() waits until all queued lines are on disk.

/// Appends `text` to the file `file`; `formatted` prepends a timestamp and ends the line (what rust-g's log_write did).
/proc/log_file_append(file, text, formatted)
	if(formatted)
		text = "\[[rustg_formatted_timestamp("%Y-%m-%d %H:%M:%S%.3f")]\] [text]\n"
	vg_verdigris_log_append(file, text)

/// Blocks until every queued log line is on disk: reboot, shutdown, a category file reset, a test reading a log back.
/proc/log_file_flush()
	vg_verdigris_log_flush()

/// Flushes and ends the writer thread (world.Del(), before the DLL unloads); a later append starts it again.
/proc/log_file_stop()
	vg_verdigris_log_stop()

/// The writer's line counts since the DLL loaded: list(queued, written, failed).
/proc/log_file_counts()
	var/list/parts = splittext(vg_verdigris_log_counts(), ",")
	. = list()
	for(var/part in parts)
		. += text2num(part)
