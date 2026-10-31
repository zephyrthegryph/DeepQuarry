// The untyped ratchet, wave 3: the text and number helpers that make a result plainly text or a number must hand back what they were given
// (the helper's contract) and nothing else, and the references that became declared relations must still clear when their target dies.

/datum/unit_test/dq_untyped3_text_num_helpers

/datum/unit_test/dq_untyped3_text_num_helpers/Run()
	TEST_ASSERT_EQUAL(text_or_null("abc"), "abc", "text comes back as it was")
	TEST_ASSERT_EQUAL(text_or_null(""), "", "empty text stays empty text")
	TEST_ASSERT_NULL(text_or_null(null), "none stays none")
	TEST_ASSERT_EQUAL(num_or_null(5), 5, "a number comes back as it was")
	TEST_ASSERT_EQUAL(num_or_null(2.5), 2.5, "a fraction too")
	TEST_ASSERT_EQUAL(num_or_null(0), 0, "zero stays zero")
	TEST_ASSERT_NULL(num_or_null(null), "none stays none")

/datum/unit_test/dq_untyped3_sanitizers_unchanged

/datum/unit_test/dq_untyped3_sanitizers_unchanged/Run()
	// sanitize_integer: in range, out of range, fraction, not a number, no default
	TEST_ASSERT_EQUAL(sanitize_integer(5, 0, 10, 3), 5, "in range")
	TEST_ASSERT_EQUAL(sanitize_integer(50, 0, 10, 3), 3, "out of range falls to the default")
	TEST_ASSERT_EQUAL(sanitize_integer(5.6, 0, 10, 3), 5, "a fraction is floored by one-argument round()")
	TEST_ASSERT_EQUAL(sanitize_integer("x", 0, 10, 3), 3, "not a number falls to the default")
	TEST_ASSERT_EQUAL(sanitize_integer("x"), 0, "the default default is 0")
	TEST_ASSERT_EQUAL(sanitize_integer("x", 0, 10, null), 0, "a null default argument is the parameter default, as in DM")
	TEST_ASSERT_EQUAL(sanitize_integer(7, 0, 10, 2.5), 7, "a number keeps its value")
	TEST_ASSERT_EQUAL(sanitize_integer(70, 0, 10, 2.5), 2.5, "a fractional default is kept")
	TEST_ASSERT_EQUAL(sanitize_float(2.6, 0, 5, 1, 3), 3, "sanitize_float rounds to its accuracy")
	TEST_ASSERT_EQUAL(sanitize_float(9, 0, 5, 0.1, 3), 3, "and falls to the default out of range")
	// sanitize_hexcolor
	TEST_ASSERT_EQUAL(sanitize_hexcolor("#ABCDEF", "#111111"), "#abcdef", "a colour is lower-cased")
	TEST_ASSERT_EQUAL(sanitize_hexcolor("#ABC", "#111111"), "#abc", "so is the short form")
	TEST_ASSERT_EQUAL(sanitize_hexcolor("nope", "#111111"), "#111111", "not a colour falls to the default")
	TEST_ASSERT_EQUAL(sanitize_hexcolor("#12345g", "#111111"), "#111111", "a bad digit falls to the default")
	TEST_ASSERT_EQUAL(sanitize_hexcolor(5), "#000000", "the default default is black")
	TEST_ASSERT_EQUAL(sanitize_hexcolor("nope", null), "#000000", "a null default argument is the parameter default, as in DM")
	// sanitize_text
	TEST_ASSERT_EQUAL(sanitize_text("abc", "d"), "abc", "text stays")
	TEST_ASSERT_EQUAL(sanitize_text(5, "d"), "d", "not text falls to the default")
	TEST_ASSERT_EQUAL(sanitize_text(null), "", "the default default is empty text")
	TEST_ASSERT_EQUAL(sanitize_text(null, null), "", "a null default argument is the parameter default, as in DM")
	// the text helpers
	TEST_ASSERT_EQUAL(strip_html_simple("<a>x</a>"), "ax/a", "angle brackets go, the text between stays")
	TEST_ASSERT_EQUAL(strip_html_simple("abcdef", 4), "abc", "and the limit holds")
	TEST_ASSERT_EQUAL(readd_quotes("&#34;a&#39;"), "\"a'", "quotes come back")
	TEST_ASSERT_EQUAL(sanitize_simple("a\nb"), "a#b", "a newline becomes #")
	TEST_ASSERT_EQUAL(sanitize_filename("a/b:c"), "abc", "a filename loses its path characters")
	TEST_ASSERT_NULL(sanitize(null), "no input, no output")
	TEST_ASSERT_NULL(sanitize(""), "empty input, no output")
	TEST_ASSERT_EQUAL(sanitize("hello"), "hello", "plain text stays")
	TEST_ASSERT_EQUAL(sanitize("a&b"), "a&amp;b", "special characters are encoded")
	TEST_ASSERT_EQUAL(sanitize("a&b", encode = 0), "a&b", "or left alone without encoding")
	TEST_ASSERT_EQUAL(sanitizeSafe("a<b"), "a b", "sanitizeSafe blanks brackets first")

