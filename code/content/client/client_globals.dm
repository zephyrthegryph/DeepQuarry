GLOBAL_LIST_EMPTY(admins) //all clients whom are admins
GLOBAL_PROTECT(admins)
GLOBAL_LIST_EMPTY(deadmins)							//all ckeys who have used the de-admin verb.
GLOBAL_LIST_EMPTY(stealthminID)
GLOBAL_LIST_EMPTY(directory)							//all ckeys with associated client
GLOBAL_LIST_EMPTY(clients)
/// z-level -> the slots of the player mobs on it (slot_datums() reads them back): the list keeps no reference to a mob.
GLOBAL_LIST_EMPTY(players_by_zlevel)
