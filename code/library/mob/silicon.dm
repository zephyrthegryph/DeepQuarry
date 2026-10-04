// The providers of the silicons that have no species to grant them (doc/rewrite/final_api.html, section 8, "Who may act, and what they can reach"; round-5
// decision NS1). A silicon's remote use is a remote() binding: a provider with AFF_CONTROL under AUTH_REMOTE_ACCESS.
//
//   The AI has no body and no tile reach (its provider is declared in its own CAPABILITIES block, ai.dm). Its interface serves the remote() ops that name REACH_VIEW (what its cameras show) or REACH_ANY.
//   A cyborg keeps its gripper (hands(), library/mob/hands.dm, where its interface provider is declared beside it) and also has an interface to what it sees: BORG_INTERFACE_REACH tiles, the view
//   range, which matters only to a remote() op that narrows itself to REACH_ADJACENT.
//
// A click or menu pick of a silicon carries the authority its providers give (click_authority()), so a borg's click can be a hand op or a remote()
// one, and an AI's only a remote() one. The AI sees through its cameras, not through view() from its core.

/mob/living/silicon/ai/click_authority()
	return AUTH_REMOTE_ACCESS

/// A cyborg looking through a camera instead of its own eyes has no remote access to work machines with (the "Blocked" robot interaction on every
/// legacy machine, machinery.dm, says the same): its clicks are physical only then.
/mob/living/silicon/robot/click_authority()
	return is_remote_viewing() ? AUTH_PHYSICAL : (AUTH_PHYSICAL | AUTH_REMOTE_ACCESS)

/mob/living/silicon/ai/reach_view_sees(atom/target)
	return has_camera_sight(target)
