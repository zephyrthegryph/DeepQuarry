// The providers of the silicons that have no species to grant them (doc/rewrite/final_api.html, section 8, "Who may act, and what they can reach"; round-5
// decision NS1; 16.8 "A cyborg: providers and affordances"). A silicon's remote use is a remote() binding: a provider with AFF_CONTROL under
// AUTH_REMOTE_ACCESS.
//
//   The AI has no body and no tile reach (remote_interface() in its own CAPABILITIES block, ai.dm). Its interface serves the remote() ops that name
//   REACH_VIEW (what its cameras show) or REACH_ANY.
//   A cyborg keeps its gripper (hands(), library/mob/hands.dm, where its interface is declared beside it) and also has an interface to what it sees:
//   BORG_INTERFACE_REACH tiles, the view range, which matters only to a remote() op that narrows itself to REACH_ADJACENT.
//
// The interface is there only while the link works (remote_link_up()): an AI whose wireless is off or that is not conscious, a cyborg that cannot act,
// carries a working restraining bolt or looks through a camera, has none, so every remote() op stops being a candidate for it at once. That is the
// one place those conditions are read: no machine asks "is this an AI" or "is the borg bolted".
//
// Whose link may work a machine is the machine's question, asked with req(PROC_REF(remote_link_allowed)) (below): the input came over a link
// (AUTH_REMOTE_ACCESS) and the actor's link is let in (remote_link_allows(): the station trusts its AI; a cyborg shows its ID card).
//
// A click or menu pick of a silicon carries the authority its providers give (click_authority()), so a borg's click can be a hand op or a remote()
// one, and an AI's only a remote() one. The AI sees through its cameras, not through view() from its core.

/// remote_interface(reach =): a silicon's link to the machines it sees: provides(AFF_CONTROL, authority = AUTH_REMOTE_ACCESS) while remote_link_up().
/// The condition is read whenever the provider set is (providers_for()), so a bolt, a camera view or a wireless switch counts at once.
/proc/remote_interface(reach = null)
	return when(TYPE_PROC_REF(/mob/living/silicon, remote_link_up), provides(AFF_CONTROL, reach = reach, authority = AUTH_REMOTE_ACCESS))

/// Does this silicon's remote link work now? A condition: it reads and writes nothing.
/mob/living/silicon/proc/remote_link_up(datum/act/A)
	return stat == CONSCIOUS

/mob/living/silicon/ai/remote_link_up(datum/act/A)
	return ..() && !control_disabled

/mob/living/silicon/robot/remote_link_up(datum/act/A)
	return can_click_act() && !get_restraining_bolt() && !is_remote_viewing()

/// Does this mob's link let it work `machine` remotely? Only a silicon has a link; the machine asks (remote_link_allowed()).
/mob/proc/remote_link_allows(obj/machine)
	return FALSE

/// The station's machines trust its AI.
/mob/living/silicon/ai/remote_link_allows(obj/machine)
	return TRUE

/// A cyborg shows its ID card: the machine's own access decides.
/mob/living/silicon/robot/remote_link_allows(obj/machine)
	return machine.check_access(idcard)

/// The requirement a machine names for its remote controls: the input came over a link (AUTH_REMOTE_ACCESS) and the actor's link is let in.
/// req(PROC_REF(remote_link_allowed)). A condition: it reads and writes nothing.
/obj/proc/remote_link_allowed(datum/act/op/A)
	if(isnull(A) || !(A.authority & AUTH_REMOTE_ACCESS))
		return FALSE
	var/mob/actor = A.actor
	return istype(actor) && actor.remote_link_allows(src)

/mob/living/silicon/ai/click_authority()
	return AUTH_REMOTE_ACCESS

/// A cyborg's inputs carry remote access only while its link works (a window button has no provider to drop it: the authority does).
/mob/living/silicon/robot/click_authority()
	return remote_link_up() ? (AUTH_PHYSICAL | AUTH_REMOTE_ACCESS) : AUTH_PHYSICAL

/mob/living/silicon/ai/reach_view_sees(atom/target)
	return has_camera_sight(target)
