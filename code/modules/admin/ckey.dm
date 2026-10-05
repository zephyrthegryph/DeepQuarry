// Command to set the ckey of a mob without requiring VV permission
/client/proc/SetCKey(mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
	set category = VERB_CAT_ADMIN_GAME
	set name = "Set CKey"
	set desc = "Mob to teleport"
	if(!admin_can(src, 0))
		to_chat(src, "Only administrators may use this command.")
		return

	var/list/keys = list()
	for(var/mob/playerMob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		keys += playerMob.client
	if(QDELETED(mob))
		return
	var/datum/admin_set_ckey_review/review = new
	review.client_ckey = ckey
	review.expected_target = !isnull(M)
	rel_set(review, nameof(review.actor), mob)
	rel_set(review, nameof(review.target_mob), M)
	open_request(review, /datum/prompt/choice/admin_set_ckey, TYPE_PROC_REF(/datum/admin_set_ckey_review, answered), answerer = mob, choices = sortKey(keys))

/datum/admin_set_ckey_review
	var/tmp/mob/actor
	var/tmp/mob/target_mob
	var/client_ckey
	var/expected_target = FALSE

CAPABILITIES(/datum/admin_set_ckey_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(target_mob), /mob)

/datum/admin_set_ckey_review/proc/refusal()
	if(QDELETED(actor) || !GLOB.directory[client_ckey] || (expected_target && QDELETED(target_mob)))
		return "The original administrator or target is no longer available."

/datum/admin_set_ckey_review/proc/answered(datum/act/request/context)
	if(context.answer)
		var/client/picked = context.request.answer_value
		var/picked_ckey = picked.ckey
		apply_choice(picked_ckey)
	retire()

/datum/admin_set_ckey_review/proc/apply_choice(picked_ckey)
	var/client/requester = GLOB.directory[client_ckey]
	if(!requester || refusal())
		return
	if(!admin_can(requester, 0))
		to_chat(requester, "Only administrators may use this command.")
		return
	var/client/selection = GLOB.directory[picked_ckey]
	if(!selection || !istype(selection))
		return
	var/mob/M = target_mob
	log_admin("[key_name(actor)] set ckey of [key_name(M)] to [selection]")
	message_admins("[key_name_admin(actor)] set ckey of [key_name_admin(M)] to [selection]", 1)
	M.ckey = selection.ckey
	feedback_add_details("admin_verb","SCK") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admin_set_ckey_review/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial request state has no inventory release contract.

/datum/prompt/choice/admin_set_ckey
	title = "Set CKey"
	question = "Please, select a player!"
	timeout = 0

/datum/prompt/choice/admin_set_ckey/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_set_ckey_review/review = owner
	. = review.refusal()
	if(.)
		return
	if(isnull(answer_value))
		return
	if(!istype(answer_value, /client))
		return "The selected player is no longer available."
	var/client/picked = answer_value
	if(!GLOB.directory[picked.ckey])
		return "The selected player is no longer available."
