use super::*;

impl Builder<'_> {
    pub(in crate::od_emit) fn resolve_pending_proc_constants(&mut self) -> Result<(), EmitError> {
        for &(variable, old) in &self.pending_proc_vars {
            let id = *self.ids.procs.get(old).ok_or_else(|| {
                EmitError::Invalid("deferred proc constant ID out of range".into())
            })?;
            if id == NONE {
                return Err(EmitError::Unsupported(
                    "proc constant has no BYOND procedure equivalent".into(),
                ));
            }
            self.dmb.variables[variable as usize].value = id;
        }
        for &(list, offset, old) in &self.pending_proc_lists {
            let id = *self.ids.procs.get(old).ok_or_else(|| {
                EmitError::Invalid("deferred proc constant ID out of range".into())
            })?;
            if id == NONE {
                return Err(EmitError::Unsupported(
                    "proc constant has no BYOND procedure equivalent".into(),
                ));
            }
            self.dmb.lists[list as usize][offset] = id;
        }
        Ok(())
    }
    pub(in crate::od_emit) fn resolve_mob_type_constants(&mut self) -> Result<(), EmitError> {
        // Class values are built before subtype MobType records exist. Tag 8
        // stores a MobType ID, so replace the temporary ClassID only for
        // authored fields whose JSON value is a mob path.
        let mut updates = Vec::new();
        for (owner_od, typ) in self.input.types.iter().enumerate() {
            let class_id = self.ids.classes[owner_od];
            if class_id == NONE {
                continue;
            }
            for (name, json) in &typ.variables {
                if json.get("type").and_then(JsonValue::as_u64) != Some(1) {
                    continue;
                }
                let target_od = json
                    .get("value")
                    .and_then(JsonValue::as_u64)
                    .ok_or_else(|| {
                        EmitError::Invalid(format!("type value {}.{name} has no ID", typ.path))
                    })? as usize;
                let target = self.input.types.get(target_od).ok_or_else(|| {
                    EmitError::Invalid(format!("type value {}.{name} is out of range", typ.path))
                })?;
                if self.input.native_type_tag(target_od) != Some(8) {
                    continue;
                }
                let target_class = self.ids.classes[target_od];
                let mob_id = self
                    .dmb
                    .mobs
                    .iter()
                    .position(|mob| mob.class == target_class)
                    .ok_or_else(|| {
                        EmitError::Invalid(format!(
                            "mob type {} has no MobType record",
                            target.path
                        ))
                    })? as u32;
                let name_id = *self.strings.get(name.as_bytes()).ok_or_else(|| {
                    EmitError::Invalid(format!("mob path field {}.{name} has no string", typ.path))
                })?;
                updates.push((class_id, name_id, mob_id));
            }
        }
        for (class_id, name_id, mob_id) in updates {
            if let Some(declarations) = self.dmb.class_variable_declarations(class_id as usize) {
                for (var_id, _) in declarations {
                    let variable = &mut self.dmb.variables[var_id as usize];
                    if variable.name == name_id && variable.kind == 8 {
                        variable.value = mob_id;
                    }
                }
            }
            let list_id = self.dmb.classes[class_id as usize].initialized_variable_list_id();
            if list_id != NONE {
                let mut entries = self
                    .dmb
                    .class_initial_values(class_id as usize)
                    .ok_or_else(|| EmitError::Invalid("malformed class initial values".into()))?;
                let mut changed = false;
                for entry in &mut entries {
                    if self.dmb.variables[entry.variable_id as usize].name == name_id
                        && entry.value.tag() == 8
                    {
                        entry.value.tag_word =
                            (entry.value.tag_word & !0xff00) | ((mob_id >> 16) << 8);
                        entry.value.data_word =
                            (entry.value.data_word & !0xffff) | (mob_id & 0xffff);
                        changed = true;
                    }
                }
                if changed {
                    let mut words = Vec::new();
                    for entry in entries {
                        words.push(entry.variable_id);
                        words.extend(entry.value.encode());
                    }
                    self.dmb.lists[list_id as usize] = words;
                }
            }
            let list_id = self.dmb.classes[class_id as usize].overriding_variable_list_id();
            if list_id != NONE {
                let mut entries = self
                    .dmb
                    .class_builtin_overrides(class_id as usize)
                    .ok_or_else(|| {
                        EmitError::Invalid("malformed class builtin overrides".into())
                    })?;
                let mut changed = false;
                for entry in &mut entries {
                    if entry.name_string_id == name_id && entry.value.tag() == 8 {
                        entry.value.tag_word =
                            (entry.value.tag_word & !0xff00) | ((mob_id >> 16) << 8);
                        entry.value.data_word =
                            (entry.value.data_word & !0xffff) | (mob_id & 0xffff);
                        changed = true;
                    }
                }
                if changed {
                    let mut words = Vec::new();
                    for entry in entries {
                        words.push(entry.name_string_id);
                        words.extend(entry.value.encode());
                    }
                    self.dmb.lists[list_id as usize] = words;
                }
            }
        }
        Ok(())
    }
    pub(in crate::od_emit) fn reindex_procs(&mut self) -> Result<(), EmitError> {
        let total = self.dmb.procs.len();
        let native = self.native.procs;
        let authored_end = self.authored.procs;
        if authored_end == native {
            return Ok(());
        }
        let mut order: Vec<usize> = self
            .ids
            .procs
            .iter()
            .enumerate()
            .filter_map(|(od_id, &id)| {
                (id != NONE && self.input.procs[od_id].name != "<init>").then_some(id as usize)
            })
            .collect();
        order.extend(0..native);
        let mut init_procs: Vec<_> = self
            .ids
            .procs
            .iter()
            .enumerate()
            .filter_map(|(od_id, &id)| {
                (id != NONE && self.input.procs[od_id].name == "<init>")
                    .then_some((od_id, id as usize))
            })
            .collect();
        init_procs.sort_by_key(|&(od_id, _)| {
            let mut depth = 0;
            let mut parent = self.input.types[self.input.procs[od_id].owning_type_id].parent;
            while let Some(id) = parent {
                depth += 1;
                parent = self.input.types[id].parent;
            }
            std::cmp::Reverse(depth)
        });
        order.extend(init_procs.into_iter().map(|(_, id)| id));
        for class in &self.dmb.classes {
            let id = class.lists_and_procs[2];
            if id != NONE
                && (native..authored_end).contains(&(id as usize))
                && !order.contains(&(id as usize))
            {
                order.push(id as usize);
            }
        }
        order.extend(authored_end..total);
        // The blank proc has no OD binding and may be absent from `order`.
        // It must occupy FFFF after authored/native/init procedures reorder.
        if total > NONE as usize {
            order.retain(|&id| id != NONE as usize);
            order.insert(NONE as usize, NONE as usize);
        }
        let mut remap = vec![0u32; total];
        for (new, &old) in order.iter().enumerate() {
            remap[old] = new as u32;
        }
        let old = self.dmb.procs.clone();
        self.dmb.procs = order.iter().map(|&id| old[id].clone()).collect();
        for id in &mut self.ids.procs {
            if *id != NONE {
                *id = remap[*id as usize];
            }
        }
        if let Some(id) = &mut self.ids.global_init_proc {
            *id = remap[*id as usize];
        }
        for class in &mut self.dmb.classes {
            let id = &mut class.lists_and_procs[2];
            if *id != NONE {
                *id = remap[*id as usize];
            }
        }
        let mut seen = std::collections::HashSet::new();
        for class in &self.dmb.classes {
            for id in [class.verb_list_id(), class.proc_list_id()] {
                if id != NONE && seen.insert(id) {
                    for proc_id in &mut self.dmb.lists[id as usize] {
                        *proc_id = remap[*proc_id as usize];
                    }
                }
            }
        }
        let world_list = self.dmb.world.proc_list_id();
        if world_list != NONE && seen.insert(world_list) {
            for proc_id in &mut self.dmb.lists[world_list as usize] {
                *proc_id = remap[*proc_id as usize];
            }
        }
        if self.dmb.world.ids[4] != NONE {
            self.dmb.world.ids[4] = remap[self.dmb.world.ids[4] as usize];
        }
        for instance in &mut self.dmb.instances {
            if instance.initializer != NONE {
                instance.initializer = remap[instance.initializer as usize];
            }
        }
        for proc_id in &mut self.dmb.proc_references {
            *proc_id = remap[*proc_id as usize];
        }
        for variable in &mut self.dmb.variables {
            if variable.kind == 38 {
                variable.value = remap[variable.value as usize];
            }
        }
        // Initial-value lists can be rebuilt after pending proc constants
        // resolve (for example, when a sibling field has a dynamic marker).
        // Remap the lists currently attached to classes, not their earlier
        // list IDs. Also remap native scaffold proc values shifted by the
        // authored-proc prefix.
        let mut value_lists = std::collections::HashSet::new();
        for class in &self.dmb.classes {
            for list_id in [
                class.initialized_variable_list_id(),
                class.overriding_variable_list_id(),
            ] {
                if list_id != NONE {
                    value_lists.insert(list_id);
                }
            }
        }
        for list_id in value_lists {
            let words = &mut self.dmb.lists[list_id as usize];
            let mut at = 0;
            while at < words.len() {
                let (value, len) = Value::decode(&words[at + 1..])
                    .map_err(|e| EmitError::Invalid(format!("class proc value: {}", e.reason)))?;
                if value.tag() == 38 {
                    let slot = at + 2;
                    words[slot] = remap[words[slot] as usize];
                }
                at += len + 1;
            }
        }
        let mut code_seen = std::collections::HashSet::new();
        for proc in &self.dmb.procs {
            let id = proc.code_locals_args[0];
            if id == NONE || !code_seen.insert(id) {
                continue;
            }
            let words = &mut self.dmb.lists[id as usize];
            let decoded = byond_dmb::bytecode::decode(words)
                .map_err(|e| EmitError::Invalid(format!("procedure code: {}", e.reason)))?;
            for instruction in decoded {
                let typed = instruction.typed_operands().map_err(|error| {
                    EmitError::Invalid(format!("procedure operands: {}", error.reason))
                })?;
                let mut operand_offset = instruction.offset + 1;
                for operand in typed {
                    use byond_dmb::bytecode::Operand;
                    let width = match operand {
                        Operand::Variable(mut variable) => {
                            let width = variable.encode().len();
                            remap_proc_variable(&mut variable, &remap)?;
                            words[operand_offset..operand_offset + width]
                                .copy_from_slice(&variable.encode());
                            width
                        }
                        Operand::Word(_) => 1,
                        Operand::Value(value) => value.encode().len(),
                        // Table operands have no variable selectors following them.
                        _ => break,
                    };
                    operand_offset += width;
                }
                if instruction.opcode == 0x30 || instruction.opcode == 0xcd {
                    let slot = instruction.offset + if instruction.opcode == 0x30 { 2 } else { 1 };
                    words[slot] = remap[words[slot] as usize];
                } else if instruction.opcode == 0x60 {
                    let (mut value, _) = Value::decode(&instruction.operands).map_err(|e| {
                        EmitError::Invalid(format!("procedure value: {}", e.reason))
                    })?;
                    if value.tag() == 38 {
                        remap_proc_value(&mut value, &remap)?;
                        for (slot, new) in words
                            [instruction.offset + 1..instruction.offset + 1 + value.encode().len()]
                            .iter_mut()
                            .zip(value.encode())
                        {
                            *slot = new;
                        }
                    }
                }
            }
        }
        Ok(())
    }
    pub(in crate::od_emit) fn reindex_instances(&mut self) -> Result<(), EmitError> {
        let total = self.dmb.instances.len();
        let start = self.native.instances;
        let end = self.authored.prototypes;
        if end == start {
            return Ok(());
        }
        let mut order: Vec<usize> = (start..end).collect();
        order.extend(0..start);
        order.extend(end..total);
        let mut remap = vec![0u32; total];
        for (new, &old) in order.iter().enumerate() {
            remap[old] = new as u32;
        }
        let old = self.dmb.instances.clone();
        self.dmb.instances = order.iter().map(|&id| old[id].clone()).collect();
        for id in &mut self.ids.instances {
            if *id != NONE {
                *id = remap[*id as usize];
            }
        }
        for id in self.ids.modified_instances.values_mut() {
            *id = remap[*id as usize];
        }
        for run in &mut self.dmb.grid {
            if run.turf != NONE {
                run.turf = remap[run.turf as usize];
            }
            if run.area != NONE {
                run.area = remap[run.area as usize];
            }
        }
        for object in &mut self.dmb.map_objects {
            object.instance = remap[object.instance as usize];
        }
        for variable in &mut self.dmb.variables {
            if variable.kind == 41 {
                variable.value = *remap.get(variable.value as usize).ok_or_else(|| {
                    EmitError::Invalid("modified type value has invalid InstanceID".into())
                })?;
            }
        }
        let mut value_lists = std::collections::HashSet::new();
        for class in &self.dmb.classes {
            for list_id in [
                class.initialized_variable_list_id(),
                class.overriding_variable_list_id(),
            ] {
                if list_id != NONE {
                    value_lists.insert(list_id);
                }
            }
        }
        for list_id in value_lists {
            let words = &mut self.dmb.lists[list_id as usize];
            let mut at = 0;
            while at < words.len() {
                let (value, len) = Value::decode(&words[at + 1..]).map_err(|e| {
                    EmitError::Invalid(format!("modified type value: {}", e.reason))
                })?;
                if value.tag() == 41 {
                    let old_id = value.id() as usize;
                    let new_id = *remap.get(old_id).ok_or_else(|| {
                        EmitError::Invalid("modified type value has invalid InstanceID".into())
                    })?;
                    words[at + 1] = (words[at + 1] & !0xff00) | ((new_id >> 16) << 8);
                    words[at + 2] = (words[at + 2] & !0xffff) | (new_id & 0xffff);
                }
                at += len + 1;
            }
        }
        let mut code_seen = std::collections::HashSet::new();
        for proc in &self.dmb.procs {
            let list_id = proc.code_locals_args[0];
            if list_id == NONE || !code_seen.insert(list_id) {
                continue;
            }
            let words = &mut self.dmb.lists[list_id as usize];
            for instruction in byond_dmb::bytecode::decode(words)
                .map_err(|e| EmitError::Invalid(format!("modified type procedure: {}", e.reason)))?
            {
                if instruction.opcode != 0x60 {
                    continue;
                }
                let (value, _) = Value::decode(&instruction.operands).map_err(|e| {
                    EmitError::Invalid(format!("modified type bytecode value: {}", e.reason))
                })?;
                if value.tag() == 41 {
                    let new_id = *remap.get(value.id() as usize).ok_or_else(|| {
                        EmitError::Invalid("modified type bytecode has invalid InstanceID".into())
                    })?;
                    words[instruction.offset + 1] =
                        (words[instruction.offset + 1] & !0xff00) | ((new_id >> 16) << 8);
                    words[instruction.offset + 2] =
                        (words[instruction.offset + 2] & !0xffff) | (new_id & 0xffff);
                }
            }
        }
        Ok(())
    }
}
