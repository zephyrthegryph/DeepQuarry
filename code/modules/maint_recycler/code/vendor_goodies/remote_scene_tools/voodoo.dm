#define DATA_SCALE "scale"
#define DATA_X_OFFSET "x"
#define DATA_Y_OFFSET "y"
#define DATA_ROTATION "rotation"

/obj/item/remote_scene_tool/voodoo_doll
	name = "voodoo doll"
	desc = "A dubiously cursed-esq Voodoo doll that mimics whoever is wearing its matching necklace via built in hardlight projection."
	icon = 'code/modules/maint_recycler/icons/goodies/remote_scene_tools.dmi'
	icon_state = "voodoo_doll_inactive"
	icon_root = "voodoo_doll"

	replacementType = /obj/item/remote_scene_tool/voodoo_necklace

	//this is just a copy of the remote scene tool, but with a different icon
	//and a different name

	var/underlayRotation = 45
	//TODO: make this generic so it's easier for other stuff to use. ideally there's a magical thing that just has all the various greebles set up so u can pick and choose which ones are rendered traditionally
	var/static/list/tail_data = list( DATA_X_OFFSET = 2, DATA_Y_OFFSET = -2,DATA_SCALE = 1.6, DATA_ROTATION = 45)
	var/static/list/taur_data = list( DATA_X_OFFSET = 2, DATA_Y_OFFSET = 2, DATA_SCALE = 1.1, DATA_ROTATION = 45)
	var/static/list/wing_data = list( DATA_X_OFFSET = 2, DATA_Y_OFFSET = -2,DATA_SCALE = 1,   DATA_ROTATION = 45)
	var/static/list/ear_data =  list( DATA_X_OFFSET = 0, DATA_Y_OFFSET = 1, DATA_SCALE = 1.5,   DATA_ROTATION = 45)
	var/static/list/hat_data =  list( DATA_X_OFFSET = 0, DATA_Y_OFFSET = 3, DATA_SCALE = 1,   DATA_ROTATION = 45)
	var/outline_size = 1

	var/static/list/discarded_layer_indicies = list(
		VORE_BELLY_LAYER, //not even gonna try with this lmfao
		TAIL_LOWER_LAYER,
		TAIL_UPPER_LAYER,
		TAIL_UPPER_LAYER_LOW,
		TAIL_UPPER_LAYER_HIGH, //drawn manually
		FIRE_LAYER, //not relevant
		TARGETED_LAYER, //not relevant
		MOB_WATER_LAYER, //not relevant
		L_HAND_LAYER, //not drawn, looks like ass
		R_HAND_LAYER,
		EARS_LAYER, //drawn manually
		WING_LAYER,
		WING_LOWER_LAYER, //drawn manually
		HEAD_LAYER, //drawn manually
	)
	appearance_flags = KEEP_TOGETHER
	var/no_fun_mode = FALSE //if true, we just draw the mob as an overlay

/obj/item/remote_scene_tool/voodoo_necklace
	name = "Gem-Encrusted Necklace"
	desc = "A bitingly cold metal necklace with a swirling gem in the center. Haters will say it's not magical"
	icon_state = "necklace_inactive"
	icon_root = "necklace"
	slot_flags = SLOT_MASK
	replacementType = /obj/item/remote_scene_tool/voodoo_doll

/obj/item/storage/box/remote_scene_tools/voodoo
	icon_state = "voodoobox"
	name = "Voodoo Supplies Box"
	desc = "a horribly dusty box from 'magici-corp' with a ludicrously corny image of a voodoo doll on the front."
	description_fluff = "originally marketed as part of a DIY magician routine, the company making them went under due to countless lawsuits from people who broke their nose upon the doll being dropped, and tesh filing descrimination suits. they haven't been made in well over a decade."
	primary =/obj/item/remote_scene_tool/voodoo_doll
	secondary =/obj/item/remote_scene_tool/voodoo_necklace

TRACKED(/obj/item/remote_scene_tool/voodoo_doll, no_fun_mode)

CAPABILITIES(/obj/item/remote_scene_tool/voodoo_doll)
	op("voodoo_doll_verb_toggle_fun", menu(), label("Disable Special Rendering"), needs(carried()), then(PROC_REF(voodoo_doll_verb_toggle_fun)))

/// Old Disable Special Rendering verb: Disables the displacement-based rendering on the doll, leaving it as just a doll at all times.
/obj/item/remote_scene_tool/voodoo_doll/proc/voodoo_doll_verb_toggle_fun(datum/act/op/A)
	var/mob/user = A.actor
	set_no_fun_mode(!no_fun_mode)
	to_chat(user,span_notice("you turn the dial on the back of \the [src], and turn the advanced projection matrix [no_fun_mode ? "off" : "on"]"))

/obj/item/remote_scene_tool/voodoo_doll/Move(atom/newloc, direct, movetime)
	. = ..()
	dir = SOUTH //we need to do this

/obj/item/remote_scene_tool/voodoo_doll/proc/get_outline_color(r,g,b,a, offset = 30)
	var/new_rgba = rgb(r-offset,g-offset,b-offset,a)
	return new_rgba

