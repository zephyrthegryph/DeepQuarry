///For switchable lights, is it on and currently emitting light?
#define LIGHTING_ON (1<<0)
///Is the parent attached to something else, its loc? Then we need to keep an eye of this.
#define LIGHTING_ATTACHED (1<<1)

#define GET_PARENT (parent_attached_to() || owner)

#define GET_LIGHT_SOURCE (directional_atom || current_holder())

#define SHORT_CAST 2

/**
 * Movable atom overlay-based lighting. An owned datum held in /atom/movable/var/overlay_light.
 *
 * * Component works by applying a visual object to the parent target.
 *
 * * The component tracks the parent's loc to determine the current_holder.
 * * The current_holder is either the parent or its loc, whichever is on a turf. If none, then the current_holder is null and the light is not visible.
 *
 * * Lighting works at its base by applying a dark overlay and "cutting" said darkness with light, adding (possibly colored) transparency.
 * * This component uses the visible_mask visual object to apply said light mask on the darkness.
 *
 * * The main limitation of this system is that it uses a limited number of pre-baked geometrical shapes, but for most uses it does the job.
 *
 * * Another limitation is for big lights: you only see the light if you see the object emiting it.
 * * For small objects this is good (you can't see them behind a wall), but for big ones this quickly becomes prety clumsy.
*/
/datum/overlay_lighting
	///The movable atom that owns this light (was the component parent).
	var/atom/movable/owner
	///How far the light reaches, float.
	var/range = 1
	///Ceiling of range, integer without decimal entries.
	var/lumcount_range = 0
	///How much this light affects the dynamic_lumcount of turfs.
	var/lum_power = 0.5
	///Transparency value.
	var/set_alpha = 0
	///For light sources that can be turned on and off.
	var/overlay_lighting_flags = NONE

	///Cache of the possible light overlays, according to size.
	var/static/list/light_overlays = list(
		"32" = 'icons/effects/light_overlays/light_32.dmi',
		"64" = 'icons/effects/light_overlays/light_64.dmi',
		"96" = 'icons/effects/light_overlays/light_96.dmi',
		"128" = 'icons/effects/light_overlays/light_128.dmi',
		"160" = 'icons/effects/light_overlays/light_160.dmi',
		"192" = 'icons/effects/light_overlays/light_192.dmi',
		"224" = 'icons/effects/light_overlays/light_224.dmi',
		"256" = 'icons/effects/light_overlays/light_256.dmi',
		"288" = 'icons/effects/light_overlays/light_288.dmi',
		"320" = 'icons/effects/light_overlays/light_320.dmi',
		"352" = 'icons/effects/light_overlays/light_352.dmi',
		)

	///Overlay effect to cut into the darkness and provide light.
	var/obj/effect/overlay/light_visible/visible_mask
	///Lazy list to track the turfs being affected by our light, to determine their visibility.
	var/list/turf/affected_turfs
	///Movable atom currently holding the light. Parent might be a flashlight, for example, but that might be held by a mob or something else.
	var/atom/movable/current_holder
	///Movable atom the parent is attached to. For example, a flashlight into a helmet or gun. We'll need to track the thing the parent is attached to as if it were the parent itself.
	var/atom/movable/parent_attached_to
	///Whether we're a directional light
	var/directional
	///Abstractional atom for directional light, we move this around to make the directional effect
	var/obj/effect/abstract/directional_lighting/directional_atom
	///A cone overlay for directional light, it's alpha and color are dependant on the light
	var/obj/effect/overlay/light_cone/cone
	///Current tracked direction for the directional cast behaviour
	var/current_direction
	///Cast range for the directional cast (how far away the atom is moved)
	var/cast_range = 2
	///Cone offset X hint from atom, used when facing south, inverted when facing north
	var/cone_hint_x
	///Cone offset Y hint from atom, when facing east/west, ignored for north/south (uses 16 in those cases)
	var/cone_hint_y

CAPABILITIES(/datum/overlay_lighting)
	owns_one(nameof(cone), /obj/effect/overlay/light_cone)
	owns_one(nameof(directional_atom), /obj/effect/abstract/directional_lighting)
	owns_one(nameof(visible_mask), /obj/effect/overlay/light_visible)

