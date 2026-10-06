// param(var, schema, default =, required =, pos =) and make(type, at =, name = value...): named, typed constructor arguments, set before init
// (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 2).
//
//	CAPABILITIES(/obj/item/paper)
//		param(nameof(info), schema_text(max_len = MAX_PAPER_MESSAGE_LEN))
//		param(nameof(stamped_by), schema_ref(/mob))
//	CAPABILITIES(/obj/effect/decal/cleanable/blood)
//		param(nameof(blood_dna), map_of(schema_text(), schema_text()), pos = 1)    // new /obj/effect/decal/cleanable/blood(loc, dna) still works
//	CAPABILITIES(/obj/machinery/autolathe)
//		built_from(nameof(component_parts))
//
//	var/obj/item/paper/P = make(/obj/item/paper, at = src, info = text, stamped_by = OWNER)
//	make(/obj/machinery/autolathe, at = frame.loc, parts = frame.take_parts())
//
// A param is a var the creator sets: its value is in place before the type's init code runs (before rolls(), which a given value suppresses).
// `schema` is a value schema (section 4: int(), num(), schema_text(), schema_ref(type), enum(), ...) or a type path (shorthand for schema_ref);
// a given value is checked against it, and a refused one is reported and replaced by the default. `default =` is a constant or PROC_REF(x)
// of the holder, used when nothing gave a value (the map, make(), a positional argument). `required = TRUE` reports an instance made without
// one. `pos = N` maps the N-th constructor argument after the location (new T(loc, a, b): a is pos 1) to the param, so a caller not yet moved
// to make() keeps working; the codemod moves the callers it can see.
//
// make() is generated (analyze gen declare writes it into code/engine/_generated/declare.dm): its named parameters are every name a param()
// declares anywhere, so DM and DreamChecker check each call, and `analyze` checks that the made type declares each name it is given and every
// required one. OWNER as a value is the caller (`by =`, default: the instance whose code is running the make is unknown to DM, so pass it).
//
// built_from(nameof(var)) takes make(..., parts = list(...)): the parts move into the instance and the var holds them, before init.
//
// `apply = PROC_REF(x)` is for a param the type puts into effect through a setter (a material key, a colour, a lifespan): x(value) runs at
// init, after the capabilities and initial contents (where the old `Initialize(mapload, arg)` called it after `..()`), with the param's value,
// given or not. A subtype that only changed the value passed up (`..(mapload, MAT_IRON)`) sets the var's default instead.
//
//	CAPABILITIES(/obj/structure/simple_door)
//		param(nameof(material_name), pos = 1, apply = PROC_REF(set_material))
//	/obj/structure/simple_door/iron
//		material_name = MAT_IRON
//
// A positional argument that is null is not given: the var keeps its default (the `arg || default` the old overrides wrote).
//
// `keep = FALSE` is for a value init only builds from: a mob a statue copies, the assembly a door is built from. The setters (apply =) and
// an Initialize() that remains read it; when Initialize() has returned (an atom) or the init ran (a plain datum), the var goes back to its
// compiled default, so the instance holds no reference to it.

/proc/param(var_name, schema = null, default = null, required = FALSE, pos = null, apply = null, keep = TRUE)
	if(!istext(var_name))
		declare_report("param(): the var is nameof(var), got [var_name]")
		return null
	if(ispath(schema, /datum))
		schema = schema_ref(schema)
	if(!isnull(apply) && !istext(apply))
		declare_report("param([var_name]): apply = is PROC_REF(x), got [apply]")
		apply = null
	return entry_make(ENTRY_PARAM, "param:[var_name]", list("var" = var_name, "schema" = schema, "default" = default, "required" = !!required, "pos" = pos, "apply" = apply, "keep" = !!keep))

/proc/built_from(var_name)
	return entry_make(ENTRY_BUILT_FROM, "built_from", list("var" = var_name))

/// What a make() call hands the instance it makes: read in /atom/New() (or /datum/New()) before anything of the type runs.
/datum/make_args
	/// param name -> value (OWNER already resolved).
	var/list/values
	/// The creator: OWNER's value, and the stream the instance rolls from.
	var/datum/by
	/// built_from() parts.
	var/list/parts
	/// The type make() was asked for: a plain datum's New() takes only a record of its own type.
	var/made_type

