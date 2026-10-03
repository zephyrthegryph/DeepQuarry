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
	/// FALSE hides the Set transfer amount Menu entry (sprays, canisters), as dropping the old set_APTFT verb did.
	var/transfer_amount_verb = TRUE

/// What one transfer from this moves: the setting var of a container that is not converted yet.
/obj/item/reagent_containers/legacy_transfer_amount()
	return amount_per_transfer_from_this

/// Old Set transfer amount verb.
/obj/item/reagent_containers/proc/reagent_container_verb_set_transfer(mob/user, obj/item/held, datum/interaction/interaction)
	var/N = rerun_ask(user, "a1", PROC_REF(reagent_container_verb_set_transfer), args, /datum/om/prompt/number, message = "Amount per transfer from this: ([min_transfer_amount]-[max_transfer_amount])", title = "[src]", default = amount_per_transfer_from_this, max = max_transfer_amount, min = min_transfer_amount)
	if(isnull(N))
		return
	if(N)
		amount_per_transfer_from_this = N

// Every container gets a holder of its (possibly mapped) volume; subtypes declare what starts in it
// (doc/rewrite/declarative_lifecycle.md).
DECLARE_REAGENTS(/obj/item/reagent_containers, "volume", null)

/obj/item/reagent_containers/afterattack(obj/target, mob/user, flag)
	return

/obj/item/reagent_containers/proc/reagentlist() // For attack logs
	if(reagents)
		return reagents.get_reagents()
	return "No reagent holder"

/obj/item/reagent_containers/proc/standard_dispenser_refill(mob/user, obj/structure/reagent_dispensers/target) // This goes into afterattack
	if(!istype(target))
		return 0

	if(target.open_top)
		return 0

	if(!target.reagents || !target.reagents.total_volume)
		balloon_alert(user, "[target] is empty.")
		return 1

	if(reagents && !reagents.get_free_space())
		balloon_alert(user, "[src] is full.")
		return 1

	var/trans = target.reagents.trans_to_obj(src, target.amount_per_transfer_from_this, user = user)
	balloon_alert(user, "[trans] units transfered to \the [src]")
	return 1

/obj/item/reagent_containers/proc/standard_splash_mob(mob/user, mob/target) // This goes into afterattack
	if(!istype(target))
		return

	if(!reagents || !reagents.total_volume)
		balloon_alert(user, "[src] is empty!")
		return 1

	if(target.reagents && !target.reagents.get_free_space())
		balloon_alert(user, "\the [target] is full!")
		return 1

	var/contained = reagentlist()
	add_attack_logs(user,target,"Splashed with [src.name] containing [contained]")
	balloon_alert_visible("[target] is splashed with something by [user]!", "splashed the solution onto [target]")
	reagents.splash(target, reagents.total_volume, user = user)
	return 1

/obj/item/reagent_containers/proc/self_feed_message(mob/user)
	balloon_alert(user, "you eat \the [src]")

/obj/item/reagent_containers/proc/other_feed_message_start(mob/user, mob/target)
	balloon_alert_visible(user, "[user] is trying to feed [target] \the [src]!")

/obj/item/reagent_containers/proc/other_feed_message_finish(mob/user, mob/target)
	balloon_alert_visible(user, "[user] has fed [target] \the [src]!")

/obj/item/reagent_containers/proc/feed_sound(mob/user)
	return

/obj/item/reagent_containers/proc/standard_feed_mob(mob/user, mob/target) // This goes into attack
	if(!istype(target) || !target.can_feed())
		return FALSE

	if(!reagents || !reagents.total_volume)
		balloon_alert(user, "\the [src] is empty.")
		return TRUE

	if(!target.consume_liquid_belly)
		if(liquid_belly_check())
			to_chat(user, span_infoplain("[user == target ? "you can't" : "\The [target] can't"] consume that, it contains something produced from a belly!"))
			return FALSE

	var/mouth_reason = mouth_blocked_reason(user, target)
	if(mouth_reason)
		balloon_alert(user, mouth_reason)
		return FALSE

	user.setClickCooldown(user.get_attack_speed(src)) //puts a limit on how fast people can eat/drink things
	if(user == target)
		self_feed_message(user)
		reagents.trans_to_mob(user, issmall(user) ? CEILING(amount_per_transfer_from_this/2, 1) : amount_per_transfer_from_this, CHEM_INGEST)
		feed_sound(user)
		return TRUE

	else
		other_feed_message_start(user, target)
		om_task_timed(user, 3 SECONDS, target, src, PROC_REF(standard_feed_done), list(user, target))
		return TRUE

