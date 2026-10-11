// body_effect(effect, when =): a body effect a mob carries from creation (doc/rewrite/framework_gaps.md, "Mob init burn-down forms").
//
//	CAPABILITIES(/mob/living/simple_mob/slime/xenobio/ruby)
//		body_effect(/datum/body_effect/slime_strength)          // always swole
//	CAPABILITIES(/mob/living/simple_mob/humanoid/astral_collective)
//		rolls(nameof(experiment_effect), pick_one(list(...)))
//		body_effect(nameof(experiment_effect))                   // a var holding the path: the rolled one
//
// `effect` is a /datum/body_effect path, or nameof(var) holding one (null applies nothing). It is applied with no duration (held) in the
// capability init, with the mob as its origin, when `when` (a condition, section 5) holds then. The key is the effect, so a type can carry
// several. It replaces the Initialize() overrides that called apply_body_effect(path, null, src) around `..()`.

CAPABILITY_TYPE(body_effect, CAP_BODY_EFFECT, /datum/capability/lib/body_effect, key = effect, effect = null, when = null)

/datum/capability/lib/body_effect
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/body_effect/on_holder_init(datum/act/eval/A)
	var/mob/living/holder = A.holder
	if(!isliving(holder))
		return
	if(!isnull(when) && !condition_holds(holder, when))
		return
	var/path = istext(effect) ? holder.vars[effect] : effect
	if(ispath(path, /datum/body_effect))
		holder.apply_body_effect(path, null, holder)
