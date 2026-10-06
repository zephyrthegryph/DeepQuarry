// Message templates (doc/rewrite/systems.md section 15): token filling, template
// singletons, and interaction feedback templates resolving to real /datum/msg types.

MSG_DEF(unit_test/pry, "You pry %T% open with %I%.", "%U% pries %T% open.")

/datum/unit_test/dq_sys_messages_tokens

/datum/unit_test/dq_sys_messages_tokens/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.real_name = "Alice Test"
	H.name = "Alice Test"
	H.gender = FEMALE
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, test_floor())
	var/obj/structure/closet/box = allocate(/obj/structure/closet, test_floor())

	TEST_ASSERT_EQUAL(msg_fill("%U% pries %T% open.", H, box, bar), "Alice Test pries the [box.name] open.", "user and target tokens")
	TEST_ASSERT_EQUAL(msg_fill("%T% creaks.", H, box, bar), "The [box.name] creaks.", "a leading token is capitalised")
	TEST_ASSERT_EQUAL(msg_fill("<span class='notice'>%I% bends.</span>", H, box, bar), "<span class='notice'>The [bar.name] bends.</span>", "capitalised after leading tags")
	TEST_ASSERT_EQUAL(msg_fill("%U% braces %THEMSELVES% on %THEIR% knee.", H, box, bar), "Alice Test braces herself on her knee.", "pronoun tokens")
	TEST_ASSERT_EQUAL(msg_fill("100% sure", H, box, bar), "100% sure", "a lone percent sign is left alone")
	TEST_ASSERT_NULL(msg_fill(null, H, box, bar), "null stays null")

/datum/unit_test/dq_sys_messages_template

/datum/unit_test/dq_sys_messages_template/Run()
	var/datum/msg/a = msg_def(/datum/msg/unit_test/pry)
	TEST_ASSERT_EQUAL(a, msg_def(/datum/msg/unit_test/pry), "one singleton per template")
	var/list/lines = a.texts(null, null, null)
	TEST_ASSERT_EQUAL(lines[1], "You pry %T% open with %I%.", "self text")
	TEST_ASSERT_EQUAL(lines[2], "%U% pries %T% open.", "others text")
	TEST_ASSERT_EQUAL(msg_span("x", a.span_class), span_notice("x"), "default span is notice")

	// act_message_t and act_message must not runtime with non-mob users or null lines.
	var/obj/structure/closet/box = allocate(/obj/structure/closet, test_floor())
	act_message(box, null, others = "%U% rattles.")
	act_message_t(box, box, /datum/msg/unit_test/pry)
	act_message_t(box, box, null)

/// Every interaction's feedback / start_feedback names a /datum/msg type with some text.
/datum/unit_test/dq_sys_messages_interaction_feedback

/datum/unit_test/dq_sys_messages_interaction_feedback/Run()
	for(var/path in subtypesof(/datum/interaction))
		var/datum/interaction/proto = path
		for(var/msg_type in list(initial(proto.feedback), initial(proto.start_feedback)))
			if(isnull(msg_type))
				continue
			if(!ispath(msg_type, /datum/msg))
				TEST_FAIL("[path] has feedback [msg_type], not a /datum/msg type")
				continue
			var/datum/msg/def = msg_def(msg_type)
			if(!def.self && !def.others && !def.blind)
				TEST_FAIL("[path]: template [msg_type] has no text")
			for(var/text in list(def.self, def.others))
				if(text && (findtext(text, "%ACTOR%") || findtext(text, "%TARGET%")))
					TEST_FAIL("[path]: template [msg_type] still uses the old %ACTOR%/%TARGET% tokens")

/// Player text is literal: a "%U%" typed into an emote, a label or a character name is shown as
/// typed, never filled.
/datum/unit_test/dq_sys_messages_literal

/datum/unit_test/dq_sys_messages_literal/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.real_name = "Alice Test"
	H.name = "Alice Test"
	var/obj/structure/closet/box = allocate(/obj/structure/closet, test_floor())

	// The emote path: the finished lines go in whole through MSG_LITERAL.
	var/typed = "waves at %U% and %T%, 100%THEIR% sure"
	var/use_3p = span_emote(span_bold("Alice Test") + " [typed]")
	TEST_ASSERT_EQUAL(msg_fill(MSG_LITERAL(use_3p), H, box), use_3p, "a typed emote renders literally")
	TEST_ASSERT_EQUAL(msg_fill(MSG_LITERAL("%U%"), H, box), "%U%", "a bare typed %U% renders literally")

	// A template around player text: only the template's own tokens are filled.
	TEST_ASSERT_EQUAL(msg_fill("%U% labels %T%: \"[MSG_LITERAL("%U%")]\"", H, box), \
		"Alice Test labels the [box.name]: \"%U%\"", "template tokens fill, typed tokens don't")

	// A character name is player text too: filling %U% must not expose a token inside it.
	H.name = "Bob %T%"
	TEST_ASSERT_EQUAL(msg_fill("%U% opens %T%.", H, box), "Bob %T% opens the [box.name].", "a %T% in a name is literal")
	TEST_ASSERT(!findtext(msg_fill("%U%", H, box), msg_percent_mark()), "no literal mark leaks out of msg_fill")

	// And the whole act_message path takes literal text without a runtime.
	act_message(H, box, MSG_SELF(MSG_LITERAL(typed)), MSG_OTHERS(MSG_LITERAL(use_3p)), runemessage = MSG_LITERAL(typed))

/// A pen-renamed item named "%T%": the name paths strip the %, and even a raw one is never
/// re-read as a token because msg_fill() is a single pass.
/datum/unit_test/dq_sys_messages_renamed_item

/datum/unit_test/dq_sys_messages_renamed_item/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.real_name = "Alice Test"
	H.name = "Alice Test"
	var/obj/structure/closet/box = allocate(/obj/structure/closet, test_floor())
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, test_floor())

	// The rename prompt a pen, a labeler or a tag opens (a name-length text prompt).
	var/datum/prompt/text/ask = new
	ask.max_len = MAX_NAME_LEN
	ask.name_text = TRUE
	var/renamed = ask.normalize("Knife %T%")
	TEST_ASSERT_EQUAL(renamed, "Knife T", "a name prompt strips %")
	var/datum/prompt/text/long = new
	TEST_ASSERT_EQUAL(long.normalize("100% sure"), "100% sure", "free (non-name) text keeps its %")
	qdel(ask)
	qdel(long)
	TEST_ASSERT(!findtext(sanitizeName("Bob %T% Smith", allow_numbers = TRUE) || "", "%"), "sanitizeName drops %")
	TEST_ASSERT_EQUAL(strip_name_tokens("A %I% b"), "A I b", "strip_name_tokens")

	// A name set from the renamed answer: nothing left to read as a token, at a call site either.
	bar.name = renamed
	TEST_ASSERT_EQUAL(msg_fill("%U% inserts [bar.name] into %T%.", H, box), "Alice Test inserts Knife T into the [box.name].", "interpolated renamed name")

	// A raw % in a name (set by code, bypassing the prompts) is still never re-scanned.
	bar.name = "knife %T%"
	TEST_ASSERT_EQUAL(msg_fill("%U% waves %I% at %T%.", H, box, bar), "Alice Test waves the knife %T% at the [box.name].", "single pass: a filled name is not re-read")
	TEST_ASSERT_EQUAL(msg_fill("%I% glints.", H, box, bar), "The knife %T% glints.", "single pass with a leading token")
	TEST_ASSERT_EQUAL(msg_fill("50%off%T%", H, box, bar), "50%offthe [box.name]", "a non-token %x% does not swallow a real token")
