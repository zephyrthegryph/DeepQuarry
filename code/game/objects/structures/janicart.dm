REGISTRY_MEMBERSHIP(/obj/structure/janitorialcart, REGISTRY_JANITORIAL_CARTS)

/obj/structure/janitorialcart
	name = "janitorial cart"
	desc = "The ultimate in janitorial carts! Has space for water, mops, signs, trash bags, and more!"
	icon = 'icons/obj/janitor.dmi'
	icon_state = "cart"
	anchored = FALSE
	density = TRUE
	flags = OPENCONTAINER
	//copypaste sorry
	var/amount_per_transfer_from_this = 5 //shit I dunno, adding this so syringes stop runtime erroring. --NeoFite
	var/obj/item/storage/bag/trash/mybag	= null
	var/obj/item/mop/mymop = null
	var/obj/item/reagent_containers/spray/myspray = null
	var/obj/item/lightreplacer/myreplacer = null
	var/obj/structure/mopbucket/mybucket = null
	var/has_items = FALSE
	var/dismantled = TRUE
	var/signs = 0	//maximum capacity hardcoded below
	var/list/tgui_icons

	var/static/list/equippable_item_whitelist

CAPABILITIES(/obj/structure/janitorialcart)
	owns_one(nameof(mybag), /obj/item/storage/bag/trash)
	owns_one(nameof(mymop), /obj/item/mop)
	owns_one(nameof(myreplacer), /obj/item/lightreplacer)
	owns_one(nameof(myspray), /obj/item/reagent_containers/spray)
	climb()

/obj/structure/janitorialcart/proc/equip_janicart_item(mob/user, obj/item/I)
	if(!equippable_item_whitelist)
		equippable_item_whitelist = typecacheof(list(
			/obj/item/storage/bag/trash,
			/obj/item/mop,
			/obj/item/mop/advanced,
			/obj/item/reagent_containers/spray,
			/obj/item/lightreplacer,
			/obj/item/clothing/suit/caution,
		))

	if(!is_type_in_typecache(I, equippable_item_whitelist))
		user.balloon_alert(user, "there's no room in [src] for [I].")
		return FALSE

	if(!user.canUnEquip(I))
		user.balloon_alert(user, "[I] is stuck to your hand.")
		return FALSE

	if(istype(I, /obj/item/storage/bag/trash))
		if(mybag)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(mybag), I)
		setTguiIcon("mybag", mybag)

	else if(istype(I, /obj/item/mop) || istype(I, /obj/item/mop/advanced))
		if(mymop)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(mymop), I)
		setTguiIcon("mymop", mymop)

	else if(istype(I, /obj/item/reagent_containers/spray))
		if(myspray)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(myspray), I)
		setTguiIcon("myspray", myspray)

	else if(istype(I, /obj/item/lightreplacer))
		if(myreplacer)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(myreplacer), I)
		setTguiIcon("myreplacer", myreplacer)

	else if(istype(I, /obj/item/clothing/suit/caution))
		if(signs < 4)
			signs++
			setTguiIcon("signs", I)
		else
			user.balloon_alert(user, "[src] can't hold any more signs.")
			return FALSE
	else
		// This may look like duplicate code, but it's important that we don't call unEquip *and* warn the user if
		// something horrible goes wrong. (this else is never supposed to happen)
		user.balloon_alert(user, "there's no room in [src] for [I].")
		return FALSE

	user.drop_from_inventory(I, src)
	update_icon()
	user.balloon_alert(user, "you put [I] into [src].")
	return TRUE

/obj/structure/janitorialcart/proc/setTguiIcon(key, atom/A)
	if(!istype(A) || !key)
		return

	var/icon/F = getFlatIcon(A, defdir = SOUTH, no_anim = TRUE)
	LAZYSET(tgui_icons, "[key]", "'data:image/png;base64,[icon2base64(F)]'")
	SStgui.update_uis(src)

/obj/structure/janitorialcart/proc/nullTguiIcon(key)
	if(!key)
		return
	LAZYREMOVE(tgui_icons, key)
	SStgui.update_uis(src)

