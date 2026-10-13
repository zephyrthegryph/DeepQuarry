// What the human's look is made of lives in human_look.dm (draw(look)). This file keeps what is not the overlays: the transform (size,
// lying, centring), the tail's animation state and the wing and belly animations, which set tracked state the draw reads.

GLOBAL_LIST_EMPTY(light_overlay_cache) //see make_worn_icon() on helmets // ALLOW(cache): written with mixed keys from clothing.dm and read-only-if-present in clothing_icons.dm

/mob/living/carbon/human
	/// The species tail's animation state (an icon_state of the tail's animation sheet: "<tail>_idle3", "<tail>_loop1", "<tail>_once"),
	/// or null for the still sprite. A dead human's tail is drawn still whatever this holds.
	var/tail_anim_state

TRACKED(/mob/living/carbon/human, tail_anim_state)

/mob/living/carbon/human/update_transform(instant = FALSE)
	var/desired_scale_x = size_multiplier * icon_scale_x
	var/desired_scale_y = size_multiplier * icon_scale_y
	desired_scale_x *= species.icon_scale_x
	desired_scale_y *= species.icon_scale_y
	var/cent_offset = species.center_offset
	if(fuzzy || offset_override || dir == EAST || dir == WEST)
		cent_offset = 0
	vis_height = species.icon_height
	appearance_flags |= PIXEL_SCALE
	if(fuzzy)
		appearance_flags &= ~PIXEL_SCALE
		center_offset = 0

	// Regular stuff again.
	var/matrix/M = matrix()
	var/anim_time = 3

	//Due to some involuntary means, you're laying now
	if(lying && !resting && !has_status(STAT_SLEEPING))
		anim_time = 1 //Thud

	if(lying && !species.prone_icon) //Only rotate them if we're not drawing a specific icon for being prone.
		if(tail_style?.can_loaf && resting) // Only call these if we're resting?
			M.Scale(desired_scale_x, desired_scale_y)
			M.Translate(cent_offset * desired_scale_x, (vis_height/2)*(desired_scale_y-1))
		else
			M.Scale(desired_scale_x, desired_scale_y)
			if(isnull(rest_dir))
				rest_dir = pick(FALSE, TRUE)
			if(rest_dir)
				M.Translate((1 / desired_scale_x * -4) + (desired_scale_x * cent_offset), 0)
				M.Turn(-90)
			else
				M.Translate((1 / desired_scale_x * 4) - (desired_scale_x * cent_offset), 0)
				M.Turn(90)
		layer = MOB_LAYER -0.01 // Fix for a byond bug where turf entry order no longer matters
	else
		M.Scale(desired_scale_x, desired_scale_y)
		M.Translate(cent_offset * desired_scale_x, (vis_height/2)*(desired_scale_y-1))
		layer = MOB_LAYER // Fix for a byond bug where turf entry order no longer matters

	if(instant)
		transform = M
	else
		animate(src, transform = M, time = anim_time)
	update_icon_special() //May contain transform-altering things

//TODO: Carbon procs in my human update_icons??
/mob/living/carbon/human/update_hud()	//TODO: do away with this if possible
	if(QDESTROYING(src))
		return

	if(client)
		client.screen |= contents
		if(hud_used)
			hud_used.hidden_inventory_update() 	//Updates the screenloc of the items on the 'other' inventory bar

// ---- the tail's animation ----

//Not really once, since BYOND can't do that.
//Update this if the ability to flick() images or make looping animation start at the first frame is ever added.
/mob/living/carbon/human/proc/animate_tail_once()
	if(QDESTROYING(src))
		return
	var/t_state = "[species.get_tail(src)]_once"
	if(tail_anim_state == t_state)
		return //let the existing animation finish
	set_tail_anim_state(t_state)
	after(src, 2 SECONDS, PROC_REF(animate_tail_once_end), with = list(t_state))

/mob/living/carbon/human/proc/animate_tail_once_end(t_state)
	//check that the animation hasn't changed in the meantime
	if(tail_anim_state == t_state)
		animate_tail_stop()

/mob/living/carbon/human/proc/animate_tail_start()
	if(QDESTROYING(src))
		return
	set_tail_anim_state("[species.get_tail(src)]_slow[rand(0,9)]")

/mob/living/carbon/human/proc/animate_tail_fast()
	if(QDESTROYING(src))
		return
	set_tail_anim_state("[species.get_tail(src)]_loop[rand(0,9)]")

/mob/living/carbon/human/proc/animate_tail_reset()
	if(QDESTROYING(src))
		return
	if(stat != DEAD)
		set_tail_anim_state("[species.get_tail(src)]_idle[rand(0,9)]")
	else
		set_tail_anim_state("[species.get_tail(src)]_static")
		toggle_tail(FALSE) //So tails stop when someone dies. TODO - Fix this hack ~Leshana

/mob/living/carbon/human/proc/animate_tail_stop()
	if(QDESTROYING(src))
		return
	set_tail_anim_state("[species.get_tail(src)]_static")

// ---- flight and the bellies ----

// TODO - Move this to where it should go ~Leshana
/mob/living/proc/stop_flying()
	if(QDESTROYING(src))
		return
	set_flying(src, FALSE)
	return 1

/mob/living/carbon/human/proc/vore_belly_animation()
	if(!struggle_anim_stomach)
		set_struggle_anim_stomach(TRUE)
		after(src, 1.2 SECONDS, PROC_REF(end_belly_struggle_anim))

/mob/living/carbon/human/proc/vore_tail_animation()
	if(tail_style.struggle_anim && !struggle_anim_taur)
		set_struggle_anim_taur(TRUE)
		after(src, 1.2 SECONDS, PROC_REF(end_tail_struggle_anim))

/mob/living/carbon/human/proc/end_belly_struggle_anim()
	set_struggle_anim_stomach(FALSE)

/mob/living/carbon/human/proc/end_tail_struggle_anim()
	set_struggle_anim_taur(FALSE)

/mob/living/carbon/human/proc/GetAppearanceFromPrefs(flavourtext, oocnotes)
	/* Jank code that effectively creates the client's mob from save, then copies its appearance to our current mob.
	Intended to be used with shapeshifter species so we don't reset their organs in doing so.*/
	if(client.prefs)
		var/mob/living/carbon/human/dummy/mannequin/Dummy = get_mannequin(client.ckey)
		client.prefs.copy_to(Dummy)
		//Important, since some sprites only work for specific species
		custom_species = Dummy.custom_species
		var/list/traits = LAZYCOPY(dna.species_traits)
		rel_set(src, nameof(dna), Dummy.dna.Clone())
		LAZYCLEARLIST(dna.species_traits)
		dna.species_traits = traits.Copy()
		UpdateAppearance()
		if(flavourtext)
			// migrated flavor_texts
			var/list/_flavor_texts = client.prefs.read_preference(/datum/preference/flavor_texts)
			bio.flavor_texts = islist(_flavor_texts) ? _flavor_texts.Copy() : list()
		if(oocnotes)
			identity().ooc_notes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes)
			identity().ooc_notes_likes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_likes)
			identity().ooc_notes_dislikes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_dislikes)
			identity().ooc_notes_favs = read_preference(/datum/preference/text/living/ooc_notes_favs)
			identity().ooc_notes_maybes = read_preference(/datum/preference/text/living/ooc_notes_maybes)
			identity().ooc_notes_style = read_preference(/datum/preference/toggle/living/ooc_notes_style)
