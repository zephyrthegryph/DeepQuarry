/obj/item/gun/launcher/grenade
	name = "grenade launcher"
	desc = "A bulky pump-action grenade launcher. Holds up to 6 grenades in a revolving magazine."
	icon_state = "riotgun"
	item_state = "riotgun"
	w_class = ITEMSIZE_HUGE //.
	force = 10

	fire_sound = SFX_WEAPONS_GRENADE_LAUNCHER
	fire_sound_text = "a metallic thunk"
	recoil = 0
	throw_distance = 7
	release_force = 5

	var/tmp/obj/item/grenade/chambered
	var/list/grenades
	var/max_grenades = 5 //holds this + one in the chamber
	MATERIAL_BULK(MAT_STEEL, 2000)
	special_handling = TRUE
	var/underslung = FALSE

// Loaded grenades sit in the launcher's contents; the chambered one is a view (chambered).
/obj/item/gun/launcher/grenade/ownership()
	. = ..()
	. += owns(nameof(grenades), policy = OWN_CONTAINED, is_list = TRUE)

//revolves the magazine, allowing players to choose between multiple grenade types
/obj/item/gun/launcher/grenade/proc/pump(mob/user)
	play_sfx(user, SFX_WEAPONS_SHOTGUNPUMP)

	var/obj/item/grenade/next
	if(length(grenades))
		next = LAZYACCESS(grenades, 1) //get this first, so that the chambered grenade can still be removed if the grenades list is empty
	if(chambered())
		rel_add(src, nameof(grenades), chambered()) //rotate the revolving magazine
		rel_clear(src, nameof(chambered))
	if(next)
		own_take_member(src, nameof(grenades), next) //Remove grenade from loaded list (it stays in our contents, chambered).
		rel_set(src, nameof(chambered), next)
		to_chat(user, span_warning("You pump [src], loading \a [next] into the chamber."))
	else
		to_chat(user, span_warning("You pump [src], but the magazine is empty."))

/obj/item/gun/launcher/grenade/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		var/grenade_count = length(grenades) + (chambered()? 1 : 0)
		. += "Has [grenade_count] grenade\s remaining."
		if(chambered())
			. += "\A [chambered()] is chambered."

/obj/item/gun/launcher/grenade/proc/load(obj/item/grenade/G, mob/user)
	if(G.loadable)
		if(length(grenades) >= max_grenades)
			to_chat(user, span_warning("[src] is full."))
			return
		if(!move_into(src, nameof(src.grenades), G, user))
			return
		moveElement(grenades, length(grenades), 1) //to the head of the list, so that it is loaded on the next pump
		act_message(user, src, MSG_SELF(span_notice("You insert \a [G] into %T%.")), MSG_OTHERS("%U% inserts \a [G] into %T%."))
		return
	to_chat(user, span_warning("[G] doesn't seem to fit in the [src]!"))

/obj/item/gun/launcher/grenade/proc/unload(mob/user)
	if(length(grenades))
		var/obj/item/grenade/G = own_take_member(src, nameof(grenades), grenades[length(grenades)])
		user.put_in_hands(G)
		act_message(user, src, MSG_SELF(span_notice("You remove \a [G] from %T%.")), MSG_OTHERS("%U% removes \a [G] from %T%."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
	else
		to_chat(user, span_warning("[src] is empty."))

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/grenade/gun_self(datum/act/op/A, callback)
	var/mob/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	if(underslung)
		return OP_DECLINE
	pump(user)

/// Old attackby.
/obj/item/gun/launcher/grenade/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if((istype(I, /obj/item/grenade)))
		load(I, user)
		return OP_PASS
	return ..()

CAPABILITIES(/obj/item/gun/launcher/grenade)
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/item/gun/launcher/grenade/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		unload(user)
	else
		return OP_DECLINE
	return TRUE

/obj/item/gun/launcher/grenade/consume_next_projectile()
	if(chambered())
		chambered().det_time = 10
		chambered().activate(null)
	return chambered()

/obj/item/gun/launcher/grenade/handle_post_fire(mob/user)
	message_admins("[key_name_admin(user)] fired a grenade ([chambered().name]) from a grenade launcher ([src.name]).")
	log_game("[key_name_admin(user)] used a grenade ([chambered().name]).")
	rel_clear(src, nameof(chambered))

//Underslung grenade launcher to be used with the Z8
/obj/item/gun/launcher/grenade/underslung
	name = "underslung grenade launcher"
	desc = "Not much more than a tube and a firing mechanism, this grenade launcher is designed to be fitted to a rifle."
	w_class = ITEMSIZE_NORMAL
	force = 5
	max_grenades = 0
	underslung = TRUE

//load and unload directly into chambered
/obj/item/gun/launcher/grenade/underslung/load(obj/item/grenade/G, mob/user)
	if(G.loadable)
		if(chambered())
			to_chat(user, span_warning("[src] is already loaded."))
			return
		user.remove_from_mob(G)
		G.forceMove(src)
		rel_set(src, nameof(chambered), G)
		act_message(user, src, MSG_SELF(span_notice("You load \a [G] into %T%.")), MSG_OTHERS("%U% load \a [G] into %T%."))
		return
	to_chat(user, span_warning("[G] doesn't seem to fit in the [src]!"))

/obj/item/gun/launcher/grenade/underslung/unload(mob/user)
	if(chambered())
		user.put_in_hands(chambered())
		act_message(user, src, MSG_SELF(span_notice("You remove \a [chambered()] from %T%.")), MSG_OTHERS("%U% removes \a [chambered()] from %T%."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		rel_clear(src, nameof(chambered))
	else
		to_chat(user, span_warning("[src] is empty."))

/// the chambered this refers to (a relation view: null once it is deleted).
/obj/item/gun/launcher/grenade/proc/chambered() as /obj/item/grenade
	return chambered
