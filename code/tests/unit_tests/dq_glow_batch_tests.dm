// set_glow() writes the light's parts in one trait write and reconciles the source once. These tests hold it to the per-part setters it replaced:
// the same trait values, switch, return value and light source, and the same legacy notices with the same old values in the same order.

/// A probe that records the legacy light notices it hears.
/obj/structure/dq_glow_batch_probe
	name = "glow batch probe"
	var/list/heard

CAPABILITIES(/obj/structure/dq_glow_batch_probe)
	on_notice(/datum/notice/atom_update_light_power, then(PROC_REF(hear_power)))
	on_notice(/datum/notice/atom_update_light_range, then(PROC_REF(hear_range)))
	on_notice(/datum/notice/atom_update_light_color, then(PROC_REF(hear_color)))
	on_notice(/datum/notice/atom_update_light_on, then(PROC_REF(hear_on)))

/obj/structure/dq_glow_batch_probe/proc/hear_power(datum/act/notice/A)
	var/datum/notice/atom_update_light_power/N = A
	LAZYADD(heard, "power:[N.old_power]")

/obj/structure/dq_glow_batch_probe/proc/hear_range(datum/act/notice/A)
	var/datum/notice/atom_update_light_range/N = A
	LAZYADD(heard, "range:[N.old_range]")

/obj/structure/dq_glow_batch_probe/proc/hear_color(datum/act/notice/A)
	var/datum/notice/atom_update_light_color/N = A
	LAZYADD(heard, "color:[N.old_color]")

/obj/structure/dq_glow_batch_probe/proc/hear_on(datum/act/notice/A)
	var/datum/notice/atom_update_light_on/N = A
	LAZYADD(heard, "on:[N.old_value]")

/// The old set_glow(): the four setters one after another.
/proc/dq_glow_legacy_set(atom/A, list/glow, on = null)
	var/range = length(glow) >= 1 ? glow[1] : null
	var/power = length(glow) >= 2 ? glow[2] : null
	var/color = length(glow) >= 3 ? glow[3] : null
	if(range > 0 && range < MINIMUM_USEFUL_LIGHT_RANGE)
		range = MINIMUM_USEFUL_LIGHT_RANGE
	if(isnull(on) && !isnull(range))
		on = range > 0
	var/changed = FALSE
	if(!isnull(power) && A.set_light_power(power) != null)
		changed = TRUE
	if(!isnull(range) && A.set_light_range(range) != null)
		changed = TRUE
	if(!isnull(color) && A.set_light_color(color) != null)
		changed = TRUE
	if(!isnull(on) && A.set_light_on(on) != null)
		changed = TRUE
	return changed

/datum/unit_test/dq_glow_batch_parity

/datum/unit_test/dq_glow_batch_parity/Run()
	var/list/steps = list(
		list(3, 1, "#ff0000"), list(3, 1, "#ff0000"), list(2, 0.5, null), list(0, 0, null), list(5, null, "#00ff00"),
		list(null, 2, null), list(0.5, 1, "#ffffff"), list(null, null, "#123456"), list(4), list(0),
	)
	var/obj/structure/dq_glow_batch_probe/fast = allocate(/obj/structure/dq_glow_batch_probe, test_floor())
	var/obj/structure/dq_glow_batch_probe/slow = allocate(/obj/structure/dq_glow_batch_probe, test_floor())
	var/index = 0
	for(var/list/glow as anything in steps)
		index++
		var/fast_changed = set_glow(fast, glow)
		var/slow_changed = dq_glow_legacy_set(slow, glow)
		var/datum/type_trait/light_glow/f = glow_of(fast)
		var/datum/type_trait/light_glow/s = glow_of(slow)
		TEST_ASSERT_EQUAL(fast_changed, slow_changed, "step [index]: the return value")
		TEST_ASSERT_EQUAL(f.range, s.range, "step [index]: range")
		TEST_ASSERT_EQUAL(f.power, s.power, "step [index]: power")
		TEST_ASSERT_EQUAL(f.color, s.color, "step [index]: color")
		TEST_ASSERT_EQUAL(fast.light_on, slow.light_on, "step [index]: the switch")
		TEST_ASSERT_EQUAL(!!fast.light, !!slow.light, "step [index]: the light source exists alike")
		TEST_ASSERT_EQUAL(json_encode(fast.heard), json_encode(slow.heard), "step [index]: the notices heard, in order, with their old values")
