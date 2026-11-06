// The persistence system's API (code/controllers/subsystems/persistence.dm declares the system).
//
//   SSpersistence.take_unpicked_painting(entry)                       a frame claimed a painting
//   SSpersistence.load_paintings(entries) / reset_unpicked_paintings()  the database read from disk, and every painting offered again
//   SSpersistence.add_painting(entry) / renew_painting(entry) / remove_painting(entry)   the database
//   persistence_*()                                                   reads (code/contracts/accessors/accessors.dm)

/datum/system/persistence/proc/take_unpicked_painting(list/entry)
	unpicked_paintings -= list(entry)

/datum/system/persistence/proc/add_painting(list/entry)
	all_paintings += list(entry)

/// Moves a painting to the back of the database (the end is the newest).
/datum/system/persistence/proc/renew_painting(list/entry)
	all_paintings.Remove(list(entry))
	all_paintings.Add(list(entry))

/// Removes one painting; returns whether it was there.
/datum/system/persistence/proc/remove_painting(list/entry)
	return all_paintings.Remove(list(entry))

/datum/system/persistence/proc/painting_count()
	return length(all_paintings)

/// Replaces the painting database with the entries read from disk.
/datum/system/persistence/proc/load_paintings(list/entries)
	all_paintings = entries

/// Offers every stored painting to the frames again.
/datum/system/persistence/proc/reset_unpicked_paintings()
	unpicked_paintings = all_paintings.Copy()
