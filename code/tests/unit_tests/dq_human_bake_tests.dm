// The human look's off-thread bakes (code/content/mob/living/carbon/human/human_bake.dm): a wound's picture and an animated tail's facing split are
// composed by iconforge, not by /icon operations in a draw. The first group proves the baked pictures equal what the /icon builders made, pixel for pixel;
// the second that a draw makes no /icon operation, shows the part once its bake lands, and bakes one limb for one wound.

#define DQ_HB_ROUNDING 1

/// How many pixels differ between the legacy picture `legacy` (an /icon) and the baked DMI `path` (state HUMAN_BAKE_STATE), over `dirs` facings and `frames` frames.
/datum/unit_test/proc/dq_hb_pixel_diff(icon/legacy, path, list/dirs, frames = 1)
	. = 0
	var/icon/baked = icon(file(path))
	for(var/facing in dirs)
		for(var/frame in 1 to frames)
			var/icon/a = icon(legacy, dir = facing, frame = frame)
			var/icon/b = icon(baked, HUMAN_BAKE_STATE, facing, frame)
			if(a.Width() != b.Width() || a.Height() != b.Height())
				return INFINITY
			for(var/x in 1 to a.Width())
				for(var/y in 1 to a.Height())
					var/pa = a.GetPixel(x, y)
					var/pb = b.GetPixel(x, y)
					if(pa == pb)
						continue
					// Iconforge and BYOND round a multiplied channel differently now and then (one level): counted as parity when no channel differs by more.
					var/list/ca = pa ? rgb2num(pa, COLORSPACE_RGB) : list(0, 0, 0, 0)
					var/list/cb = pb ? rgb2num(pb, COLORSPACE_RGB) : list(0, 0, 0, 0)
					if(length(ca) < 4)
						ca += 255
					if(length(cb) < 4)
						cb += 255
					var/worst = 0
					for(var/i in 1 to 4)
						worst = max(worst, abs(ca[i] - cb[i]))
					if(worst > DQ_HB_ROUNDING)
						if(!.)
							TEST_NOTICE(src, "first differing pixel dir [facing] frame [frame] at [x],[y]: legacy [pa] baked [pb]")
						.++

/// A human of `species` with the damage states of `limbs` (tag -> state) set, drawn.
/datum/unit_test/proc/dq_hb_wounded(species, list/limbs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(species)
	for(var/tag in limbs)
		var/obj/item/organ/external/limb = H.limb_tagged(tag)
		limb.set_damage_state(limbs[tag])
	refresh_flush()
	return H

/// A wound's baked picture is the one the /icon builder made: every pixel of every facing, for several limbs, states, species and blood colours.
/datum/unit_test/dq_human_bake_wound_pixel_parity

/datum/unit_test/dq_human_bake_wound_pixel_parity/Run()
	var/list/cases = list(
		list(SPECIES_HUMAN, BP_TORSO, "10"),
		list(SPECIES_HUMAN, BP_TORSO, "33"),
		list(SPECIES_HUMAN, BP_L_ARM, "21"),
		list(SPECIES_HUMAN, BP_HEAD, "02"),
		list(SPECIES_TAJARAN, BP_R_LEG, "13"),
		list(SPECIES_UNATHI, BP_GROIN, "30"),
	)
	var/checked = 0
	for(var/list/case as anything in cases)
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
		H.set_species(case[1])
		var/obj/item/organ/external/limb = H.limb_tagged(case[2])
		if(!limb)
			continue
		var/part = "[case[3]]/[limb.icon_name]"
		var/blood = H.species.get_blood_colour(H)
		var/path = human_bake_blocking(H.damage_sprite(H.species.get_damage_overlays(H), H.species.get_damage_mask(H), blood, part), "test_wound_[checked]")
		TEST_ASSERT(path, "the wound [part] of a [case[1]] baked")
		if(!path)
			continue
		var/diff = dq_hb_pixel_diff(H.build_damage_part(part, blood), path, GLOB.cardinal)
		fdel(path)
		TEST_ASSERT_EQUAL(diff, 0, "the baked wound [part] of a [case[1]] (blood [blood]) differs from the /icon build in [diff] pixels")
		checked++
	TEST_ASSERT(checked >= 4, "the parity cases ran ([checked])")

/// A tail's baked facing split is the one icon_keep_dirs() made: every frame of every facing, and the frame delays.
/datum/unit_test/dq_human_bake_tail_dirs_pixel_parity

/datum/unit_test/dq_human_bake_tail_dirs_pixel_parity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_TAJARAN)
	var/tail_file = H.species.get_tail_animation(H)
	TEST_ASSERT(tail_file, "an animated tail species")
	var/state = "[H.species.get_tail(H)]_idle0"
	var/frames = 1
	var/list/source_delays
	for(var/list/state_data as anything in icon_metadata(tail_file)?["states"])
		if(state_data["name"] == state)
			frames = length(state_data["delay"]) || 1
			source_delays = state_data["delay"]
	TEST_ASSERT(frames > 1, "the idle tail has frames ([frames]): [json_encode(icon_metadata(tail_file))]")
	var/n = 0
	for(var/list/dirs in list(list(SOUTH, EAST, WEST), list(NORTH), list(EAST, WEST)))
		var/list/sprite = H.tail_dirs_sprite(tail_file, state, dirs)
		TEST_ASSERT(sprite, "a facing split of the tail has a sprite")
		var/path = human_bake_blocking(sprite, "test_tail_[n++]")
		TEST_ASSERT(path, "the tail split [jointext(dirs, ",")] baked")
		if(!path)
			continue
		var/diff = dq_hb_pixel_diff(icon_keep_dirs(icon(tail_file, state), dirs), path, GLOB.cardinal, frames)
		TEST_ASSERT_EQUAL(diff, 0, "the baked tail ([jointext(dirs, ",")], [frames] frames) differs from icon_keep_dirs() in [diff] pixels")
		var/list/baked_delays
		for(var/list/state_data as anything in icon_metadata(path)?["states"])
			if(state_data["name"] == HUMAN_BAKE_STATE)
				baked_delays = state_data["delay"]
		TEST_ASSERT_EQUAL(json_encode(baked_delays), json_encode(source_delays), "the baked tail keeps the frame delays")
		fdel(path)

