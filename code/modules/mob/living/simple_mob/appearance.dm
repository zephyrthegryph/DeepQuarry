/// A simple mob's whole look: its life state, hands, body effects, belly fullness, eyes, pounce and spit. Subtypes call ..() and refine
/// (look.state_so_far(src) is the state chosen so far). Every input is tracked state: stat, resting, status_flags, the hand sprites,
/// vore_fullness(_ex), pouncing and spitting, so a change redraws it with no call.
/mob/living/simple_mob/draw(datum/look/look)
	..()
	if(!draws_life_state)
		return
	var/state = look.life_state(src, icon_living, icon_rest, icon_dead)
	var/awake = (state == icon_living)
	var/eye_state = (has_eye_glow && awake) ? state : null

	if(has_hands)
		look.overlay(r_hand_sprite)
		look.overlay(l_hand_sprite)
	for(var/image/effect as anything in body_effect_overlays(TRUE))
		look.overlay(effect)

	// Belly fullness: the sprite of the fullness suffix, and the per-class belly overlays of that state.
	if(vore_active && vore_fullness)
		if((stat == CONSCIOUS) && (!icon_rest || !resting || !incapacitated(INCAPACITATION_DISABLED)) && (vore_icons & SA_ICON_LIVING))
			state = "[icon_living]-[vore_fullness]"
		else if(stat >= DEAD && (vore_icons & SA_ICON_DEAD))
			state = "[icon_dead]-[vore_fullness]"
		else if(((stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED)) && icon_rest && (vore_icons & SA_ICON_REST))
			state = "[icon_rest]-[vore_fullness]"
		if(vore_eyes && awake)
			eye_state = state
		for(var/belly_state in vore_fullness_states(state))
			look.overlay(belly_state)

	// Pounce: the leap swaps the icon file and state and shifts the sprite; the crouch before it swaps the state.
	var/leaping = pouncing && (status_flags & LEAPING)
	var/draw_icon = icon
	if(leaping)
		if(!isnull(icon_state_pounce))
			state = icon_state_pounce
		if(!isnull(icon_pounce))
			look.set_icon(icon_pounce)
			draw_icon = icon_pounce
		if(icon_pounce_x || icon_pounce_y)
			look.offset(icon_pounce_x ? icon_pounce_x : initial(pixel_x), icon_pounce_y ? icon_pounce_y : initial(pixel_y))
	else if(pouncing && !isnull(icon_state_prepounce))
		state = icon_state_prepounce

	// A spit being readied.
	if(spitting)
		var/spit_state = null
		if(!isnull(icon_overlay_spit) && (state == icon_living))
			spit_state = icon_overlay_spit
		else if(!isnull(icon_overlay_spit_pounce) && (state == icon_state_prepounce))
			spit_state = icon_overlay_spit_pounce
		if(spit_state)
			look.overlay(look_overlay_image(draw_icon, spit_state, layer = MOB_LAYER, plane = MOB_PLANE, appearance_flags = (RESET_COLOR|PIXEL_SCALE)))

	// Ghosts see whether a revived mob can be joined.
	if(ghostjoin)
		look.overlay(look_overlay_image('icons/mob/hud_vr.dmi', "ghostjoin", plane = PLANE_GHOSTS, appearance_flags = (KEEP_APART|RESET_TRANSFORM), invisibility = INVISIBILITY_OBSERVER))

	look.state(state)
	look.eyes(src, eye_state, custom_eye_color, !isnull(eye_state))

/mob/living/simple_mob/gib()
	..(icon_gib,1,icon) // we need to specify where the gib animation is stored
