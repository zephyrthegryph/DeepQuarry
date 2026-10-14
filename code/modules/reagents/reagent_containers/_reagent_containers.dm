/obj/item/reagent_containers
	name = "Container"
	desc = "..."
	icon = 'icons/obj/chemical.dmi'
	icon_state = null
	w_class = ITEMSIZE_SMALL
	var/amount_per_transfer_from_this = 5
	var/max_transfer_amount = 30
	var/min_transfer_amount = 5
	var/volume = 30

/// What one transfer from this moves: the setting var of a container that is not converted yet.
/obj/item/reagent_containers/legacy_transfer_amount()
	return amount_per_transfer_from_this

// Every container gets a holder of its (possibly mapped) volume; subtypes declare what starts in it
// (doc/rewrite/declarative_lifecycle.md).
CAPABILITIES(/obj/item/reagent_containers)
	reagents(nameof(volume))

/obj/item/reagent_containers/afterattack(obj/target, mob/user, flag)
	return

/obj/item/reagent_containers/proc/reagentlist() // For attack logs
	if(reagents)
		return reagents.get_reagents()
	return "No reagent holder"

/obj/item/reagent_containers/proc/self_feed_message(mob/user)
	balloon_alert(user, "you eat \the [src]")

/obj/item/reagent_containers/proc/other_feed_message_start(mob/user, mob/target)
	balloon_alert_visible(user, "[user] is trying to feed [target] \the [src]!")

/obj/item/reagent_containers/proc/other_feed_message_finish(mob/user, mob/target)
	balloon_alert_visible(user, "[user] has fed [target] \the [src]!")

/obj/item/reagent_containers/proc/feed_sound(mob/user)
	return

/// Why user can't put something in target's mouth (no mouth, or a mask in the way), or null.
/proc/mouth_blocked_reason(mob/user, mob/target)
	if(!ishuman(target))
		return null
	var/mob/living/carbon/human/H = target
	if(!H.check_has_mouth())
		return "[user == target ? "you don't" : "\the [H] doesn't"] have a mouth!"
	var/obj/item/blocked = H.check_mouth_coverage()
	if(blocked)
		return "\the [blocked] is in the way!"
	return null

/// Whether source holds a reagent produced from a belly (refused by mobs that don't consume those).
/proc/reagents_from_belly(atom/source)
	if(!source?.reagents)
		return FALSE
	for(var/datum/reagent/R in source.reagents.reagent_list)
		if(R.from_belly)
			return TRUE
	return FALSE

/obj/item/reagent_containers/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run = FALSE)
	. = ..()
	EXTRAPOLATOR_ACT_SET(., EXTRAPOLATOR_ACT_PRIORITY_ISOLATE)
	var/datum/reagent/blood/blood = reagents.get_reagent(REAGENT_ID_BLOOD)
	EXTRAPOLATOR_ACT_ADD_DISEASES(., blood?.get_diseases())

/// A hot thing held over an open container with blood in it.
/obj/item/reagent_containers/proc/blood_test_fits(datum/act/op/A)
	var/obj/item/held = A.held
	return (!isnull(held) && is_open_container() && !!reagents.get_reagent(REAGENT_ID_BLOOD) && held.is_hot()) ? null : /datum/msg/req_failed

/// The heat shows a changeling's blood for what it is.
/obj/item/reagent_containers/proc/blood_tested(datum/act/op/A)
	var/datum/reagent/blood/B = reagents.get_reagent(REAGENT_ID_BLOOD)
	if(B)
		balloon_alert(A.actor, "\The [A.held] burns the blood in \the [src].")
		B.changling_blood_test(reagents)
	return OP_OK
