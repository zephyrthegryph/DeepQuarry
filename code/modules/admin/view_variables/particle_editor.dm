/datum/particle_editor
	/// movable whose particles we want to be editing
	var/tmp/atom/movable/target

/datum/particle_editor/New(atom/target)
	rel_set(src, nameof(target), target)

CAPABILITIES(/datum/particle_editor)
	interface("ParticleEdit", rights = R_VAREDIT)
	op("delete_and_close", ui_act("delete_and_close"), then(PROC_REF(ui_act_delete_and_close)))
	op("new_type", ui_act("new_type"), asks(/datum/prompt/choice/particle_editor_type, fields = list("choices" = computed(PROC_REF(particle_type_choices))), step = "type"), then(PROC_REF(ui_act_new_type)))
	op("transform_size", ui_act("transform_size", arg("new_value")), then(PROC_REF(ui_act_transform_size)))
	op("edit", ui_act("edit", arg("new_value"), arg("var", schema_text(4096)), arg("var_mod", schema_text(4096))), then(PROC_REF(ui_act_edit)))

/datum/particle_editor/ui_assets(mob/user)
	. = ..()
	. += get_asset_datum(/datum/asset/simple/particle_editor)

///returns ui_data values for the particle editor
/particles/proc/return_ui_representation(mob/user)
	var/data = list()
	//affect entire set: no generators
	data["width"] = width //float
	data["height"] = height //float
	data["count"] = count //float
	data["spawning"] = spawning //float
	data["bound1"] = islist(bound1) ? bound1 : list(bound1,bound1,bound1) //float OR list(x, y, z)
	data["bound2"] = islist(bound2) ? bound2 : list(bound2,bound2,bound2) //float OR list(x, y, z)
	data["gravity"] = gravity //list(x, y, z)

	var/list/tgui_grad_list = list()
	for(var/entry in gradient)
		if(entry == "space")
			tgui_grad_list += list(list("[entry]" = gradient[entry])) // package this thing else json encoding breaks
			continue
		tgui_grad_list += entry
	data["gradient"] = tgui_grad_list //gradient array list(number, string, number, string, "loop", "space"=COLORSPACE_RGB)

	data["transform"] = transform //list(a, b, c, d, e, f) OR list(xx,xy,xz, yx,yy,yz, zx,zy,zz) OR list(xx,xy,xz, yx,yy,yz, zx,zy,zz, cx,cy,cz) OR list(xx,xy,xz,xw, yx,yy,yz,yw, zx,zy,zz,zw, wx,wy,wz,ww)

	//applied on spawn
	if(islist(icon))
		var/list/icon_data = list()
		for(var/file in icon)
			icon_data["[file]"] = icon[file]
		data["icon"] = icon_data
	else
		data["icon"] = "[icon]"  //list(icon = weight) OR file reference
	data["icon_state"] = icon_state // list(icon_state = weight) OR string
	if(isgenerator(lifespan))
		data["lifespan"] = return_generator_args(lifespan)
	else
		data["lifespan"] = lifespan //float
	if(isgenerator(fade))
		data["fade"] = return_generator_args(fade)
	else
		data["fade"] = fade //float
	if(isgenerator(fadein))
		data["fadein"] = return_generator_args(fadein)
	else
		data["fadein"] = fadein //float
	if(isgenerator(color))
		data["color"] = return_generator_args(color, TRUE)
	else
		data["color"] = color //float OR string
	if(isgenerator(color_change))
		data["color_change"] = return_generator_args(color_change)
	else
		data["color_change"] = color_change //float
	if(isgenerator(position))
		data["position"] = return_generator_args(position)
	else
		data["position"] = position //list(x,y) OR list(x,y,z)
	if(isgenerator(velocity))
		data["velocity"] = return_generator_args(velocity)
	else
		data["velocity"] = velocity //list(x,y) OR list(x,y,z)
	if(isgenerator(scale))
		data["scale"] = return_generator_args(scale)
	else
		data["scale"] = scale
	if(isgenerator(grow))
		data["grow"] = return_generator_args(grow)
	else
		data["grow"] = grow //float OR list(x,y)
	if(isgenerator(rotation))
		data["rotation"] = return_generator_args(rotation)
	else
		data["rotation"] = rotation
	if(isgenerator(spin))
		data["spin"] = return_generator_args(spin)
	else
		data["spin"] = spin //float
	if(isgenerator(friction))
		data["friction"] = return_generator_args(friction)
	else
		data["friction"] = friction //float: 0-1

	//evaluated every tick
	if(isgenerator(drift))
		data["drift"] = return_generator_args(drift)
	else
		data["drift"] = drift
	return data

