// Behavior-grant declarations on existing item types.
//
// Items declare what AI behaviors they grant to a mob holding them. The brain
// aggregates these into effective_behaviors on each slow tick.
//
// Each item subtype overrides the item_granted_behaviors type table: one
// shared list per subtype with zero per-instance cost. The default is null so
// items that grant nothing pay nothing.

TYPE_TABLE_DECLARE(/obj/item, item_granted_behaviors, null)

// --- Concrete grants --------------------------------------------------------

TYPE_TABLE(/obj/item/grenade, item_granted_behaviors, list(/datum/ai_behavior/throw_grenade))

TYPE_TABLE(/obj/item/gun, item_granted_behaviors, list(/datum/ai_behavior/aimed_shot))
