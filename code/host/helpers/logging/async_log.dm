/// Game log files are written by a verdigris writer thread: a call here queues the line and returns, so a stalled disk
/// never stalls the tick. Lines land in the order of the calls; log_file_flush() waits until all queued lines are on disk.

/// Appends `text` to the file `file`; `formatted` prepends a timestamp and ends the line (what rust-g's log_write did).
/proc/log_file_append(file, text, formatted)
	if(formatted)
		text = "\[[rustg_formatted_timestamp("%Y-%m-%d %H:%M:%S%.3f")]\] [text]\n"
	vg_verdigris_log_append(file, text)

/// The header a log file starts with. If the file is deleted while the round runs, the writer thread finds it gone when it next opens the
/// file and writes the header first, so the game thread never looks at the disk to check (it once did, an fexists() per file every 10 s).
/proc/log_file_set_header(file, header)
	vg_verdigris_log_header(file, header)

/// Synchronous file writes made for log files (a category file's reset at boot). Nothing logged by log_world() or logger.Log() may raise it.
GLOBAL_VAR_INIT(log_sync_writes, 0)

/// Writes `text` over `file` on the calling thread: only a category file's start-up reset uses this, before any line is logged to it.
/proc/log_file_write_sync(file, text)
	GLOB.log_sync_writes++
	rustg_file_write(text, file)

/// Appends `text` to `file` on the calling thread: only the reset marker of a category file that already existed at boot.
/proc/log_file_append_sync(file, text)
	GLOB.log_sync_writes++
	rustg_file_append(text, file)

/// Blocks until every queued log line is on disk: reboot, shutdown, a category file reset, a test reading a log back.
/proc/log_file_flush()
	vg_verdigris_log_flush()

/// Flushes and ends the writer thread (world.Del(), before the DLL unloads); a later append starts it again.
/proc/log_file_stop()
	vg_verdigris_log_stop()

/// The writer's line counts since the DLL loaded: list(queued, written, failed, recovered).
/proc/log_file_counts()
	var/list/parts = splittext(vg_verdigris_log_counts(), ",")
	. = list()
	for(var/part in parts)
		. += text2num(part)
