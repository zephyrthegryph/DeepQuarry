/obj/item/ammo_casing/macrobattery
	caliber = "macrobat"
	name = "macrobattery"
	icon = 'icons/obj/ammo_vr.dmi'
	icon_state = "macrobat_wtf"
	desc = "A large nanite fabricator for a Curabitur cannon. Powered by a mix of precursor and modern tech, this fancy device recharges without an outside power source. Takes approximately three seconds to charge one shot." // Clearer charge time

	projectile_type = /obj/item/projectile/beam/chain_lightning //why the hell not

	var/bat_colour = "#ff33cc"
	var/max_charge = 10
	var/ticks = 1
	var/ticks_to_charge = 3 // Reduced from 15 ticks to 3 for a faster recharge, which comes out to around 3 seconds on a localhost. These things are VERY rare.

OM_FIELD(/obj/item/ammo_casing/macrobattery, charge, null, CHANGE_EXPLICIT)
/// Below full charge: derived from charge (raised by set_charge()).
OM_DERIVE_FIELD(/obj/item/ammo_casing/macrobattery, charge_short, list("charge"))
/obj/item/ammo_casing/macrobattery/proc/charge_short()
	return charge < max_charge
/// Recharges while below full; full, it parks until a shot is expended.
DECLARE_PERIODIC_WHILE(/obj/item/ammo_casing/macrobattery, PERIODIC_SLOW, "charge_short")

/obj/item/ammo_casing/macrobattery/Initialize(mapload, ...)
	. = ..()
	set_charge(max_charge)

/obj/item/ammo_casing/macrobattery/periodic_step()
	ticks++
	if(ticks%ticks_to_charge == 0)
		recharge()

/obj/item/ammo_casing/macrobattery/expend()
	if(charge)
		ticks = 1 //so we have to start over on the charge time.
		set_charge(charge - 1)
		. = BB
		//alright, the below seems jank. it IS jank, but for whatever reason I can't reuse BB. big bad
		rel_take(src, nameof(BB))
		rel_set(src, nameof(BB), new projectile_type)
		// TGMC Ammo HUD - Update the HUD every time we expend/fire, given the Curabitur's method of handling firing.
		if(istype(loc, /obj/item/gun/projectile/multi_cannon))
			var/obj/item/gun/projectile/multi_cannon = loc
			var/mob/living/user = multi_cannon.loc
			if(istype(user))
				user?.hud_used?.update_ammo_hud(user, multi_cannon)
		return
	else
		rel_clear(src, nameof(BB))
		return null

/obj/item/ammo_casing/macrobattery/proc/recharge()
	if(charge < max_charge)
		set_charge(charge + 1)
		if(!BB)
			rel_set(src, nameof(BB), new projectile_type)
	if(istype(loc,/obj/item/gun/projectile/multi_cannon))
		loc.update_icon()

	// TGMC Ammo HUD - Update the HUD every time we're called to recharge.
	if(istype(loc, /obj/item/gun/projectile/multi_cannon))
		var/obj/item/gun/projectile/multi_cannon = loc
		var/mob/living/user = multi_cannon.loc
		if(istype(user))
			user?.hud_used?.update_ammo_hud(user, multi_cannon)

//variants here, there's not many of them.

/obj/item/ammo_casing/macrobattery/stabilize
	name = "Macrobattery - STABILIZE"
	icon_state = "macrobat_stabilize"
	desc = "A large nanite fabricator for a Curabitur cannon. Powered by a mix of precursor and modern tech, \
			this fancy device recharges without an outside power source. This one alleviates oxygen loss, disinfects and closes open wounds, \
			salves burn wounds and stabilizes the patient's heartrate. Takes approximately three \
			seconds to charge one shot." // Clearer applied effects
	bat_colour = "#3399ff"
	projectile_type = /obj/item/projectile/beam/medical_cell/stabilize2

/obj/item/ammo_casing/macrobattery/buff
	name = "Macrobattery - BOOSTER"
	icon_state = "macrobat_uber"
	desc = "A large nanite fabricator for a Curabitur cannon. Powered by a mix of precursor and modern tech, \
			this fancy device recharges without an outside power source. This one provides patients with a 15% resistance to incoming damage \
			and reduces stun effect times by 15% for 20 seconds. Takes approximately three seconds to charge one shot." // Clearer applied effects
	bat_colour = "#993300"
	projectile_type = /obj/item/projectile/beam/medical_cell/resist

/obj/item/ammo_casing/macrobattery/detox
	name = "Macrobattery - DETOX"
	icon_state = "macrobat_purifier"
	desc = "A large nanite fabricator for a Curabitur cannon. Powered by a mix of precursor and modern tech, \
			this fancy device recharges without an outside power source. This one removes toxins and radiation buildup from a patient. \
			Takes approximately three seconds to charge one shot." // Clearer applied effects
	bat_colour = "#339933"
	projectile_type = /obj/item/projectile/beam/medical_cell/detox

/obj/item/ammo_casing/macrobattery/ouchie
	name = "Macrobattery - LETHAL"
	icon_state = "macrobat_ouchie"
	desc = "A large nanite fabricator for a Curabitur cannon. Powered by a mix of precursor and modern tech, \
			this fancy device recharges without an outside power source. This one deals damage. \
			Takes approximately three seconds to charge one shot." // Clearer applied effects
	bat_colour = "#cc3300"
	projectile_type = /obj/item/projectile/beam/heavylaser/lessheavy

/obj/item/ammo_casing/macrobattery/healie
	name = "Macrobattery - RESTORE"
	icon_state = "macrobat_inverseouchie"
	desc = "A large nanite fabricator for a Curabitur cannon. Powered by a mix of precursor and modern tech, \
			this fancy device recharges without an outside power source. This one alleviates burn and brute trauma. \
			Takes approximately three seconds to charge one shot." // Clearer applied effects
	bat_colour = "#ff9966"
	projectile_type = /obj/item/projectile/beam/medical_cell/phys_heal

/obj/item/projectile/beam/medical_cell/phys_heal/on_hit(mob/living/carbon/human/target)
	if(ishuman(target))
		target.mend(TREAT_TISSUE_REPAIR, 20)
		target.mend(TREAT_BURN_CARE, 20)
	else
		return 1

/obj/item/projectile/beam/medical_cell/detox/on_hit(mob/living/carbon/human/target)
	if(ishuman(target))
		target.mend(TREAT_ANTITOXIN, 15)
		target.purge_radiation(75) //worse than mlem for rad, better for tox.
	else
		return 1

/obj/item/projectile/beam/heavylaser/lessheavy //all bark. no (or little) bite.
	damage = 15
	fire_sound = SFX_WEAPONS_GUNSHOT_CANNON
