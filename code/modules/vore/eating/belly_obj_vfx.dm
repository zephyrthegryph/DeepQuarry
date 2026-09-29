//
// (Stage 5): belly fullscreen overlay has been migrated to a TGUI
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
		rel_clear(living_prey, "previewing_belly")
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
		rel_clear(living_prey, "previewing_belly")
		return
	rel_set(living_prey, "previewing_belly", src)
	vore_fx(living_prey)
	belly_reschedule() // A previewed belly keeps its liquid overlay current each cycle.

/obj/belly/proc/clear_preview(mob/living/living_prey)
	rel_clear(living_prey, "previewing_belly")
	living_prey.belly_overlay_tgui?.hide()
