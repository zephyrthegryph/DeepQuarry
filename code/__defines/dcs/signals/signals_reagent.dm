// Atom reagent signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

///from base of [/datum/reagent/proc/touch_obj]: (var/obj/O, var/amount)
#define COMSIG_REAGENT_EXPOSE_OBJ "reagent_expose_obj"


//Non TG signals:
///from base of /datum/reagents/proc/handle_reactions(): (list/datum/decl/chemical_reaction)
#define COMSIG_REAGENTS_HOLDER_REACTED "reagents_holder_reacted"
