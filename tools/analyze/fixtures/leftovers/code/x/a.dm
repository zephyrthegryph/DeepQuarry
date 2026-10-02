show_radial_menu(user, src, choices)
x = show_radial_menu_persistent (a)
x.show_radial_menu(a)
/proc/show_radial_menu(a)
xshow_radial_menu(a)
new /datum/radial_menu
new/datum/radial_menu
var/y = new /datum/radial_menu/persistent
// show_radial_menu(a)
x = "show_radial_menu("
show_radial_menu(a) // ALLOW(radial): not an action picker
// ALLOW(radial): above
show_radial_menu(b)
// ALLOW(traits): wrong kind
show_radial_menu(c)
	/* ALLOW(radial): block */ show_radial_menu(d)
ADD_TRAIT(user, T, src)
REMOVE_TRAIT (user, T, src)
HAS_TRAIT(user, T)
x.HAS_TRAIT(a)
/ADD_TRAIT(a)
HAS_TRAIT_FROM(a, b, c)
HAS_TRAIT_FROM_ONLY(a)
REMOVE_TRAITS_IN(a, b)
HAS_MIND_TRAIT(a)
TRAIT_CALLBACK_ADD(a)
GET_TRAIT_SOURCES(a)
x = _status_traits
x = my_status_traits
x = _status_traits_extra
ADD_TRAIT(a, b, c) // ALLOW(traits): no effect
// ALLOW(traits): none
ADD_TRAIT(a, b, c)
HAS_TRAIT
/datum/disease
/datum/disease/flu
x = new /datum/disease2
/datum/diseasex
/datum/disease // ALLOW(disease): no effect
var/s = "/datum/disease"
ADD_TRAIT(a) /datum/disease show_radial_menu(a)
