// The gate fixtures of E2 (doc/rewrite/final_api.html, section 19 "The seven workers", "E2, parts": "One op through each input kind (hand, item,
// in-hand, menu, drag, UI, topic, inside) resolves to its intended winner; a refusal shows its reason; asks() cancel leaves costs unspent, and an effect
// written above an asks() is a build error; wait() is cancelled with feedback when the target is deleted; two ops with the same input, intent and
// tier are a build error; explain_click matches a golden; a legacy DECLARE_INTERACTIONS entry resolves beside a new op").
// Test-only types, compiled under UNIT_TESTS only (code/modules/unit_tests/dq_e2_parts_tests.dm drives them).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_DEF_SELF(e2/locked, "It is locked.")
MSG_DEF_SELF(e2/is_open, "It is open.")
MSG_DEF_SELF(e2/no_name, "It needs a name first.")

// A headless interactive transport for the input-kind fixture. Production obj topic
// admission still checks its normal tgui gate, including the actual actor's distance.
/mob/living/simple_mob/e0_fixture/e2_topic_actor/default_can_use_tgui_topic(src_object)
	if(stat)
		return STATUS_DISABLED
	if(incapacitated())
		return STATUS_UPDATE
	if(!loc)
		return STATUS_CLOSE
	return min(STATUS_INTERACTIVE, loc.contents_tgui_distance(src_object, src))

/// A crowbar-like tool and a key and a cloth: the things a held item can be.
/obj/item/e2_key
	name = "e2 key"

/obj/item/e2_cloth
	name = "e2 cloth"

/// Used on itself in hand: the in_hand() binding.
/obj/item/e2_cloth/proc/note_polish(datum/act/op/A)
	polished++
	return OP_OK

/obj/item/e2_cloth
	var/polished = 0

CAPABILITIES(/obj/item/e2_cloth)
	op("polish", in_hand(), then(PROC_REF(note_polish)))

/// One type with an op for every input kind of the table in section 8.
/obj/e2_box
	name = "e2 box"
	var/opened = FALSE
	var/pried = 0
	var/keys = 0
	var/slid = 0
	var/peeked = 0
	var/escaped = 0
	var/label_text
	var/last_ping

TRACKED(/obj/e2_box, opened)

CAPABILITIES(/obj/e2_box)
	op("open", hand(), toggles(nameof(opened)), logs(LOG_GAME))
	op("pry", tool(TOOL_CROWBAR), then(PROC_REF(note_pry)))
	op("insert_key", item(/obj/item/e2_key), consumes(), then(PROC_REF(note_key)))
	op("slide_in", item(/obj/item/e2_cloth), answers(INTENT_DROP_ONTO), then(PROC_REF(note_slide)))
	op("peek", menu(), then(PROC_REF(note_peek)))
	op("set_label", ui_act("set_label", arg("text", schema_text(8))), then(PROC_REF(apply_label)))
	op("ping", topic("ping", arg("n", int(0, 9))), then(PROC_REF(note_ping)))
	op("escape", inside(), priority(above("open")), then(PROC_REF(note_escape)))

/obj/e2_box/proc/note_pry(datum/act/op/A)
	pried++
	return OP_OK

/obj/e2_box/proc/note_key(datum/act/op/A)
	keys++
	return OP_OK

/obj/e2_box/proc/note_slide(datum/act/op/A)
	slid++
	return OP_OK

/obj/e2_box/proc/note_peek(datum/act/op/A)
	peeked++
	return OP_OK

/obj/e2_box/proc/apply_label(datum/act/op/A, text)
	label_text = text
	return OP_OK

/obj/e2_box/proc/note_ping(datum/act/op/A, n)
	last_ping = n
	return OP_OK

/obj/e2_box/proc/note_escape(datum/act/op/A)
	escaped++
	return OP_OK

/// A locked thing: the requirement says no, with its reason.
/obj/e2_vault
	name = "e2 vault"
	var/locked = TRUE
	var/opened = FALSE

TRACKED(/obj/e2_vault, locked)
TRACKED(/obj/e2_vault, opened)

CAPABILITIES(/obj/e2_vault)
	op("open", hand(), needs(req_is(nameof(locked), FALSE, because = MSG(e2/locked))), toggles(nameof(opened)))

/// A machine whose op spends and asks: costs are reserved only after the answer.
/obj/e2_machine
	name = "e2 machine"
	var/label_text

CAPABILITIES(/obj/e2_machine)
	op("rename", ui_act("rename"), costs(RES_DARK_ENERGY, 5), asks(/datum/prompt/text, fields = list("question" = "What is it called?")), then(PROC_REF(apply_name)), logs(LOG_GAME))

/obj/e2_machine/proc/apply_name(datum/act/op/A)
	var/datum/prompt/R = A.answer
	label_text = R.value
	return OP_OK

/// A thing with a wait: its target deleted while it waits cancels the op.
/obj/e2_lever
	name = "e2 lever"
	var/pulled = FALSE

TRACKED(/obj/e2_lever, pulled)

CAPABILITIES(/obj/e2_lever)
	op("pull_slow", hand(), wait(2 SECONDS), toggles(nameof(pulled)), logs(LOG_GAME))

/// A new op and a legacy DECLARE_INTERACTIONS entry on one type: a plain click is the new op's, an alt-click the legacy entry's.
/obj/e2_mixed
	name = "e2 mixed"
	var/waved = 0
	var/legacy_alt_by
	var/legacy_used = 0

CAPABILITIES(/obj/e2_mixed)
	op("wave", hand(), then(PROC_REF(note_wave)))

DECLARE_INTERACTIONS(/obj/e2_mixed, \
	INTERACT_ALT(null, PROC_REF(legacy_alt)))

/obj/e2_mixed/proc/note_wave(datum/act/op/A)
	waved++
	return OP_OK

/obj/e2_mixed/proc/legacy_alt(mob/user, obj/item/held, datum/interaction/interaction)
	legacy_used++
	legacy_alt_by = "[user.type]"
	return TRUE

#endif
