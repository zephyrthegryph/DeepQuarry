use super::*;

impl Builder<'_> {
    pub(in crate::od_emit) fn resolve_modified_type_constants(&mut self) -> Result<(), EmitError> {
        // OpenDream's ordinary Variables map retains only the target type.
        // The optional exporter annotation preserves the modified instance
        // initializer, which BYOND addresses through Value tag 41.
        let mut pending = Vec::new();
        for (owner, typ) in self.input.types.iter().enumerate() {
            for (name, value) in &typ.modified_type_declaration_values {
                pending.push((
                    owner,
                    name.clone(),
                    true,
                    value.type_path.clone(),
                    value.overrides.clone(),
                    value.override_order.clone(),
                ));
            }
            for (name, value) in &typ.modified_type_override_values {
                pending.push((
                    owner,
                    name.clone(),
                    false,
                    value.type_path.clone(),
                    value.overrides.clone(),
                    value.override_order.clone(),
                ));
            }
            for (name, json) in &typ.variable_declaration_values {
                if let Some(ModifiedTypeParts {
                    path,
                    overrides,
                    order,
                }) = modified_type_json(json)?
                {
                    pending.push((owner, name.clone(), true, path, overrides, order));
                }
            }
            for (name, json) in &typ.variables {
                if let Some(ModifiedTypeParts {
                    path,
                    overrides,
                    order,
                }) = modified_type_json(json)?
                {
                    let declaration_same = typ
                        .variable_declaration_values
                        .get(name)
                        .is_some_and(|original| original == json);
                    if !declaration_same {
                        pending.push((owner, name.clone(), false, path, overrides, order));
                    }
                }
            }
        }
        let type_ids: HashMap<_, _> = self
            .input
            .types
            .iter()
            .enumerate()
            .map(|(id, typ)| (typ.path.as_str(), id))
            .collect();
        for (owner, name, declaration, target_path, overrides, override_order) in pending {
            let &type_id = type_ids.get(target_path.as_str()).ok_or_else(|| {
                EmitError::Invalid(format!(
                    "modified type target {target_path} is absent from Types"
                ))
            })?;
            if self.input.native_type_tag(type_id) != Some(9) {
                return Err(EmitError::Unsupported(format!(
                    "modified type path {target_path} is not a paired movable type"
                )));
            }
            let instance = self.instance(&OpenDreamMapObject {
                type_id,
                var_overrides: overrides,
                override_order,
            })?;
            let value = Value {
                tag_word: 41,
                data_word: instance,
                extra_word: None,
            };
            let class_id = self.ids.classes[owner];
            if class_id == NONE {
                return Err(EmitError::Invalid(format!(
                    "modified type owner {} has no class",
                    self.input.types[owner].path
                )));
            }
            if declaration {
                let list_id = self.dmb.classes[class_id as usize].defining_variable_list_id();
                let var_id = self
                    .dmb
                    .lists
                    .get(list_id as usize)
                    .and_then(|words| {
                        words.chunks_exact(2).map(|pair| pair[0]).find(|&id| {
                            self.dmb
                                .variables
                                .get(id as usize)
                                .and_then(|var| self.dmb.string(var.name))
                                == Some(name.as_bytes())
                        })
                    })
                    .ok_or_else(|| {
                        EmitError::Invalid(format!(
                            "modified type declaration {}.{} has no Variable",
                            self.input.types[owner].path, name
                        ))
                    })?;
                let var = &mut self.dmb.variables[var_id as usize];
                var.kind = 41;
                var.value = instance;
            } else {
                let list_id = self.dmb.classes[class_id as usize].initialized_variable_list_id();
                let mut records = self
                    .dmb
                    .class_initial_values(class_id as usize)
                    .ok_or_else(|| {
                        EmitError::Invalid(format!(
                            "modified type override {}.{} has no class initials",
                            self.input.types[owner].path, name
                        ))
                    })?;
                let mut found = false;
                for record in &mut records {
                    let var = &self.dmb.variables[record.variable_id as usize];
                    if self.dmb.string(var.name) == Some(name.as_bytes()) {
                        record.value = value;
                        found = true;
                    }
                }
                if !found {
                    return Err(EmitError::Invalid(format!(
                        "modified type override {}.{} has no target",
                        self.input.types[owner].path, name
                    )));
                }
                let mut words = Vec::new();
                for record in records {
                    words.push(record.variable_id);
                    words.extend(record.value.encode());
                }
                self.dmb.lists[list_id as usize] = words;
            }
        }
        if let Some(globals) = &self.input.globals {
            let mut global_modified = Vec::new();
            for old in 0..globals.names.len() {
                let json = globals
                    .declaration_values
                    .get(&old)
                    .or_else(|| globals.globals.get(&old));
                if let Some(ModifiedTypeParts {
                    path,
                    overrides,
                    order,
                }) = json.map(modified_type_json).transpose()?.flatten()
                {
                    global_modified.push((old, path, overrides, order));
                }
            }
            for (old, path, overrides, order) in global_modified {
                let &type_id = type_ids.get(path.as_str()).ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "modified global type target {path} is absent from Types"
                    ))
                })?;
                let instance = self.instance(&OpenDreamMapObject {
                    type_id,
                    var_overrides: overrides,
                    override_order: order,
                })?;
                let var_id = self.ids.globals[old];
                let variable = &mut self.dmb.variables[var_id as usize];
                variable.kind = 41;
                variable.value = instance;
            }
        }
        let codes = self
            .input
            .procs
            .iter()
            .filter_map(|proc| proc.bytecode.as_deref())
            .chain(
                self.input
                    .global_init_proc
                    .as_ref()
                    .and_then(|proc| proc.bytecode.as_deref()),
            );
        let mut inline = HashMap::new();
        for code in codes {
            for bytes in code.windows(16) {
                if bytes[0] != 0x03 || bytes[5] != 0x02 || bytes[10] != 0x2e {
                    continue;
                }
                let Some(string_id) = read_u32_le(bytes, 1) else {
                    continue;
                };
                let Some(type_id) = read_u32_le(bytes, 6) else {
                    continue;
                };
                let string_id = string_id as usize;
                let type_id = type_id as usize;
                let (Some(json), Some(typ)) = (
                    self.input.strings.get(string_id),
                    self.input.types.get(type_id),
                ) else {
                    continue;
                };
                if !typ.path.starts_with("/atom/movable/")
                    && !typ.path.starts_with("/obj/")
                    && typ.path != "/datum"
                    && !typ.path.starts_with("/datum/")
                {
                    continue;
                }
                let Ok(overrides) = serde_json::from_str::<HashMap<String, JsonValue>>(json) else {
                    continue;
                };
                inline.entry((type_id, json.clone())).or_insert(overrides);
            }
            for bytes in code.windows(9) {
                if bytes[0] != 0x9f {
                    continue;
                }
                let Some(type_id) = read_u32_le(bytes, 1) else {
                    continue;
                };
                let Some(string_id) = read_u32_le(bytes, 5) else {
                    continue;
                };
                let type_id = type_id as usize;
                let string_id = string_id as usize;
                let (Some(json), Some(typ)) = (
                    self.input.strings.get(string_id),
                    self.input.types.get(type_id),
                ) else {
                    continue;
                };
                if !typ.path.starts_with("/atom/movable/")
                    && !typ.path.starts_with("/obj/")
                    && typ.path != "/datum"
                    && !typ.path.starts_with("/datum/")
                {
                    continue;
                }
                let Ok(overrides) = serde_json::from_str::<HashMap<String, JsonValue>>(json) else {
                    continue;
                };
                inline.entry((type_id, json.clone())).or_insert(overrides);
            }
        }
        for ((type_id, json), overrides) in inline {
            let instance = self.instance(&OpenDreamMapObject {
                type_id,
                var_overrides: overrides,
                override_order: Vec::new(),
            })?;
            self.ids
                .modified_instances
                .insert((type_id, json), instance);
        }
        Ok(())
    }
    pub(in crate::od_emit) fn reindex_variables(&mut self) -> Result<(), EmitError> {
        let old_len = self.dmb.variables.len();
        let order = self.variable_reindex_order()?;
        let mut remap = vec![0u32; old_len];
        for (new, &old) in order.iter().enumerate() {
            remap[old] = new as u32;
        }
        let original = self.dmb.variables.clone();
        self.dmb.variables = order.iter().map(|&old| original[old].clone()).collect();
        let mut marker = 0;
        for variable in &mut self.dmb.variables {
            if variable.kind == 62 {
                variable.value = marker;
                marker += 1;
            }
        }
        for id in &mut self.ids.globals {
            // Every entry was resolved by build_globals. Variable IDs are
            // mandatory references, and native Variable 65535 is legal.
            *id = remap[*id as usize];
        }
        let mut declaration_lists = std::collections::HashSet::new();
        if self.dmb.variable_footer != NONE {
            declaration_lists.insert(self.dmb.variable_footer);
            for pair in self.dmb.lists[self.dmb.variable_footer as usize].chunks_exact_mut(2) {
                pair[0] = remap[pair[0] as usize];
            }
        }
        let mut initial_lists = std::collections::HashSet::new();
        for index in 0..self.dmb.classes.len() {
            let declarations = self.dmb.classes[index].defining_variable_list_id();
            if declarations != NONE && declaration_lists.insert(declarations) {
                for pair in self.dmb.lists[declarations as usize].chunks_exact_mut(2) {
                    pair[0] = remap[pair[0] as usize];
                }
            }
            let initial = self.dmb.classes[index].initialized_variable_list_id();
            if initial != NONE && initial_lists.insert(initial) {
                let decoded = self.dmb.class_initial_values(index).ok_or_else(|| {
                    EmitError::Invalid("malformed class initializer values".into())
                })?;
                let mut words = Vec::new();
                for record in decoded {
                    words.push(remap[record.variable_id as usize]);
                    words.extend(record.value.encode());
                }
                self.dmb.lists[initial as usize] = words;
            }
        }
        let mut locals_lists = std::collections::HashSet::new();
        let mut argument_lists = std::collections::HashSet::new();
        for proc in &self.dmb.procs {
            let locals = proc.code_locals_args[1];
            if locals != NONE && locals_lists.insert(locals) {
                for id in &mut self.dmb.lists[locals as usize] {
                    *id = remap[*id as usize];
                }
            }
            let args = proc.code_locals_args[2];
            if args != NONE && argument_lists.insert(args) {
                for record in self.dmb.lists[args as usize].chunks_exact_mut(4) {
                    record[2] = remap[record[2] as usize];
                }
            }
        }
        Ok(())
    }
    pub(in crate::od_emit) fn reindex_classes(&mut self) -> Result<(), EmitError> {
        let total = self.dmb.classes.len();
        let split = self.native.classes;
        if total == split {
            return Ok(());
        }
        let mut order = Vec::with_capacity(total);
        let mut used = vec![false; total];
        let mut custom_ids: Vec<_> = (split..total).collect();
        custom_ids.sort_by_key(|&id| {
            let mut depth = 0;
            let mut parent = self.dmb.classes[id].parent_class_id();
            while parent != NONE && depth < total {
                depth += 1;
                parent = self.dmb.classes[parent as usize].parent_class_id();
            }
            std::cmp::Reverse(depth)
        });
        for custom in custom_ids {
            if !used[custom] {
                order.push(custom);
                used[custom] = true;
            }
            let mut parent = self.dmb.classes[custom].parent_class_id();
            while parent != NONE {
                let parent_id = parent as usize;
                if !used[parent_id] {
                    order.push(parent_id);
                    used[parent_id] = true;
                }
                if parent_id < split {
                    break;
                }
                parent = self.dmb.classes[parent_id].parent_class_id();
            }
        }
        for (native, seen) in used.iter_mut().enumerate().take(split) {
            if !*seen {
                order.push(native);
                *seen = true;
            }
        }
        // Optional class references use FFFF even in a wide table. Keep the
        // native blank record fixed at that index when ordering authored types.
        if total > NONE as usize {
            order.retain(|&id| id != NONE as usize);
            order.insert(NONE as usize, NONE as usize);
        }
        let mut remap = vec![0u32; total];
        for (new, &old) in order.iter().enumerate() {
            remap[old] = new as u32;
        }
        let old = self.dmb.classes.clone();
        self.dmb.classes = order.iter().map(|&id| old[id].clone()).collect();
        for class in &mut self.dmb.classes {
            if class.initial_ids[1] != NONE {
                class.initial_ids[1] = remap[class.initial_ids[1] as usize];
            }
        }
        for id in &mut self.ids.classes {
            if *id != NONE {
                *id = remap[*id as usize];
            }
        }
        for mob in &mut self.dmb.mobs {
            mob.class = remap[mob.class as usize];
        }
        for instance in &mut self.dmb.instances {
            if instance.kind != 8 {
                instance.class = remap[instance.class as usize];
            }
        }
        for slot in [1usize, 2usize] {
            let id = &mut self.dmb.world.ids[slot];
            if *id != NONE {
                *id = remap[*id as usize];
            }
        }
        if self.dmb.world.client != NONE {
            self.dmb.world.client = remap[self.dmb.world.client as usize];
        }
        if self.dmb.world.image != NONE {
            self.dmb.world.image = remap[self.dmb.world.image as usize];
        }
        for variable in &mut self.dmb.variables {
            if is_class_value_tag(variable.kind)
                && !(variable.value == 0 && matches!(variable.kind, 36 | 39 | 40))
            {
                variable.value = remap[variable.value as usize];
            }
        }
        let mut class_value_lists = std::collections::HashSet::new();
        for index in 0..self.dmb.classes.len() {
            for list_id in [
                self.dmb.classes[index].initialized_variable_list_id(),
                self.dmb.classes[index].overriding_variable_list_id(),
            ] {
                if list_id == NONE || !class_value_lists.insert(list_id) {
                    continue;
                }
                let words = self.dmb.lists[list_id as usize].clone();
                let mut at = 0;
                let mut rewritten = Vec::with_capacity(words.len());
                while at < words.len() {
                    rewritten.push(words[at]);
                    at += 1;
                    let (mut value, consumed) = Value::decode(&words[at..])
                        .map_err(|e| EmitError::Invalid(format!("class value: {}", e.reason)))?;
                    remap_class_value(&mut value, &remap)?;
                    rewritten.extend(value.encode());
                    at += consumed;
                }
                self.dmb.lists[list_id as usize] = rewritten;
            }
        }
        let mut visited = std::collections::HashSet::new();
        for proc in &self.dmb.procs {
            let list_id = proc.code_locals_args[0];
            if list_id == NONE || !visited.insert(list_id) {
                continue;
            }
            let words = &mut self.dmb.lists[list_id as usize];
            let instructions = byond_dmb::bytecode::decode(words)
                .map_err(|e| EmitError::Invalid(format!("procedure code: {}", e.reason)))?;
            for instruction in instructions {
                if instruction.opcode != 0x60 {
                    continue;
                }
                let (mut value, _) = Value::decode(&instruction.operands).map_err(|e| {
                    EmitError::Invalid(format!("procedure type value: {}", e.reason))
                })?;
                if !is_class_value_tag(value.tag()) {
                    continue;
                }
                remap_class_value(&mut value, &remap)?;
                for (slot, new) in words
                    [instruction.offset + 1..instruction.offset + 1 + value.encode().len()]
                    .iter_mut()
                    .zip(value.encode())
                {
                    *slot = new;
                }
            }
        }
        Ok(())
    }
}
