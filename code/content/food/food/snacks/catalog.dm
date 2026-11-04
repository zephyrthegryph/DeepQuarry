/obj/item/storage/box/admints
	name = "Ad-mints"
	desc = "A pack of air fresheners for your mouth."
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "admint_pack"
	item_state = "candy"
	w_class = ITEMSIZE_TINY
	starts_with = list(/obj/item/reagent_containers/food/snacks/mint/admints = 6)
	use_sound = SFX_ITEMS_DROP_PAPER
	max_storage_space = 6
	foldable = null
	trash = /obj/item/trash/admints

CAPABILITIES(/obj/item/storage/box/admints)
	configure(atom_rules(description_fluff = "Ad-mints earned their name, and reputation when a Major Bill's senior executive attended a meeting at a large a marketing firm and was so astounded by the quality of their complimentary mints, that he immediately bought the company - the mints company, not the ad agency - and began providing 'Ad-mints' on every MBT flight."))
	configure(item_worn(slots = SLOT_EARS))
	configure(item_sounds(drop = SFX_ITEMS_DROP_WRAPPER))
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/mint/admints)))

/obj/item/storage/box/wings //This is kinda like the donut box.
	name = "wing basket"
	desc = "A basket of chicken wings! Get some before they're all gone! Or maybe you're too late..."
	icon = 'icons/obj/food.dmi'
	icon_state = "wings5"
	var/icon_base = "wings"
	var/startswith = 5
	max_storage_space = ITEMSIZE_COST_SMALL * 5
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/chickenwing = 5
	)
	foldable = null

/obj/item/storage/box/wings

CAPABILITIES(/obj/item/storage/box/wings)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/chickenwing)))

/obj/item/storage/box/wings/draw(datum/look/look)
	. = ..()
	look.state("[icon_base][held_count()]")

/obj/item/storage/box/wings/tray //Might as well re-use this code.
	name = "ration cube tray"
	desc = "A tray of food cubes, the label warns not to consume before adding water or mixing with virusfood."
	icon_state = "tray8"
	icon_base = "tray"
	startswith = 8
	w_class = ITEMSIZE_SMALL
	max_storage_space = ITEMSIZE_COST_TINY * 8
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/cube/protein = 4,
		/obj/item/reagent_containers/food/snacks/cube/nutriment = 4
	)

/obj/item/storage/box/wings/tray

CAPABILITIES(/obj/item/storage/box/wings/tray)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks/cube/protein,
		/obj/item/reagent_containers/food/snacks/cube/nutriment)))

//Fennec foods
/obj/item/storage/box/wings/bucket
	name = "Bucket o' grubs"
	desc = "A bucket full of writhing grubs."
	icon_state = "bucket6"
	icon_base = "bucket"
	startswith = 6
	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_SMALL * 6
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/grub = 6
	)

CAPABILITIES(/obj/item/storage/box/wings/bucket)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/grub)))

/obj/item/storage/box/jaffacake //This is kinda like the donut box.
	name = "Desatti Jaffa Cakes"
	desc = "A box full of desatti brand jaffa cakes, with twelve in a pack!"
	icon = 'icons/obj/food.dmi'
	icon_state = "jaffacake_pack"
	var/icon_base = "jaffacake_pack"
	var/startswith = 12
	max_storage_space = ITEMSIZE_COST_SMALL * 12
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/jaffacake = 12
	)
	foldable = null

/obj/item/storage/box/jaffacake

CAPABILITIES(/obj/item/storage/box/jaffacake)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/jaffacake)))

/obj/item/storage/box/winegum //This is kinda like the donut box.
	name = "Desatti Wine Gums"
	desc = "A pack of wine gums, randomly assorted shapes and fruity flavours!"
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "winegum_pack"
	var/icon_base = "winegum_pack"
	var/startswith = 20
	max_storage_space = ITEMSIZE_COST_TINY * 20
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/winegum = 3,
		/obj/item/reagent_containers/food/snacks/winegum/orange = 4,
		/obj/item/reagent_containers/food/snacks/winegum/black = 3,
		/obj/item/reagent_containers/food/snacks/winegum/green = 3,
		/obj/item/reagent_containers/food/snacks/winegum/yellow = 3,
		/obj/item/reagent_containers/food/snacks/winegum/white = 4
	)
	foldable = null

/obj/item/storage/box/winegum

CAPABILITIES(/obj/item/storage/box/winegum)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/winegum)))

/obj/item/storage/box/saucer //This is kinda like the donut box.
	name = "Desatti Sherbert Saucers"
	desc = "A pack of sherbert saucers, delicious pure sugar barely held together in packets of rice paper!"
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "saucer_pack"
	var/icon_base = "saucer_pack"
	var/startswith = 20
	max_storage_space = ITEMSIZE_COST_TINY * 20
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/saucer = 20,
	)
	foldable = null

/obj/item/storage/box/saucer

CAPABILITIES(/obj/item/storage/box/saucer)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/saucer)))

/obj/item/storage/box/custardcream //This is kinda like the donut box.
	name = "Desatti Custard Creams"
	desc = "A box full of desatti brand custard cream biscuits!"
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "custard_cream_pack"
	var/icon_base = "custard_cream_pack"
	var/startswith = 12
	max_storage_space = ITEMSIZE_COST_SMALL * 12
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/custardcream = 12
	)
	foldable = null

/obj/item/storage/box/custardcream

CAPABILITIES(/obj/item/storage/box/custardcream)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/custardcream)))

/obj/item/storage/box/bourbon //This is kinda like the donut box.
	name = "Desatti Bourbons"
	desc = "A box full of desatti brand chocolate bourbon biscuits!"
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "bourbon_pack"
	var/icon_base = "bourbon_pack"
	var/startswith = 12
	max_storage_space = ITEMSIZE_COST_SMALL * 12
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/bourbon = 12
	)
	foldable = null

/obj/item/storage/box/bourbon

CAPABILITIES(/obj/item/storage/box/bourbon)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/bourbon)))

/obj/item/storage/box/shrimpsandbananas //This is kinda like the donut box.
	name = "Shrimps and Bananas"
	desc = "A pack of foam bananas and shrimps, the shrimps apparently don't taste of seafood! Branded as Desatti Catering."
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "shrimpbanana_pack"
	var/icon_base = "shrimpbanana_pack"
	var/startswith = 20
	max_storage_space = ITEMSIZE_COST_TINY * 20
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/foam_banana = 10,
		/obj/item/reagent_containers/food/snacks/foam_shrimp = 10
	)
	foldable = null

/obj/item/storage/box/shrimpsandbananas

CAPABILITIES(/obj/item/storage/box/shrimpsandbananas)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks/foam_banana,
		/obj/item/reagent_containers/food/snacks/foam_shrimp)))

/obj/item/storage/box/rhubarbcustard //This is kinda like the donut box.
	name = "Desatti Rhubarb and Custards"
	desc = "A pack of rhubarb and custard boiled sweets, the taste combination might sound usual, but they insist it's actually kind of okay!"
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "rhubarbcustard_pack"
	var/icon_base = "rhubarbcustard_pack"
	var/startswith = 15
	max_storage_space = ITEMSIZE_COST_TINY * 15
	starts_with = list(
		/obj/item/reagent_containers/food/snacks/rhubarbcustard = 15,
	)
	foldable = null

/obj/item/storage/box/rhubarbcustard

CAPABILITIES(/obj/item/storage/box/rhubarbcustard)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/rhubarbcustard)))