/// Why user can't put something in target's mouth (no mouth, or a mask in the way), or null.
/// Shared by standard_feed_mob() and the edible/drinkable capabilities.
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

/obj/item/reagent_containers/proc/standard_feed_done(mob/user, mob/target)
	if(!reagents?.total_volume)
		return
	other_feed_message_finish(user, target)

	var/contained = reagentlist()
	add_attack_logs(user,target,"Fed from [src.name] containing [contained]")
	reagents.trans_to_mob(target, amount_per_transfer_from_this, CHEM_INGEST)
	feed_sound(user)

/obj/item/reagent_containers/proc/standard_pour_into(mob/user, atom/target) // This goes into afterattack and yes, it's atom-level
	if(!target.is_open_container() || !target.reagents)
		return 0

	if(!reagents || !reagents.total_volume)
		balloon_alert(user, "[src] is empty!")
		return 1

	if(!target.reagents.get_free_space())
		balloon_alert(user, "[target] is full!")
		return 1

	var/trans = reagents.trans_to(target, amount_per_transfer_from_this, user = user)
	balloon_alert(user, "transfered [trans] units to [target]")
	return 1

/obj/item/reagent_containers/proc/liquid_belly_check()
	return reagents_from_belly(src)

/obj/item/reagent_containers/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run = FALSE)
	. = ..()
	EXTRAPOLATOR_ACT_SET(., EXTRAPOLATOR_ACT_PRIORITY_ISOLATE)
	var/datum/reagent/blood/blood = reagents.get_reagent(REAGENT_ID_BLOOD)
	EXTRAPOLATOR_ACT_ADD_DISEASES(., blood?.get_diseases())

/obj/item/reagent_containers/proc/attempt_changeling_test(obj/item/W,mob/user)
	if(is_open_container() && W.is_hot())
		var/datum/reagent/blood/B = reagents.get_reagent("blood")
		if(B)
			balloon_alert(user, "\The [W] burns the blood in \the [src].")
			B.changling_blood_test(reagents)

// EXTEND (not DECLARE) so the many subtypes that DECLARE their own specs keep this one.
EXTEND_INTERACTIONS(/obj/item/reagent_containers, \
	INTERACT_ALT("Set transfer amount", PROC_REF(transfer_amount_alt), REQ_ON(PRED_TARGET, /obj/item/reagent_containers/proc/pred_can_set_transfer, "its transfer amount is fixed")), \
	INTERACT_VERB("Set transfer amount", PROC_REF(reagent_container_verb_set_transfer), REQ_IN_INVENTORY, REQ_ON(PRED_TARGET, /obj/item/reagent_containers/proc/pred_can_set_transfer, "its transfer amount is fixed")), \
)

/// Requirement for the Set transfer amount Menu entry (old verb, removed on Initialize when it did not apply).
/obj/item/reagent_containers/proc/pred_can_set_transfer(mob/actor, atom/target, obj/item/held)
	return transfer_amount_verb && max_transfer_amount

/// Old click_alt. It ran the default alt-click first, so this always returns FALSE to let it follow.
/obj/item/reagent_containers/proc/transfer_amount_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return FALSE
	if(!max_transfer_amount)
		return FALSE
	var/N = rerun_ask(user, "a2", PROC_REF(transfer_amount_alt), args, /datum/om/prompt/number, message = "Amount per transfer from this: ([min_transfer_amount]-[max_transfer_amount])", title = "[src]", default = amount_per_transfer_from_this, max = max_transfer_amount, min = min_transfer_amount)
	if(isnull(N))
		return FALSE
	if(N)
		amount_per_transfer_from_this = N
	return FALSE
