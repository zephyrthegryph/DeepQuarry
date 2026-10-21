// Object state is serialized by the state schema (code/datums/state/schema.dm).

/atom
	/// Not used for anything, but present so DM's map reader doesn't forfeit
	/// on reading a JSON-serialized map.
	var/tmp/map_json_data
