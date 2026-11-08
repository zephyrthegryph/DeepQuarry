// plan_spares_draw() keeps the running definitions' part of its key on the holder (rx.spares_defs_key) until its activations change. It must equal
// the key made fresh after every change: a grant that comes, one that goes.

/// Observes a human so the human carries a grant (a hook activation) while it listens.
/obj/item/dq_spares_listener

/obj/item/dq_spares_listener/proc/heard(datum/act/A)
	return

/datum/unit_test/dq_spares_defs_key_follows_activations

/datum/unit_test/dq_spares_defs_key_follows_activations/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/dq_spares_listener/listener = allocate(/obj/item/dq_spares_listener, test_floor())
	plan_spares_draw(H, nameof(/atom::desc))
	TEST_ASSERT_EQUAL(H.rx.spares_defs_key, fresh_key(H), "the kept key is the fresh one")
	observe(H, /datum/notice/moved, listener, then(TYPE_PROC_REF(/obj/item/dq_spares_listener, heard)))
	TEST_ASSERT(isnull(H.rx.spares_defs_key), "a grant clears it")
	plan_spares_draw(H, nameof(/atom::desc))
	TEST_ASSERT_EQUAL(H.rx.spares_defs_key, fresh_key(H), "rebuilt with the grant")
	unobserve(H, /datum/notice/moved, listener)
	TEST_ASSERT(isnull(H.rx.spares_defs_key), "its end clears it")
	plan_spares_draw(H, nameof(/atom::desc))
	TEST_ASSERT_EQUAL(H.rx.spares_defs_key, fresh_key(H), "rebuilt without it")

/datum/unit_test/dq_spares_defs_key_follows_activations/proc/fresh_key(datum/E)
	var/list/defs = list()
	for(var/datum/activation/A as anything in E.rx?.activations)
		if(!A.dead && A.runs)
			defs |= "[A.def.key]"
	return length(defs) ? "||[jointext(sortList(defs), ",")]" : ""
