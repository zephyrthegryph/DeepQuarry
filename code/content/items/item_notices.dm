// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From base of /obj/item/attack(): (mob/living, mob/living, list/modifiers, list/attack_modifiers)
ACTION(item_attack, target_, user, target_zone, FIXED, notice = /datum/notice/item_attack)

/// From base of obj/item/dropped(): (mob/user)
ACTION(item_dropped, user, FIXED, notice = /datum/notice/item_dropped)

/// From base of obj/item/equipped(): (mob/equipper, slot)
ACTION(item_equipped, equipper, slot, FIXED, notice = /datum/notice/item_equipped)

/// From base of obj/item/pickup(): (/mob/taker)
ACTION(item_pickup, taker, FIXED, notice = /datum/notice/item_pickup)

/// Sent from [atom/proc/item_interaction], when this atom is used as a tool and an event occurs
ACTION(item_tool_acted, target_, user, tool_quality, modifiers, FIXED, notice = /datum/notice/item_tool_acted)
