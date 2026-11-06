/obj/item/reagent_containers/pill/benzilate
	name = "Benzilate pill"
	desc = "You probably shouldn't swallow this."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/benzilate)
	configure(reagents(add = list(REAGENT_ID_BENZILATE = 50), tint = TRUE))

/obj/item/reagent_containers/pill/phenethylamine
	name = "Phenethylamine pill"
	desc = "Smells like... lilacs?"
	icon_state = "pill5"

CAPABILITIES(/obj/item/reagent_containers/pill/phenethylamine)
	configure(reagents(add = list(REAGENT_ID_PHENETHYLAMINE = 50), tint = TRUE))

// PILLS THAT WE PROBABLY SHOULDN'T HAVE AAAAAAAAAA. The below is only so they can be included through mapping or "spawn " command. -Carl

/obj/item/storage/pill_bottle/benzilate
	name = "bottle of Benzilate pills"
	desc = "This just hurts to look at with how many words of caution are scrawled on the lable. Better eat all of 'em!"

/obj/item/storage/pill_bottle/benzilate
	starts_with = list(
		/obj/item/reagent_containers/pill/benzilate = 7,
	)

/obj/item/storage/pill_bottle/phenethylamine
	name = "bottle of Phenethylamine pills"
	desc = "Looks like someone drew a happy face on the label, replacing whatever was previously present."

/obj/item/storage/pill_bottle/phenethylamine
	starts_with = list(
		/obj/item/reagent_containers/pill/phenethylamine = 7,
	)