/// Creates and attaches the overlay light of `new_owner` (stored in new_owner.overlay_light).
/// Returns null when new_owner cannot have one.
/proc/add_overlay_lighting(atom/movable/new_owner, _range, _power, _color, starts_on, is_directional)
	if(!ismovable(new_owner))
		return null
	if(new_owner.light_system != MOVABLE_LIGHT && new_owner.light_system != MOVABLE_LIGHT_DIRECTIONAL)
		stack_trace("/datum/overlay_lighting added to [new_owner], with [new_owner.light_system] value for the light_system var. Use [MOVABLE_LIGHT] or [MOVABLE_LIGHT_DIRECTIONAL] instead.")
		return null
	if(new_owner.overlay_light)
		return new_owner.overlay_light
	var/datum/overlay_lighting/light = new(new_owner, _range, _power, _color, starts_on, is_directional)
	rel_set(new_owner, nameof(new_owner.overlay_light), light)
	light.attach()
	return light

/datum/overlay_lighting/New(atom/movable/new_owner, _range, _power, _color, starts_on, is_directional)
	..()
	rel_set(src, nameof(owner), new_owner)
	var/atom/movable/movable_parent = owner

	rel_set(src, nameof(visible_mask), new /obj/effect/overlay/light_visible())
	if(is_directional)
		directional = TRUE
		rel_set(src, nameof(directional_atom), new /obj/effect/abstract/directional_lighting())
		rel_set(src, nameof(cone), new /obj/effect/overlay/light_cone())
		cone_hint_x = movable_parent.light_cone_x_offset
		cone_hint_y = movable_parent.light_cone_y_offset
		set_direction(movable_parent.dir)
	if(!isnull(_range))
		movable_parent.set_light_range(_range)
	set_range(owner, movable_parent.light_range)
	if(!isnull(_power))
		movable_parent.set_light_power(_power)
	set_power(owner, movable_parent.light_power)
	if(!isnull(_color))
		movable_parent.set_light_color(_color)
	set_color(owner, movable_parent.light_color)
	if(!isnull(starts_on))
		movable_parent.set_light_on(starts_on)

/// Hooks the owner's events and starts tracking its holder (was RegisterWithParent).
/datum/overlay_lighting/proc/attach()
	if(directional)
		observe(owner, /datum/notice/atom_dir_change, src, then(PROC_REF(on_parent_dir_change)))
	observe(owner, /datum/notice/moved, src, then(PROC_REF(on_parent_moved_event)))
	observe(owner, /datum/notice/atom_update_light_range, src, then(PROC_REF(on_range_event)))
	observe(owner, /datum/notice/atom_update_light_power, src, then(PROC_REF(on_power_event)))
	observe(owner, /datum/notice/atom_update_light_color, src, then(PROC_REF(on_color_event)))
	observe(owner, /datum/notice/atom_update_light_on, src, then(PROC_REF(on_toggle)))
	observe(owner, /datum/notice/atom_update_light_flags, src, then(PROC_REF(on_light_flags_change)))
	observe(owner, /datum/notice/atom_used_in_craft, src, then(PROC_REF(on_parent_crafted)))
	var/atom/movable/movable_parent = owner
	if(movable_parent.light_flags & LIGHT_ATTACHED)
		overlay_lighting_flags |= LIGHTING_ATTACHED
		set_parent_attached_to(ismovable(movable_parent.loc) ? movable_parent.loc : null)
	check_holder()
	if(movable_parent.light_on)
		turn_on()

/// Unhooks the owner and removes the light (was UnregisterFromParent).
/datum/overlay_lighting/proc/detach()
	if(!owner)
		return
	overlay_lighting_flags &= ~LIGHTING_ATTACHED
	set_parent_attached_to(null)
	set_holder(null)
	clean_old_turfs()
	unobserve(owner, /datum/notice/moved, src)
	unobserve(owner, /datum/notice/atom_update_light_range, src)
	unobserve(owner, /datum/notice/atom_update_light_power, src)
	unobserve(owner, /datum/notice/atom_update_light_color, src)
	unobserve(owner, /datum/notice/atom_update_light_on, src)
	unobserve(owner, /datum/notice/atom_update_light_flags, src)
	unobserve(owner, /datum/notice/atom_used_in_craft, src)
	unobserve(owner, /datum/notice/atom_dir_change, src)
	if(overlay_lighting_flags & LIGHTING_ON)
		turn_off()

