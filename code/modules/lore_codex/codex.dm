// Inherits from /book/ so it can fit on bookshelves.
/obj/item/book/codex // s throughout this object.
	name = "The Traveler's Guide to Human Space: Borealis Edition"
	desc = "Contains useful information about the world around you.  It seems to have been written for travelers to the Borealis system, human or not. It also \
	has the words 'Don't Panic' in small, friendly letters on the cover."
	icon_state = "codex"
	item_state = "book4"
	unique = TRUE
	var/datum/codex_tree/tree = null
	var/root_type = /datum/lore/codex/category/main_borealis_lore

	special_handling = TRUE

/obj/item/book/codex/Initialize(mapload)
	// the tree is shared by every codex of this root type (the codex_trees shared cache holds it): we only view it
	rel_set(src, "tree", CACHED_KEY(codex_trees, root_type, src, root_type))
	. = ..()

/// One codex_tree per root type, shared by every codex of that type for the round (never invalidated,
/// never owned by a book: a codex dying doesn't take the others' tree with it).
DECLARE_SHARED_CACHE(codex_trees, GLOBAL_PROC_REF(build_codex_tree), SC_NEVER)

/proc/build_codex_tree(atom/movable/first_holder, root_type)
	return new /datum/codex_tree(first_holder, root_type)

EXTEND_INTERACTIONS(/obj/item/book/codex, INTERACT_USE("Read", PROC_REF(interaction_read_codex)))

/// Old attack_self.
/obj/item/book/codex/proc/interaction_read_codex(mob/user, obj/item/held, datum/interaction/interaction)
	if(!tree)
		rel_set(src, "tree", CACHED_KEY(codex_trees, root_type, src, root_type))
	icon_state = "[initial(icon_state)]-open"
	tree.display(user)

/obj/item/book/codex/lore/vir // s throughout this object.
	name = "The Traveler's Guide to Human Space: Borealis Edition"
	desc = "Contains useful information about the world around you.  It seems to have been written for travelers to the Borealis system, human or not. It also \
	has the words 'Don't Panic' in small, friendly letters on the cover."
	icon_state = "codex"
	root_type = /datum/lore/codex/category/main_borealis_lore
	libcategory = "Reference"

/obj/item/book/codex/lore/robutt
	name = "A Buyer's Guide to Artificial Bodies"
	desc = "Recommended reading for the newly cyborgified, new positronics, and the upwardly-mobile FBP."
	icon_state = "codex_robutt"
	item_state = "book6"
	root_type = /datum/lore/codex/category/main_robutts
	libcategory = "Reference"

/obj/item/book/codex/lore/news
	name = "Daedalus Pocket Newscaster"
	desc = "A regularly-updating compendium of articles on current events. Essential for new arrivals in the Borealis system and anyone interested in politics."
	icon_state = "newscodex"
	item_state = "book1"
	w_class = ITEMSIZE_SMALL
	root_type = /datum/lore/codex/category/main_news
	libcategory = "Reference"
	drop_sound = 'sound/items/drop/device.ogg'

/* // REMOVAL
// Combines SOP/Regs/Law
/obj/item/book/codex/corp_regs
	name = "NanoTrasen Regulatory Compendium"
	desc = "Contains large amounts of information on Standard Operating Procedure, Corporate Regulations, and important regional laws.  The best friend of \
	Internal Affairs."
	icon_state = "corp_regs"
	item_state = "book10"
	root_type = /datum/lore/codex/category/main_corp_regs
	throwforce = 5 // Throw the book at 'em.
	libcategory = "Reference"
*/


/obj/item/book/codex/chef_recipes
	name = "Chef Recipes Ultramatus Edition"
	color = "#585a5e"
	icon = 'icons/obj/library_ch.dmi'
	icon_state = "cooked_book"
	item_state = "book16"
	root_type = /datum/lore/codex/category/cooking_recipe_list
	libcategory = "Reference"