/obj/structure/janitorialcart/proc/clearTguiIcons()
	LAZYCLEARLIST(tgui_icons)
	SStgui.update_uis(src)


// drops its cached tgui icons.
/obj/structure/janitorialcart/on_destroy(force)
	clearTguiIcons()
	..()

/obj/structure/janitorialcart/examine(mob/user)
	. = ..(user)
	if(istype(mybucket))
		var/contains = mybucket.reagents.total_volume
		. += "[icon2html(src, user.client)] The bucket contains [contains] unit\s of liquid!"
	else
		. += "[icon2html(src, user.client)] There is no bucket mounted on it!"

/// Old MouseDrop_T: mount a dragged mop bucket.
/datum/interaction/entry_drag/janitorialcart_drag
	id = "janitorialcart_drag"
	name = "Mount bucket"
	effect = /obj/structure/janitorialcart/proc/interaction_drag

/obj/structure/janitorialcart/proc/interaction_drag(mob/living/user, atom/movable/O, datum/interaction/interaction)
	if (istype(O, /obj/structure/mopbucket) && !mybucket)
		own_set(src, nameof(src.mybucket), O, user = user, into = TRUE)
		setTguiIcon("mybucket", mybucket)
		user.balloon_alert(user, "you mount the [O] on the janicart.")
		update_icon()
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/structure/janitorialcart/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/janitorialcart_item,
		/datum/interaction/entry_alt/janitorialcart_alt,
		/datum/interaction/entry_hand/janitorialcart_hand,
		/datum/interaction/entry_drag/janitorialcart_drag,
	)
	..()

/// Old attackby: wet a mop/rag/soap, empty the bucket, equip a tool, or drop trash in the bag.
/datum/interaction/entry_item/janitorialcart_item
	id = "janitorialcart_item"
	name = "Use"
	effect = /obj/structure/janitorialcart/proc/interaction_item

/obj/structure/janitorialcart/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/mop) || istype(I, /obj/item/reagent_containers/glass/rag) || istype(I, /obj/item/soap))
		if (mybucket)
			if(I.reagents.total_volume < I.reagents.maximum_volume)
				if(mybucket.reagents.total_volume < 1)
					user.balloon_alert(user, "[mybucket] is empty!")
				else
					mybucket.reagents.trans_to_obj(I, 5)	//
					user.balloon_alert(user, "you wet [I] in [mybucket].")
					play_sfx(src, SFX_EFFECTS_SLOSH)
			else
				user.balloon_alert(user, "[I] can't absorb anymore liquid!")
		else
			to_chat(user, span_notice("There is no bucket mounted here to dip [I] into!"))
		return TRUE

	else if (istype(I, /obj/item/reagent_containers/glass/bucket) && mybucket)
		I.afterattack(mybucket, user, 1, null, I_HELP) // wetting it in the bucket is a peaceful use
		update_icon()
		return TRUE

	else if(istype(I, /obj/item/reagent_containers/spray) && !myspray)
		equip_janicart_item(user, I)
		return TRUE

	else if(istype(I, /obj/item/lightreplacer) && !myreplacer)
		equip_janicart_item(user, I)
		return TRUE

	else if(istype(I, /obj/item/storage/bag/trash) && !mybag)
		equip_janicart_item(user, I)
		return TRUE

	else if(istype(I, /obj/item/clothing/suit/caution))
		equip_janicart_item(user, I)
		return TRUE

	else if(mybag)
		mybag.attackby(I, user)
		//This prevents dumb stuff like splashing the cart with the contents of a container, after putting said container into trash
	return TRUE

/obj/structure/janitorialcart/wrench_act(mob/user, obj/item/I)
	if(has_items)
		return TRUE
	om_task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user))
	return TRUE

/obj/structure/janitorialcart/proc/wrench_act_timed_done(mob/user)
	dismantle(user)

