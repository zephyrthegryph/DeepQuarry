/*
 * Bolt-Action Rifle
 */
/obj/item/gun/projectile/shotgun/pump/rifle
	name = "bolt-action rifle"
	desc = "The Weissen Company Type-19 is a modern interpretation of an almost ancient weapon design. \
	The model is popular among hunters and collectors due to its reliability. Uses 7.62mm rounds."
	description_fluff = "The frontier’s largest home-grown firearms manufacturer, \
	the Weissen Arms Company are the leading manufacturer of - not only quality - \
	but affordable rifles for the average frontiersman looking to protect his \
	claim. The company operates just one production plant in the Mytis system, \
	but their weapons have found popularity on garden worlds as far afield as \
	the Tajaran homeworld due to their excellent build quality, precision, and \
	stopping power. Thier bolt-action rifles and brushguns are a staple amongst \
	the rural communities that dot this infinite frontier."
	icon = 'icons/obj/gun.dmi'
	icon_state = "boltaction"
	item_state = "boltaction"
	fire_sound = SFX_WEAPONS_GUNSHOT_GENERIC_RIFLE
	max_shells = 5
	caliber = "7.62mm"// Old as shit rifle doesn't have very good tech.
	ammo_type = /obj/item/ammo_casing/a762
	load_method = SINGLE_CASING|SPEEDLOADER
	action_sound = SFX_WEAPONS_RIFLEBOLT
	pump_animation = "boltaction-cycling"

/*
 * Practice Rifle
 */
/obj/item/gun/projectile/shotgun/pump/rifle/practice // For target practice
	name = "practice bolt-action rifle"
	icon_state = "boltaction_practice"
	desc = "A bolt-action rifle with a lightweight synthetic wood stock, designed for competitive shooting. \
	Comes shipped with practice rounds pre-loaded into the gun. Popular among professional marksmen. Uses 7.62mm rounds."
	ammo_type = /obj/item/ammo_casing/a762/practice
	pump_animation = "boltaction_practice-cycling"
	max_shells = 4

/*
 * Moist Nugget
 */
/obj/item/gun/projectile/shotgun/pump/rifle/moistnugget
	name = "mosin-nagant"
	icon_state = "moistnugget"
	item_state = "rifle"
	desc = "Developed from 1882 to 1891, it was used by the armed forces of the Russian Empire, the Soviet \
	Union and various other nations. It is one of the most mass-produced military bolt-action rifles in history. Uses 7.62mm rounds."
	description_fluff = "Hailing from the Human homeworld, the M1891, otherwise known as the Mosin-Nagant is one of the most \
	prevalant and cheapest rifles of its time. This modern remake of the classic design was used by early colonists of the \
	Commonwealth to stake claims. It was favored because of how cheap and easy the weapon was to manufacture as well as its \
	ease of use making it a better choice for those that didn't have proper firearms training."
	ammo_type = /obj/item/ammo_casing/a762
	pump_animation = "moistnugget-cycling"

/*
 * Ceremonial Rifle
 */
/obj/item/gun/projectile/shotgun/pump/rifle/ceremonial
	name = "ceremonial bolt-action rifle"
	desc = "A bolt-action rifle with a heavy, high-quality wood stock that has a beautiful finish. \
	Clearly not intended to be used in combat. Uses 7.62mm rounds."
	item_state = "ceremonial_rifle"
	icon_state = "ceremonial_rifle"
	ammo_type = /obj/item/ammo_casing/a762/blank
	pump_animation = "ceremonial_rifle-cycling"
	max_shells = 5

	var/sawn_off = FALSE

/// Old attackby.
/obj/item/gun/projectile/shotgun/pump/rifle/ceremonial/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held, /obj/item/surgical/circular_saw) || istype(held, /obj/item/melee/energy) || istype(held, /obj/item/pickaxe/plasmacutter) && w_class != ITEMSIZE_NORMAL)
		. = OP_PASS
		if(sawn_off)
			to_chat(user, span_warning("The [src] is already shortened!"))
			return
		to_chat(user, span_notice("You begin to shorten the barrel and stock of \the [src]."))
		if(length(loaded))
			afterattack(user, user)
			playsound(src, fire_sound, 50, 1)
			act_message(user, src, MSG_SELF(span_danger("The rifle goes off in your face!")), MSG_OTHERS(span_danger("%T% goes off!")))
			return
		task_timed(user, 3 SECONDS, src, src, PROC_REF(saw_off_done), list(user))
	else
		return ..()

