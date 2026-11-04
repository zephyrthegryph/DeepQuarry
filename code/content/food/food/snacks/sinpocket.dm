/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket
	name = "\improper Sin-pocket"
	desc = "The food of choice for the veteran. Do <B>NOT</B> overconsume."
	filling_color = "#6D6D00"
	var/has_been_heated = FALSE
	special_handling = TRUE

TYPE_TABLE(/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket, donkpocket_heated_reagents, list(REAGENT_ID_DOCTORSDELIGHT = 5, REAGENT_ID_HYPERZINE = 0.75, REAGENT_ID_SYNAPTIZINE = 0.25))

// Its package is crushed once; twenty seconds later it is heated.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket)
	op("crush", in_hand(), priority(OP_PRIORITY_PART), label("Crush package"), needs(req(PROC_REF(not_yet_heated))), then(PROC_REF(crushed)))

MSG_DEF_SELF(snack/heat_spent, "The heating chemicals have already been spent.")

/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket/proc/not_yet_heated(datum/act/op/A)
	return (!has_been_heated) ? null : /datum/msg/snack/heat_spent

/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket/proc/crushed(datum/act/op/A)
	var/mob/user = A.actor
	set_has_been_heated(TRUE)
	act_message(user, src, MSG_SELF("You crush %T% package and feel a comfortable heat build up. Now just to wait for it to be ready."), \
		MSG_OTHERS(span_notice("%U% crushes %T% package.")))
	after(src, 20 SECONDS, PROC_REF(self_heated), key = "self_heated", with = list(user))
	return OP_OK

/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket/proc/self_heated(mob/user)
	if(!QDELETED(src))
		if(src.loc == user)
			to_chat(user, "You think \the [src] is ready to eat about now.")
		heat()
