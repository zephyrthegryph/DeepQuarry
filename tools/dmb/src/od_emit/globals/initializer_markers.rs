use super::*;

impl Builder<'_> {
    pub(in crate::od_emit) fn mark_class_dynamic_initials(&mut self) -> Result<(), EmitError> {
        for (type_id, typ) in self.input.types.iter().enumerate() {
            let class_id = self.ids.classes[type_id];
            if class_id == NONE || typ.dynamic_initializer_assignments.is_empty() {
                continue;
            }
            // Dream Maker retains a marker for an authored runtime override
            // even when a later assignment clears that field to null.
            let assignments: Vec<_> = typ.dynamic_initializer_assignments.iter().collect();
            if assignments.is_empty() {
                continue;
            }
            let mut variable_ids = Vec::with_capacity(assignments.len());
            for name in &assignments {
                if (*name == "transform" && self.matrix_transform_initializer(type_id).is_some())
                    || (*name == "color" && self.matrix_color_initializer(type_id).is_some())
                {
                    continue;
                }
                if !typ.variables.get(*name).is_some_and(JsonValue::is_null) {
                    return Err(EmitError::Invalid(format!(
                        "dynamic initializer {}.{} must have a null JSON placeholder",
                        typ.path, name
                    )));
                }
                let variable_id = self.inherited_variable(class_id, name).ok_or_else(|| {
                    EmitError::Unsupported(format!(
                        "dynamic initializer {}.{} has no DMB variable",
                        typ.path, name
                    ))
                })?;
                variable_ids.push(variable_id);
            }
            if variable_ids.is_empty() {
                continue;
            }
            let mut entries = self
                .dmb
                .class_initial_values(class_id as usize)
                .ok_or_else(|| {
                    EmitError::Invalid(format!("class {} has malformed initial values", typ.path))
                })?;
            entries.retain(|entry| !variable_ids.contains(&entry.variable_id));
            for &variable_id in &variable_ids {
                entries.push(crate::dmb::ClassInitialValue {
                    variable_id,
                    value: Value {
                        tag_word: 62,
                        data_word: 0,
                        extra_word: None,
                    },
                });
            }
            // A later authored null assignment leaves the earlier allocator
            // marker in the native list and appends a final null value. The
            // paired obelisk catalogue_data class has exactly this sequence.
            let mut final_nulls = std::collections::HashSet::new();
            for (name, &variable_id) in assignments.iter().zip(&variable_ids) {
                if !typ.dynamic_initializer_fields.contains(*name)
                    && typ
                        .constant_initializer_fields
                        .get(*name)
                        .is_some_and(JsonValue::is_null)
                    && final_nulls.insert(variable_id)
                {
                    entries.push(crate::dmb::ClassInitialValue {
                        variable_id,
                        value: Value {
                            tag_word: 0,
                            data_word: 0,
                            extra_word: None,
                        },
                    });
                }
            }
            let mut words = Vec::new();
            let mut offsets = Vec::new();
            for entry in entries {
                words.push(entry.variable_id);
                if entry.value.tag() == 62 && entry.value.id() == 0 {
                    offsets.push(words.len());
                }
                words.extend(entry.value.encode());
            }
            let list_id = self.list(words);
            self.dmb.classes[class_id as usize].lists_and_procs[3] = list_id;
            self.pending_class_markers
                .extend(offsets.into_iter().map(|offset| (list_id, offset)));
        }
        Ok(())
    }
    pub(in crate::od_emit) fn assign_class_initializer_markers(&mut self) -> Result<(), EmitError> {
        if self.pending_class_markers.is_empty() {
            return Ok(());
        }
        let class_by_list: HashMap<u32, usize> = self
            .dmb
            .classes
            .iter()
            .enumerate()
            .filter_map(|(class_id, class)| {
                (class.initialized_variable_list_id() != NONE)
                    .then_some((class.initialized_variable_list_id(), class_id))
            })
            .collect();
        self.pending_class_markers
            .sort_by_key(|&(list_id, offset)| {
                (
                    class_by_list.get(&list_id).copied().unwrap_or(usize::MAX),
                    offset,
                )
            });
        let first = self
            .dmb
            .variables
            .iter()
            .filter(|variable| variable.kind == 62)
            .map(|variable| variable.value)
            .max()
            .map_or(0, |last| last + 1);
        for (next, &(list_id, offset)) in (first..).zip(&self.pending_class_markers) {
            if next > 0x00ff_ffff {
                return Err(EmitError::Unsupported(
                    "hidden initializer marker exceeds 24 bits".into(),
                ));
            }
            let words = self.dmb.lists.get_mut(list_id as usize).ok_or_else(|| {
                EmitError::Invalid("class initializer marker list is missing".into())
            })?;
            if words.get(offset..offset + 2) != Some(&[62, 0][..]) {
                return Err(EmitError::Invalid(
                    "class initializer marker moved before assignment".into(),
                ));
            }
            words[offset] = 62 | ((next >> 16) << 8);
            words[offset + 1] = next & 0xffff;
        }
        Ok(())
    }
    /// Normalize expression leaves through the same native constant codec as
    /// executable output. In particular resource aliases must share CRC identity
    /// and numeric folding must use native f32 bits rather than JSON spelling.
    pub(in crate::od_emit) fn initializer_identity_key(
        &mut self,
        identity: &JsonValue,
    ) -> Result<JsonValue, EmitError> {
        let Some(items) = identity.as_array() else {
            return Ok(identity.clone());
        };
        let tag = items.first().and_then(JsonValue::as_str);
        if tag == Some("constant") && items.len() == 2 {
            let value = self.constant(&items[1])?;
            return Ok(serde_json::json!(["native-value", value.encode()]));
        }
        if tag == Some("type") && items.len() == 2 {
            let path = items[1]
                .as_str()
                .ok_or_else(|| EmitError::Invalid("initializer type identity lacks path".into()))?;
            let old = self
                .input
                .types
                .iter()
                .position(|typ| typ.path == path)
                .ok_or_else(|| {
                    EmitError::Invalid(format!("initializer identity type missing: {path}"))
                })?;
            let value = self.constant(&serde_json::json!({"type":1,"value":old}))?;
            return Ok(serde_json::json!(["native-value", value.encode()]));
        }
        if tag == Some("new") && items.len() == 3 {
            let target = self.initializer_identity_key(&serde_json::json!(["type", items[1]]))?;
            let args = self.initializer_identity_key(&items[2])?;
            return Ok(serde_json::json!(["new", target, args]));
        }
        items
            .iter()
            .map(|item| self.initializer_identity_key(item))
            .collect::<Result<Vec<_>, _>>()
            .map(JsonValue::Array)
    }

    pub(in crate::od_emit) fn intern_initializer_identities(&mut self) -> Result<(), EmitError> {
        match self
            .input
            .metadata
            .native_initializer_interning_mode
            .as_deref()
        {
            None | Some("unique") => return Ok(()),
            Some("expression") => {}
            Some(mode) => {
                return Err(EmitError::Unsupported(format!(
                    "native initializer interning mode: {mode}"
                )))
            }
        }
        // Existing marker IDs remain distinct when source identity is unknown.
        // Supported source keys can reuse those IDs across globals, declarations,
        // and overrides without altering executable initialization order.
        let mut variables = Vec::new();
        let mut overrides = Vec::new();
        for (owner, typ) in self.input.types.iter().enumerate() {
            if typ.native_initializer_identity_version == 0 {
                continue;
            }
            if typ.native_initializer_identity_version != 1 {
                return Err(EmitError::Unsupported(
                    "initializer identity annotation version".into(),
                ));
            }
            let class = self.ids.classes[owner];
            if class == NONE {
                continue;
            }
            if let Some(declarations) = self.dmb.class_variable_declarations(class as usize) {
                for (id, _) in declarations {
                    let variable = &self.dmb.variables[id as usize];
                    let Some(name) = self
                        .dmb
                        .string(variable.name)
                        .and_then(|bytes| std::str::from_utf8(bytes).ok())
                    else {
                        continue;
                    };
                    if variable.kind == 62 {
                        if let Some(key) = typ.native_initializer_declaration_identities.get(name) {
                            variables.push((id, key.clone()));
                        }
                    }
                }
            }
            let list = self.dmb.classes[class as usize].initialized_variable_list_id();
            if list == NONE {
                continue;
            }
            if !typ.native_initializer_assignment_identities.is_empty()
                && typ.native_initializer_assignment_identities.len()
                    != typ.dynamic_initializer_assignments.len()
            {
                return Err(EmitError::Invalid(format!(
                    "initializer assignment identity count mismatch: {}",
                    typ.path
                )));
            }
            let mut assignment_keys: HashMap<&str, std::collections::VecDeque<Option<JsonValue>>> =
                HashMap::new();
            for (name, key) in typ
                .dynamic_initializer_assignments
                .iter()
                .zip(&typ.native_initializer_assignment_identities)
            {
                assignment_keys
                    .entry(name)
                    .or_default()
                    .push_back(key.clone());
            }
            let words = &self.dmb.lists[list as usize];
            let mut at = 0;
            while at < words.len() {
                let id = words[at];
                let (value, width) = Value::decode(&words[at + 1..]).map_err(|error| {
                    EmitError::Invalid(format!("malformed initializer identity value: {error:?}"))
                })?;
                if value.tag() == 62 {
                    let name = self
                        .dmb
                        .string(self.dmb.variables[id as usize].name)
                        .and_then(|bytes| std::str::from_utf8(bytes).ok());
                    let key = name.and_then(|name| {
                        if typ.native_initializer_assignment_identities.is_empty() {
                            typ.native_initializer_identities.get(name).cloned()
                        } else {
                            assignment_keys
                                .get_mut(name)
                                .and_then(|keys| keys.pop_front())
                                .flatten()
                        }
                    });
                    if let Some(key) = key {
                        overrides.push((list, at + 1, value.id(), key));
                    }
                }
                at += 1 + width;
            }
        }
        if let Some(globals) = &self.input.globals {
            if globals.native_initializer_identity_version > 1 {
                return Err(EmitError::Unsupported(
                    "global initializer identity annotation version".into(),
                ));
            }
            if globals.native_initializer_identity_version == 1 {
                for (&old, key) in &globals.native_initializer_identities {
                    let id = *self.ids.globals.get(old).ok_or_else(|| {
                        EmitError::Invalid("initializer identity global ID out of range".into())
                    })?;
                    if self.dmb.variables[id as usize].kind == 62 {
                        variables.push((id, key.clone()));
                    }
                }
            }
        }
        variables.sort_by_key(|(id, _)| *id);
        let mut interned = BTreeMap::new();
        for (id, key) in variables {
            let key = serde_json::to_string(&self.initializer_identity_key(&key)?)
                .map_err(|error| EmitError::Invalid(error.to_string()))?;
            let old = self.dmb.variables[id as usize].value;
            let token = *interned.entry(key).or_insert(old);
            self.dmb.variables[id as usize].value = token;
        }
        for (list, offset, old, key) in overrides {
            let key = serde_json::to_string(&self.initializer_identity_key(&key)?)
                .map_err(|error| EmitError::Invalid(error.to_string()))?;
            let token = *interned.entry(key).or_insert(old);
            self.dmb.lists[list as usize][offset..offset + 2]
                .copy_from_slice(&[62 | ((token >> 16) << 8), token & 0xffff]);
        }
        Ok(())
    }
    pub(in crate::od_emit) fn variable_reindex_order(&self) -> Result<Vec<usize>, EmitError> {
        // Dream Maker places persistent globals and class fields ahead of
        // procedure-local Variable records. Preserve that layout even though
        // the native scaffold's procedure records were allocated earlier.
        let old_len = self.dmb.variables.len();
        let mut order = Vec::with_capacity(old_len);
        let mut used = vec![false; old_len];
        for old in (0..self.native.globals)
            .chain(self.new_globals.iter().map(|&id| id as usize))
            .chain(self.new_args.iter().map(|&id| id as usize))
            .chain(self.new_fields.iter().map(|&id| id as usize))
            .chain(self.native.globals..self.native.variables)
        {
            if old >= old_len {
                return Err(EmitError::Invalid("variable reorder out of range".into()));
            }
            if !used[old] {
                used[old] = true;
                order.push(old);
            }
        }
        order.extend((0..old_len).filter(|&id| !used[id]));
        Ok(order)
    }
    pub(in crate::od_emit) fn preview_variable_ids(&mut self) -> Result<(), EmitError> {
        let order = self.variable_reindex_order()?;
        self.predicted_variable_ids = vec![0; order.len()];
        for (new, &old) in order.iter().enumerate() {
            self.predicted_variable_ids[old] = new as u32;
        }
        Ok(())
    }
}
