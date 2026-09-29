// A datum used to link multiple mobs together in some form.
// The code is from TG, however tweaked to be within the preferred code style.

/mob/living
	var/list/datum/soul_link/owned_soul_links	// Soul links we are the owner of (owned: deleted with us).
	var/list/datum/soul_link/shared_soul_links	// Soul links we are a/the sharer of (a relation list view).

// Keeps track of a Mob->Mob (potentially Player->Player) connection.
// Can be used to trigger actions on one party when events happen to another.
// Eg: shared deaths.
// Can be used to form a linked list of mob-hopping.
// Does NOT transfer with minds.
/datum/soul_link
	var/mob/living/soul_owner
	var/mob/living/soul_sharer
	var/id // Optional ID, for tagging and finding specific instances.

// The owner mob owns the link (owned_soul_links); soul_owner is the one-sided back view. Sharers
// are plain relations both ways (a multi-sharer link names several), kept in step by the procs below.
REL_LIST(/mob/living, shared_soul_links)
REL_LIST(/datum/soul_link/multi_sharer, soul_sharers)

/datum/soul_link/proc/remove_soul_sharer(mob/living/sharer)
	if(soul_sharer == sharer)
		rel_clear(src, "soul_sharer")
		rel_remove(sharer, "shared_soul_links", src)

// Used to assign variables, called primarily by soullink()
// Override this to create more unique soullinks (Eg: 1->Many relationships)
// Return TRUE/FALSE to return the soullink/null in soullink()
/datum/soul_link/proc/parse_args(mob/living/owner, mob/living/sharer)
	if(!owner || !sharer)
		return FALSE
	rel_set(src, "soul_owner", owner)
	rel_set(src, "soul_sharer", sharer)
	own_add(owner, "owned_soul_links", src)
	rel_add(sharer, "shared_soul_links", src)
	return TRUE

// Runs after /living death()
// Override this for content.
/datum/soul_link/proc/owner_died(gibbed, mob/living/owner)

// Runs after /living death()
// Override this for content.
/datum/soul_link/proc/sharer_died(gibbed, mob/living/owner)

// Quick-use helper.
/proc/soul_link(typepath, ...)
	var/datum/soul_link/S = new typepath()
	if(S.parse_args(arglist(args.Copy(2, 0))))
		return S

/////////////////
// MULTISHARER //
/////////////////
// Abstract soullink for use with 1 Owner -> Many Sharer setups
/datum/soul_link/multi_sharer
	var/list/mob/living/soul_sharers

/datum/soul_link/multi_sharer/parse_args(mob/living/owner, list/sharers)
	if(!owner || !LAZYLEN(sharers))
		return FALSE
	rel_set(src, "soul_owner", owner)
	own_add(owner, "owned_soul_links", src)
	for(var/mob/living/L as anything in sharers)
		rel_add(src, "soul_sharers", L)
		rel_add(L, "shared_soul_links", src)
	return TRUE

/datum/soul_link/multi_sharer/remove_soul_sharer(mob/living/sharer)
	rel_remove(src, "soul_sharers", sharer)
	rel_remove(sharer, "shared_soul_links", src)

/////////////////
// SHARED FATE //
/////////////////
// When the soulowner dies, the soulsharer dies, and vice versa
// This is intended for two players(or AI) and two mobs

/datum/soul_link/shared_fate/owner_died(gibbed, mob/living/owner)
	if(soul_sharer)
		soul_sharer.death(gibbed)

/datum/soul_link/shared_fate/sharer_died(gibbed, mob/living/sharer)
	if(soul_owner)
		soul_owner.death(gibbed)

//////////////
// ONE WAY  //
//////////////
// When the soul owner dies, the soul sharer dies, but NOT vice versa.
// This is intended for two players (or AI) and two mobs.

/datum/soul_link/one_way/owner_died(gibbed, mob/living/owner)
	if(soul_sharer)
		soul_sharer.dust(FALSE)

/////////////////
// SHARED BODY //
/////////////////
// When the soulsharer dies, they're placed in the soulowner, who remains alive
// If the soulowner dies, the soulsharer is killed and placed into the soulowner (who is still dying)
// This one is intended for one player moving between many mobs

/datum/soul_link/shared_body/owner_died(gibbed, mob/living/owner)
	if(soul_owner && soul_sharer)
		if(soul_sharer.mind)
			soul_sharer.mind.transfer_to(soul_owner)
		soul_sharer.death(gibbed)

/datum/soul_link/shared_body/sharer_died(gibbed, mob/living/sharer)
	if(soul_owner && soul_sharer && soul_sharer.mind)
		soul_sharer.mind.transfer_to(soul_owner)

//////////////////////
// REPLACEMENT POOL //
//////////////////////
// When the owner dies, one of the sharers is placed in the owner's body, fully healed
// Sort of a "winner-stays-on" soullink
// Gibbing ends it immediately

/datum/soul_link/multi_sharer/replacement_pool/owner_died(gibbed, mob/living/owner)
	if(LAZYLEN(soul_sharers) && !gibbed) //let's not put them in some gibs
		var/list/souls = shuffle(soul_sharers.Copy())
		for(var/mob/living/L as anything in souls)
			if(L.stat != DEAD && L.mind)
				L.mind.transfer_to(soul_owner)
				soul_owner.revive(TRUE, TRUE)
				L.death(FALSE)
				break

// Lose your claim to the throne!
/datum/soul_link/multi_sharer/replacement_pool/sharer_died(gibbed, mob/living/sharer)
	remove_soul_sharer(sharer)
