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
