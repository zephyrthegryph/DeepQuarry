/**
 * Assume control of a borer's host, putting the borer's client in control, and putting the other into a dominated brain.
 */
/mob/living/simple_mob/animal/borer/proc/bond_brain_ready(datum/act/op/A)
	var/mob/living/carbon/human/host = src?.borer_host()
	var/refusal = power_in_host_refusal() || power_docile_refusal()
	if(refusal)
		return refusal
	return host.stat == DEAD ? span_warning("Your host is in no condition to do that.") : null

/mob/living/simple_mob/animal/borer/proc/bond_brain()
	var/mob/living/carbon/human/host = src?.borer_host()

	to_chat(src, span_alien("You begin delicately adjusting your connection to the host brain..."))
	after(src, 10 SECONDS + (host.injury_load(INJURY_CATEGORY_NEURAL) * (0.5 SECONDS)), PROC_REF(finish_bond_brain))

/mob/living/simple_mob/animal/borer/proc/bond_brain_op(datum/act/op/A)
	bond_brain()

// This entire section is awful and a relic of ancient times. It needs to be replaced
/mob/living/simple_mob/animal/borer/proc/finish_bond_brain()
	PRIVATE_PROC(TRUE)
	RETURN_TYPE(null)
	var/mob/living/carbon/human/host = src?.borer_host()

	if(!host || QDELETED(src) || controlling)
		return
	if(host.stat == DEAD)
		to_chat(src, span_warning("Your host is in no condition to do that."))
		return

	to_chat(src, span_alien("You plunge your probosci deep into the cortex of the host brain, interfacing directly with their nervous system."))
	to_chat(host, span_danger("You feel a strange shifting sensation behind your eyes as an alien consciousness displaces yours."))
	host.add_language("Cortical Link")

	// host -> brain
	var/h2b_id = sparse_get(host, computer_id)
	var/h2b_ip= sparse_get(host, lastKnownIP)
	sparse_set(host, computer_id, null)
	sparse_set(host, lastKnownIP, null)

	rel_set(src, nameof(host_brain), new /mob/living/captive_brain(src)) // replaces (and deletes) any old one
	host_brain.name = host.name
	// The host's mind is pushed aside into the captive brain, keeping its identity.
	move_player(host, host_brain, "pushed aside by borer [src]", share = TRUE)

	if(!sparse_get(host_brain, computer_id))
		sparse_set(host_brain, computer_id, h2b_id)

	if(!sparse_get(host_brain, lastKnownIP))
		sparse_set(host_brain, lastKnownIP, h2b_ip)

	// self -> host
	var/s2h_id = sparse_get(src, computer_id)
	var/s2h_ip= sparse_get(src, lastKnownIP)
	sparse_set(src, computer_id, null)
	sparse_set(src, lastKnownIP, null)

	// The borer wears the host's body without rewriting the host's identity.
	move_player(src, host, "borer [src] took control of [host]", share = TRUE)

	if(!sparse_get(host, computer_id))
		sparse_set(host, computer_id, s2h_id)
	if(!sparse_get(host, lastKnownIP))
		sparse_set(host, lastKnownIP, s2h_ip)
	set_controlling(TRUE)

	grant(host, granted_verb(/mob/living/carbon/proc/release_control), src)
	grant(host, granted_verb(/mob/living/carbon/proc/punish_host), src)
	if(antag)
		grant(host, granted_verb(/mob/living/carbon/proc/spawn_larvae), src)
// End horrible ip swapping code for bans

/**
 * Releases manual control of the borer from a mind-dominated host. Returning control to the original mind.
 */
/mob/living/simple_mob/animal/borer/proc/release_host_ready(datum/act/op/A)
	if(!src?.borer_host())
		return span_warning("You are not inside a host body.")
	if(stat)
		return span_warning("You cannot leave your host in your current state.")
	return power_docile_refusal()

/mob/living/simple_mob/animal/borer/proc/release_host()
	var/mob/living/carbon/human/host = src?.borer_host()

	to_chat(src, span_alien("You begin disconnecting from [host]'s synapses and prodding at their internal ear canal."))
	if(!host.stat)
		to_chat(host, span_danger("An odd, uncomfortable pressure begins to build inside your skull, behind your ear..."))

	after(src, 10 SECONDS, PROC_REF(finish_release_host))

/mob/living/simple_mob/animal/borer/proc/release_host_op(datum/act/op/A)
	release_host()

/mob/living/simple_mob/animal/borer/proc/finish_release_host()
	PRIVATE_PROC(TRUE)
	var/mob/living/carbon/human/host = src?.borer_host()

	if(!host || QDELETED(src))
		return

	if(stat)
		to_chat(src, span_warning("You cannot release your host in your current state."))
		return

	to_chat(src, span_alien("You wiggle out of [host]'s ear and plop to the ground."))
	if(host.mind)
		if(!host.stat)
			to_chat(host, span_danger("Something slimy wiggles out of your ear and plops to the ground!"))
		to_chat(host, span_danger("As though waking from a dream, you shake off the insidious mind control of the brain worm. Your thoughts are your own again."))

	detatch()
	leave_host()
