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
	light_range = 5
	light_color = "#3e0000"
	var/obj/item/wepon

	var/shatter_message = "The pylon shatters!"
	var/impact_sound = SFX_EFFECTS_GLASSHIT
	var/shatter_sound = SFX_EFFECTS_GLASSBR3

	var/activation_cooldown = 30 SECONDS
	COOLDOWN_DECLARE(activation_cooldown_until)

/obj/structure/cult/pylon/var/isbroken = FALSE
TRACKED(/obj/structure/cult/pylon, isbroken)
CAPABILITIES(/obj/structure/cult/pylon)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	/// Surges near players while intact; a broken pylon does nothing until repaired.
	every(2 SECONDS, then(PROC_REF(pylon_step)), when = cond_not(nameof(isbroken)))
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_hand.
/obj/structure/cult/pylon/proc/interaction_hand(datum/act/op/A)
	var/mob/M = A.actor
	attackpylon(M, 5)
	return TRUE

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/cult/pylon/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	var/damage = A.damage
	attackpylon(user, damage)
	return OP_OK

/// Old attackby.
/obj/structure/cult/pylon/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	attackpylon(user, W.force)
	return OP_PASS

/obj/structure/cult/pylon/take_damage(damage)
	pylonhit(damage)

/obj/structure/cult/pylon/bullet_act(obj/item/projectile/Proj)
	pylonhit(Proj.get_structure_damage())

/obj/structure/cult/pylon/proc/pylonhit(damage)
	if(!isbroken)
		if(prob(1+ damage * 5))
			visible_message(span_danger("[shatter_message]"))
			playsound(src,shatter_sound, 75, 1)
			set_isbroken(TRUE)
			set_density(FALSE)
			icon_state = "[initial(icon_state)]-broken"
			set_light(0)

/obj/structure/cult/pylon/proc/attackpylon(mob/user as mob, damage)
	if(!isbroken)
		if(prob(1+ damage * 5))
			act_message(user, src, MSG_SELF(span_warning("You hit %T%, and its crystal breaks apart!")), \
				MSG_OTHERS(span_danger("%U% smashed %T%!")), \
				MSG_BLIND("You hear a tinkle of crystal shards."))
			user.do_attack_animation(src)
			playsound(src,shatter_sound, 75, 1)
			set_isbroken(TRUE)
			set_density(FALSE)
			icon_state = "[initial(icon_state)]-broken"
			set_light(0)
		else
			to_chat(user, "You hit \the [src]!")
			playsound(src,impact_sound, 75, 1)
	else
		if(prob(damage * 2))
			to_chat(user, "You pulverize what was left of \the [src]!")
			consume(src, user)
		else
			to_chat(user, "You hit \the [src]!")
		playsound(src,impact_sound, 75, 1)

/obj/structure/cult/pylon/proc/repair(mob/user as mob)
	if(isbroken)
		to_chat(user, "You repair \the [src].")
		set_isbroken(FALSE)
		set_density(TRUE)
		icon_state = initial(icon_state)
		set_light(5)

// Returns 1 if the pylon does something special.
/obj/structure/cult/pylon/proc/pylon_unique()
	COOLDOWN_START(src, activation_cooldown_until, activation_cooldown)
	return 0

/// Acts only while a player is near; otherwise it sleeps until one comes near.
/obj/structure/cult/pylon/proc/pylon_step(datum/act/timer/A)
	if(!mob_near(world.view, TRUE))
		return sleep_until_mob_near(world.view, TRUE)
	if(COOLDOWN_FINISHED(src, activation_cooldown_until) && pylon_unique())
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

CAPABILITIES(/obj/effect/gateway/active)
	after_init(PROC_REF(open_delay), then(PROC_REF(spawn_and_qdel)))

/// An open gateway lets something through after 30 to 60 seconds.
/obj/effect/gateway/active/proc/open_delay(datum/act/timer/A)
	return rand(30, 60) SECONDS

/obj/effect/gateway/active/proc/spawn_and_qdel(datum/act/timer/A)
	if(LAZYLEN(spawnable))
		var/t = pick(spawnable)
		new t(get_turf(src))
	consume(src)

/obj/effect/gateway/active/Crossed(atom/A)
	if(A.is_incorporeal())
		return
	if(!isliving(A))
		return

	var/mob/living/M = A

	to_chat(M, span_danger("Walking into \the [src] is probably a bad idea, you think."))

/// Wepon (a relation view).
/obj/structure/cult/pylon/proc/wepon() as /obj/item
	return wepon