//New Altclick functionality!
//Altclick the cart with a mop to stow the mop away
//Altclick the cart with a reagent container to pour things into the bucket without putting the bottle in trash
/// Old click_alt: stow a mop, or pour a reagent container into the bucket.
/datum/interaction/entry_alt/janitorialcart_alt
	id = "janitorialcart_alt"
	name = "Use item"
	effect = /obj/structure/janitorialcart/proc/interaction_alt

/obj/structure/janitorialcart/proc/interaction_alt(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(user.incapacitated() || !Adjacent(user))	return TRUE
	var/obj/I = user.get_active_hand()
	if(istype(I, /obj/item/mop))
		equip_janicart_item(user, I)
	else if(istype(I, /obj/item/reagent_containers) && mybucket)
		var/obj/item/reagent_containers/C = I
		C.afterattack(mybucket, user, 1, null, I_HELP) // refilling from the bucket is a peaceful use
		update_icon()
	return TRUE

/// Old attack_hand: open the UI.
/datum/interaction/entry_hand/janitorialcart_hand
	id = "janitorialcart_hand"
	name = "Use"
	effect = /obj/structure/janitorialcart/proc/interaction_hand

/obj/structure/janitorialcart/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/structure/janitorialcart, "JanitorCart")

UI_DATA(/obj/structure/janitorialcart, "merge:ui_data_obj_structure_janitorialcart{mybag:text,mybucket:text,mymop:text,myspray:text,myreplacer:text,signs:text,icons:bool}")

