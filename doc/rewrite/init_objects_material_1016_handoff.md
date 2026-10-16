# Material weapon initialization follow-up

Source-only proposal: 13 retained init baseline identities in /obj/item/material.
A global anchored search finds no descendant Initialize overrides; the only actual match is material_weapons.dm. This corrects the earlier blanket hierarchy caution for material weapons (which remains true for clothing).

The existing material setter and matter-scaling work move to native setup, ancestor-first. No field, constructor parameter, forced-material table, material reference policy, setter implementation or effect formula changes. The existing setter already deletes invalid materials; the callback stops on the same missing-material branch. setup_run stops dispatch when its holder is deleted. Existing descendant setup (notably ashtray prepare_dish) follows the new ancestor setup, preserving its material-ready input.

Two focused leaves assert real positional/type-default/forced-material precedence, tint, integrity, force, shard-specific setter dispatch, invalid rejection, borrowed material lifetime, twohanded force dispatch and ashtray setup ordering. No tests, generation or analyzer runs have occurred for this proposal. Root must wire dq_init_objects_material_tests.dm.
