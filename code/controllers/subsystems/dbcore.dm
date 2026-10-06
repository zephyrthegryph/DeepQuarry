SYSTEM_DEF(dbcore)
	name = "Database"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	init_stage = INITSTAGE_EARLY

	EXPIRY_DECLARE(failed_connection_timeout)

	var/schema_mismatch = 0
	var/db_minor = 0
	var/db_major = 0
	var/failed_connections = 0

	var/last_error

	var/max_concurrent_queries = 25

	var/connection  // Arbitrary handle returned from rust_g.


/datum/system/dbcore/initialize()
	Connect()
	if(IsConnected() && CONFIG_GET(flag/database_logging))
		// Boot only: nothing else is running yet.
		if(isnull(db_query_now("TRUNCATE erro_dialog")))
			log_sql("ERROR TRYING TO CLEAR erro_dialog: "+ErrorMsg())
	return

/datum/system/dbcore/stat_entry(msg)
	msg = "Connected: [IsConnected() ? "yes" : "no"]"
	return ..()

/datum/system/dbcore/on_shutdown()
	log_sql("Database shutting down")
	//This is as close as we can get to the true round end before Disconnect() without changing where it's called, defeating the reason this is a subsystem
	if(SSdbcore.Connect())
		// Last metrics before the disconnect (world services shut down after the subsystems).
		SSserver_metrics?.final_flush()
		if(isnull(db_query_now(
			"UPDATE [format_table_name("round")] SET shutdown_datetime = Now(), end_state = :end_state WHERE id = :round_id",
			//list("end_state" = SSticker.end_state, "round_id" = GLOB.round_id),
			list("end_state" = "undefined", "round_id" = GLOB.round_id) // FIXME: end_state does not exist on ticker
		)))
			log_sql("Round shutdown stamp failed: [ErrorMsg()]")

	log_sql("Done shutting down the database")
	if(IsConnected())
		Disconnect()

//nu
/datum/system/dbcore/can_vv_get(var_name)
	if(var_name == NAMEOF(src, connection))
		return FALSE
	return ..()

/datum/system/dbcore/vv_edit_var(var_name, var_value)
	if(var_name == NAMEOF(src, connection))
		return FALSE
	return ..()

/datum/system/dbcore/proc/Connect()
	if(IsConnected())
		return TRUE

	if(EXPIRY_EXPIRED(src, failed_connection_timeout, CLOCK_WORLD)) //it's been more than 5 seconds since we failed to connect, reset the counter
		failed_connections = 0

	if(failed_connections > 5) //If it failed to establish a connection more than 5 times in a row, don't bother attempting to connect for 5 seconds.
		EXPIRY_SET(src, failed_connection_timeout, 5 SECONDS, CLOCK_WORLD)
		return FALSE

	if(!CONFIG_GET(flag/sql_enabled))
		return FALSE


	var/user = CONFIG_GET(string/feedback_login)
	var/pass = CONFIG_GET(string/feedback_password)
	var/db = CONFIG_GET(string/feedback_database)
	var/address = CONFIG_GET(string/address)
	var/port = CONFIG_GET(number/port)
	var/timeout = max(CONFIG_GET(number/async_query_timeout), CONFIG_GET(number/blocking_query_timeout))
	var/min_sql_connections = CONFIG_GET(number/pooling_min_sql_connections)
	var/max_sql_connections = CONFIG_GET(number/pooling_max_sql_connections)

	var/result = json_decode(rustg_sql_connect_pool(json_encode(list(
		"host" = address,
		"port" = port,
		"user" = user,
		"pass" = pass,
		"db_name" = db,
		"read_timeout" = timeout,
		"write_timeout" = timeout,
		"min_threads" = min_sql_connections,
		"max_threads" = max_sql_connections,
	))))
	. = (result["status"] == "ok")
	if (.)
		connection = result["handle"]
	else
		connection = null
		last_error = result["data"]
		log_sql("Connect() failed | [last_error]")
		++failed_connections

/datum/system/dbcore/proc/CheckSchemaVersion()
	if(CONFIG_GET(flag/sql_enabled))
		if(Connect())
			log_world("Database connection established.")
		else
			log_sql("Your server failed to establish a connection with the database.")
	else
		log_sql("Database is not enabled in configuration.")

/datum/system/dbcore/proc/InitializeRound()
	if(!Connect())
		return
	// The round id is needed before anything else runs: a blocking write (boot only).
	var/list/initialized = db_exec_now(
		"INSERT INTO [format_table_name("round")] (initialize_datetime, server_ip, server_port) VALUES (Now(), INET_ATON(:internet_address), :port)",
		list("internet_address" = world.internet_address || "0", "port" = "[world.port]")
	)
	GLOB.round_id = "[initialized?["last_insert_id"]]"

/// Stamps the round's start time: a write on the I/O lane (io_job), so the ticker never waits.
/datum/system/dbcore/proc/SetRoundStart()
	if(!Connect())
		return
	sql_write(
		"UPDATE [format_table_name("round")] SET start_datetime = Now() WHERE id = :round_id",
		list("round_id" = GLOB.round_id)
	)

/// Stamps the round's end: a write on the I/O lane (io_job), so declare_completion never waits.
/datum/system/dbcore/proc/SetRoundEnd()
	if(!Connect())
		return
	sql_write(
		"UPDATE [format_table_name("round")] SET end_datetime = Now(), game_mode_result = :game_mode_result, station_name = :station_name WHERE id = :round_id",
		list("game_mode_result" = "extended", "station_name" = station_name(), "round_id" = GLOB.round_id) // FIXME: temporary solution as we only use extended so far
	)

