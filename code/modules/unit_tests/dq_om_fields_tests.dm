// Declared fields (code/datums/om/fields.dm, object_model_core.md §5.1): setters raise the
// declared channel once per change, and every stage's wake_on covers what it reads.

/datum/om_field_test_entity

OM_FIELD(/datum/om_field_test_entity, level, 0, CHANGE_DATUM_A)

/// Every stage and behaviour that reads a declared field is woken by that field's channel.
/datum/unit_test/dq_om_declared_fields_cover_reads

/datum/unit_test/dq_om_declared_fields_cover_reads/Run()
	var/datum/om/registry/reg = om_registry()
	var/list/problems = reg.check_field_reads()
	TEST_ASSERT(!length(problems), "declared field reads not covered by wake_on: [jointext(problems, "; ")]")
	var/list/pump_fields = reg.fields_of(/obj/machinery/portable_atmospherics/powered/pump)
	TEST_ASSERT_EQUAL(pump_fields["on"], CHANGE_MACHINE_SETTINGS, "the pump's on field channel")

/// A setter writes and raises the declared channel, once per change and never when unchanged.
/datum/unit_test/dq_om_field_setter_raises

/datum/unit_test/dq_om_field_setter_raises/Run()
	var/datum/om_field_test_entity/E = allocate(/datum/om_field_test_entity)
	var/datum/om/rec/rec = om_rec_of(E)
	var/datum/om/scheduler/sched = rec.sched
	E.om_listen |= CHANGE_DATUM_A
	sched.test_raises = list()
	TEST_ASSERT(E.set_level(5), "a change returned FALSE")
	TEST_ASSERT(!E.set_level(5), "an unchanged value returned TRUE")
	TEST_ASSERT(E.set_level(6), "a second change returned FALSE")
	TEST_ASSERT_EQUAL(E.level, 6, "the field was not written")
	var/raised = 0
	for(var/list/raise as anything in sched.test_raises)
		if(raise[1] == E && (raise[2] & CHANGE_DATUM_A))
			raised++
	sched.test_raises = null
	TEST_ASSERT_EQUAL(raised, 2, "raises for two changes and one no-op")
