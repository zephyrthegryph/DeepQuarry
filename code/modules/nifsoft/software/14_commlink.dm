///////////
// Commlink - Has a bunch of extra stuff due to communicator defines.
/datum/nifsoft/commlink
	name = "Commlink"
	desc = "An internal communicator for keeping in touch with people."
	list_pos = NIF_COMMLINK
	cost = 250
	wear = 0
	p_drain = 0.01
	other_flags = (NIF_O_COMMLINK)

/datum/nifsoft/commlink/install()
	if((. = ..()))
		rel_set(nif(), nameof(/mob/living/voice::comm), new /obj/item/communicator/commlink(nif(),src))
		if(nif().human?.client?.prefs?.read_preference(/datum/preference/toggle/human/communicator_visibility)) // migrated
			nif().comm.initialize_exonet(nif().human) //no harm in running this twice.

/datum/nifsoft/commlink/uninstall()
	var/obj/item/nif/lnif = nif() //Awkward. Parent clears it in an attempt to clean up.
	if((. = ..()) && lnif)
		own_clear(lnif, nameof(lnif.comm), OWN_DELETE)

/datum/nifsoft/commlink/activate()
	if((. = ..()))
		nif().comm.initialize_exonet(nif().human)
		nif().comm.tgui_interact(nif().human, custom_state = GLOB.tgui_commlink_state)
		after(src, 0, PROC_REF(deactivate))

/datum/nifsoft/commlink/stat_text()
	return "Show Commlink"

CAPABILITIES(/datum/nifsoft/commlink)
	op("open", topic("open"), then(PROC_REF(topic_open)))

/datum/nifsoft/commlink/proc/topic_open(datum/act/op/A)
	activate()
	return TRUE

/obj/item/communicator/commlink
	name = "commlink"
	desc = "An internal communicator, basically."
	occupation = "\[Commlink\]"
	var/obj/item/nif/nif
	var/tmp/datum/nifsoft/commlink/nifsoft

CAPABILITIES(/obj/item/communicator/commlink)
	param(nameof(nifsoft), pos = 1, apply = PROC_REF(join_nif))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The commlink belongs to the NIF it is made in.
/obj/item/communicator/commlink/proc/join_nif(soft)
	rel_set(src, nameof(nif), loc)

// The NIF creates and owns its commlink (in its contents, deleted with it); the commlink's `nif`
// is a plain back relation.

/obj/item/communicator/commlink/register_device(new_name)
	owner = new_name
	name = "[owner]'s [initial(name)]"
	nif.save_data["commlink_name"] = owner

//So that only the owner's chat is relayed to others.
/obj/item/communicator/commlink/hear_talk(mob/living/M, list/message_pieces, verb)
	if(M != nif.human)
		return

	for(var/obj/item/communicator/comm in communicating)
		var/turf/T = get_turf(comm)
		if(!T) return

		var/icon_object = src

		var/list/mobs_to_relay
		if(istype(comm, /obj/item/communicator/commlink))
			var/obj/item/communicator/commlink/CL = comm
			mobs_to_relay = list(CL.nif.human)
			icon_object = CL.nif.big_icon
		else
			var/list/in_range = get_mobs_and_objs_in_view_fast(T,world.view,0)
			mobs_to_relay = in_range["mobs"]

		for(var/mob/mob in mobs_to_relay)
			var/list/combined = mob.combine_message(message_pieces, verb, M)
			var/message = combined["formatted"]
			var/name_used = M.GetVoice()
			var/rendered = null
			rendered = span_game(span_say("[icon2html(icon_object,mob.client)] [span_name(name_used)] [message]"))
			mob.show_message(rendered, 2)

//Not supported by the internal one
/obj/item/communicator/commlink/show_message(msg, type, alt, alt_type)
	return

//The silent treatment
/obj/item/communicator/commlink/request(atom/candidate)
	if(candidate in voice_requests)
		return
	var/who = null
	if(isobserver(candidate))
		who = candidate.name
	else if(istype(candidate, /obj/item/communicator))
		var/obj/item/communicator/comm = candidate
		who = comm.owner
		rel_add(comm, nameof(comm.voice_invites), src)

	if(!who)
		return

	LAZYOR(voice_requests, candidate)

	if(ringer && nif.human)
		nif.notify("New commlink call from [who]. (<a href='byond://?src=\ref[nifsoft()];open=1'>Open</a>)")

//Similar reason
/obj/item/communicator/commlink/request_im(atom/candidate, origin_address, text)
	var/who = null
	if(isobserver(candidate))
		var/mob/observer/dead/ghost = candidate
		who = ghost
		LAZYADD(im_list, list(list("address" = origin_address, "to_address" = exonet.address, "im" = text)))
	else if(istype(candidate, /obj/item/communicator))
		var/obj/item/communicator/comm = candidate
		who = comm.owner
		rel_add(comm, nameof(comm.im_contacts), src)
		LAZYADD(im_list, list(list("address" = origin_address, "to_address" = exonet.address, "im" = text)))
	else return

	rel_add(src, nameof(im_contacts), candidate)

	if(!who)
		return

	if(ringer && nif.human)
		nif.notify("Commlink message from [who]: \"[text]\" (<a href='byond://?src=\ref[nifsoft()];open=1'>Open</a>) (<a href='byond://?src=\ref[src];action=Reply;target=\ref[candidate]'>Reply</a>)")

/// LC-refs: the nifsoft this refers to -- a relation view: null once it is deleted.
/obj/item/communicator/commlink/proc/nifsoft() as /datum/nifsoft/commlink
	return nifsoft