/datum/system/dbcore/proc/Disconnect()
	failed_connections = 0
	if (connection)
		rustg_sql_disconnect_pool(connection)
	connection = null

/datum/system/dbcore/proc/IsConnected()
	if (!CONFIG_GET(flag/sql_enabled))
		return FALSE
	if (!connection)
		return FALSE
	return json_decode(rustg_sql_connected(connection))["status"] == "online"

/datum/system/dbcore/proc/ErrorMsg()
	if(!CONFIG_GET(flag/sql_enabled))
		return "Database disabled by configuration"
	return last_error

/datum/system/dbcore/proc/ReportError(error)
	last_error = error

/*
Takes a list of rows (each row being an associated list of column => value) and inserts them via a
single multi-row INSERT. All rows are sent as a single query; the driver either commits all or none
unless ignore_errors is TRUE (see below).

Rows missing columns present in other rows resolve to SQL NULL.
Values are passed through the parameterized-query mechanism (:pN placeholders), so no manual
escaping of value data is required. Column and table names ARE interpolated directly — callers
are responsible for supplying safe, validated names (use format_table_name() for table names).

Arguments:
	table          — SQL table name. Use format_table_name() to produce it.
	rows           — list of assoc lists, each mapping column => value.
	duplicate_key  — Controls ON DUPLICATE KEY UPDATE behaviour:
	                   FALSE  (default): no duplicate handling; a duplicate primary/unique key causes
	                          the entire INSERT to fail (all rows rolled back).
	                   TRUE:  auto-generates "ON DUPLICATE KEY UPDATE col = VALUES(col), ..." for every
	                          column in the union of all rows. Useful for upserts, but note that MySQL
	                          counts this as 2 affected rows per updated row, not 1.
	                   string: the string is appended verbatim after VALUES(...); use this to supply a
	                          custom ON DUPLICATE KEY UPDATE clause (e.g. targeting only specific
	                          conflict columns).
	ignore_errors  — If TRUE, uses INSERT IGNORE. Rows that violate constraints are silently skipped;
	                 the rest are inserted. PARTIAL SUCCESS IS POSSIBLE: the proc returns TRUE even if
	                 some rows were dropped. Callers that need per-row status must issue individual
	                 queries instead.
	special_columns — Assoc list of column => SQL-expression overrides (e.g. list("ts" = "NOW()")).
	                 Expressions containing "?" are treated as placeholders; those without are
	                 interpolated verbatim into the query.

mass_insert_io() runs it on the I/O lane; on_done gets the outcome.
*/
/// Builds a mass insert's statement: list(sql, arguments), or null for no rows.
/datum/system/dbcore/proc/mass_insert_sql(table, list/rows, duplicate_key = FALSE, ignore_errors = FALSE, special_columns = null)
	if (!table || !rows || !istype(rows))
		return null

	// Prepare column list
	var/list/columns = list()
	var/list/has_question_mark = list()
	for (var/list/row in rows)
		for (var/column in row)
			columns[column] = "?"
			has_question_mark[column] = TRUE
	for (var/column in special_columns)
		columns[column] = special_columns[column]
		has_question_mark[column] = findtext(special_columns[column], "?")

	// Prepare SQL query full of placeholders
	var/list/query_parts = list("INSERT")
	if (ignore_errors)
		query_parts += " IGNORE"
	query_parts += " INTO "
	query_parts += table
	query_parts += "\n([columns.Join(", ")])\nVALUES"

	var/list/arguments = list()
	var/has_row = FALSE
	for (var/list/row in rows)
		if (has_row)
			query_parts += ","
		query_parts += "\n  ("
		var/has_col = FALSE
		for (var/column in columns)
			if (has_col)
				query_parts += ", "
			if (has_question_mark[column])
				var/name = "p[length(arguments)]"
				query_parts += replacetext(columns[column], "?", ":[name]")
				arguments[name] = row[column]
			else
				query_parts += columns[column]
			has_col = TRUE
		query_parts += ")"
		has_row = TRUE

	if (duplicate_key == TRUE)
		var/list/column_list = list()
		for (var/column in columns)
			column_list += "[column] = VALUES([column])"
		query_parts += "\nON DUPLICATE KEY UPDATE [column_list.Join(", ")]"
	else if (duplicate_key != FALSE)
		query_parts += duplicate_key

	return list(query_parts.Join(), arguments)

/// A mass insert (mass_insert_sql()) on the I/O lane: returns at once. `on_done` (optional) runs on E as
/// on_done(result, error, context...) like any io_job() callback; without it a failure is logged.
/datum/system/dbcore/proc/mass_insert_io(datum/E, table, list/rows, duplicate_key = FALSE, ignore_errors = FALSE, special_columns = null, on_done = null, ...)
	var/list/statement = mass_insert_sql(table, rows, duplicate_key, ignore_errors, special_columns)
	if(!statement)
		return 0
	if(!on_done)
		return io_job(E, /datum/io_backend/sql, statement[1], statement[2], /proc/io_log_sql_error, statement[1])
	var/list/call_args = list(E, /datum/io_backend/sql, statement[1], statement[2], on_done)
	if(length(args) > 7)
		call_args += args.Copy(8)
	return io_job(arglist(call_args))

/// Runs `query` on the connection and waits for the answer: the blocking call db_query_now() wraps. Returns rust_g's raw JSON.
/datum/system/dbcore/proc/query_blocking(query, list/params)
	return rustg_sql_query_blocking(connection, query, json_encode(params || list()))
