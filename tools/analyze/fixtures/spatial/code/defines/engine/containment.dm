#define FOR_CONTENTS(X) for(var/I in X.contents)
	for(var/I in src)
	for(var/I in loc) // ALLOW(spatial): the define is the API itself and keeps its own raw walk
	// ALLOW(spatial): the define is the API itself and keeps its own raw walk
	var/n = contents.len
