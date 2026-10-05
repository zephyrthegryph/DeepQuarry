// How severely an explosion reaches what a holder carries (doc/rewrite/final_api.html, section 14 "Damage": explosions). A declared entry the
// explosion service reads (explosion_contents_severity_of(), explosion_service.dm) when it queues a holder's contents in the same batch epoch:
//
//   blast_contents()             the contents take the full blast (a scanner's patient, a pipe's ventcrawler, a bookcase's books)
//   blast_contents(shield = 1)   one step lighter (severity 1 -> 2 -> 3); a blast lighter than light reaches nothing (a closet)
//
// A holder that declares nothing shields its contents entirely. Replaces explosion_contents_severity() overrides.

CAPABILITY_TYPE(blast_contents, CAP_BLAST_CONTENTS, /datum/capability/lib/blast_contents, key = NONE, shield = 0)

// shield (a param, declared by the generator): severity steps the holder takes off the blast before it reaches its contents (1 is the worst, 3 the lightest).

/// The severity an explosion of `severity` on the holder delivers to its contents: 0 when it does not reach them.
/datum/capability/lib/blast_contents/proc/contents_severity(severity)
	if(!severity)
		return 0
	var/reached = severity + shield
	return reached > 3 ? 0 : reached
