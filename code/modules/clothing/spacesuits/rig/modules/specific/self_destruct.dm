/obj/item/rig_module/self_destruct

	name = "self-destruct module"
	desc = "Oh my God, a bomb!"
	icon_state = "deadman"
	usable = 1
	active = 1
	permanent = 1
	var/datum/effect/effect/system/smoke_spread/bad/smoke
	var/smoke_strength = 8

	engage_string = "Detonate"

	interface_name = "dead man's switch"
	interface_desc = "An integrated self-destruct module. When the wearer dies, they vanish in smoke. Do not press this button."

CAPABILITIES(/obj/item/rig_module/self_destruct)
	owns_one(nameof(smoke), /datum/effect/effect/system/smoke_spread/bad, starts = /datum/effect/effect/system/smoke_spread/bad)

/obj/item/rig_module/self_destruct/Initialize(mapload)
	. = ..()
	smoke.attach(src)


/obj/item/rig_module/self_destruct/activate(skip_engage = 0, mob/user)
	return

/obj/item/rig_module/self_destruct/deactivate(forced = FALSE, mob/user)
	return

/obj/item/rig_module/self_destruct/periodic_step()

	// Not being worn, leave it alone.
	if(!holder || !holder.wearer() || holder.wearer().get_equipped_item(SLOT_ID_SUIT) != holder)
		return 0

	//OH SHIT.
	if(holder.wearer().stat == 2)
		engage(1)

/obj/item/rig_module/self_destruct/engage(skip_check, notify_ai = FALSE, mob/user)
	// The automatic no-user call could not open the old rerun question either.
	if(!ismob(user))
		return
	var/atom/original_target = isatom(skip_check) ? skip_check : null
	open_request(src, /datum/prompt/choice/rig_self_destruct, PROC_REF(self_destruct_answered), answerer = user, subject = original_target, original_target_expected = !isnull(original_target), skip_check = !!skip_check)

/datum/prompt/choice/rig_self_destruct
	timeout = 0
	recheck_on_open = TRUE
	buttons = TRUE
	title = "Self-destruct"
	question = "Are you sure you want to push that button?"
	choices = list("No", "Yes")
	var/original_target_expected = FALSE
	var/skip_check = FALSE

/datum/prompt/choice/rig_self_destruct/recheck_extra()
	var/mob/user = answerer
	if(!istype(user) || QDELETED(user))
		return "gone"
	var/atom/original_target = subject
	if(original_target_expected && (!original_target || QDELETED(original_target)))
		return "gone"
	return null

/obj/item/rig_module/self_destruct/proc/self_destruct_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/rig_self_destruct/ask = A.request
	if(ask.skip_check || ask.value == "Yes")
		self_destruct_detonate()
	SStgui.update_uis(src)

/obj/item/rig_module/self_destruct/proc/self_destruct_detonate()
	if(holder && holder.wearer())
		smoke.set_up(10, 0, holder.loc)
		for(var/i = 1 to smoke_strength)
			smoke.start(272727)
		holder.wearer().ash()
