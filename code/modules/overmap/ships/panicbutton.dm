/obj/structure/panic_button/get_mechanics_info(list/additional_information)
	return ..(list("Sends a message to people on other z-levels requesting their aid. They may take a while to arrive, as they need to prepare. Only use it if you really need it.") + additional_information)

/obj/structure/panic_button
	name = "distress beacon trigger"
	desc = "WARNING: Will deploy ship's distress beacon and request help. Misuse may result in fines and jail time."
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "panicbutton"
	anchored = TRUE

	var/glass = TRUE
	var/launched = FALSE

// In case we're annihilated by a meteor
// an unlaunched button launches.
/obj/structure/panic_button/on_destroy(force)
	if(!launched)
		launch()
	..()

/// Appearance reader: icon_state suffix for launched / glass broken / intact.
/obj/structure/panic_button/proc/appearance_panic_suffix()
	if(launched)
		return "_launched"
	if(!glass)
		return "_open"
	return ""

/// The look (the draw sweep: from its template).
/obj/structure/panic_button/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_panic_suffix()]")

DECLARE_INTERACTIONS(/obj/structure/panic_button, INTERACT_HAND_AS(I_HURT, "Smash the glass", PROC_REF(interaction_hand)), INTERACT_HAND(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/panic_button/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user))
		return FALSE

	if(user.incapacitated())
		return TRUE

	// Already launched
	if(launched)
		to_chat(user, span_warning("The button is already depressed; the beacon has been launched already."))
	// Glass present
	else if(glass)
		if(interaction.stance == I_HURT)
			user.automatic_custom_emote(VISIBLE_MESSAGE, "smashes the glass on [src]!")
			glass = FALSE
			play_sfx(src, SFX_EFFECTS_HIT_ON_SHATTERED_GLASS, volume = 0, vary = FALSE)
			changed(src)
		else
			user.automatic_custom_emote(VISIBLE_MESSAGE, "pats [src] in a friendly manner.")
			to_chat(user, span_warning("If you're trying to break the glass, you'll have to hit it harder than that..."))
	// Must be !glass and !launched
	else
		user.automatic_custom_emote(VISIBLE_MESSAGE, "pushes the button on [src]!")
		launch(user)
		playsound(src, get_sfx(SFX_BUTTON))
		changed(src)
	return TRUE

/obj/structure/panic_button/proc/launch(mob/living/user)
	if(launched)
		return
	launched = TRUE
	var/obj/effect/overmap/visitable/S = get_overmap_sector(z)
	if(!S)
		log_mapping("## ERROR Distress button hit on z[z] but that's not an overmap sector...")
		return
	S.distress(user)
	//Kind of pricey, but this is a one-time thing that can't be reused, so I'm not too worried.
	var/list/hear_z = GetConnectedZlevels(z) // multiz 'physical' connections only, not crazy overmap connections

	var/mapsize = (world.maxx+world.maxy)*0.5
	var/turf/us = get_turf(src)

	for(var/hz in hear_z)
		for(var/mob/M as anything in GLOB.players_by_zlevel[hz])
			var/sound/SND = sound('sound/misc/emergency_beacon_launched.ogg') // Inside the loop because playsound_local modifies it for each person, so, need separate instances
			var/turf/them = get_turf(M)
			var/volume = max(0.20, 1-(get_dist(us,them) / mapsize*0.8))*100
			M.playsound_local(get_turf(M), SND, vol = volume)
