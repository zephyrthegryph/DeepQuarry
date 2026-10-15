/// Static presentation facts, independent of a viewer's wireless/control authority.
/// These preserve existing window payload distinctions (AI-only versus all silicon).
TYPE_TABLE_DECLARE(/mob, window_viewer_facts, list("ai" = FALSE, "robot" = FALSE, "silicon" = FALSE, "person_console" = FALSE, "paper_readable" = FALSE))
TYPE_TABLE(/mob/living/carbon/human, window_viewer_facts, list("ai" = FALSE, "robot" = FALSE, "silicon" = FALSE, "person_console" = TRUE, "paper_readable" = TRUE))
TYPE_TABLE(/mob/living/silicon, window_viewer_facts, list("ai" = FALSE, "robot" = FALSE, "silicon" = TRUE, "person_console" = FALSE, "paper_readable" = TRUE))
TYPE_TABLE(/mob/living/silicon/ai, window_viewer_facts, list("ai" = TRUE, "robot" = FALSE, "silicon" = TRUE, "person_console" = TRUE, "paper_readable" = TRUE))
TYPE_TABLE(/mob/living/silicon/robot, window_viewer_facts, list("ai" = FALSE, "robot" = TRUE, "silicon" = TRUE, "person_console" = FALSE, "paper_readable" = TRUE))

/mob/proc/ui_viewer_profile()
	return TYPE_TABLE_GET(src, window_viewer_facts)
TYPE_TABLE(/mob/observer/dead, window_viewer_facts, list("ai" = FALSE, "robot" = FALSE, "silicon" = FALSE, "person_console" = FALSE, "paper_readable" = TRUE))

/// A null UI viewer has none of these presentation facts, as the old payload did.
/proc/ui_viewer_fact(mob/viewer, name)
	if(!viewer)
		return FALSE
	var/list/profile = viewer.ui_viewer_profile()
	return profile[name]