// Runs in destroy phase 1, before phase 4 clears the `owner` relation view.
/datum/overlay_lighting/lifecycle_unbind()
	. = ..()
	detach()
	set_parent_attached_to(null)
	set_holder(null)
	clean_old_turfs()
	if(owner?.overlay_light == src)
		rel_take(owner, nameof(owner.overlay_light))
	rel_clear(src, nameof(owner))
	// The mask, cone and directional atom refuse any delete that isn't
	// forced (only we may delete them). Phase 4's owned-var sweep qdels
	// without force, so release them here, forced, before it runs.
	spent(visible_mask, force = TRUE)
	rel_take(src, nameof(visible_mask))
	spent(directional_atom, force = TRUE)
	rel_take(src, nameof(directional_atom))
	spent(cone, force = TRUE)
	rel_take(src, nameof(cone))

///Clears the affected_turfs lazylist, removing from its contents the effects of being near the light.
/datum/overlay_lighting/proc/clean_old_turfs()
	for(var/turf/lit_turf as anything in affected_turfs)
		lit_turf.dynamic_lumcount -= lum_power
	affected_turfs = null // ALLOW(ownership): hot lighting cache rebuilt on every move; a turf relation index entry per lit turf per step would grow without bound

///Populates the affected_turfs lazylist, adding to its contents the effects of being near the light.
/datum/overlay_lighting/proc/get_new_turfs()
	if(!current_holder())
		return
	var/atom/movable/light_source = GET_LIGHT_SOURCE
	. = list()
	for(var/turf/lit_turf in view(lumcount_range, get_turf(light_source)))
		lit_turf.dynamic_lumcount += lum_power
		. += lit_turf
	if(length(.))
		affected_turfs = . // ALLOW(ownership): hot lighting cache rebuilt on every move; a turf relation index entry per lit turf per step would grow without bound

///Clears the old affected turfs and populates the new ones.
/datum/overlay_lighting/proc/make_luminosity_update()
	clean_old_turfs()
	if(!isturf(current_holder()?.loc))
		return
	if(directional)
		cast_directional_light()
	get_new_turfs()

///Adds the luminosity and source for the afected movable atoms to keep track of their visibility.
/datum/overlay_lighting/proc/add_dynamic_lumi()
	var/atom/movable/light_source = GET_LIGHT_SOURCE
	dq_affected_dynamic_lights_set(light_source, src, lumcount_range + 1)
	light_source.vis_contents += visible_mask
	light_source.update_dynamic_luminosity()
	if(directional)
		current_holder().vis_contents += cone

///Removes the luminosity and source for the afected movable atoms to keep track of their visibility.
/datum/overlay_lighting/proc/remove_dynamic_lumi()
	var/atom/movable/light_source = GET_LIGHT_SOURCE
	dq_affected_dynamic_lights_remove(light_source, src)
	light_source.vis_contents -= visible_mask
	light_source.update_dynamic_luminosity()
	if(directional)
		current_holder().vis_contents -= cone
		directional_atom.moveToNullspace()

///Called to change the value of parent_attached_to.
/datum/overlay_lighting/proc/set_parent_attached_to(atom/movable/new_parent_attached_to)
	if(new_parent_attached_to == parent_attached_to())
		return

	. = parent_attached_to()
	rel_set(src, nameof(parent_attached_to), new_parent_attached_to)
	if(.)
		var/atom/movable/old_parent_attached_to = .
		unobserve(old_parent_attached_to, /datum/notice/qdeleting, src)
		unobserve(old_parent_attached_to, /datum/notice/moved, src)
		if(old_parent_attached_to == current_holder())
			observe(old_parent_attached_to, /datum/notice/qdeleting, src, then(PROC_REF(on_holder_qdel)))
			observe(old_parent_attached_to, /datum/notice/moved, src, then(PROC_REF(on_holder_moved)))
	if(parent_attached_to())
		if(parent_attached_to() == current_holder())
			unobserve(current_holder(), /datum/notice/qdeleting, src)
			unobserve(current_holder(), /datum/notice/moved, src)
		observe(parent_attached_to(), /datum/notice/qdeleting, src, then(PROC_REF(on_parent_attached_to_qdel)))
		observe(parent_attached_to(), /datum/notice/moved, src, then(PROC_REF(on_parent_attached_to_moved)))
	check_holder()

