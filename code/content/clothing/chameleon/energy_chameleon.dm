//*****************
//**Chameleon Gun**
//*****************
/obj/item/gun/energy/chameleon
	name = "desert eagle"
	desc = "A hologram projector in the shape of a gun. There is a dial on the side to change the gun's disguise."
	icon_state = "deagle"
	w_class = ITEMSIZE_NORMAL
	MATERIAL_NONE

	fire_sound = SFX_WEAPONS_GUNSHOT1
	projectile_type = /obj/item/projectile/chameleon
	charge_meter = 0
	charge_cost = 48 //uses next to no power, since it's just holograms
	battery_lock = 1

	var/copy_projectile	// a projectile type path
	/// The icon_state of the gun it mimics (null: its own base sprite); the look draws it, so a redraw keeps the disguise.
	var/disguise_state

/// The look: the mimicked gun's sprite, whatever the charge.
/obj/item/gun/energy/chameleon/charge_state_name()
	return disguise_state ? disguise_state : initial(icon_state)

/obj/item/gun/energy/chameleon/on_materialize()
	if(!LAZYLEN(GLOB.gun_choices))
		for(var/gun_type in typesof(/obj/item/gun/) - src.type)
			var/obj/item/gun/G = gun_type
			GLOB.gun_choices[initial(G.name)] = gun_type
	. = ..()

/obj/item/gun/energy/chameleon/consume_next_projectile()
	var/obj/item/projectile/P = ..()
	var/obj/item/projectile/copy_type = copy_projectile
	if(P && ispath(copy_projectile))
		P.name = initial(copy_type.name)
		P.set_icon(initial(copy_type.icon))
		P.set_icon_state(initial(copy_type.icon_state))
		P.pass_flags = initial(copy_type.pass_flags)
		P.fire_sound = initial(copy_type.fire_sound)
		P.hitscan = initial(copy_type.hitscan)
		P.speed = initial(copy_type.speed)
		P.muzzle_type = initial(copy_type.muzzle_type)
		P.tracer_type = initial(copy_type.tracer_type)
		P.impact_type = initial(copy_type.impact_type)
	return P

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/gun/energy/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "desert eagle"
	desc = "It's a desert eagle."
	set_disguise_state("deagle")

/obj/item/gun/energy/chameleon/disguise(newtype)
	var/obj/item/gun/copy = ..()
	set_disguise_state(copy.icon_state)

	set_flags_inv(worn_of(copy).hides)
	if(copy.fire_sound)
		fire_sound = copy.fire_sound
	else
		fire_sound = null
	fire_sound_text = copy.fire_sound_text

	var/obj/item/gun/G = copy
	if(istype(G))
		copy_projectile = G.projectile_type
		//charge_meter = E.charge_meter //does not work very well with icon_state changes, ATM
	else
		copy_projectile = null

CAPABILITIES(/obj/item/gun/energy/chameleon)
	configure(atom_rules(description_antag = "This gun is actually a hologram projector that can alter its appearance to mimick other weapons.  To change the appearance, use \
	the appropriate verb in the chameleon items tab. Any beams or projectiles fired from this gun are actually holograms and useless for actual combat. \
	Projecting these holograms over distance uses a little bit of charge."))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("energy_chameleon_change_verb", menu(), label("Change Gun Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(energy_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(energy_chameleon_change_verb)))

/// Old verb "Change Gun Appearance".
/obj/item/gun/energy/chameleon/proc/energy_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.gun_choices

/obj/item/gun/energy/chameleon/proc/energy_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.gun_choices[picked]))
		return

	disguise(GLOB.gun_choices[picked])

	//so our overlays update.
