// The AFK kick world service (fold wave F4; was SSinactivity): every minute on the background lane
// (/datum/om/behaviour/world/inactivity, code/datums/om/world_lanes.dm) it disconnects clients idle
// longer than the kick_inactive config minutes. Does nothing while that config is 0.
GLOBAL_DATUM_INIT(inactivity_service, /datum/world_service/inactivity, new)

/datum/world_service/inactivity
	name = "Inactivity"
	lane = /datum/om/behaviour/world/inactivity
	var/tmp/list/client_list
	var/number_kicked = 0

/datum/world_service/inactivity/service_step(resumed)
	if (!CONFIG_GET(number/kick_inactive))
		return TRUE
	if (!resumed)
		client_list = GLOB.clients.Copy()

	while(length(client_list))
		var/client/C = client_list[length(client_list)]
		client_list.len--
		if(C.is_afk(CONFIG_GET(number/kick_inactive) MINUTES) && can_kick(C))
			to_chat_immediate(C, span_warning("You have been inactive for more than [CONFIG_GET(number/kick_inactive)] minute\s and have been disconnected."))

			var/information
			if(C.mob)
				if(ishuman(C.mob))
					var/job
					var/mob/living/carbon/human/H = C.mob
					var/datum/data/record/R = find_general_record("name", H.real_name)
					if(R)
						job = R.fields["real_rank"]
					if(!job && H.mind)
						job = H.mind.assigned_role
					if(!job && H.job)
						job = H.job
					if(job)
						information = " while [job]."

				else if(isobserver(C.mob))
					information = " while a ghost."

				else if(issilicon(C.mob))
					information = " while a silicon."
					if(isAI(C.mob))
						var/mob/living/silicon/ai/A = C.mob
						registry_join(REGISTRY_EMPTY_AI_CORES, new /obj/structure/AIcore/deactivated(A.loc))
						GLOB.global_announcer.autosay("[A] has been moved to intelligence storage.", "Artificial Intelligence Oversight")
						A.clear_client()
						information = " while an AI."

			var/adminlinks
			adminlinks = " (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[C.mob.x];Y=[C.mob.y];Z=[C.mob.z]'>JMP</a>|<A href='byond://?_src_=holder;[HrefToken()];cryoplayer=\ref[C.mob]'>CRYO</a>)"

			log_and_message_admins("being kicked for AFK[information][adminlinks]", C.mob)

			qdel(C)
			number_kicked++

		if (TICK_CHECK)
			return FALSE
	return TRUE

/datum/world_service/inactivity/stat_line()
	return "Kicked: [number_kicked]"

/datum/world_service/inactivity/proc/can_kick(client/C)
	if(check_rights_for(C, R_HOLDER|R_MENTOR)) return FALSE // Don't kick admins.
	return TRUE