/// The computed part of /obj/structure/janitorialcart's window data (declared on its UI_DATA row).
/obj/structure/janitorialcart/proc/ui_data_obj_structure_janitorialcart(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["mybag"] = mybag ? capitalize(mybag.name) : null
	data["mybucket"] = mybucket ? capitalize(mybucket.name) : null
	data["mymop"] = mymop ? capitalize(mymop.name) : null
	data["myspray"] = myspray ? capitalize(myspray.name) : null
	data["myreplacer"] = myreplacer ? capitalize(myreplacer.name) : null
	data["signs"] = signs ? "[signs] sign\s" : null

	data["icons"] = (tgui_icons || list())
	return data

UI_ACT(/obj/structure/janitorialcart, "bag", ui_act_bag)
UI_ACT_PROC(/obj/structure/janitorialcart, ui_act_bag)
	var/obj/item/I = ui.user.get_active_hand()
	if(mybag)
		ui.user.put_in_hands(mybag)
		ui.user.balloon_alert(ui.user, "you take [mybag] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::mybag))
		nullTguiIcon("mybag")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(ui.user, I)
	update_icon()
	return TRUE

UI_ACT(/obj/structure/janitorialcart, "mop", ui_act_mop)
UI_ACT_PROC(/obj/structure/janitorialcart, ui_act_mop)
	var/obj/item/I = ui.user.get_active_hand()
	if(mymop)
		ui.user.put_in_hands(mymop)
		ui.user.balloon_alert(ui.user, "you take [mymop] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::mymop))
		nullTguiIcon("mymop")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(ui.user, I)
	update_icon()
	return TRUE

UI_ACT(/obj/structure/janitorialcart, "spray", ui_act_spray)
UI_ACT_PROC(/obj/structure/janitorialcart, ui_act_spray)
	var/obj/item/I = ui.user.get_active_hand()
	if(myspray)
		ui.user.put_in_hands(myspray)
		ui.user.balloon_alert(ui.user, "you take [myspray] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::myspray))
		nullTguiIcon("myspray")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(ui.user, I)
	update_icon()
	return TRUE

UI_ACT(/obj/structure/janitorialcart, "replacer", ui_act_replacer)
UI_ACT_PROC(/obj/structure/janitorialcart, ui_act_replacer)
	var/obj/item/I = ui.user.get_active_hand()
	if(myreplacer)
		ui.user.put_in_hands(myreplacer)
		ui.user.balloon_alert(ui.user, "you take [myreplacer] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::myreplacer))
		nullTguiIcon("myreplacer")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(ui.user, I)
	update_icon()
	return TRUE

UI_ACT(/obj/structure/janitorialcart, "sign", ui_act_sign)
UI_ACT_PROC(/obj/structure/janitorialcart, ui_act_sign)
	var/obj/item/I = ui.user.get_active_hand()
	if(istype(I, /obj/item/clothing/suit/caution) && signs < 4)
		equip_janicart_item(ui.user, I)
	else if(signs)
		var/obj/item/clothing/suit/caution/sign = locate_within(src, /obj/item/clothing/suit/caution)
		if(sign)
			ui.user.put_in_hands(sign)
			ui.user.balloon_alert(ui.user, "you take \a [sign] from [src].")
			signs--
			if(!signs)
				nullTguiIcon("signs")
	else
		ui.user.balloon_alert(ui.user, "[src] doesn't have any signs left.")
	update_icon()
	return TRUE

UI_ACT(/obj/structure/janitorialcart, "bucket", ui_act_bucket)
UI_ACT_PROC(/obj/structure/janitorialcart, ui_act_bucket)
	if(mybucket)
		mybucket.forceMove(get_turf(ui.user))
		ui.user.balloon_alert(ui.user, "you unmount [mybucket] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::mybucket))
		nullTguiIcon("mybucket")
	else
		to_chat(ui.user, span_notice("((Drag and drop a mop bucket onto [src] to equip it.))"))
		return FALSE
	update_icon()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/structure/janitorialcart, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/janitorialcart/appearance_overlays()
	. = list()

	if(mybucket)
		. += "cart_bucket"
		if(mybucket.reagents.total_volume >= 1)
			. += "water_cart"
	if(mybag)
		. += "cart_garbage"
	if(mymop)
		. += "cart_mop"
	if(myspray)
		. += "cart_spray"
	if(myreplacer)
		. += "cart_replacer"
	if(signs)
		. += "cart_sign[signs]"

//This is called if the cart is caught in an explosion, or destroyed by weapon fire
/obj/structure/janitorialcart/proc/spill(chance = 100)
	var/turf/dropspot = get_turf(src)
	if (mymop && prob(chance))
		mymop.forceMove(dropspot)
		mymop.tumble(2)
		own_take(src, nameof(mymop))

	if (myspray && prob(chance))
		myspray.forceMove(dropspot)
		myspray.tumble(3)
		own_take(src, nameof(myspray))

	if (myreplacer && prob(chance))
		myreplacer.forceMove(dropspot)
		myreplacer.tumble(3)
		own_take(src, nameof(myreplacer))

	if (mybucket && prob(chance*0.5))//bucket is heavier, harder to knock off
		mybucket.forceMove(dropspot)
		mybucket.tumble(1)
		own_take(src, nameof(mybucket))

	if (signs)
		for (var/obj/item/clothing/suit/caution/Sign in contents_of(src))
			if (prob(min((chance*2),100)))
				signs--
				Sign.forceMove(dropspot)
				Sign.tumble(3)
				if (signs < 0)//safety for something that shouldn't happen
					signs = 0
					update_icon()
					return

	if (mybag && prob(min((chance*2),100)))//Bag is flimsy
		mybag.forceMove(dropspot)
		mybag.tumble(1)
		mybag.spill()//trashbag spills its contents too
		own_take(src, nameof(mybag))

	update_icon()
	clearTguiIcons()

/obj/structure/janitorialcart/proc/dismantle(mob/user = null)
	if (!dismantled)
		if (has_items)
			spill()

		new /obj/item/stack/material/steel(src.loc, 10)
		new /obj/item/stack/material/plastic(src.loc, 10)
		dismantled = 1
		replace_with(src, /obj/item/stack/rods, 20)

DAMAGE_REACTION(/obj/structure/janitorialcart, DAMAGE_EXPLOSION, PROC_REF(janicart_blast))
/// A blast spills the bucket.
/obj/structure/janitorialcart/proc/janicart_blast(datum/damage_packet/packet)
	spill(100 / packet.severity)
