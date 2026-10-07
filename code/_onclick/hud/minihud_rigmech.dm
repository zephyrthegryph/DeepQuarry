// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// Specific types
/datum/mini_hud/rig
	var/obj/item/rig/owner_rig
	var/atom/movable/screen/rig/power/power
	var/atom/movable/screen/rig/health/health
	var/atom/movable/screen/rig/air/air
	var/atom/movable/screen/rig/airtoggle/airtoggle

	needs_processing = TRUE

/datum/mini_hud/rig/New(datum/hud/other, obj/item/rig/owner)
	rel_set(src, nameof(owner_rig), owner)
	// screenobjs owns every element; power/health/air/airtoggle are views into it.
	rel_set(src, nameof(power), rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/power ()))
	rel_set(src, nameof(health), rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/health ()))
	rel_set(src, nameof(air), rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/air ()))
	rel_set(src, nameof(airtoggle), rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/airtoggle ()))
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/deco1)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/deco2)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/deco1_f)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/rig/deco2_f)

	for(var/atom/movable/screen/S as anything in screenobjs)
		rel_set(S, nameof(S.master_ref), owner_rig())
	..()

/datum/mini_hud/rig/hud_step()
	if(!owner_rig())
		ended_with(src)
		return

	var/obj/item/cell/rigcell = owner_rig().cell
	var/obj/item/tank/rigtank = owner_rig().air_supply

	var/charge_percentage = rigcell ? rigcell.charge / rigcell.maxcharge : 0
	var/air_percentage = rigtank?.air_contents ? CLAMP(rigtank.air_contents.total_moles() / 17.4693, 0, 1) : 0
	var/air_on = owner_rig().wearer()?.internal ? 1 : 0

	power.icon_state = "pwr[round(charge_percentage / 0.2, 1)]"
	air.icon_state = "air[round(air_percentage / 0.2, 1)]"
	health.icon_state = owner_rig().malfunctioning ? "health1" : "health5"
	airtoggle.icon_state = "airon[air_on]"

/datum/mini_hud/mech
	var/obj/mecha/owner_mech
	var/atom/movable/screen/mech/power/power
	var/atom/movable/screen/mech/health/health
	var/atom/movable/screen/mech/air/air
	var/atom/movable/screen/mech/airtoggle/airtoggle

	needs_processing = TRUE

/datum/mini_hud/mech/New(datum/hud/other, obj/mecha/owner)
	rel_set(src, nameof(owner_mech), owner)
	// screenobjs owns every element; power/health/air/airtoggle are views into it.
	rel_set(src, nameof(power), rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/power ()))
	rel_set(src, nameof(health), rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/health ()))
	rel_set(src, nameof(air), rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/air ()))
	rel_set(src, nameof(airtoggle), rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/airtoggle ()))
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/deco1)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/deco2)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/deco1_f)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/mech/deco2_f)

	for(var/atom/movable/screen/S as anything in screenobjs)
		rel_set(S, nameof(S.master_ref), owner_mech())
	..()

// the mech owns us as its minihud; owner_mech is a plain relation back.

/datum/mini_hud/mech/hud_step()
	if(!owner_mech())
		ended_with(src)
		return

	var/obj/item/cell/mechcell = owner_mech().cell
	var/obj/machinery/portable_atmospherics/canister/mechtank = owner_mech().internal_tank

	var/charge_percentage = mechcell ? mechcell.charge / mechcell.maxcharge : 0
	var/air_percentage = mechtank ? CLAMP(mechtank.air_contents.total_moles() / 1863.47, 0, 1) : 0
	var/health_percentage = owner_mech().get_integrity() / owner_mech().max_integrity
	var/air_on = owner_mech().use_internal_tank

	power.icon_state = "pwr[round(charge_percentage / 0.2, 1)]"
	air.icon_state = "air[round(air_percentage / 0.2, 1)]"
	health.icon_state = "health[round(health_percentage / 0.2, 1)]"
	airtoggle.icon_state = "airon[air_on]"

