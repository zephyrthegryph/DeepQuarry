// Robot mob-state writers that used to clobber other contributors (no source
// tracking). See doc/rewrite roadmap.
//
// - robot_modules/station.dm's remove_status_flags() unconditionally OR'd
//   CANPUSH back into status_flags on module removal, regardless of whether
//   some other source also wanted the robot unpushable. Fixed by tracking
//   push-disabling sources (code/modules/mob/_push_sources.dm) and only
//   restoring CANPUSH once every source has withdrawn.
// - The VTEC upgrade (robot_upgrades.dm) added a verb with no removal path,
//   so a robot kept toggle_vtec forever even after a module reset. Fixed by
//   giving upgrades an uninstall() hook, called from module_reset().

/datum/unit_test/dq_robot_module_swap_does_not_clobber_other_push_disable_source

/datum/unit_test/dq_robot_module_swap_does_not_clobber_other_push_disable_source/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)

	TEST_ASSERT(R.status_flags & CANPUSH, "a fresh robot should be pushable by default")

	// Some other, unrelated source (an anchoring effect, a trait, whatever)
	// independently wants the robot unpushable.
	var/datum/anchor = new
	R.add_push_disable_source(anchor)
	TEST_ASSERT(!(R.status_flags & CANPUSH), "an independent push-disable source should clear CANPUSH")

	// A robot module that also disables pushing is installed, then removed
	// (e.g. via a module swap/reset).
	var/obj/item/robot_module/module = new(R)
	TEST_ASSERT_EQUAL(module.can_be_pushed, 0, "the base robot module should disable pushing by default (precondition for this test)")
	TEST_ASSERT(!(R.status_flags & CANPUSH), "installing a second push-disabling source should leave CANPUSH cleared")

	module.remove_status_flags(R)
	TEST_ASSERT(!(R.status_flags & CANPUSH), "removing the module's own push-disable source must not clobber the other still-active source's CANPUSH suppression")

	// Now the other source withdraws too -- only now should CANPUSH return.
	R.remove_push_disable_source(anchor)
	qdel(anchor)
	TEST_ASSERT(R.status_flags & CANPUSH, "once every push-disable source has withdrawn, CANPUSH should be restored")

	qdel(module)

/datum/unit_test/dq_robot_vtec_upgrade_has_a_removal_path

/datum/unit_test/dq_robot_vtec_upgrade_has_a_removal_path/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/obj/item/borg/upgrade/basic/vtec/proto = robot_upgrade_prototype(/obj/item/borg/upgrade/basic/vtec)
	TEST_ASSERT_NOTNULL(proto, "the VTEC upgrade prototype should resolve")

	// Simulate the upgrade having been installed (mirrors what action() does).
	R.grant_ability(ABILITY_ID_ROBOT_TOGGLE_VTEC, R)
	R.vtec_active = TRUE
	TEST_ASSERT(proto.is_installed(R), "VTEC should be detected as installed once its verb is present")

	proto.remove_upgrade(R)
	TEST_ASSERT(!proto.is_installed(R), "uninstall() should remove the toggle_vtec verb")
	TEST_ASSERT(!R.vtec_active, "uninstall() should turn off vtec_active so no lingering speed bonus remains")

/// The removal path must actually be wired into module_reset(), not just exist.
/datum/unit_test/dq_robot_module_reset_uninstalls_vtec

/datum/unit_test/dq_robot_module_reset_uninstalls_vtec/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/obj/item/borg/upgrade/basic/vtec/proto = robot_upgrade_prototype(/obj/item/borg/upgrade/basic/vtec)

	R.grant_ability(ABILITY_ID_ROBOT_TOGGLE_VTEC, R)
	R.vtec_active = TRUE
	TEST_ASSERT(proto.is_installed(R), "VTEC should be installed before the reset")

	R.set_hud_used(new /datum/hud(R)) // module_reset() needs a HUD to update; test mobs have no client to build one automatically.
	new /obj/item/robot_module(R)
	R.module_reset(notify = FALSE)

	TEST_ASSERT(!proto.is_installed(R), "module_reset() should uninstall VTEC along with the module, not leave the verb behind")
	TEST_ASSERT(!R.vtec_active, "module_reset() should clear vtec_active")
	own_turf_contents(get_turf(R)) // the reset plays smoke and fade effects
