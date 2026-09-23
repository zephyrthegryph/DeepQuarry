
//Food

// Eating stuff
/// From datum/component/edible/proc/TakeBite: (mob/living/eater, mob/feeder, bitecount, bitesize)
#define COMSIG_FOOD_EATEN "food_eaten"
	#define DESTROY_FOOD (1<<0)


// Deep frying foods
/// An item becomes fried - From /datum/element/fried_item/Attach: (fry_time)
#define COMSIG_ITEM_FRIED "item_fried"

// Microwaving foods

// Grilling foods (griddle, grill, and bonfire)

///Called when the object is grilled by the grill (not to be confused by the griddle, but oh gee the two should be merged in one)
#define COMSIG_ITEM_BARBEQUE_GRILLED "item_barbeque_grilled"

// Baking foods (oven)
//Called when an object is inserted into an oven (atom/oven, mob/baker)
//Called when an object is in an oven


//Drink

///from base of:
/// /obj/item/reagent_containers/food/drinks/proc/On_Consume(var/mob/living/eater, var/mob/feeder, var/changed = FALSE)
/// and /obj/item/reagent_containers/proc/standard_feed_mob(var/mob/user, var/mob/target)
#define COMSIG_GLASS_DRANK "glass_drank"
