// SEND_SIGNAL(COMSIG_BELLY_UPDATE_VORE_FX) is sometimes used when calling vore_fx() to send belly visuals
// to certain non-belly atoms. Not called here as vore_fx() is usually only called if a mob is in the belly.
// Don't forget it if you need to rework vore_fx().
//
// DQEdit (Stage 5): belly fullscreen overlay has been migrated to a TGUI
// window (interfaces/BellyOverlay.tsx) backed by /datum/belly_overlay_tgui
// in code/modules/belly_overlay/. The previous in-DM compositor
// (4 colored layers + bubbles.dmi mush/liquid layers) is gone — see git
// history if you need to reference the original logic.
/obj/belly/proc/vore_fx(mob/living/living_prey, severity = 0)
	if(!istype(living_prey))
		return
	if(!living_prey.client)
		return
	if(living_prey.previewing_belly && living_prey.previewing_belly != src)
		return
	if(living_prey.previewing_belly == src && living_prey.vore_selected != src)
		living_prey.previewing_belly = null
		living_prey.belly_overlay_tgui?.hide()
		return
	var/datum/belly_overlay_tgui/dq_overlay = get_belly_overlay_tgui(living_prey)
	if(!living_prey.show_vore_fx || !belly_fullscreen)
		dq_overlay?.hide()
		check_hud_disable(living_prey)
		return
	dq_overlay.show(src, living_prey)
	check_hud_disable(living_prey)

/obj/belly/proc/check_hud_disable(mob/living/living_prey)
	if(disable_hud && living_prey != owner)
		if(living_prey?.hud_used?.hud_shown)
			to_chat(living_prey, span_vnotice("((Your pred has disabled huds in their belly. Turn off vore FX and hit F12 to get it back; or relax, and enjoy the serenity.))"))
			living_prey.toggle_hud_vis(TRUE)

/obj/belly/proc/vore_preview(mob/living/living_prey)
	if(!istype(living_prey) || !living_prey.client)
		living_prey.previewing_belly = null
		return
	living_prey.previewing_belly = src
	vore_fx(living_prey)

/obj/belly/proc/clear_preview(mob/living/living_prey)
	living_prey.previewing_belly = null
	living_prey.belly_overlay_tgui?.hide()