/datum/unit_test/dq_untyped3_handle_texts

/datum/unit_test/dq_untyped3_handle_texts/Run()
	var/obj/item/pen/P = new(dq_containment_floor())
	var/token = ref_token(P)
	TEST_ASSERT(istext(token), "a datum's handle is text")
	TEST_ASSERT_EQUAL(ref_token(P), token, "and is stable")
	TEST_ASSERT_EQUAL(entity_handle_of(P), token, "entity_handle_of() names the same handle")
	TEST_ASSERT_EQUAL(resolve_token(token), P, "and resolves back to it")
	var/turf/T = dq_containment_floor()
	TEST_ASSERT(istext(ref_token(T)), "a turf's handle is text")
	TEST_ASSERT_NULL(ref_token(null), "no datum, no handle")
	qdel(P)
	TEST_ASSERT_NULL(resolve_token(token), "a deleted datum's handle resolves to nothing")

/datum/unit_test/dq_untyped3_relations_clear

/datum/unit_test/dq_untyped3_relations_clear/Run()
	var/obj/item/pen/P = new(dq_containment_floor())
	rel_set(GLOB, nameof(GLOB.act_next_actor), P)
	TEST_ASSERT_EQUAL(GLOB.act_next_actor, P, "the next actor is set")
	qdel(P)
	TEST_ASSERT_NULL(GLOB.act_next_actor, "a deleted actor leaves the global")
	rel_clear(GLOB, nameof(GLOB.act_next_actor))

	var/obj/item/pen/Q = new(dq_containment_floor())
	var/datum/kernel_job/J = job(Q, TYPE_PROC_REF(/obj/item/pen, dq_untyped3_job_step), budget = 100)
	TEST_ASSERT_NOTNULL(J, "the job started")
	rel_set(SSkernel_jobs, nameof(SSkernel_jobs.next_job), J)
	TEST_ASSERT_EQUAL(SSkernel_jobs.next_job, J, "the job is where the next pass starts")
	SSkernel_jobs.jobs -= J
	qdel(J)
	TEST_ASSERT_NULL(SSkernel_jobs.next_job, "a deleted job is no longer where the pass starts")
	qdel(Q)

/obj/item/pen/proc/dq_untyped3_job_step(datum/kernel_job/J)
	return STEP_DONE

/datum/unit_test/dq_untyped3_immunity_stats

/datum/unit_test/dq_untyped3_immunity_stats/Run()
	var/found = 0
	for(var/id in GLOB.stat_defs)
		var/datum/stat_def/def = GLOB.stat_defs[id]
		if(!def.immune_of)
			continue
		found++
		TEST_ASSERT(istype(def.immune_of, /datum/stat_def), "[def.name]: the companion points at a stat definition")
		TEST_ASSERT_EQUAL(def.name, "[def.immune_of.name]_immune", "[def.name]: an immunity stat is named for its status")
	TEST_ASSERT(found > 0, "the stat definitions have immunity companions")

// The bodies master had before the wave, verbatim: the current helpers must answer exactly as they did over a sweep of inputs.
/proc/dq_untyped3_master_sanitize_integer(number, min=0, max=1, default=0)
	if(isnum(number))
		number = round(number)
		if(min <= number && number <= max)
			return number
	return default

/proc/dq_untyped3_master_sanitize_float(number, min=0, max=1, accuracy=1, default=0)
	if(isnum(number))
		number = round(number, accuracy)
		if(round(min, accuracy) <= number && number <= round(max, accuracy))
			return number
	return default

/datum/unit_test/dq_untyped3_sanitizers_match_master

/datum/unit_test/dq_untyped3_sanitizers_match_master/Run()
	var/list/numbers = list(-3, 0, 0.4, 1, 2.5, 2.6, 5.6, 7, 10, 10.4, 11, 50, "x", "", null)
	var/list/defaults = list(0, 3, 2.5, -1, null)
	for(var/n in numbers)
		for(var/d in defaults)
			var/was = dq_untyped3_master_sanitize_integer(n, 0, 10, d)
			var/now = sanitize_integer(n, 0, 10, d)
			TEST_ASSERT_EQUAL(now, was, "sanitize_integer([n], 0, 10, [d]) answers as before")
			var/was_f = dq_untyped3_master_sanitize_float(n, 0, 5, 0.1, d)
			var/now_f = sanitize_float(n, 0, 5, 0.1, d)
			TEST_ASSERT_EQUAL(now_f, was_f, "sanitize_float([n], 0, 5, 0.1, [d]) answers as before")
	TEST_ASSERT_EQUAL(sanitize_integer(7), dq_untyped3_master_sanitize_integer(7), "default arguments answer as before")
	for(var/t in list("abc", "", 5, null))
		TEST_ASSERT_EQUAL(sanitize_text(t, "d"), (istext(t) ? t : "d"), "sanitize_text([t])")
