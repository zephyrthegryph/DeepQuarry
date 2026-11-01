/// The log writer: the type and its entry point are what the engine calls, content (code/content/logging/) implements them.
GLOBAL_REAL(logger, /datum/log_holder)
/datum/log_holder
/datum/log_holder/proc/Log(category, message, list/data)
	return

//print a warning message to world.log
#define WARNING(MSG) warning("[MSG] in [__FILE__] at line [__LINE__] src: [UNLINT(src)] usr: [usr].")
/proc/warning(msg)
	msg = "## WARNING: [msg]"
	boot_noise_note(msg)
	log_world(msg)

/// Every "## WARNING" and refused MOVE_INTO the world logged, and the first few of them: the unit-test suite reads
/// these at its start (the boot gate, doc/rewrite/boot_gate.md) and fails a run whose boot was not clean.
GLOBAL_VAR_INIT(boot_noise_count, 0)
GLOBAL_LIST_EMPTY(boot_noise_first)

/proc/boot_noise_note(msg)
	GLOB.boot_noise_count++
	if(length(GLOB.boot_noise_first) < 20)
		GLOB.boot_noise_first += "[msg]"

//not an error or a warning, but worth to mention on the world log, just in case.
#define NOTICE(MSG) notice(MSG)
/proc/notice(msg)
	msg = "## NOTICE: [msg]"
	log_world(msg)


//print a testing-mode debug message to world.log and world
#ifdef TESTING
#define testing(msg) log_world("## TESTING: [msg]"); to_chat(world, "## TESTING: [msg]")

GLOBAL_LIST_INIT(testing_global_profiler, list("_PROFILE_NAME" = "Global"))
// we don't really check if a word or name is used twice, be aware of that
#define testing_profile_start(NAME, LIST) LIST[NAME] = world.timeofday
#define testing_profile_current(NAME, LIST) round((world.timeofday - LIST[NAME])/10,0.1)
#define testing_profile_output(NAME, LIST) testing("[LIST["_PROFILE_NAME"]] profile of [NAME] is [testing_profile_current(NAME,LIST)]s")
#define testing_profile_output_all(LIST) { for(var/_NAME in LIST) { testing_profile_current(,_NAME,LIST); }; };
#else
#define testing(msg)
#define testing_profile_start(NAME, LIST)
#define testing_profile_current(NAME, LIST)
#define testing_profile_output(NAME, LIST)
#define testing_profile_output_all(LIST)
#endif

#if defined(REFERENCE_TRACKING_LOG_APART)
#define log_reftracker(msg) log_harddel("## REF SEARCH [msg]")

/proc/log_harddel(text)
	WRITE_LOG(GLOB.harddel_log, text)

#elif defined(REFERENCE_TRACKING) // Doing it locally
#define log_reftracker(msg) log_world("## REF SEARCH [msg]")

#else //Not tracking at all
#define log_reftracker(msg)
#endif

/* For logging round startup. */
/proc/start_log(log)
	WRITE_LOG(log, "Starting up round ID [GLOB.round_id].\n-------------------------")

/// What key_name() prints for a datum that stands for a player: list(key, mob, fallback name). Null for any other datum. Content answers.
/datum/proc/key_name_fields()
	return null

/proc/key_name_fields_of(datum/D)
	return D.key_name_fields()

/// TRUE when this client's key is hidden in logs that leave the name out. Content answers.
/client/proc/key_name_masked()
	return FALSE

/// The key a masked client's links use. Content answers.
/client/proc/getStealthKey()
	return null

/* Helper procs for building detailed log lines */
/proc/key_name(whom, include_link = null, include_name = TRUE)
	var/mob/M
	var/client/C
	var/key
	var/ckey
	var/fallback_name

	if(!whom)
		return "*null*"
	if(istype(whom, /client))
		C = whom
		M = C.mob
		key = C.key
		ckey = C.ckey
	else if(ismob(whom))
		M = whom
		C = M.client
		key = M.key
		ckey = M.ckey
	else if(istext(whom))
		key = whom
		ckey = ckey(whom)
		C = GLOB.directory[ckey]
		if(C)
			M = C.mob
	else if(isdatum(whom) && !isnull(key_name_fields_of(whom)))
		var/list/fields = key_name_fields_of(whom)
		key = fields[1]
		ckey = ckey(key)
		if(fields[2])
			M = fields[2]
			if(M.client)
				C = M.client
		else
			fallback_name = fields[3]
	else // Catch-all cases if none of the types above match
		var/swhom = null

		if(istype(whom, /atom))
			var/atom/A = whom
			swhom = "[A.name]"
		else if(isdatum(whom))
			swhom = "[whom]"

		if(!swhom)
			swhom = "*invalid*"

		return "\[[swhom]\]"

	. = ""

	if(!ckey)
		include_link = FALSE

	if(key)
		if(C?.key_name_masked() && !include_name)
			if(include_link)
				. += "<a href='byond://?priv_msg=[C.getStealthKey()]'>"
			. += "Administrator"
		else
			if(include_link)
				. += "<a href='byond://?priv_msg=[ckey]'>"
			. += key
		if(!C)
			. += "\[DC\]"

		if(include_link)
			. += "</a>"
	else
		. += "*no key*"

	if(include_name)
		if(M)
			if(M.real_name)
				. += "/([M.real_name])"
			else if(M.name)
				. += "/([M.name])"
		else if(fallback_name)
			. += "/([fallback_name])"

	return .

/proc/key_name_admin(whom, include_name = TRUE)
	return key_name(whom, TRUE, include_name)

/proc/key_name_and_tag(whom, include_link = null, include_name = TRUE)
	var/tag = "!tagless!" // whom can be null in key_name() so lets set this as a safety
	if(isatom(whom))
		var/atom/subject = whom
		tag = subject.tag
	return "[key_name(whom, include_link, include_name)] ([tag])"

/proc/loc_name(atom/A)
	if(!istype(A))
		return "(INVALID LOCATION)"

	var/turf/T = A
	if (!istype(T))
		T = get_turf(A)

	if(istype(T))
		return "([AREACOORD(T)])"
	else if(A.loc)
		return "(UNKNOWN (?, ?, ?))"

// Virgo specific Helper procs for building detailed log lines
//
// These procs must not fail under ANY CIRCUMSTANCES!
// Are these even still required?

/datum/proc/log_info_line()
	return "[src] ([type])"

/atom/log_info_line()
	. = ..()
	var/turf/t = get_turf(src)
	if(istype(t))
		return "[.] @ [t.log_info_line()]"
	else if(loc)
		return "[.] @ ([loc]) (0,0,0) ([loc.type])"
	else
		return "[.] @ (NULL) (0,0,0) (NULL)"

/turf/log_info_line()
	return "([src]) ([x],[y],[z]) ([type])"

/mob/log_info_line()
	return "[..()] (ckey=[ckey])"

/proc/log_info_line(datum/d)
	if(!d)
		return "*null*"
	if(!istype(d))
		return json_encode(d)
	return d.log_info_line()

/mob/proc/simple_info_line()
	return "[key_name(src)] ([x],[y],[z])"
