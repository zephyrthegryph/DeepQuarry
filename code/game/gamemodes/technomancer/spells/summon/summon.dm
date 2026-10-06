/mob/living/
	var/summoned = 0

/obj/item/spell/summon
	name = "summon template"
	desc = "Chitter chitter."
	cast_methods = CAST_RANGED | CAST_USE
	aspect = ASPECT_TELE
	var/summoned_mob_type = null // The type to use when making new mobs when summoned.
	var/list/summon_options
	var/energy_cost = 0
	var/instability_cost = 0

/obj/item/spell/summon/on_ranged_cast(atom/hit_atom, mob/living/user)
	var/turf/T = get_turf(hit_atom)
	if(summoned_mob_type && length(core.summoned_mobs) < core.max_summons && within_range(hit_atom) && pay_energy(energy_cost))
		var/obj/effect/E = new(T)
		E.icon = 'icons/obj/objects.dmi'
		E.icon_state = "anom"
		after(src, 5 SECONDS, PROC_REF(summon_arrives), with = list(E, T, user))

/obj/item/spell/summon/proc/summon_arrives(obj/effect/E, turf/T, mob/living/user)
	spent(E, user)
	if(owner_ref()) // We might've been dropped.
		var/mob/living/L = new summoned_mob_type(T)
		rel_add(core, nameof(core.summoned_mobs), L)
		L.summoned = 1
		var/image/summon_underlay = image('icons/obj/objects.dmi',"anom")
		summon_underlay.alpha = 127
		L.underlays |= summon_underlay
		on_summon(L)
		to_chat(user, span_notice("You've successfully teleported \a [L] to you!"))
		visible_message(span_warning("\A [L] appears from no-where!"))
		log_and_message_admins("has summoned \a [L] at [T.x],[T.y],[T.z].")
		user.adjust_instability(instability_cost)

/// Item spell and device selections recheck the original carried/capable policy.
/datum/prompt/choice/technomancer_carried
	timeout = 0
	ask_flags = ASK_CARRIED | ASK_CAPABLE

/obj/item/spell/summon/on_use_cast(mob/living/user)
	if(length(summon_options))
		open_request(src, /datum/prompt/choice/technomancer_carried, PROC_REF(summon_choice_made), answerer = user, subject = src, title = "Summon", question = "Choose a creature to kidnap from somewhere!", choices = summon_options)

/obj/item/spell/summon/proc/summon_choice_made(datum/act/request/A)
	if(!A.answer)
		return
	return summon_choice_made_apply(A)

/obj/item/spell/summon/proc/summon_choice_made_apply(datum/act/request/A)
	var/datum/prompt/choice/technomancer_carried/ask = A.answer
	if(ask.value)
		summoned_mob_type = LAZYACCESS(summon_options, ask.value)

// Called when a new mob is summoned, override for special behaviour.
/obj/item/spell/summon/proc/on_summon(mob/living/summoned)
	return