/// /datum/particle_editor's window data.
/datum/particle_editor/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["target_name"] = target().name
	if(!target().particles)
		target().particles = new /particles
	data["particle_data"] = target().particles.return_ui_representation(user)
	return data

/datum/particle_editor/proc/ui_act_delete_and_close(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	ui?.close()
	target().particles = null
	rel_clear(src, nameof(target))
	. = FALSE

/datum/particle_editor/proc/particle_type_choices(datum/act/op/A)
	return make_types_fancy(typesof(/particles))

/datum/particle_editor/proc/ui_act_new_type(datum/act/op/A)
	var/list/types = make_types_fancy(typesof(/particles))
	var/new_type = types[A.step_value("type")]
	if(!ispath(new_type, /particles))
		return
	return apply_particle_type(new_type)

/datum/particle_editor/proc/ui_act_transform_size(datum/act/op/A, new_value)
	var/static/list/matrix_size = list("Simple Matrix" = 6, "Complex Matrix" = 12, "Projection Matrix" = 16)
	var/new_size = matrix_size[new_value]
	if(!new_size)
		return FALSE
	. = TRUE
	target().particles.datum_flags |= DF_VAR_EDITED
	if(!target().particles.transform || length(target().particles.transform) != new_size)
		switch(new_size)
			if(6)
				target().particles.transform = list(1,0,0, 1,0,0) // TRANSFORM_MATRIX_IDENTITY seems wrong for only particles?
			if(12)
				target().particles.transform = TRANSFORM_COMPLEX_MATRIX_IDENTITY
			if(16)
				target().particles.transform = TRANSFORM_PROJECTION_MATRIX_IDENTITY
		return

/datum/particle_editor/proc/ui_act_edit(datum/act/op/A, new_value, var_arg, var_mod_arg)
	var/mob/user = A.actor
	if(!isnull(new_value) && !islist(new_value))
		return FALSE
	var/particles/owner = target().particles
	var/param_var_name = var_arg
	if(!(param_var_name in owner.vars))
		return FALSE
	var/var_value = new_value
	var/var_mod = var_mod_arg
	// we can only return arrays from tgui so lets convert it to something usable if needed
	switch(var_mod)
		if(P_DATA_GENERATOR)
			//these MUST be vectors and the others MUST be floats
			if(var_value[1] in list(GEN_VECTOR, GEN_BOX))
				if(!islist(var_value[2]))
					var_value[2] = list(var_value[2],var_value[2],var_value[2])
				if(!islist(var_value[3]))
					var_value[3] = list(var_value[3],var_value[3],var_value[3])
			//this means we just switched off a vector-requiring generator type
			else if(islist(var_value[2]) && islist(var_value[3]))
				var_value[2] = var_value[1]
				var_value[3] = var_value[1]
			var_value = generator(arglist(var_value))
		if(P_DATA_ICON_ADD)
			if(!GLOB.prompt_flow) // the icon questions re-run this action
				return prompt_flow(src, PROC_REF(tgui_act), args)
			var_value = pick_and_customize_icon(user, pick_only=TRUE)
			if(!var_value)
				return FALSE
			var/list/new_values = list()
			new_values += var_value
			new_values[var_value] = 1
			if(isicon(owner.icon))
				new_values[owner.icon] = 1
				owner.icon = new_values
			else if(islist(owner.icon))
				owner.icon[var_value] = 1
			else
				owner.icon = new_values
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE
		if(P_DATA_ICON_REMOVE)
			for(var/file in owner.icon)
				if("[file]" == var_value)
					owner.icon -= file
			UNSETEMPTY(owner.icon)
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE
		if(P_DATA_ICON_WEIGHT)
			// [filename, new_weight]
			var/list/mod_data = var_value
			for(var/file in owner.icon)
				if("[file]" == mod_data[1])
					owner.icon[file] = mod_data[2]
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE
		if(P_DATA_GRADIENT)
			var/list/new_grad_list = list()
			for(var/entry in var_value)
				new_grad_list += entry // Unpackage nested lists
			owner.gradient = new_grad_list
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE

	owner.vars[param_var_name] = var_value // ALLOW(api): admin particle editor
	target().particles.datum_flags |= DF_VAR_EDITED
	return TRUE

/// The target this refers to (a relation view: null once that is deleted).
/datum/particle_editor/proc/target() as /atom/movable
	return target

/datum/particle_editor/proc/apply_particle_type(new_type)
	target().particles = new new_type
	target().particles.datum_flags |= DF_VAR_EDITED
	return TRUE

/datum/prompt/choice/particle_editor_type
	question = "Select a type"
	title = "Pick Type"
	timeout = 0
