// Hot-list fixture: a listed var is homed, an unlisted one is a site, a listed var with a short justification or a TRACKED home is a hot_home finding.
/atom
	var/hot_listed = 1
	var/hot_unlisted = 2
	var/hot_short = 3

/mob
	var/hot_tracked = 4

TRACKED(/mob, hot_tracked)
