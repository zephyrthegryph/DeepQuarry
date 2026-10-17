// Fixtures for the quantity slot (code/modules/unit_tests/dq_slot_quantity_tests.dm): a bay whose limit is a var of the holder and that
// takes a thing by units.

/obj/qty_fixture
	name = "quantity bay holder"
	/// The bay's limit, in units: per instance (slot(capacity = nameof(bay_room))).
	var/bay_room = 5

CAPABILITIES(/obj/qty_fixture)
	slot("qty_bay", accepts = /obj/item/stack, capacity = nameof(bay_room), unit = SLOT_CAPACITY_UNITS, quantity = TRUE)
	slot("qty_whole", capacity = 2)

/obj/qty_fixture/proc/set_bay_room(value)
	if(TRACKED_UNCHANGED(bay_room, value))
		return FALSE
	bay_room = value
	tracked_changed(src, nameof(bay_room))
	return TRUE
SETTER(/obj/qty_fixture, bay_room)
