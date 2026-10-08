// A robot's look: one draw over tracked state (sprite_datum, stat, resting, opened, wiresexposed, lights_on, glowy_enabled, robotdecal_on,
// rest_style, vore_fullness_ex, vore_light_states, the active module types, the hat). Types with their own sprite sheet (drone, thinktank
// platform) override look_parts() instead of draw(): they replace the sprite datum's parts, they do not add to them.

TRACKED(/mob/living/silicon/robot, opened)
TRACKED(/mob/living/silicon/robot, wiresexposed)
TRACKED(/mob/living/silicon/robot, lights_on)
TRACKED(/mob/living/silicon/robot, glowy_enabled)
TRACKED(/mob/living/silicon/robot, rest_style)
TRACKED(/mob/living/silicon/robot, sprite_type)
TRACKED(/mob/living/silicon/robot, module_active)
TRACKED(/mob/living/silicon/robot, shell)
TRACKED(/mob/living/silicon/robot, deployed)

/mob/living/silicon/robot/draw(datum/look/look)
	..()
	look_parts(look)

/// The sprite parts of this robot. A type with its own sheet overrides this and does not call ..().
/mob/living/silicon/robot/proc/look_parts(datum/look/look)
	if(!sprite_datum)
		return
	look.watch(sprite_datum)
	look.watch(hat)
	look.watch(robot_belly)
	look.set_icon(sprite_datum.sprite_icon)
	look.state(sprite_datum.sprite_icon_state)
	if(stat == DEAD && sprite_datum.has_dead_sprite)
		look.state(sprite_datum.get_dead_sprite(src))
		if(sprite_datum.has_dead_sprite_overlay)
			look.overlay(sprite_datum.get_dead_sprite_overlay(src))
	else
		// Glow accents and decals. Emissive overlays go on first so everything else layers over them.
		if(sprite_datum.has_glow_sprites && glowy_enabled)
			look.overlay(look_appearance(sprite_datum.sprite_icon, sprite_datum.get_glow_overlay(src)))
			look.overlay(emissive_appearance(sprite_datum.sprite_icon, sprite_datum.get_glow_overlay(src)))
		if(LAZYLEN(robotdecal_on) && LAZYLEN(sprite_datum.sprite_decals) && has_eyes())
			for(var/enabled_decal in robotdecal_on)
				look.overlay(sprite_datum.get_robotdecal_overlay(src, enabled_decal))
		if(stat == CONSCIOUS)
			// Eyes, bellies, equipment, rest pose and eye lights.
			if(sprite_datum.has_eye_sprites && has_eyes())
				look.overlay(sprite_datum.get_eyes_overlay(src))
			for(var/belly_state in belly_look_states())
				look.overlay(belly_state)
			sprite_datum.look_extras(look, src) // Various equipment-based sprites go here.
			if(resting && sprite_datum.has_rest_sprites)
				look.state(sprite_datum.get_rest_sprite(src))
			if(lights_on && sprite_datum.has_eye_light_sprites && has_eyes())
				look.overlay(sprite_datum.get_eye_light_overlay(src))
	look.overlay(sprite_datum.get_open_sprite(src))
	look.overlay(hat_look())

/// The sprite changed (a module pick, a reset): what the new sprite sets on the body, once, here and not in every draw.
/mob/living/silicon/robot/proc/sprite_changed(datum/act/A)
	if(!sprite_datum)
		return
	vis_height = sprite_datum.vis_height
	if(default_pixel_x != sprite_datum.pixel_x)
		default_pixel_x	= sprite_datum.pixel_x
		pixel_x = sprite_datum.pixel_x
		old_x = sprite_datum.pixel_x
	if(!(rest_style in sprite_datum.rest_sprite_options))
		set_rest_style("Default")
	handle_status_indicators() // they sit over the sprite's top edge

/// Shell borgs that are not deployed have no eyes.
/mob/living/silicon/robot/has_eyes()
	return !shell || deployed

/// Fullness a belly class shows. Components (the sleeper belly) may adjust it.
/mob/living/silicon/robot/proc/belly_display_fullness(belly_class)
	var/list/fullness_ref = list(vore_fullness_ex[belly_class] || 0)
	PUBLISH_LEGACY(src, /datum/notice/robot_belly_fullness, belly_class, fullness_ref)
	return fullness_ref[1]

/// The belly overlays now shown, from the tracked fullness and belly lights.
/mob/living/silicon/robot/proc/belly_look_states()
	. = list()
	for(var/belly_class in vore_fullness_ex)
		var/vs_fullness = belly_display_fullness(belly_class)
		if(vs_fullness <= 0)
			continue
		var/belly_state
		if(resting)
			if(!sprite_datum.has_vore_belly_resting_sprites)
				continue
			belly_state = sprite_datum.get_belly_resting_overlay(src, vs_fullness, belly_class)
		else
			belly_state = sprite_datum.get_belly_overlay(src, vs_fullness, belly_class)
		if(glowy_enabled)
			. += look_appearance(sprite_datum.sprite_icon, belly_state, appearance_flags = KEEP_APART)
			. += emissive_appearance(sprite_datum.sprite_icon, belly_state)
		else
			. += belly_state

