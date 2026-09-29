/obj/structure/cult
	density = TRUE
	anchored = TRUE
	icon = 'icons/obj/cult.dmi'

/obj/structure/cult/cultify()
	return

/obj/structure/cult/talisman
	name = "Altar"
	desc = "A bloodstained altar dedicated to Nar-Sie."
	icon_state = "talismanaltar"

/obj/structure/cult/forge
	name = "Daemon forge"
	desc = "A forge used in crafting the unholy weapons used by the armies of Nar-Sie."
	icon_state = "forge"

/obj/structure/cult/pylon
	name = "Pylon"
	desc = "A floating crystal that hums with an unearthly energy."
	icon_state = "pylon"
	var/isbroken = 0
	light_range = 5
	light_color = "#3e0000"
	var/wepon_handle

	var/shatter_message = "The pylon shatters!"
	var/impact_sound = SFX_EFFECTS_GLASSHIT
	var/shatter_sound = SFX_EFFECTS_GLASSBR3

	var/activation_cooldown = 30 SECONDS
	COOLDOWN_DECLARE(activation_cooldown_until)

DECLARE_PERIODIC(/obj/structure/cult/pylon, PERIODIC_SLOW)

DECLARE_INTERACTIONS(/obj/structure/cult/pylon, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/structure/cult/pylon/proc/interaction_hand(mob/M, obj/item/held, datum/interaction/interaction)
	attackpylon(M, 5)
	return TRUE

/obj/structure/cult/pylon/attack_generic(mob/user, damage)
	attackpylon(user, damage)

/// Old attackby.
/obj/structure/cult/pylon/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	attackpylon(user, W.force)
	return INTERACTION_HANDLED_PASS

/obj/structure/cult/pylon/take_damage(damage)
	pylonhit(damage)

/obj/structure/cult/pylon/bullet_act(obj/item/projectile/Proj)
	pylonhit(Proj.get_structure_damage())

/obj/structure/cult/pylon/proc/pylonhit(damage)
	if(!isbroken)
		if(prob(1+ damage * 5))
			visible_message(span_danger("[shatter_message]"))
			om_task_periodic_stop(src)
			playsound(src,shatter_sound, 75, 1)
			isbroken = 1
			set_density(FALSE)
			icon_state = "[initial(icon_state)]-broken"
			set_light(0)

/obj/structure/cult/pylon/proc/attackpylon(mob/user as mob, damage)
	if(!isbroken)
		if(prob(1+ damage * 5))
			user.visible_message(
				span_danger("[user] smashed \the [src]!"),
				span_warning("You hit \the [src], and its crystal breaks apart!"),
				"You hear a tinkle of crystal shards."
				)
			om_task_periodic_stop(src)
			user.do_attack_animation(src)
			playsound(src,shatter_sound, 75, 1)
			isbroken = 1
			set_density(FALSE)
			icon_state = "[initial(icon_state)]-broken"
			set_light(0)
		else
			to_chat(user, "You hit \the [src]!")
			playsound(src,impact_sound, 75, 1)
	else
		if(prob(damage * 2))
			to_chat(user, "You pulverize what was left of \the [src]!")
			qdel(src)
		else
			to_chat(user, "You hit \the [src]!")
		playsound(src,impact_sound, 75, 1)

/obj/structure/cult/pylon/proc/repair(mob/user as mob)
	if(isbroken)
		om_task_periodic(src, PERIODIC_SLOW)
		to_chat(user, "You repair \the [src].")
		isbroken = 0
		set_density(TRUE)
		icon_state = initial(icon_state)
		set_light(5)

// Returns 1 if the pylon does something special.
/obj/structure/cult/pylon/proc/pylon_unique()
	COOLDOWN_START(src, activation_cooldown_until, activation_cooldown)
	return 0

/// Acts only while a player is near; otherwise it sleeps until one comes near.
/obj/structure/cult/pylon/periodic_step()
	if(!mob_near(world.view, TRUE))
		return sleep_until_mob_near(world.view, TRUE)
	if(!isbroken && (COOLDOWN_FINISHED(src, activation_cooldown_until)) && pylon_unique())
		flick("[initial(icon_state)]-surge",src)

/obj/structure/cult/tome
	name = "Desk"
	desc = "A desk covered in arcane manuscripts and tomes in unknown languages. Looking at the text makes your skin crawl."
	icon_state = "tomealtar"

//sprites for this no longer exist	-Pete
//(they were stolen from another game anyway)

/obj/effect/gateway
	name = "gateway"
	desc = "You're pretty sure that abyss is staring back."
	icon = 'icons/obj/cult.dmi'
	icon_state = "hole"
	density = TRUE
	unacidable = TRUE
	anchored = TRUE
	var/spawnable = null

/obj/effect/gateway/active
	light_range=5
	light_color="#ff0000"
	spawnable=list(
		/mob/living/simple_mob/animal/space/bats,
		/mob/living/simple_mob/creature,
		/mob/living/simple_mob/faithless
	)

/obj/effect/gateway/active/cult
	light_range=5
	light_color="#ff0000"
	spawnable=list(
		/mob/living/simple_mob/animal/space/bats/cult,
		/mob/living/simple_mob/creature/cult,
		/mob/living/simple_mob/faithless/cult
	)

/obj/effect/gateway/active/cult/cultify()
	return

/obj/effect/gateway/active/Initialize(mapload)
	. = ..()
	om_after(src, rand(30, 60) SECONDS, PROC_REF(spawn_and_qdel))

/obj/effect/gateway/active/proc/spawn_and_qdel()
	if(LAZYLEN(spawnable))
		var/t = pick(spawnable)
		new t(get_turf(src))
	qdel(src)

/obj/effect/gateway/active/Crossed(atom/A)
	if(A.is_incorporeal())
		return
	if(!isliving(A))
		return

	var/mob/living/M = A

	to_chat(M, span_danger("Walking into \the [src] is probably a bad idea, you think."))

/// LC-refs: wepon -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/cult/pylon/proc/wepon() as /obj/item
	return om_resolve(wepon_handle)