/// The placeholder OWNER names (a type path, so it travels in a list): replaced by the creator wherever a make() or starts_args value holds it.
/datum/lifeform_owner

/// `value` with OWNER replaced by `owner` (a list is copied, one level deep).
/proc/owner_resolve(value, datum/owner)
	if(value == OWNER)
		return owner
	if(islist(value))
		var/list/L = value
		if(!(OWNER in L))
			return value
		var/list/out = L.Copy()
		for(var/i in 1 to length(out))
			if(out[i] == OWNER)
				out[i] = owner
		return out
	return value

/// make_args(name = value, ...) for a starts_args: the named params of what starts = makes, with OWNER the holder. The generated make_args()
/// has the same named parameters as make(); this is its body.
/proc/make_args_build(list/given)
	var/datum/make_args/M = new
	M.values = given
	return M

/// The body of the generated make(): checks the names against the type's declaration, builds the record and creates the instance with it.
/proc/make_build(type, at, datum/by, list/parts, list/given)
	if(!ispath(type, /datum))
		CRASH("make([type]): not a type")
	var/datum/make_args/M = new
	M.by = by // ALLOW(ownership): a make() record names its creator for one construction and is dropped after
	M.parts = parts
	M.values = list()
	for(var/name in given)
		M.values[name] = owner_resolve(given[name], by)
	if(ispath(type, /atom))
		if(ispath(type, /turf))
			var/turf/T = get_turf(at)
			return T?.ChangeTurf(type)
		return new type(at, M)
	M.made_type = type
	GLOB.make_pending += M
	var/datum/D = new type
	GLOB.make_pending -= M
	return D

/// make() records of plain datums being made now (innermost last): /datum/New() takes the top one for an instance of its type.
GLOBAL_LIST_EMPTY(make_pending)
/// instance -> param names a creator gave (make() or a positional argument), until its preinit checks them.
/// A real global: atoms are made (and take positional params) while the globals are still being made.
GLOBAL_REAL_VAR(list/param_given)

/// /atom/New(loc, ...) with more than a location: a make() record, or positional arguments a param(pos =) takes. Writes the values before init.
/// Returns TRUE when it consumed a make() record (the caller drops it from the arguments Initialize() gets).
/proc/lifeform_new_args(atom/A, list/new_args)
	var/datum/make_args/M = new_args[2]
	if(istype(M))
		make_apply(A, M)
		return TRUE
	var/datum/type_table/T = type_table_cache()[A.type] || table_of(A)
	if(!(T.hook_flags & ENGINE_HOOK_LIFEFORMS))
		return FALSE
	var/datum/lifeform_plan/P = lifeform_plan_of(A)
	if(!P.param_pos)
		return FALSE
	var/list/given = list()
	for(var/i in 2 to length(new_args))
		var/var_name = P.param_pos["[i - 1]"]
		if(var_name && !isnull(new_args[i]))
			param_write(A, var_name, new_args[i])
			given += var_name
	if(length(given))
		LAZYINITLIST(param_given)
		param_given[A] = given
	return FALSE

/// Writes a make() record's values onto the instance being made, before its init: params, then the built_from parts.
/proc/make_apply(datum/D, datum/make_args/M)
	var/list/given = list()
	for(var/name in M.values)
		if(!(name in D.vars))
			declare_report("make([D.type]): [name] is not a var of the type")
			continue
		param_write(D, name, M.values[name])
		given += name
	if(M.parts)
		var/datum/lifeform_plan/P = lifeform_plan_of(D)
		var/datum/centry/C = P.built_from?[1]
		if(!C)
			declare_report("make([D.type], parts = ...): the type declares no built_from()")
		else
			var/datum/entry/E = C.item
			var/list/held = list()
			for(var/atom/movable/part in M.parts)
				if(isatom(D))
					part.forceMove(D)
				held += part
			D.vars[E.args["var"]] = held
			given += E.args["var"]
	if(M.by && !QDELETED(M.by))
		// The made instance rolls from its creator's stream: the creator's live roller while it initializes, else its seed text and a serial.
		var/datum/roller/creator = GLOB.roll_rollers[M.by]
		var/base = creator ? "[creator.base]/[++creator.children]" : "[roll_base_for(M.by)]/[++GLOB.roll_serial]"
		GLOB.roll_rollers[D] = new /datum/roller(base)
	if(length(given))
		LAZYINITLIST(param_given)
		param_given[D] = given