/// The sleeper indicator shows red while the belly is busy (see the belly component).
/mob/living/silicon/robot/proc/sleeper_red_light()
	var/datum/robot_belly/belly = robot_belly
	return belly?.sleeper_state == SLEEPER_STATE_BUSY

/// The light a belly class shows: 0 none, 1 red (a living prey is being digested), 2 green. Resting shows none.
/mob/living/silicon/robot/proc/belly_light(b_class)
	if(resting)
		return 0
	return LAZYACCESS(vore_light_states, b_class) || 0

/// vore_light_states, compared by content.
/mob/living/silicon/robot/proc/set_vore_light_states(list/value)
	if(!list_content_differs(value, vore_light_states))
		return FALSE
	vore_light_states = value
	tracked_changed(src, nameof(vore_light_states))
	return TRUE
SETTER(/mob/living/silicon/robot, vore_light_states)

/// The fullness is recomputed (a belly changed): the belly lights follow it.
/mob/living/silicon/robot/update_fullness()
	. = ..()
	set_vore_light_states(compute_belly_lights())

/mob/living/silicon/robot/proc/compute_belly_lights()
	if(!sprite_datum || !length(sprite_datum.belly_light_list))
		return null
	var/list/lights
	for(var/b_class in vore_fullness_ex)
		if(!LAZYFIND(sprite_datum.belly_light_list, b_class))
			continue
		var/light = 0
		if(vore_fullness_ex[b_class] > 0)
			light = 2
			for(var/obj/belly/B as anything in vore_organs)
				if(b_class == "sleeper" && !(B.silicon_belly_overlay_preference == "Vorebelly" || B.silicon_belly_overlay_preference == "Both"))
					continue
				if(B.digest_mode != DM_DIGEST || B.belly_sprite_to_affect != b_class || !contents_count(B))
					continue
				for(var/contents in contents_of(B))
					if(isliving(contents))
						light = 1
						break
				if(light == 1)
					break
		LAZYSET(lights, b_class, light)
	return lights

/// The hat, worn at the sprite's hat offset for the facing and pose.
/mob/living/silicon/robot/proc/hat_look()
	if(!hat)
		return null
	var/mutable_appearance/worn = hat.make_worn_icon(SPECIES_HUMAN, slot_head_str, default_icon = 'icons/inventory/head/mob.dmi', default_layer = 0)
	if(!worn)
		return null
	var/list/offset_list = resting ? sprite_datum.hat_offset[SPRITE_HAT_REST_OFFSET] : sprite_datum.hat_offset[SPRITE_HAT_OFFSET]
	if(islist(offset_list))
		var/list/offset = offset_list[isDiagonal(dir) ? dir2text(dir & (WEST|EAST)) : dir2text(dir)]
		if(offset)
			worn.pixel_x = offset[1]
			worn.pixel_y = offset[2]
	return worn

/// The module slots changed: the active types the look reads, and the melee modules' lights.
/mob/living/silicon/robot/proc/module_slots_changed(atom/movable/leaving)
	var/list/types
	for(var/obj/item/I in get_active_modules())
		if(I == leaving)
			continue
		LAZYADD(types, I.type)
		var/obj/item/melee/robotic/melee = I
		if(istype(melee))
			melee.refresh_light(TRUE)
	set_active_module_types(types)

/mob/living/silicon/robot/proc/set_active_module_types(list/value)
	if(!list_content_differs(value, active_module_types))
		return FALSE
	active_module_types = value
	tracked_changed(src, nameof(active_module_types))
	return TRUE
SETTER(/mob/living/silicon/robot, active_module_types)

/// The decals shown, compared by content.
/mob/living/silicon/robot/proc/set_robotdecal_on(list/value)
	if(!list_content_differs(value, robotdecal_on))
		return FALSE
	robotdecal_on = value
	tracked_changed(src, nameof(robotdecal_on))
	return TRUE
SETTER(/mob/living/silicon/robot, robotdecal_on)

/// The extra customisation of the sprite (a booze borg's drink), compared by content.
/mob/living/silicon/robot/proc/set_sprite_extra_customization(list/value)
	if(!list_content_differs(value, sprite_extra_customization))
		return FALSE
	sprite_extra_customization = value
	tracked_changed(src, nameof(sprite_extra_customization))
	return TRUE
SETTER(/mob/living/silicon/robot, sprite_extra_customization)

/// TRUE when two lists (plain or assoc) differ in length, entries or values.
/proc/list_content_differs(list/a, list/b)
	if(length(a) != length(b))
		return TRUE
	for(var/key in a)
		if(!(key in b))
			return TRUE
		if(!isnum(key) && !isnull(a[key]) && a[key] != b[key])
			return TRUE
	return FALSE
