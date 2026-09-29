// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// Specific types
/datum/mini_hud/rig
	var/owner_rig_handle
	var/atom/movable/screen/rig/power/power
	var/atom/movable/screen/rig/health/health
	var/atom/movable/screen/rig/air/air
	var/atom/movable/screen/rig/airtoggle/airtoggle

	needs_processing = TRUE

/datum/mini_hud/rig/New(datum/hud/other, obj/item/rig/owner)
	owner_rig_handle = om_handle(owner)
	power = new ()
	health = new ()
	air = new ()
	airtoggle = new ()

	screenobjs = list(power, health, air, airtoggle)
	screenobjs += new /atom/movable/screen/rig/deco1
	screenobjs += new /atom/movable/screen/rig/deco2
	screenobjs += new /atom/movable/screen/rig/deco1_f
	screenobjs += new /atom/movable/screen/rig/deco2_f

	for(var/atom/movable/screen/S as anything in screenobjs)
		S.master_ref = om_handle(owner_rig())
	..()

/datum/mini_hud/rig/periodic_step()
	if(!owner_rig())
		qdel(src)
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
	var/owner_mech_handle
	var/atom/movable/screen/mech/power/power
	var/atom/movable/screen/mech/health/health
	var/atom/movable/screen/mech/air/air
	var/atom/movable/screen/mech/airtoggle/airtoggle

	needs_processing = TRUE

/datum/mini_hud/mech/New(datum/hud/other, obj/mecha/owner)
	owner_mech_handle = om_handle(owner)
	power = new ()
	health = new ()
	air = new ()
	airtoggle = new ()

	screenobjs = list(power, health, air, airtoggle)
	screenobjs += new /atom/movable/screen/mech/deco1
	screenobjs += new /atom/movable/screen/mech/deco2
	screenobjs += new /atom/movable/screen/mech/deco1_f
	screenobjs += new /atom/movable/screen/mech/deco2_f

	for(var/atom/movable/screen/S as anything in screenobjs)
		S.master_ref = om_handle(owner_mech())
	..()

// the mech points at its minihud; the minihud going clears that var.

/datum/mini_hud/mech/periodic_step()
	if(!owner_mech())
		qdel(src)
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

/atom/movable/screen/rig/airtoggle/Click()
	var/mob/living/carbon/human/user = usr
	if(!istype(user) || user.stat || user.incapacitated())
		return
	var/obj/item/rig/owner_rig = om_resolve(master_ref)
	if(!owner_rig || user != owner_rig.wearer())
		return
	user.toggle_internals()

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

/atom/movable/screen/mech/airtoggle/Click()
	var/mob/living/carbon/human/user = usr
	if(!istype(user) || user.stat || user.incapacitated())
		return
	var/obj/mecha/owner_mech = om_resolve(master_ref)
	if(user != owner_mech?.slot_item(MECHA_SLOT_PILOT))
		return
	owner_mech.toggle_internal_tank()


/// LC-refs: the rig this hud shows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/rig/proc/owner_rig() as /obj/item/rig
	return om_resolve(owner_rig_handle)

/// LC-refs: the mech this hud shows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/mech/proc/owner_mech() as /obj/mecha
	return om_resolve(owner_mech_handle)


