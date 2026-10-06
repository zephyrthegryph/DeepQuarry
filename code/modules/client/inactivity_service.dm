// The AFK kick system (was SSinactivity): every minute on the background lane it disconnects clients idle
// longer than the kick_inactive config minutes. Does nothing while that config is 0.
SYSTEM_DEF(inactivity)
	name = "Inactivity"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	var/tmp/list/client_list
	var/number_kicked = 0
	/// TRUE while a kick pass that ran out of budget waits to resume.
	VAR_PRIVATE/kick_resuming = FALSE

/datum/system/inactivity/reactions()
	. = ..()
	. += every(1 MINUTE, PROC_REF(kick_step), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/inactivity/proc/kick_step(dt)
	if (!CONFIG_GET(number/kick_inactive))
		return STEP_DONE
	if (!kick_resuming)
		client_list = GLOB.clients.Copy()
	kick_resuming = FALSE

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

			spent(C)
			number_kicked++

		if (KERNEL_OVER_BUDGET)
			kick_resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/inactivity/stat_entry(msg)
	return "[..()]Kicked: [number_kicked]"

/datum/system/inactivity/proc/can_kick(client/C)
	if(check_rights_for(C, R_HOLDER|R_MENTOR)) return FALSE // Don't kick admins.
	return TRUE