// Screen objects
/atom/movable/screen/rig
	icon = 'icons/mob/screen_rigmech.dmi'

/atom/movable/screen/rig/deco1
	name = "RIG Status"
	icon_state = "frame1_1"
	screen_loc = ui_rig_deco1

/atom/movable/screen/rig/deco2
	name = "RIG Status"
	icon_state = "frame1_2"
	screen_loc = ui_rig_deco2

/atom/movable/screen/rig/deco1_f
	name = "RIG Status"
	icon_state = "frame1_1_far"
	screen_loc = ui_rig_deco1_f

/atom/movable/screen/rig/deco2_f
	name = "RIG Status"
	icon_state = "frame1_2_far"
	screen_loc = ui_rig_deco2_f

/atom/movable/screen/rig/power
	name = "Charge Level"
	icon_state = "pwr5"
	screen_loc = ui_rig_pwr

/atom/movable/screen/rig/health
	name = "Integrity Level"
	icon_state = "health5"
	screen_loc = ui_rig_health

/atom/movable/screen/rig/air
	name = "Air Storage"
	icon_state = "air5"
	screen_loc = ui_rig_air

/atom/movable/screen/rig/airtoggle
	name = "Toggle Air"
	icon_state = "airoff"
	screen_loc = ui_rig_airtoggle

CAPABILITIES(/atom/movable/screen/rig/airtoggle)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/rig/airtoggle/proc/click_input(datum/act/input/A)
	toggle_air_with_actor(A.actor)
	return TRUE

/atom/movable/screen/rig/airtoggle/proc/toggle_air_with_actor(mob/living/carbon/human/user)
	if(!istype(user) || user.stat || user.incapacitated())
		return
	var/obj/item/rig/owner_rig = master_ref
	if(!owner_rig || user != owner_rig.wearer())
		return
	user.toggle_internals(user)

/atom/movable/screen/mech
	icon = 'icons/mob/screen_rigmech.dmi'

/atom/movable/screen/mech/deco1
	name = "Mech Status"
	icon_state = "frame1_1"
	screen_loc = ui_mech_deco1

/atom/movable/screen/mech/deco2
	name = "Mech Status"
	icon_state = "frame1_2"
	screen_loc = ui_mech_deco2

/atom/movable/screen/mech/deco1_f
	name = "Mech Status"
	icon_state = "frame1_1_far"
	screen_loc = ui_mech_deco1_f

/atom/movable/screen/mech/deco2_f
	name = "Mech Status"
	icon_state = "frame1_2_far"
	screen_loc = ui_mech_deco2_f

/atom/movable/screen/mech/power
	name = "Charge Level"
	icon_state = "pwr5"
	screen_loc = ui_mech_pwr

/atom/movable/screen/mech/health
	name = "Integrity Level"
	icon_state = "health5"
	screen_loc = ui_mech_health

/atom/movable/screen/mech/air
	name = "Air Storage"
	icon_state = "air5"
	screen_loc = ui_mech_air

/atom/movable/screen/mech/airtoggle
	name = "Toggle Air"
	icon_state = "airoff"
	screen_loc = ui_mech_airtoggle

CAPABILITIES(/atom/movable/screen/mech/airtoggle)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/mech/airtoggle/proc/click_input(datum/act/input/A)
	toggle_air_with_actor(A.actor)
	return TRUE

/atom/movable/screen/mech/airtoggle/proc/toggle_air_with_actor(mob/living/carbon/human/user)
	if(!istype(user) || user.stat || user.incapacitated())
		return
	var/obj/mecha/owner_mech = master_ref
	if(user != owner_mech?.slot_item(MECHA_SLOT_PILOT))
		return
	owner_mech.toggle_internal_tank(user)


/// The rig this hud shows (a relation view: null once that is deleted).
/datum/mini_hud/rig/proc/owner_rig() as /obj/item/rig
	return owner_rig

/// The mech this hud shows (a relation view: null once that is deleted).
/datum/mini_hud/mech/proc/owner_mech() as /obj/mecha
	return owner_mech