///Called to change the value of current_holder.
/datum/overlay_lighting/proc/set_holder(atom/movable/new_holder)
	if(new_holder == current_holder())
		return
	if(istype(new_holder,/obj/structure/closet))
		new_holder = null // Forbid crates from holding lights, this only applies to contents 'holding', when you put a flashlight into a crate for example. Not crates with lights... Not that there are any.
	if(current_holder())
		if(current_holder() != owner && current_holder() != parent_attached_to())
			unobserve(current_holder(), /datum/notice/qdeleting, src)
			unobserve(current_holder(), /datum/notice/moved, src)
			if(directional)
				unobserve(current_holder(), /datum/notice/atom_dir_change, src)
		if(overlay_lighting_flags & LIGHTING_ON)
			remove_dynamic_lumi()
	rel_set(src, nameof(current_holder), new_holder)
	if(new_holder && current_holder() != new_holder)
		// The relation refused a holder that is being destroyed (a moved notice sent from its own teardown): there is nothing to light from.
		clean_old_turfs()
		return
	if(new_holder == null)
		clean_old_turfs()
		return
	if(new_holder != owner && new_holder != parent_attached_to())
		observe(new_holder, /datum/notice/qdeleting, src, then(PROC_REF(on_holder_qdel)))
		observe(new_holder, /datum/notice/moved, src, then(PROC_REF(on_holder_moved)))
		if(directional)
			observe(new_holder, /datum/notice/atom_dir_change, src, then(PROC_REF(on_holder_dir_change)))
	if(overlay_lighting_flags & LIGHTING_ON)
		make_luminosity_update()
		add_dynamic_lumi()

///Used to determine the new valid current_holder from the parent's loc.
/datum/overlay_lighting/proc/check_holder()
	var/atom/movable/movable_parent = GET_PARENT
	if(isturf(movable_parent.loc))
		set_holder(movable_parent)
		return
	var/atom/inside = movable_parent.loc //Parent's loc
	if(isnull(inside))
		set_holder(null)
		return
	if(isturf(inside.loc))
		set_holder(inside)
		return
	set_holder(null)

