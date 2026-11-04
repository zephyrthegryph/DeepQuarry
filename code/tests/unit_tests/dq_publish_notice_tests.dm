// PUBLISH(E, name, field = v) delivery of the occurrences that used to be hand-written notices (ACTION(..., FIXED, notice = ...)): a listener
// gets the fields by name, a sender reads back what a handler wrote into a payload list, a notice published from a handler is delivered at
// once, in publish order, and a notice with no fields still reaches its listener.

/// Hears several converted occurrences and logs what they carried.
/datum/publish_ear
	var/list/log = list()
	/// atom_entered handlers publish atom_exited from inside the delivery.
	var/republish = FALSE
	/// examine handlers publish another examine from inside the answer.
	var/recurse_examine = FALSE

CAPABILITIES(/datum/publish_ear)
	on_notice(/datum/notice/atom_dir_change, then(PROC_REF(on_dir)))
	on_notice(/datum/notice/atom_entered, then(PROC_REF(on_entered)))
	on_notice(/datum/notice/atom_exited, then(PROC_REF(on_exited)))
	on_notice(/datum/notice/examine, then(PROC_REF(on_examine)))
	on_notice(/datum/notice/hitby, then(PROC_REF(on_hitby)))
	on_notice(/datum/notice/in_range_of_irradiation, then(PROC_REF(on_irradiation)))
	on_notice(/datum/notice/living_shield_injury, then(PROC_REF(on_shield)))
	on_notice(/datum/notice/atom_extinguish, then(PROC_REF(on_extinguish)))

/datum/publish_ear/proc/on_dir(datum/act/A)
	var/datum/notice/atom_dir_change/N = A
	log += "dir:[N.old_dir]>[N.new_dir]"

/datum/publish_ear/proc/on_entered(datum/act/A)
	var/datum/notice/atom_entered/N = A
	log += "entered:[N.arrived]<[N.old_loc]"
	if(republish)
		PUBLISH(src, atom_exited, gone = N.arrived, new_loc = "nested")
		log += "entered:done"

/datum/publish_ear/proc/on_exited(datum/act/A)
	var/datum/notice/atom_exited/N = A
	log += "exited:[N.gone]>[N.new_loc]"

/datum/publish_ear/proc/on_examine(datum/act/A)
	var/datum/notice/examine/N = A
	log += "examine:[N.user]"
	N.texts += "line from [N.user]"
	if(recurse_examine)
		recurse_examine = FALSE
		PUBLISH(src, examine, user = "deeper", texts = N.texts)

/datum/publish_ear/proc/on_hitby(datum/act/A)
	var/datum/notice/hitby/N = A
	log += "hitby:[N.source_]:[N.throwingdatum]"

/datum/publish_ear/proc/on_irradiation(datum/act/A)
	var/datum/notice/in_range_of_irradiation/N = A
	log += "rad:[N.pulse_information]:[N.insulation_to_target]"

/datum/publish_ear/proc/on_shield(datum/act/A)
	var/datum/notice/living_shield_injury/N = A
	var/list/amount = N.amount_ref
	amount[1] = amount[1] * 0.5
	log += "shield:[N.kind]:[N.zone]"

/datum/publish_ear/proc/on_extinguish(datum/act/A)
	log += "extinguished"

/// Each converted notice carries its fields under their names, and a notice with no fields is heard.
/datum/unit_test/dq_publish_notice_fields/Run()
	var/datum/publish_ear/ear = allocate(/datum/publish_ear)
	PUBLISH(ear, atom_dir_change, old_dir = NORTH, new_dir = SOUTH)
	PUBLISH(ear, hitby, source_ = "rock", throwingdatum = "throw")
	PUBLISH(ear, in_range_of_irradiation, pulse_information = "pulse", insulation_to_target = 0.5)
	PUBLISH(ear, atom_extinguish)
	TEST_ASSERT_EQUAL(jointext(ear.log, ","), "dir:[NORTH]>[SOUTH],hitby:rock:throw,rad:pulse:0.5,extinguished", "each occurrence reached its listener at once with its fields")

/// Occurrences are never coalesced: back-to-back publishes of one type are all delivered, in publish order.
/datum/unit_test/dq_publish_notice_not_coalesced/Run()
	var/datum/publish_ear/ear = allocate(/datum/publish_ear)
	PUBLISH(ear, atom_dir_change, old_dir = NORTH, new_dir = EAST)
	PUBLISH(ear, atom_dir_change, old_dir = EAST, new_dir = NORTH)
	PUBLISH(ear, atom_dir_change, old_dir = NORTH, new_dir = EAST)
	TEST_ASSERT_EQUAL(jointext(ear.log, ","), "dir:[NORTH]>[EAST],dir:[EAST]>[NORTH],dir:[NORTH]>[EAST]", "three changes that end where the first did: all three delivered")

/// A handler that publishes from inside a delivery is answered at once: the nested notice is delivered before the handler's next line.
/datum/unit_test/dq_publish_notice_nested_in_order/Run()
	var/datum/publish_ear/ear = allocate(/datum/publish_ear)
	ear.republish = TRUE
	PUBLISH(ear, atom_entered, arrived = "crate", old_loc = "hall")
	TEST_ASSERT_EQUAL(jointext(ear.log, ","), "entered:crate<hall,exited:crate>nested,entered:done", "the nested publish was delivered inside the handler, in publish order")

/// The sender reads back what handlers wrote into a payload list (examine lines, a shield's scaled amount), including from a nested examine.
/datum/unit_test/dq_publish_notice_read_back/Run()
	var/datum/publish_ear/ear = allocate(/datum/publish_ear)
	var/list/texts = list("base")
	PUBLISH(ear, examine, user = "viewer", texts = texts)
	TEST_ASSERT_EQUAL(jointext(texts, "|"), "base|line from viewer", "the examine handler has appended its line when the sender reads the list back")
	ear.recurse_examine = TRUE
	texts = list("base")
	PUBLISH(ear, examine, user = "viewer", texts = texts)
	TEST_ASSERT_EQUAL(jointext(texts, "|"), "base|line from viewer|line from deeper", "a nested examine answered before its sender read the list")
	var/list/amount = list(10)
	PUBLISH(ear, living_shield_injury, kind = "burn", amount_ref = amount, zone = "chest", source_ = null, flags = 0)
	TEST_ASSERT_EQUAL(amount[1], 5, "the shield handler scaled the amount the injury goes on with")