/// At preinit: each param checked against its schema, defaulted when nothing gave it, and a missing required one reported.
/proc/params_preinit(datum/holder, datum/lifeform_plan/P, mapload)
	var/list/given = param_given?[holder]
	if(given)
		param_given -= holder
	for(var/datum/centry/C as anything in P.params)
		var/datum/entry/E = C.item
		var/var_name = E.args["var"]
		if(!(var_name in holder.vars))
			continue
		var/value = holder.vars[var_name]
		var/was_given = (var_name in given) || value != initial(holder.vars[var_name])
		if(!was_given)
			var/default = E.args["default"]
			if(istext(default) && hascall(holder, default))
				holder.vars[var_name] = call(holder, default)() // ALLOW(api): a param's PROC_REF default, before init
			else if(!isnull(default))
				holder.vars[var_name] = default // ALLOW(api): a param's declared default, before init
			else if(E.args["required"])
				declare_report("[C.origin]: [holder.type] was made without its required param [var_name] (make(..., [var_name] = ...))")
			continue
		var/datum/schema/S = E.args["schema"]
		if(istype(S) && !isnull(value))
			var/list/checked = schema_check(S, value, FALSE, holder)
			if(checked[1] == SCHEMA_REJECT)
				declare_report("[C.origin]: [holder.type].[var_name] = [value] refused by its schema: [checked[2]]")
				holder.vars[var_name] = initial(holder.vars[var_name]) // ALLOW(api): a refused param falls back to the compiled default
			else
				holder.vars[var_name] = checked[1] // ALLOW(api): a param's schema-normalised value, before init

/// /datum/New() of a type declaring a form: the top make() record of its type, if one is pending.
/proc/make_pending_for(datum/D)
	for(var/i in length(GLOB.make_pending) to 1 step -1)
		var/datum/make_args/M = GLOB.make_pending[i]
		if(M.made_type != D.type)
			continue
		make_apply(D, M)
		GLOB.make_pending.Cut(i, i + 1)
		return M
	return null

/// Writes a param before init: a declared relation var through rel_set() (its back-reference and teardown are the relation layer's), any
/// other var directly, as a map edit would.
/proc/param_write(datum/D, var_name, value)
	if(own_table_of(D).entries?[var_name])
		rel_set(D, var_name, value)
		return
	D.vars[var_name] = value // ALLOW(api): a param is written before init, as a map edit would be

/// At init: each param declared with apply = is put into effect through its setter, with its value (given, defaulted or the compiled one).
/// The keep = FALSE params are marked to drop when Initialize() returns (params_drop()).
/proc/params_apply(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.param_applies)
		var/datum/entry/E = C.item
		var/var_name = E.args["var"]
		try
			call(holder, E.args["apply"])(holder.vars[var_name])
		catch(var/exception/e)
			stack_trace("param([var_name], apply = [E.args["apply"]]) on [holder.type]: [e] ([e.file]:[e.line])")
		if(QDELETED(holder))
			return
	if(P.param_drops)
		if(!param_drop_pending)
			param_drop_pending = list()
		param_drop_pending[holder] = TRUE

/// instance -> TRUE while it holds keep = FALSE params to drop (InitAtom() drops them when Initialize() returns). A real global: atoms
/// initialize while the globals are still being made.
GLOBAL_REAL_VAR(list/param_drop_pending)

/// Drops `holder`'s keep = FALSE params: each var goes back to its compiled default.
/proc/params_drop(datum/holder)
	param_drop_pending -= holder
	if(QDELETED(holder))
		return
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	for(var/datum/centry/C as anything in P.param_drops)
		var/datum/entry/E = C.item
		holder.vars[E.args["var"]] = initial(holder.vars[E.args["var"]])
