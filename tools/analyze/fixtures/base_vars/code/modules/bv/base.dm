// Base-type vars: every BASE_TYPES entry, with the modifiers that cost nothing per instance.
/atom
	var/atom_plain = 1
	var/static/atom_static = 2
	var/const/atom_const = 3
	var/global/atom_global = 4
	var/tmp/atom_tmp = 5
	var/final/atom_final = 6
	var/atom_kept = 7 // ALLOW(base_vars): the fixture keeps this base var on purpose
	// ALLOW(base_vars): the fixture keeps the next base var from the comment line above
	var/atom_kept_above = 8
	var/atom_noreason = 9 // ALLOW(base_vars)
	var/atom_wrong_name = 10 // ALLOW(instance_list): names the other lint, so the base var still counts
	var/atom_two_names = 11 // ALLOW(init, base_vars): two names on one annotation
/atom/movable
	var/mv = 1
/obj
	var/obj_plain
	var/list/obj_list = list()
/obj/item
	var/item_plain
/obj/machinery
	var/mach_plain
/mob
	var/mob_plain
	var/dupe
/mob/living
	var/living_plain
	var/dupe
/mob/living/carbon
	var/carbon_plain
/mob/living/carbon/human
	var/human_plain
/mob/living/carbon/human/sub
	var/not_a_base_type
/obj/items
	var/also_not_base
/datum/obj
	var/not_base_either
// A var block: every member is a var of the owner, with the block's modifiers.
/obj
	var
		blockvar_a = 1
		static/blockvar_s = 2
		list/blockvar_l = list()
	var/tmp
		tmpblock_a
		tmpblock_l = list()
	var/static
		static_block_a
		static_block_l = list()
/obj/proc/a_proc()
	var/proc_local = 1
	var/list/proc_list = list()
/obj/var/base_path_decl = 3
/obj/thing/var/list/path_decl = list()
/obj/thing/var/static/list/path_decl_static = list()
/mob/verb/a_verb()
	var/verb_local = 1
