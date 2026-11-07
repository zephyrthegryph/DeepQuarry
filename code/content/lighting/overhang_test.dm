// Lighting overhang test kit. A character larger than one tile is drawn whole when the tile it stands on is seen, so the part that hangs over a
// dark neighbour (luminosity 0, outside the client's view) may have nothing multiplying it. This verb cycles three experiments on the caller so
// the cause can be told in a real client:
//   mode 1  SEE_BLACKNESS on the caller's sight (a sight_flags hold): changes where BYOND draws the unseen-area black relative to the planes.
//   mode 2  KEEP_APART on the light masks and light cones: tests whether KEEP_TOGETHER on movables folds them into the mob's plane.
//   mode 3  luminosity 1 forced on the dark turfs around the caller (temporary: the lighting engine writes it back when a turf next updates),
//           so every dark turf's opaque black underlay is sent to the client.
// Each cycle step undoes the previous mode first, and every change is logged (admin log and the caller's chat).

/// Lighting overhang test: ckey -> mode (0 off, 1 blackness, 2 keep apart, 3 forced luminosity).
GLOBAL_LIST_EMPTY(lighting_overhang_modes)
/// Mode 2 is on for someone: new light masks and cones carry KEEP_APART.
GLOBAL_VAR_INIT(lighting_overhang_keep_apart, FALSE)

#define LIGHTING_OVERHANG_MODE_COUNT 4
#define LIGHTING_OVERHANG_RADIUS 12

ADMIN_VERB(lighting_overhang_test, R_DEBUG, "Lighting Overhang Test", "Cycles experiments on the lighting of characters larger than one tile (off, SEE_BLACKNESS, KEEP_APART, forced turf luminosity). Affects you only.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/mob/M = user.mob
	if(QDELETED(M))
		return
	var/old_mode = GLOB.lighting_overhang_modes[user.ckey] || 0
	var/new_mode = (old_mode + 1) % LIGHTING_OVERHANG_MODE_COUNT
	lighting_overhang_apply(M, old_mode, FALSE)
	lighting_overhang_apply(M, new_mode, TRUE)
	GLOB.lighting_overhang_modes[user.ckey] = new_mode
	var/message = "[key_name(user)] cycled the lighting overhang test: [lighting_overhang_mode_name(old_mode)] -> [lighting_overhang_mode_name(new_mode)]."
	log_admin(message)
	log_admin(message)
	to_chat(user, span_notice("Lighting overhang test: [lighting_overhang_mode_name(new_mode)]. Stand a large character on a lit tile next to a dark one and look at the overhang."))
	feedback_add_details("admin_verb","LOHT") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/proc/lighting_overhang_mode_name(mode)
	switch(mode)
		if(1)
			return "SEE_BLACKNESS on"
		if(2)
			return "KEEP_APART on light masks and cones"
		if(3)
			return "dark turfs forced to luminosity 1"
	return "off"

/// Turns one experiment on or off for `M`.
/proc/lighting_overhang_apply(mob/M, mode, on)
	switch(mode)
		if(1)
			if(!isliving(M))
				M.sight = on ? (M.sight | SEE_BLACKNESS) : (M.sight & ~SEE_BLACKNESS)
				return
			if(on)
				hold(M, STAT_SIGHT_FLAGS, SEE_BLACKNESS, SRC_VV)
			else
				release(M, STAT_SIGHT_FLAGS, SRC_VV)
			M.sight = on ? (M.sight | SEE_BLACKNESS) : (M.sight & ~SEE_BLACKNESS)
		if(2)
			GLOB.lighting_overhang_keep_apart = on
			var/refit = 0
			for(var/atom/movable/AM in range(LIGHTING_OVERHANG_RADIUS, M))
				var/datum/overlay_lighting/light = AM.overlay_light
				if(light)
					if(light.visible_mask)
						light.visible_mask.appearance_flags = on ? (light.visible_mask.appearance_flags | KEEP_APART) : (light.visible_mask.appearance_flags & ~KEEP_APART)
					if(light.cone)
						light.cone.appearance_flags = on ? (light.cone.appearance_flags | KEEP_APART) : (light.cone.appearance_flags & ~KEEP_APART)
					refit++
			log_admin("lighting overhang test: KEEP_APART [on ? "set" : "cleared"] on [refit] lights near [key_name(M)].")
		if(3)
			var/changed = 0
			for(var/turf/T in range(LIGHTING_OVERHANG_RADIUS, M))
				if(!T.lighting_object)
					continue
				if(on)
					if(!T.luminosity)
						T.set_luminosity(1, TRUE)
						changed++
				else
					T.lighting_object.update() // recomputes the luminosity from the corners
					changed++
			log_admin("lighting overhang test: luminosity [on ? "forced to 1 on [changed] dark turfs" : "recomputed on [changed] turfs"] near [key_name(M)].")

#undef LIGHTING_OVERHANG_MODE_COUNT
#undef LIGHTING_OVERHANG_RADIUS
