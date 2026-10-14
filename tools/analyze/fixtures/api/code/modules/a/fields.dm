OM_FIELD(/obj/machinery/thing, on, FALSE, CHANGE_X)
OM_FIELD_TYPED(/obj/machinery/thing, /list, items, null, CHANGE_Y)
OM_FLAG_FIELD(/obj/machinery/thing, flags_x, 0, CHANGE_Z)
OM_FLAG_FIELD_BITS(/mob/living, bits, 0, CHANGE_Z)
OM_FIELD_SETTER(/obj/item/gizmo, charge, CHANGE)
OM_FIELD(/mob/living/carbon, mode, 0, CH)
OM_FIELD(/obj/item/other, on, 0, CH)
OM_FIELD(/obj/item/other, active_thing, 0, CH)
GLOBAL_DATUM(thing_glob, /obj/machinery/thing)
GLOBAL_DATUM_INIT(carbon_glob, /mob/living/carbon, new)

/obj/machinery/thing
	var/obj/machinery/other/partner
	var/mob/living/carbon/pilot
	var/datum/gizmo/helper
	var/tmp/obj/item/other/held
	var/static/obj/machinery/thing/twin
	var/on_plain

/obj/machinery/other
	var/on
	var/mob/living/carbon/rider
	var/obj/machinery/thing/back

/obj/machinery/thing/var/obj/item/other/abs_member

/obj/machinery/thing/proc/set_on(v)
	on = v
	src.on = v
	return 1

/obj/machinery/thing/proc/flags_x_add(v)
	flags_x |= v

/obj/machinery/thing/proc/flags_x_remove(v)
	flags_x &= ~v

/obj/machinery/thing/sub/proc/set_on(v)
	on = v

/obj/machinery/thing/proc/poke(M, x)
	on = TRUE
	src.on = FALSE
	on |= 1
	on &= 2
	on ^= 3
	on += 4
	on -= 5
	on *= 6
	on /= 7
	on++
	on--
	on == 1
	on = 1 == 2
	to_chat(M, "on = 1")
	// on = 1
	var on = 2
	var/on_local = 1
	foo(on = 1)
	foo(a, on = 1)
	x = list(a, on = 1)
	y = list(
		on = 1,
		items = 2,
	)
	z = list(
		on = 1
	)
	partner.on = TRUE
	pilot.on = 1
	helper.on = 1
	held.on = 1
	twin.on = 1
	abs_member.on = 1
	unknown.on = 1
	M.on = 1
	other_thing?.on = 1
	GLOB.thing_glob.on = 1
	GLOB.carbon_glob.on = 1
	GLOB.missing_glob.on = 1
	partner.back.on = 1
	partner.rider.on = 1
	partner.nothing.on = 1
	src.partner.on = 1
	src.twin.on = 1
	src.pilot.on = 1
	partner?.back.on = 1
	partner.on == 1
	thing.on = 1 == 2
	thing.on=1
	thing.on  =  1
	thing.on |= 1
	thing.on++
	thing.on--
	thing.items = list()
	thing.items[1] = 2
	thing.flags_x |= 4
	thing.bits = 1
	thing.charge = 2
	thing.mode = 3
	thing.on_plain = 4
	on_plain = 4
	thing.on = 1 // ALLOW(api): fixture keep
	// ALLOW(api): fixture keep above
	thing.on = 1
	on = 2 // ALLOW(api): bare keep
	var/obj/item/other/it = x
	it.on = 1
	var/mob/living/carbon/rv = x
	rv.on = 1
	var/obj/machinery/thing/tt = x
	tt.on = 1
	var/datum/gizmo/gz = x
	gz.on = 1
	gz.charge = 1

/obj/machinery/thing/proc/shadow(on)
	on = 1
	src.on = 2
	thing.on = 3

/obj/machinery/thing/proc/shadow_typed(obj/item/other/it, mob/living/m, untyped_a, untyped_b = 5)
	it.on = 1
	m.on = 1
	untyped_a.on = 1
	untyped_b = 2
	on = 4

/obj/machinery/thing/proc/shadow_var()
	var/on = 1
	on = 2
	var/tmp/items
	items = 3
	var/static/mode
	mode = 4
	var/obj/mode_thing
	flags_x = 1

/obj/proc/obj_writer()
	on = 1
	items = 2
	charge = 3
	mode = 4

/obj/item/gizmo/proc/gizmo_writer()
	charge = 1
	on = 1

/obj/item/gizmo/proc/set_charge(v)
	charge = v

/mob/living/proc/living_writer()
	mode = 1
	bits = 2
	on = 3

/mob/living/carbon/human/proc/human_writer()
	mode = 1
	bits = 2

/mob/living/carbon/proc/set_mode(v)
	mode = v

/mob/living/proc/set_mode(v)
	mode = v

/area/proc/area_writer()
	on = 1

/atom/proc/atom_writer()
	on = 1
	charge = 2

/datum/proc/datum_writer()
	on = 1
	mode = 2

/proc/global_writer()
	on = 1
	mode = 2

/obj/machinery/thing/verb/verb_writer()
	on = 1

/obj/machinery/thing/Initialize(mapload)
	on = TRUE
	mode = 1
	return ..()

/obj/machinery/thing/New()
	on = FALSE

#define WRITE_ON on = 1
/obj/machinery/thing/proc/after_define()
	on = 1

/obj/machinery/thing/proc/after_blank(a)
	on = 1

junk_line_resets_owner
	on = 1

/obj/machinery/thing/proc/line_continuation(a)
	var/obj/machinery/other/o = a
	o.on = 1
	var/obj/machinery/other/o2 = a
	o2.back.on = 1
	o2.back.back.on = 1