/obj/item/remote_scene_tool/voodoo_doll/proc/generate_layer_matrix(list/data)
	var/matrix/output = matrix()
	output.Translate(data[DATA_X_OFFSET], data[DATA_Y_OFFSET])
	output.Turn(data[DATA_ROTATION])
	output.Scale(data[DATA_SCALE], data[DATA_SCALE])
	return output

/// The outline colour of the wearer's tail: a grey, or a darker version of the tail's colouration.
/obj/item/remote_scene_tool/voodoo_doll/proc/tail_outline_color(mob/living/carbon/human/buddy)
	if(buddy.tail_style?.do_colouration)
		return get_outline_color(buddy.r_tail, buddy.g_tail, buddy.b_tail, buddy.a_tail)
	return rgb(50,50,50)

/// The outline colour of the wearer's wings, the same way.
/obj/item/remote_scene_tool/voodoo_doll/proc/wing_outline_color(mob/living/carbon/human/buddy)
	if(buddy.wing_style?.do_colouration)
		return get_outline_color(buddy.r_wing, buddy.g_wing, buddy.b_wing, buddy.a_wing)
	return rgb(50,50,50)

/obj/item/remote_scene_tool/voodoo_doll/proc/generate_layer_image(image/input, matrix/newtransform, outline_width = 0, outline_color = rgb(50,50,50), mask_inverse = FALSE)
	if(input == null)
		return null

	input.dir = SOUTH
	input.transform = newtransform
	input.layer = FLOAT_LAYER
	if(outline_width > 0)
		input.filters += filter(type="outline", size = outline_width, color = outline_color)
	if(mask_inverse)
		input.filters += filter(type = "alpha", flags = MASK_INVERSE)

	return input

/// The doll shows its necklace's wearer: the wearer's worn layers displaced onto the doll, with the ears, hat, tail and wings drawn as layers of their own.
/// It composes the wearer's whole look through look.watch_look(), so it is drawn again when that look changes and not when the wearer writes any other var.
/obj/item/remote_scene_tool/voodoo_doll/draw(datum/look/look)
	..()
	look.set_dir(SOUTH)
	var/mob/owner = partner_wearer
	look.identity(owner ? "Voodoo doll of [partner_name]" : initial(name), owner ? "A small, marketable doll that looks suspiciously like [partner_name]... " : initial(desc))
	if(!owner)
		return
	if(istype(owner, /mob/living/carbon/human/teshari))
		return //no flesh horror, sorry
	if(!worn_mob)
		return //only render the funny when we're on a humie
	if(no_fun_mode)
		return //no fun allowed
	if(!ishuman(owner))
		return
	var/mob/living/carbon/human/buddy = owner
	look.watch_look(buddy)
	var/is_tail_taur = istaurtail(buddy.tail_style)
	var/icon/displacement_map = icon(src.icon, is_tail_taur ? "taurdisplacement" : "displacement", SOUTH)
	var/image/displacement_rendered = get_humanoid_displacement_map_image(buddy, discarded_layer_indicies, displacement_map, 2, null)

	//tails need special attention because taurs
	var/tailoutlinecolor = tail_outline_color(buddy) //default to a grey, otherwise we use a darker version of one of the tail colors
	var/image/tail_image
	if(is_tail_taur)
		tail_image = generate_layer_image(buddy.get_tail_image(), generate_layer_matrix(taur_data), outline_size, tailoutlinecolor, mask_inverse = TRUE)
	else
		tail_image = generate_layer_image(buddy.get_tail_image(), generate_layer_matrix(tail_data), outline_size, tailoutlinecolor)

	//same kind of scenario for wings
	var/wingoutlinecolor = wing_outline_color(buddy)
	var/image/wing_image = generate_layer_image(buddy.get_wing_image(FALSE), generate_layer_matrix(wing_data), outline_size, wingoutlinecolor)
	var/image/under_wing_image = generate_layer_image(buddy.get_wing_image(TRUE), generate_layer_matrix(wing_data), outline_size, wingoutlinecolor)

	//the rest are pretty simple
	var/ear_icon = buddy.get_ears_overlay()
	var/image/ear_image = generate_layer_image(image(icon = ear_icon), generate_layer_matrix(ear_data))

	//hat
	var/hat_icon = buddy.get_equipped_item(SLOT_ID_HEAD)?.make_worn_icon(body_type = buddy.species.get_bodytype(src), slot_name = slot_head_str, default_icon = INV_HEAD_DEF_ICON, default_layer = HEAD_LAYER)
	var/image/hat_image = generate_layer_image(image(icon = hat_icon), generate_layer_matrix(hat_data))

	//add them all
	look.overlay(displacement_rendered)
	look.overlay(ear_image)
	look.overlay(hat_image)
	if(is_tail_taur)
		look.overlay(tail_image)
	else
		look.underlay(tail_image)
	look.underlay(wing_image)
	look.underlay(under_wing_image)

	//filtering time: a very slight blur. this is unironically the best way to do it, any of the blur filters are just way too strong at a minimum value.
	var/matrix/blur = matrix()
	blur.Turn(2)
	look.set_transform(blur)

#undef DATA_X_OFFSET
#undef DATA_Y_OFFSET
#undef DATA_SCALE
#undef DATA_ROTATION
