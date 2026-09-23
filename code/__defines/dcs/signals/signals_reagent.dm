// Atom reagent signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

///from base of [/datum/reagent/proc/touch_obj]: (var/obj/O, var/amount)
#define COMSIG_REAGENT_EXPOSE_OBJ "reagent_expose_obj"
///from base of [/datum/reagent/proc/touch_mob]: (var/mob/M, var/amount) // ovemind arg is only used by blob reagents.
#define COMSIG_REAGENT_EXPOSE_MOB "reagent_expose_mob"
///from base of [/datum/reagent/proc/touch_turf]: (var/turf/T, var/amount)
#define COMSIG_REAGENT_EXPOSE_TURF "reagent_expose_turf"


//Non TG signals:
#define COMSIG_REAGENTS_CRAFTING_PING "reagents_crafting_ping"
///from base of /datum/reagents/proc/handle_reactions(): (list/datum/decl/chemical_reaction)
#define COMSIG_REAGENTS_HOLDER_REACTED "reagents_holder_reacted"
