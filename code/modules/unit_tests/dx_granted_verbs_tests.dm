// granted_verbs(): verbs an atom has because of what it HAS (capabilities, a mob's species and traits).

/datum/capability/dx_verbful
	key = "dx_verbful"

/datum/capability/dx_verbful/verbs()
	return list(/obj/cap_fixture/dx_granted/proc/dx_cap_verb)

/obj/cap_fixture/dx_granted
	var/grant_extra = FALSE
	var/hide_extra = FALSE

/obj/cap_fixture/dx_granted/declared_capabilities(list/into)
	..()
	into += new /datum/capability/dx_verbful

/obj/cap_fixture/dx_granted/granted_verbs()
	. = ..()
	if(grant_extra)
		. += /obj/cap_fixture/dx_granted/proc/dx_var_verb

/obj/cap_fixture/dx_granted/hidden_verbs()
	. = ..()
	if(hide_extra)
		. += /obj/cap_fixture/dx_granted/proc/dx_var_verb

/obj/cap_fixture/dx_granted/proc/dx_cap_verb()
	set name = "DX Cap Verb"
	set src in view(1)

/obj/cap_fixture/dx_granted/proc/dx_var_verb()
	set name = "DX Var Verb"
	set src in view(1)

/obj/cap_fixture/dx_plain

/datum/capability/dx_extra_verbful
	key = "dx_extra_verbful"

/datum/capability/dx_extra_verbful/verbs()
	return list(/obj/cap_fixture/dx_plain/proc/dx_extra_verb)

/obj/cap_fixture/dx_plain/proc/dx_extra_verb()
	set name = "DX Extra Verb"
	set src in view(1)

/datum/unit_test/dx_granted_verbs_capability/Run()
	var/obj/cap_fixture/dx_granted/F = allocate(/obj/cap_fixture/dx_granted)
	TEST_ASSERT(/obj/cap_fixture/dx_granted/proc/dx_cap_verb in F.verbs, "capability verb present from init")
	refresh_flush()
	TEST_ASSERT(/obj/cap_fixture/dx_granted/proc/dx_cap_verb in F.verbs, "and after the first refresh")

/datum/unit_test/dx_granted_verbs_extra_capability/Run()
	var/obj/cap_fixture/dx_plain/F = allocate(/obj/cap_fixture/dx_plain)
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_plain/proc/dx_extra_verb in F.verbs), "no verb before the capability")
	TEST_ASSERT(add_capability(F, new /datum/capability/dx_extra_verbful), "extra capability added")
	refresh_flush()
	TEST_ASSERT(/obj/cap_fixture/dx_plain/proc/dx_extra_verb in F.verbs, "extra capability's verb granted")
	TEST_ASSERT(remove_capability(F, "dx_extra_verbful"), "extra capability removed")
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_plain/proc/dx_extra_verb in F.verbs), "its verb went with it")

/datum/unit_test/dx_granted_verbs_override/Run()
	var/obj/cap_fixture/dx_granted/F = allocate(/obj/cap_fixture/dx_granted)
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_granted/proc/dx_var_verb in F.verbs), "not granted while the var is clear")
	F.grant_extra = TRUE
	changed(F)
	refresh_flush()
	TEST_ASSERT(/obj/cap_fixture/dx_granted/proc/dx_var_verb in F.verbs, "granted while the var is set")
	F.grant_extra = FALSE
	changed(F)
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_granted/proc/dx_var_verb in F.verbs), "removed when cleared")

/datum/unit_test/dx_granted_verbs_hidden_wins/Run()
	var/obj/cap_fixture/dx_granted/F = allocate(/obj/cap_fixture/dx_granted)
	F.grant_extra = TRUE
	F.hide_extra = TRUE
	changed(F)
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_granted/proc/dx_var_verb in F.verbs), "hidden_verbs() wins over granted_verbs()")
	F.hide_extra = FALSE
	changed(F)
	refresh_flush()
	TEST_ASSERT(/obj/cap_fixture/dx_granted/proc/dx_var_verb in F.verbs, "granted once the hide lifts")
