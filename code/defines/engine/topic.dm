// Topic ref sources: the `among =` of an href arg (arg("target", schema_ref(/mob), among = TOPIC_IN_MOBS)), resolved by topic_resolve_ref()
// (code/datums/topic/topic_dispatch.dm). Omitted: /client -> TOPIC_IN_CLIENTS, /turf -> TOPIC_IN_WORLD, else TOPIC_ANY.
/// Any object of the declared type (datums, mobs in nullspace, records): the istype is the check.
#define TOPIC_ANY "any"
/// An atom on the map.
#define TOPIC_IN_WORLD "world"
/// A connected client.
#define TOPIC_IN_CLIENTS "clients"
/// A live mob (the mob registry).
#define TOPIC_IN_MOBS "mobs"
/// Something inside the target itself (target.contents).
#define TOPIC_IN_CONTENTS "contents"
// Anything else is a proc name on the target (PROC_REF(my_list)) returning the list to search.
