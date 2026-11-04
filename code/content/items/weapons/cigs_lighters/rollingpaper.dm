/obj/item/reagent_containers/rollingpaper
	name = "rolling paper"
	desc = "A small, thin piece of easily flammable paper, commonly used for rolling and smoking various dried plants."
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "cig paper"
	volume = 25
	var/crafted_type = /obj/item/clothing/mask/smokable/cigarette/joint

/obj/item/reagent_containers/rollingpaper/blunt
	name = "blunt wrap"
	desc = "A small piece of easily flammable paper similar to that which encases cigars. It's made out of tobacco, bigger than a standard rolling paper, and will last longer."
	icon_state = "blunt paper"
	volume = 45
	crafted_type = /obj/item/clothing/mask/smokable/cigarette/joint/blunt

// A rolling paper is a sealed holder of its volume: a dried plant used on it is added (if it fits), and using it in hand rolls what is in it into a joint.
CAPABILITIES(/obj/item/reagent_containers/rollingpaper)
	configure(atom_rules(description_fluff = "The legalization of certain substances propelled the sale of rolling \
	papers through the roof. Now almost every Trans-stellar produces a variety, often of questionable quality."))
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		settable = FALSE,
		shows_contents = FALSE)
	op("add", item(/obj/item/reagent_containers/food/snacks), label("Add it to the paper"), needs(req(PROC_REF(plant_dried)), req(PROC_REF(plant_fits))), then(PROC_REF(plant_added)))
	op("roll", in_hand(), label("Roll it"), then(PROC_REF(rolled)))

MSG_DEF_SELF(rollingpaper/not_dried, span_notice("%I% must be dried before you add it to %T%."))
MSG_DEF_SELF(rollingpaper/too_full, span_warning("%T% is too full to add %I%."))

/// needs: the plant is dried; this prevents people from just stuffing cheeseburgers into their joint.
/obj/item/reagent_containers/rollingpaper/proc/plant_dried(datum/act/op/A)
	var/obj/item/reagent_containers/food/snacks/grown/G = A.held
	return (istype(G) && G.dry) ? null : MSG(rollingpaper/not_dried)

/// needs: the paper has room for the plant's reagents.
/obj/item/reagent_containers/rollingpaper/proc/plant_fits(datum/act/op/A)
	var/obj/item/reagent_containers/food/snacks/grown/G = A.held
	if(!istype(G) || !G.reagents)
		return null
	return (G.reagents.total_volume + src.reagents.total_volume > src.reagents.maximum_volume) ? MSG(rollingpaper/too_full) : null

/// A plant is added (it must be dried, and fit).
/obj/item/reagent_containers/rollingpaper/proc/plant_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/grown/G = A.held
	if (!istype(G) || !G.dry || G.reagents.total_volume + src.reagents.total_volume > src.reagents.maximum_volume)
		log_world("ROLLINGPAPER: [src] refused [A.held] after the dry and room checks")
		return OP_FAILED
	if (src.reagents.total_volume == 0)
		if (istype(src, /obj/item/reagent_containers/rollingpaper/blunt))                         //update the icon if this is the first thing we're adding to the paper
			set_icon_state("blunt_full")
		else
			set_icon_state("paper_full")
	to_chat(user, span_notice("You add the [G.name] to the [src.name]."))
	src.add_fingerprint(user)
	if(G.reagents)
		G.reagents.trans_to_obj(src, G.reagents.total_volume)                                            //adds the reagents from the plant into the paper
	consume(G, user)
	return OP_OK

/// Rolled into a joint that holds what was in it.
/obj/item/reagent_containers/rollingpaper/proc/rolled(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/clothing/mask/smokable/cigarette/J = new crafted_type()
	to_chat(user,span_notice("You roll the [src] into a blunt!"))
	J.add_fingerprint(user)
	if(reagents)
		reagents.trans_to_obj(J, reagents.total_volume)
	user.drop_from_inventory(src)
	user.put_in_hands(J)
	consume(src, user)
	return OP_OK