/obj/item/gun/projectile/shotgun/pump/rifle/ceremonial/proc/saw_off_done(mob/user)
	if(sawn_off)
		return
	icon_state = "sawn_rifle"
	w_class = ITEMSIZE_NORMAL
	recoil = 2 // Owch
	accuracy = -15 // You know damn well why.
	item_state = "gun"
	slot_flags &= ~SLOT_BACK // You can't sling it on your back
	slot_flags |= (SLOT_BELT|SLOT_HOLSTER) // But you can wear it on your belt (poorly concealed under a trenchcoat, ideally) - or in a holster, why not.
	name = "sawn-off rifle"
	desc = "The firepower of a rifle, now the size of a pistol, with an effective combat range of about three feet. Uses 7.62mm rounds."
	pump_animation = "sawn_rifle-cycling"
	to_chat(user, span_warning("You shorten the barrel and stock of \the [src]!"))
	sawn_off = TRUE

/*
 * Surplus Rifle
 */
/obj/item/gun/projectile/shotgun/pump/surplus
	name = "surplus rifle"
	desc = "An ancient weapon from an era long past, crude in design, but still just as effective \
	as any modern interpretation. Uses 7.62mm rounds."
	icon_state = "surplus"
	item_state = "rifle"
	fire_sound = SFX_WEAPONS_GUNSHOT_GENERIC_RIFLE
	max_shells = 4
	slot_flags = null
	caliber = "7.62mm" // Old(er) as shit rifle doesn't have very good tech.
	ammo_type = /obj/item/ammo_casing/a762
	load_method = SINGLE_CASING|SPEEDLOADER
	action_sound = SFX_WEAPONS_RIFLEBOLT
	pump_animation = "surplus-cycling"

/*
 * Scoped Rifle
 */
/obj/item/gun/projectile/shotgun/pump/rifle/scoped
	name = "scoped bolt-action rifle"
	desc = "The Weissen Company Type-19 is a modern interpretation of an almost ancient weapon design. \
	The model is popular among hunters and collectors due to its reliability. Uses 7.62mm rounds."
	description_fluff = "The frontier’s largest home-grown firearms manufacturer, \
	the Weissen Arms Company are the leading manufacturer of - not only quality - \
	but affordable rifles for the average frontiersman looking to protect his \
	claim. The company operates just one production plant in the Mytis system, \
	but their weapons have found popularity on garden worlds as far afield as \
	the Tajaran homeworld due to their excellent build quality, precision, and \
	stopping power. Thier bolt-action rifles and brushguns are a staple amongst \
	the rural communities that dot this infinite frontier."
	icon_state = "scoped-boltaction"
	item_state = "boltaction_scoped"
	fire_sound = SFX_WEAPONS_GUNSHOT_GENERIC_RIFLE
	max_shells = 5
	caliber = "7.62mm"// Old as shit rifle doesn't have very good tech, but it does have a scope.
	ammo_type = /obj/item/ammo_casing/a762
	load_method = SINGLE_CASING|SPEEDLOADER
	action_sound = SFX_WEAPONS_RIFLEBOLT
	pump_animation = "scoped-boltaction-cycling"

/obj/item/gun/projectile/shotgun/pump/rifle/ui_action_click(mob/user, actiontype)
	pump_rifle_verb_scope(user)

CAPABILITIES(/obj/item/gun/projectile/shotgun/pump/rifle)
	op("pump_rifle_verb_scope", menu(), label("Use Scope"), needs(carried()), then(PROC_REF(pump_rifle_verb_scope_op)))

/// The pump_rifle_verb_scope op: the verb's effect, as the old resolver ran it.
/obj/item/gun/projectile/shotgun/pump/rifle/proc/pump_rifle_verb_scope_op(datum/act/op/A)
	pump_rifle_verb_scope(A.actor, A.held)
	return OP_OK

/// Old Use Scope verb.
/obj/item/gun/projectile/shotgun/pump/rifle/proc/pump_rifle_verb_scope(mob/user, obj/item/held)



/obj/item/gun/projectile/shotgun/pump/rifle/vox_hunting
	name = "vox hunting rifle"
	desc = "This ancient rifle bears traces of an assembly meant to house power cells, implying it used to fire energy beams. It has since been crudely modified to fire standard 7.62mm rounds."
	icon_state = "vox_hunting" //Broken
	item_state = "vox_hunting"
	ammo_type = /obj/item/ammo_casing/a762
	throwforce = 10
	force = 20
