// look_from(): a family of icon states named after one key var (doc/rewrite/framework_gaps.md, "Mob init burn-down forms").
//
//	CAPABILITIES(/mob/living/simple_mob/animal/passive/chicken)
//		rolls(nameof(body_color), pick_one(list("brown", "black", "white")), when = cond_not(nameof(body_color)))
//		look_from(nameof(body_color), state = "chicken_*", living = "chicken_*", dead = "chicken_*_dead")
//	CAPABILITIES(/mob/living/simple_mob/vore/catgirl)
//		rolls(nameof(icon_living), nameof(skins), when = nameof(random_skin))
//		look_from(nameof(icon_living), rest = "*asleep", dead = "*-dead", only_if = nameof(random_skin))
//
// Each format names one icon var: `state` icon_state, `item` item_state, `living` icon_living, `dead` icon_dead, `rest` icon_rest. A `*`
// in it is the key var's value. It runs in the capability preinit, after rolls() (so a rolled key is in place) and before any subtype's
// code after `..()`. Nothing is written when the key is null, or when `only_if` (a holder var) is false. The old overrides did this with
// set_icon_living()/set_icon_dead()/set_icon_rest() after `..()`; before init nothing has drawn yet, so the plain write is the whole job.

CAPABILITY_TYPE(look_from, CAP_LOOK_FROM, /datum/capability/lib/look_from, key = NONE, from_var = null, state = null, item = null, living = null, dead = null, rest = null, only_if = null)

/datum/capability/lib/look_from
	holder_hooks = HOLDER_HOOK_PREINIT

/datum/capability/lib/look_from/on_holder_preinit(datum/act/eval/A)
	var/datum/holder = A.holder
	if(!from_var || !(from_var in holder.vars))
		return
	if(only_if && !holder.vars[only_if])
		return
	var/value = holder.vars[from_var]
	if(isnull(value))
		return
	var/list/formats = list("icon_state" = state, "item_state" = item, "icon_living" = living, "icon_dead" = dead, "icon_rest" = rest)
	for(var/var_name in formats)
		var/format = formats[var_name]
		if(isnull(format) || !(var_name in holder.vars))
			continue
		holder.vars[var_name] = replacetext(format, "*", "[value]") // ALLOW(api): a declared look written before init, as a map edit would be
