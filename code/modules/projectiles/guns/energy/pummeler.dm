// -------------- Pummeler -------------
/obj/item/gun/energy/pummeler/get_mechanics_info(list/additional_information)
	return ..(list("This gun punts people away and has a chance of knocking them down briefly. It may also throw them over railings in the process!") + additional_information)

/obj/item/gun/energy/pummeler
	name = "hypersonic gun"
	desc = "For when you want to get that pesky marketing guy out of your face ASAP. The PML9 'Pummeler' fires one HUGE \
	sonic blast in the direction of fire, throwing the target away from you at high speed. Now you can REALLY \
	turn up the bass to max."
	description_fluff = ""
	description_antag = ""

	icon = 'icons/vore/custom_guns_vr.dmi'
	icon_state = "pum"

	icon_override = 'icons/vore/custom_guns_vr.dmi'
	item_state = "gun"

	fire_sound = SFX_EFFECTS_BASSCANNON
	projectile_type = /obj/item/projectile/pummel

	charge_cost = 600


	slot_flags = SLOT_BELT|SLOT_BACK
	w_class = ITEMSIZE_HUGE //.

//Projectile
/obj/item/projectile/pummel
	name = "sonic blast"
	icon_state = "sound"
	damage = 5
	embed_chance = 0
	vacuum_traversal = 0
	range = 6 //Scary name, but just deletes the projectile after this range

/obj/item/projectile/pummel/on_hit(atom/movable/target, blocked = 0)
	if(isliving(target))
		var/mob/living/L = target
		var/throwdir = get_dir(firer,L)
		if(prob(40) && !blocked)
			L.status_at_least(STAT_STUNNED, 1)
			L.status_at_least(STAT_CONFUSED, 1)
		L.throw_at(get_edge_target_turf(L, throwdir), rand(3,6), 10)

		if(istype(L, /mob/living/simple_mob/vore/alienanimals/startreader))
			var/mob/living/simple_mob/vore/alienanimals/startreader/S = L
			if(!S.flipped)
				S.injure(INJURY_BLUNT, 100, source = src)
				act_message(S, null, others = span_notice("%U% is flipped over!!!"))
				S.flipped = TRUE
				S.flip_cooldown = 10
				S.handle_flip()
		return 1
