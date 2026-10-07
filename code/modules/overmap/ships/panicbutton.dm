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
TRACKED(/obj/structure/panic_button, launched)

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

CAPABILITIES(/obj/structure/panic_button)
	op("smash", hand(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Smash the glass"), then(PROC_REF(interaction_smash)))
	op("hand", hand(), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_DEFAULT - 2), then(PROC_REF(interaction_hand)))

/// Old attack_hand with a harmful stance.
/obj/structure/panic_button/proc/interaction_smash(datum/act/op/A)
	return panic_press(A.actor, TRUE)

/// Old attack_hand with any other stance.
/obj/structure/panic_button/proc/interaction_hand(datum/act/op/A)
	return panic_press(A.actor, FALSE)

/obj/structure/panic_button/proc/panic_press(mob/living/user, smash)
	if(!istype(user))
		return OP_DECLINE

	if(user.incapacitated())
		return OP_OK

	// Already launched
	if(launched)
		to_chat(user, span_warning("The button is already depressed; the beacon has been launched already."))
	// Glass present
	else if(glass)
		if(smash)
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
	return OP_OK

/obj/structure/panic_button/proc/launch(mob/living/user)
	if(launched)
		return
	set_launched(TRUE)
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