/// Waits for every queued bake to land (kernel time), at most `limit` seconds.
/datum/unit_test/proc/dq_hb_settle(limit = 20)
	for(var/i in 1 to limit * 4)
		if(!length(GLOB.human_baker.pending))
			break
		test_time(0.25 SECONDS)
	refresh_flush()

/// Drawing a wounded human makes no /icon operation: the wound layer is empty while its bakes run, and whole once they land, again with no /icon operation.
/datum/unit_test/dq_human_bake_wounds_draw_without_icon_operations

/datum/unit_test/dq_human_bake_wounds_draw_without_icon_operations/Run()
	test_driver_begin()
	var/ops = GLOB.human_look_icon_ops
	var/landed = GLOB.human_baker.landed
	var/mob/living/carbon/human/H = dq_hb_wounded(SPECIES_HUMAN, list(BP_TORSO = "21", BP_L_ARM = "10"))
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "drawing a wounded human made /icon operations: [human_look_stats_line()]")
	dq_hb_settle()
	TEST_ASSERT(GLOB.human_baker.landed - landed >= 2, "the wound bakes landed ([GLOB.human_baker.landed - landed]): [human_look_stats_line()]")
	var/list/layers = H.look_layers()
	var/image/wounds = layers[MOB_DAM_LAYER]
	TEST_ASSERT(wounds, "the wound layer shows once the bakes landed")
	TEST_ASSERT_EQUAL(length(wounds?.overlays), 2, "one picture per wounded limb")
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "showing the baked wounds made /icon operations: [human_look_stats_line()]")
	// One wound changing bakes one limb only.
	var/asked = GLOB.human_baker.asked
	H.limb_tagged(BP_L_ARM).set_damage_state("22")
	refresh_flush()
	dq_hb_settle()
	TEST_ASSERT_EQUAL(GLOB.human_baker.asked - asked, 1, "a wound change on one limb asked for [GLOB.human_baker.asked - asked] bakes: [human_look_stats_line()]")
	TEST_ASSERT_EQUAL(length(H.look_layers()[MOB_DAM_LAYER]?.overlays), 2, "both wounds still show")
	// Another human with the same wound shares the bake.
	asked = GLOB.human_baker.asked
	dq_hb_wounded(SPECIES_HUMAN, list(BP_TORSO = "21"))
	TEST_ASSERT_EQUAL(GLOB.human_baker.asked, asked, "a second body with a known wound baked again: [human_look_stats_line()]")
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "the wound draws made /icon operations: [human_look_stats_line()]")
	test_driver_end()

/// An animated tail draws with no /icon operation: it shows once its facing split is baked, and the bake is shared by every body with that tail.
/datum/unit_test/dq_human_bake_animated_tail_draws_without_icon_operations

/datum/unit_test/dq_human_bake_animated_tail_draws_without_icon_operations/Run()
	test_driver_begin()
	var/ops = GLOB.human_look_icon_ops
	var/landed = GLOB.human_baker.landed
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_TAJARAN)
	H.set_tail_anim_state("[H.species.get_tail(H)]_idle0")
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "drawing an animated tail made /icon operations: [human_look_stats_line()]")
	dq_hb_settle()
	TEST_ASSERT(GLOB.human_baker.landed > landed, "the tail's bakes landed: [human_look_stats_line()]")
	var/list/layers = H.look_layers()
	TEST_ASSERT(layers[TAIL_LOWER_LAYER] || layers[TAIL_UPPER_LAYER], "the tail shows once its bakes landed")
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "showing the baked tail made /icon operations: [human_look_stats_line()]")
	var/asked = GLOB.human_baker.asked
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	other.set_species(SPECIES_TAJARAN)
	other.set_tail_anim_state("[other.species.get_tail(other)]_idle0")
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.human_baker.asked, asked, "a second body with the same tail baked again: [human_look_stats_line()]")
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "the second tail's draw made /icon operations: [human_look_stats_line()]")
	test_driver_end()