///Called when the current_holder is qdeleted, to remove the light effect.
/datum/overlay_lighting/proc/on_holder_qdel(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	unobserve(current_holder(), /datum/notice/qdeleting, src)
	unobserve(current_holder(), /datum/notice/moved, src)
	if(directional)
		unobserve(current_holder(), /datum/notice/atom_dir_change, src)
	set_holder(null)

///Called when current_holder changes loc.
/datum/overlay_lighting/proc/on_holder_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(!(overlay_lighting_flags & LIGHTING_ON))
		return
	make_luminosity_update()

///Called when parent changes loc.
/datum/overlay_lighting/proc/on_parent_moved_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/source = A.target
	var/datum/notice/moved/event = A
	on_parent_moved(source, event.old_loc, event.direction, event.forced)

///Called when parent changes loc (also called directly by turf translation).
/datum/overlay_lighting/proc/on_parent_moved(atom/movable/source, OldLoc, Dir, Forced)
	var/atom/movable/movable_parent = owner
	if(overlay_lighting_flags & LIGHTING_ATTACHED)
		set_parent_attached_to(ismovable(movable_parent.loc) ? movable_parent.loc : null)
	check_holder()
	if(!(overlay_lighting_flags & LIGHTING_ON) || !current_holder())
		return
	make_luminosity_update()

///Called when the current_holder is qdeleted, to remove the light effect.
/datum/overlay_lighting/proc/on_parent_attached_to_qdel(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	unobserve(parent_attached_to(), /datum/notice/qdeleting, src)
	unobserve(parent_attached_to(), /datum/notice/moved, src)
	if(directional)
		unobserve(parent_attached_to(), /datum/notice/atom_dir_change, src)
	if(parent_attached_to() == current_holder())
		set_holder(null)
	set_parent_attached_to(null)

///Called when parent_attached_to changes loc.
/datum/overlay_lighting/proc/on_parent_attached_to_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	check_holder()
	if(!(overlay_lighting_flags & LIGHTING_ON) || !current_holder())
		return
	make_luminosity_update()

///Changes the range which the light reaches. 0 means no light, 6 is the maximum value.
/datum/overlay_lighting/proc/on_range_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	var/datum/notice/atom_update_light_range/event = A
	set_range(source, event.old_range)

/datum/overlay_lighting/proc/set_range(atom/source, old_range)
	var/new_range = source.light_range
	if(range == new_range)
		return
	if(range == 0)
		turn_off()
	range = clamp(CEILING(new_range, 0.5), 1, 6)
	var/pixel_bounds = ((range - 1) * 64) + 32
	lumcount_range = CEILING(range, 1)
	visible_mask.icon = light_overlays["[pixel_bounds]"]
	if(pixel_bounds == 32)
		visible_mask.transform = null
		return
	var/offset = (pixel_bounds - 32) * 0.5
	var/matrix/transform = new
	transform.Translate(-offset, -offset)
	visible_mask.transform = transform
	if(directional)
		cast_range = clamp(round(new_range * 0.5), 1, 3)
	if(overlay_lighting_flags & LIGHTING_ON)
		make_luminosity_update()

///Changes the intensity/brightness of the light by altering the visual object's alpha.
/datum/overlay_lighting/proc/on_power_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	var/datum/notice/atom_update_light_power/event = A
	set_power(source, event.old_power)

/datum/overlay_lighting/proc/set_power(atom/source, old_power)
	var/new_power = source.light_power
	set_lum_power(new_power >= 0 ? 0.5 : -0.5)
	set_alpha = min(230, (abs(new_power) * 120) + 30)
	visible_mask.alpha = set_alpha
	if(directional)
		cone.alpha = min(200, (abs(new_power) * 90)+20)

///Changes the light's color, pretty straightforward.
/datum/overlay_lighting/proc/on_color_event(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	var/datum/notice/atom_update_light_color/event = A
	set_color(source, event.old_color)

/datum/overlay_lighting/proc/set_color(atom/source, old_color)
	var/new_color = source.light_color
	visible_mask.color = new_color
	if(directional)
		cone.color = new_color

///Toggles the light on and off.
/datum/overlay_lighting/proc/on_toggle(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	var/new_value = source.light_on
	if(new_value) //Truthy value input, turn on.
		turn_on()
		return
	turn_off() //Falsey value, turn off.

///Triggered right after the parent light flags change.
/datum/overlay_lighting/proc/on_light_flags_change(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	var/datum/notice/atom_update_light_flags/event = A
	var/old_flags = event.old_flags
	var/new_flags = source.light_flags
	var/atom/movable/movable_parent = owner
	if(!((new_flags ^ old_flags) & LIGHT_ATTACHED))
		return

	if(new_flags & LIGHT_ATTACHED) // Gained the [LIGHT_ATTACHED] property
		overlay_lighting_flags |= LIGHTING_ATTACHED
		if(ismovable(movable_parent.loc))
			set_parent_attached_to(movable_parent.loc)
	else // Lost the [LIGHT_ATTACHED] property
		overlay_lighting_flags &= ~LIGHTING_ATTACHED
		set_parent_attached_to(null)

///Toggles the light on.
/datum/overlay_lighting/proc/turn_on()
	if(overlay_lighting_flags & LIGHTING_ON)
		return
	if(current_holder())
		if(directional)
			cast_directional_light()
		add_dynamic_lumi()
	overlay_lighting_flags |= LIGHTING_ON
	get_new_turfs()

///Toggles the light off.
/datum/overlay_lighting/proc/turn_off()
	if(!(overlay_lighting_flags & LIGHTING_ON))
		return
	if(current_holder())
		remove_dynamic_lumi()
	overlay_lighting_flags &= ~LIGHTING_ON
	clean_old_turfs()

///Here we append the behavior associated to changing lum_power.
/datum/overlay_lighting/proc/set_lum_power(new_lum_power)
	if(lum_power == new_lum_power)
		return
	. = lum_power
	lum_power = new_lum_power
	var/difference = . - lum_power
	for(var/turf/lit_turf as anything in affected_turfs)
		lit_turf.dynamic_lumcount -= difference

///Moves the light directional_atom that emits our "light" based on our position and our direction
/datum/overlay_lighting/proc/cast_directional_light()
	var/final_distance = cast_range

	//Lower the distance by 1 if we're not looking at a GLOB.cardinal direction, and we're not a short cast
	if(final_distance > SHORT_CAST && !(ALL_CARDINALS & current_direction))
		final_distance -= 1
	var/turf/scanning = get_turf(current_holder())

	. = 0
	for(var/i in 1 to final_distance)
		var/turf/next_turf = get_step(scanning, current_direction)
		if(isnull(next_turf) || IS_OPAQUE_TURF_DIR(next_turf, GLOB.reverse_dir[current_direction]))
			break
		scanning = next_turf
		.++

	directional_atom.forceMove(scanning)
	directional_atom.face_light(GET_PARENT, dir2angle(current_direction), .)

///Tries to place the directional light in a specific turf
/datum/overlay_lighting/proc/place_directional_light(turf/target)
	var/final_distance = round(cast_range*2)

	//Lower the distance by 1 if we're not looking at a GLOB.cardinal direction, and we're not a short cast
	if(final_distance > SHORT_CAST && !(ALL_CARDINALS & get_dir(GET_PARENT, target)))
		final_distance -= 1
	var/turf/scanning = get_turf(GET_PARENT)

	. = 0
	for(var/i in 1 to final_distance)
		var/next_dir = get_dir(scanning, target)
		var/turf/next_turf = get_step(scanning, next_dir)
		if(isnull(next_turf) || IS_OPAQUE_TURF_DIR(next_turf, get_dir(scanning, next_turf)))
			break
		scanning = next_turf
		.++

	directional_atom.forceMove(scanning)
	var/turf/Ts = get_turf(GET_PARENT)
	var/turf/To = get_turf(GET_LIGHT_SOURCE)

	var/angle = Get_Angle(Ts, To)

	directional_atom.face_light(GET_PARENT, angle, .)
	set_cone_direction(NORTH, angle)

///Called when current_holder changes loc.
/datum/overlay_lighting/proc/on_holder_dir_change(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/atom_dir_change/event = A
	set_direction(event.new_dir)

///Called when parent changes loc.
/datum/overlay_lighting/proc/on_parent_dir_change(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/atom_dir_change/event = A
	set_direction(event.new_dir)

///Sets the cone's direction for directional lighting
/datum/overlay_lighting/proc/set_cone_direction(dir, angle)
	cone.reset_transform()
	if(dir)
		cone.set_dir(dir)
	if(angle)
		cone.transform = turn(cone.transform, angle)
	cone.apply_standard_transform()

///Sets a new direction for the directional cast, then updates luminosity
/datum/overlay_lighting/proc/set_direction(newdir, skip_update)
	if(!newdir)
		return
	if(current_direction == newdir)
		return
	current_direction = newdir
	set_cone_direction(newdir)

	if(newdir & NORTH)
		cone.pixel_y = 16
	else if(newdir & SOUTH)
		cone.pixel_y = -16
	else
		if(!isnull(cone_hint_y))
			cone.pixel_y = cone_hint_y
			directional_atom.pixel_y = cone_hint_y
		else
			cone.pixel_y = 0
			directional_atom.pixel_y = 0

	if(newdir & EAST)
		cone.pixel_x = 16
	else if(newdir & WEST)
		cone.pixel_x = -16
	else
		if(!isnull(cone_hint_x))
			if(newdir & NORTH)
				cone.pixel_x = -1*cone_hint_x
				directional_atom.pixel_x = -1*cone_hint_x
			else
				cone.pixel_x = cone_hint_x
				directional_atom.pixel_x = cone_hint_x
		else
			cone.pixel_x = 0
			directional_atom.pixel_x = 0

	if(!skip_update && (overlay_lighting_flags & LIGHTING_ON))
		make_luminosity_update()

/datum/overlay_lighting/proc/on_parent_crafted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/atom_used_in_craft/event = A
	var/atom/movable/new_craft = event.result_
	if(!istype(new_craft))
		return

	unobserve(owner, /datum/notice/atom_used_in_craft, src)
	observe(new_craft, /datum/notice/atom_used_in_craft, src, then(PROC_REF(on_parent_crafted)))
	set_parent_attached_to(new_craft)

/// Handles putting the source for overlay lights into the light eater queue since we aren't tracked by [/atom/var/light_sources]
#undef LIGHTING_ON
#undef LIGHTING_ATTACHED
#undef GET_PARENT
#undef GET_LIGHT_SOURCE
#undef SHORT_CAST

/// The atom the light is currently drawn on (a relation view).
/datum/overlay_lighting/proc/current_holder() as /atom/movable
	return current_holder

/// The atom our parent is attached to (a relation view).
/datum/overlay_lighting/proc/parent_attached_to() as /atom/movable
	return parent_attached_to


/atom/movable
	///The overlay light of MOVABLE_LIGHT / MOVABLE_LIGHT_DIRECTIONAL atoms (see add_overlay_lighting()).
	var/tmp/datum/overlay_lighting/overlay_light

/// Lit turfs: rebuilt by make_luminosity_update(), dropped by clean_old_turfs() (unbind).
// turfs, never freed
