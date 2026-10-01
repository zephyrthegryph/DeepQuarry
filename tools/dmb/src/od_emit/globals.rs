use super::*;

impl Builder<'_> {
    pub(super) fn constant(&mut self, value: &JsonValue) -> Result<Value, EmitError> {
        let (tag, id, number) = match value {
            JsonValue::Null => (0, 0, None),
            JsonValue::String(s) => (6, self.string(s), None),
            JsonValue::Number(n) => {
                (
                    42,
                    0,
                    Some(n.as_f64().ok_or_else(|| {
                        EmitError::Unsupported("non-finite numeric constant".into())
                    })? as f32),
                )
            }
            JsonValue::Object(map) => match map.get("type").and_then(JsonValue::as_u64) {
                Some(0) => {
                    let path = map
                        .get("resourcePath")
                        .and_then(JsonValue::as_str)
                        .ok_or_else(|| EmitError::Invalid("resource value lacks path".into()))?;
                    let i = self
                        .input
                        .resources
                        .iter()
                        .position(|p| p == path)
                        .ok_or_else(|| {
                            EmitError::Invalid(format!("resource not in table: {path}"))
                        })?;
                    (12, self.ids.resources[i], None)
                }
                Some(1) => {
                    let old = map
                        .get("value")
                        .and_then(JsonValue::as_u64)
                        .ok_or_else(|| EmitError::Invalid("type constant lacks ID".into()))?
                        as usize;
                    let tag = self.input.native_type_tag(old).ok_or_else(|| {
                        EmitError::Invalid("type constant has invalid ancestry".into())
                    })?;
                    let class = *self
                        .ids
                        .classes
                        .get(old)
                        .ok_or_else(|| EmitError::Invalid("type ID unresolved".into()))?;
                    let id = if matches!(tag, 36 | 39 | 40 | 59) {
                        0 // Client paths are the native singleton type value.
                    } else if tag == 8 {
                        self.dmb
                            .mobs
                            .iter()
                            .position(|mob| mob.class == class)
                            .map_or(class, |index| index as u32)
                    } else {
                        class
                    };
                    (tag, id, None)
                }
                Some(2) => {
                    let old = map
                        .get("value")
                        .and_then(JsonValue::as_u64)
                        .ok_or_else(|| EmitError::Invalid("proc constant lacks ID".into()))?
                        as usize;
                    if old >= self.input.procs.len() {
                        return Err(EmitError::Invalid("proc constant ID out of range".into()));
                    }
                    let id = if self.ids.procs.is_empty() {
                        old as u32 // Resolved after all procedure IDs are allocated.
                    } else {
                        self.ids.procs[old]
                    };
                    if id == NONE {
                        return Err(EmitError::Unsupported(
                            "proc constant has no BYOND procedure equivalent".into(),
                        ));
                    }
                    (38, id, None)
                }
                Some(4) => (42, 0, Some(f32::INFINITY)),
                Some(5) => (42, 0, Some(f32::NEG_INFINITY)),
                Some(7) => (41, 0, None), // Resolved after instance prototypes exist.
                other => {
                    return Err(EmitError::Unsupported(format!(
                        "OpenDream constant type {other:?}"
                    )))
                }
            },
            _ => {
                return Err(EmitError::Unsupported(
                    "unsupported OpenDream constant".into(),
                ))
            }
        };
        if let Some(number) = number {
            let bits = number.to_bits();
            return Ok(Value {
                tag_word: 42,
                data_word: bits >> 16,
                extra_word: Some(bits & 0xffff),
            });
        }
        Ok(Value {
            tag_word: (tag as u32) | ((id >> 16) << 8),
            data_word: id & 0xffff,
            extra_word: None,
        })
    }
    /// Standard globals are root bindings, not every global slot sharing their name.
    pub(super) fn native_baseline_global_id(&self, id: usize, name: &str) -> Option<usize> {
        let root = self.input.types.iter().find(|typ| typ.path == "/")?;
        if root.global_variables.get(name) != Some(&id) {
            return None;
        }
        let baseline = self.baseline?;
        let baseline_root = baseline.types.iter().find(|typ| typ.path == "/")?;
        let old = *baseline_root.global_variables.get(name)?;
        (baseline
            .globals
            .as_ref()?
            .names
            .get(old)
            .map(String::as_str)
            == Some(name))
        .then_some(old)
    }

    pub(super) fn build_globals(&mut self) -> Result<(), EmitError> {
        let Some(globals) = &self.input.globals else {
            return Ok(());
        };
        if globals
            .const_global_ids
            .iter()
            .chain(globals.const_field_global_ids.iter())
            .any(|id| *id >= globals.global_count)
            || !globals
                .const_field_global_ids
                .is_subset(&globals.const_global_ids)
        {
            return Err(EmitError::Invalid(
                "constant global provenance contains an invalid binding ID".into(),
            ));
        }
        let mut footer = if self.dmb.variable_footer == NONE {
            Vec::new()
        } else {
            self.dmb.lists[self.dmb.variable_footer as usize].clone()
        };
        let baseline_names = self.baseline.and_then(|base| base.globals.as_ref());
        if globals.globals.keys().any(|&id| id >= globals.names.len()) {
            return Err(EmitError::Invalid(
                "OpenDream global constant index exceeds names table".into(),
            ));
        }
        for (od_id, name) in globals.names.iter().enumerate() {
            if let Some(old) = self.native_baseline_global_id(od_id, name) {
                if let Some((base, baseline_globals)) = self.baseline.zip(baseline_names) {
                    let current = globals.globals.get(&od_id).unwrap_or(&JsonValue::Null);
                    let original = baseline_globals
                        .globals
                        .get(&old)
                        .unwrap_or(&JsonValue::Null);
                    if !same_od_constant(current, original, self.input, base) {
                        return Err(EmitError::Unsupported(format!(
                            "native global {name} changes its default value"
                        )));
                    }
                }
                let native = self
                    .dmb
                    .variables
                    .iter()
                    .position(|var| self.dmb.string(var.name) == Some(name.as_bytes()))
                    .ok_or_else(|| {
                        EmitError::Unsupported(format!(
                            "OpenDream native global {name} has no DMB slot"
                        ))
                    })?;
                self.ids.globals.push(native as u32);
                continue;
            }
            let value = if let Some(literal) = globals
                .declaration_values
                .get(&od_id)
                .or_else(|| globals.globals.get(&od_id))
            {
                self.constant(literal)?
            } else if let Some(bits) = self.global_init_float_assignment(od_id) {
                Value {
                    tag_word: 42,
                    data_word: bits >> 16,
                    extra_word: Some(bits & 0xffff),
                }
            } else {
                self.constant(&JsonValue::Null)?
            };
            let id = if globals.const_field_global_ids.contains(&od_id) {
                self.class_variable(name, &value)
            } else {
                self.variable(name, &value)
            };
            self.new_globals.push(id);
            self.ids.globals.push(id);
            let is_const = globals.const_global_ids.contains(&od_id)
                || self.input.types.iter().any(|typ| {
                    typ.global_variables.get(name) == Some(&od_id)
                        && typ.const_variables.contains(name)
                });
            if self.input.types.iter().any(|typ| {
                typ.global_variables.get(name) == Some(&od_id) && typ.tmp_variables.contains(name)
            }) {
                return Err(EmitError::Unsupported(format!(
                    "temporary global variable {name} has no verified DMB declaration flags"
                )));
            }
            footer.extend([id, if is_const { 3 } else { 1 }]);
        }
        if self.ids.globals.len() != globals.global_count {
            return Err(EmitError::Invalid(
                "OpenDream global count does not match names".into(),
            ));
        }
        for (type_id, typ) in self.input.types.iter().enumerate() {
            let class_id = self.ids.classes[type_id];
            if class_id == NONE {
                continue;
            }
            let mut additions = Vec::new();
            let mut statics: Vec<_> = typ.global_variables.iter().collect();
            statics.sort_by_key(|(name, _)| *name);
            for (name, &old) in statics {
                if self.native_baseline_global_id(old, name).is_some() {
                    continue;
                }
                let variable = *self.ids.globals.get(old).ok_or_else(|| {
                    EmitError::Invalid("class static global ID out of range".into())
                })?;
                additions.extend([
                    variable,
                    if typ.const_variables.contains(name) {
                        3
                    } else if globals.temporary_global_ids.contains(&old) {
                        5
                    } else {
                        1
                    },
                ]);
            }
            if !additions.is_empty() {
                let current = self.dmb.classes[class_id as usize].defining_variable_list_id();
                let mut declarations = if current == NONE {
                    Vec::new()
                } else {
                    self.dmb.lists[current as usize].clone()
                };
                declarations.extend(additions);
                let id = self.list(declarations);
                self.dmb.classes[class_id as usize].lists_and_procs[4] = id;
            }
        }
        // Dream Maker serializes proc-local compile-time `var/const` values
        // in the global footer even though OpenDream has no global ID for
        // them. Keep each authored declaration, including duplicate names.
        for declaration in &globals.compile_time_const_declarations {
            if declaration.proc_id >= self.input.procs.len() {
                return Err(EmitError::Invalid(format!(
                    "compile-time const {} has invalid ProcID {}",
                    declaration.name, declaration.proc_id
                )));
            }
            let value = self.constant(&declaration.value)?;
            let id = self.variable(&declaration.name, &value);
            self.new_globals.push(id);
            footer.extend([id, 3]);
        }
        // Dream Maker also places nonstatic `var/const` declarations in the
        // global footer, referring to the same VariableID as their class
        // declaration. OpenDream omits these from Globals.Names. Static
        // consts are already present there, so preserve each ID only once.
        let mut footer_ids: HashSet<u32> = footer.chunks_exact(2).map(|pair| pair[0]).collect();
        for class in &self.dmb.classes {
            let declarations = class.defining_variable_list_id();
            if declarations == NONE {
                continue;
            }
            for pair in self.dmb.lists[declarations as usize].chunks_exact(2) {
                if pair[1] == 3 && footer_ids.insert(pair[0]) {
                    footer.extend([pair[0], 3]);
                }
            }
        }
        // OpenDream also emits a `<init>` procedure for literal globals.
        // Their values live directly in DMB Variable records above.
        self.dmb.variable_footer = self.list(footer);
        if self.input.global_init_proc.is_some() && !self.global_init_is_encoded_literals(globals) {
            let empty = self.list(Vec::new());
            let code = self.list(vec![0]);
            self.reserve_proc_sentinel();
            let id = self.dmb.procs.len() as u32;
            self.dmb.procs.push(Proc {
                strings: [NONE; 4],
                source_parameter: 255,
                source_kind: 0,
                flags: 4,
                extended_flags: None,
                code_locals_args: [code, empty, empty],
            });
            self.ids.global_init_proc = Some(id);
            self.dmb.world.ids[4] = id;
        }
        Ok(())
    }
    pub(super) fn global_init_is_encoded_literals(
        &self,
        globals: &crate::opendream::OpenDreamGlobals,
    ) -> bool {
        let Some(code) = self
            .input
            .global_init_proc
            .as_ref()
            .and_then(|proc| proc.bytecode.as_ref())
        else {
            return false;
        };
        if code.is_empty() {
            return true;
        }
        code.chunks_exact(10).remainder().is_empty()
            && code.chunks_exact(10).all(|chunk| {
                if chunk[0] != 0x9a || chunk[5] != 0x0a {
                    return false;
                }
                let Some(bits) = read_u32_le(chunk, 1) else {
                    return false;
                };
                let Some(id) = read_u32_le(chunk, 6) else {
                    return false;
                };
                let id = id as usize;
                globals
                    .globals
                    .get(&id)
                    .map_or(Some(0.0), JsonValue::as_f64)
                    .is_some_and(|value| (value as f32).to_bits() == bits)
            })
    }
    pub(super) fn global_init_float_assignment(&self, target: usize) -> Option<u32> {
        let code = self.input.global_init_proc.as_ref()?.bytecode.as_ref()?;
        if !code.chunks_exact(10).remainder().is_empty() {
            return None;
        }
        code.chunks_exact(10).find_map(|chunk| {
            (chunk[0] == 0x9a && chunk[5] == 0x0a && read_u32_le(chunk, 6)? as usize == target)
                .then(|| read_u32_le(chunk, 1))
                .flatten()
        })
    }
    pub(super) fn mark_initializer_variables(&mut self) -> Result<(), EmitError> {
        let mut final_float_defaults = Vec::new();
        let annotated_declarations = self.input.types.iter().any(|typ| {
            !typ.initializer_value_kinds.is_empty()
                || !typ.dynamic_initializer_assignments.is_empty()
                || !typ.dynamic_declaration_fields.is_empty()
        });
        // Assignment bytecode alone cannot distinguish list/icon construction
        // from scalar or image initialization. Prefer the compiler's optional
        // source declaration annotation when present.
        let annotated_globals = self.input.globals.as_ref().is_some_and(|globals| {
            !globals.initializer_value_kinds.is_empty()
                || !globals.dynamic_initializer_global_ids.is_empty()
        });
        if annotated_globals {
            for &old in &self
                .input
                .globals
                .as_ref()
                .unwrap()
                .dynamic_initializer_global_ids
            {
                let id = *self.ids.globals.get(old).ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "dynamic global initializer ID {old} is out of range"
                    ))
                })?;
                let variable = &mut self.dmb.variables[id as usize];
                if variable.kind == 0 {
                    variable.kind = 62;
                } else if variable.kind != 62 {
                    return Err(EmitError::Unsupported(format!(
                        "dynamic global initializer ID {old} has a non-null static default"
                    )));
                }
            }
        } else if let Some(proc) = &self.input.global_init_proc {
            if let Some(code) = &proc.bytecode {
                for bytes in code.windows(6).filter(|bytes| bytes[0..2] == [0x85, 0x0a]) {
                    let Some(old) = read_u32_le(bytes, 2) else {
                        continue;
                    };
                    let old = old as usize;
                    if let Some(&id) = self.ids.globals.get(old) {
                        let variable = &mut self.dmb.variables[id as usize];
                        if variable.kind == 0 {
                            variable.kind = 62;
                        }
                    }
                }
            }
        }
        for (type_id, typ) in self.input.types.iter().enumerate() {
            let Some(init_id) = typ.init_proc else {
                continue;
            };
            let Some(code) = self
                .input
                .procs
                .get(init_id)
                .and_then(|proc| proc.bytecode.as_deref())
            else {
                continue;
            };
            let class_id = self.ids.classes[type_id];
            if class_id == NONE {
                continue;
            }
            let declarations = self.dmb.classes[class_id as usize].defining_variable_list_id();
            if declarations == NONE {
                continue;
            }
            if annotated_declarations {
                let replacements: Vec<_> = self.dmb.lists[declarations as usize]
                    .chunks_exact(2)
                    .enumerate()
                    .filter_map(|(index, pair)| {
                        let old_id = pair[0];
                        let variable = &self.dmb.variables[old_id as usize];
                        (variable.kind == 0
                            && typ.dynamic_declaration_fields.iter().any(|name| {
                                self.dmb.strings[variable.name as usize].data == name.as_bytes()
                            }))
                        .then_some((index * 2, old_id))
                    })
                    .collect();
                for (offset, old_id) in replacements {
                    // Ordinary zero defaults are shared across declarations.
                    // A hidden initializer marker belongs to this declaration
                    // alone, so clone its Variable record before tagging it.
                    let mut variable = self.dmb.variables[old_id as usize].clone();
                    variable.kind = 62;
                    let new_id = self.dmb.variables.len() as u32;
                    self.dmb.variables.push(variable);
                    self.new_fields.push(new_id);
                    self.dmb.lists[declarations as usize][offset] = new_id;
                    if let Some(mut entries) = self.dmb.class_initial_values(class_id as usize) {
                        let mut changed = false;
                        for entry in &mut entries {
                            if entry.variable_id == old_id {
                                entry.variable_id = new_id;
                                changed = true;
                            }
                        }
                        if changed {
                            let mut words = Vec::new();
                            for entry in entries {
                                words.push(entry.variable_id);
                                words.extend(entry.value.encode());
                            }
                            let list_id = self.list(words);
                            self.dmb.classes[class_id as usize].lists_and_procs[3] = list_id;
                        }
                    }
                }
            } else {
                for bytes in code.windows(6).filter(|bytes| bytes[0..2] == [0x85, 0x0d]) {
                    let Some(string_id) = read_u32_le(bytes, 2) else {
                        continue;
                    };
                    let string_id = string_id as usize;
                    let Some(name) = self.input.strings.get(string_id) else {
                        continue;
                    };
                    for pair in self.dmb.lists[declarations as usize].chunks_exact(2) {
                        let variable = &mut self.dmb.variables[pair[0] as usize];
                        if variable.kind == 0
                            && self.dmb.strings[variable.name as usize].data == name.as_bytes()
                        {
                            variable.kind = 62;
                        }
                    }
                }
            }
            // Proven straight-line pattern from a declaration initialized by
            // list(), immediately overridden with a literal float in the same
            // type block (e.g. DeepQuarry spacecash.access). OpenDream's JSON
            // reports null, while Dream Maker also records the final literal
            // in the class initial-value table. Any other init shape remains
            // bytecode-only until its control flow is understood.
            if code.len() == 28
                && code[..7] == [0x0a, 0x06, 0, 0, 0, 0, 0]
                && code[7..14] == [0x22, 0, 0, 0, 0, 0x85, 0x0d]
                && code[18] == 0x9a
                && code[23] == 0x0d
                && code[14..18] == code[24..28]
            {
                let Some(string_id) = read_u32_le(code, 14) else {
                    continue;
                };
                let string_id = string_id as usize;
                if let Some(name) = self.input.strings.get(string_id) {
                    if let Some(var_id) = self.dmb.lists[declarations as usize]
                        .chunks_exact(2)
                        .map(|pair| pair[0])
                        .find(|&id| {
                            self.dmb.string(self.dmb.variables[id as usize].name)
                                == Some(name.as_bytes())
                        })
                    {
                        let Some(bits) = read_u32_le(code, 19) else {
                            continue;
                        };
                        final_float_defaults.push((class_id, var_id, bits));
                    }
                }
            }
        }
        for (class_id, var_id, bits) in final_float_defaults {
            let mut values = self
                .dmb
                .class_initial_values(class_id as usize)
                .unwrap_or_default();
            values.retain(|item| item.variable_id != var_id);
            values.push(crate::dmb::ClassInitialValue {
                variable_id: var_id,
                value: Value {
                    tag_word: 42,
                    data_word: bits >> 16,
                    extra_word: Some(bits & 0xffff),
                },
            });
            let mut words = Vec::new();
            for item in values {
                words.push(item.variable_id);
                words.extend(item.value.encode());
            }
            let id = self.list(words);
            self.dmb.classes[class_id as usize].lists_and_procs[3] = id;
        }
        // OpenDream can leave a literal assignment in `<init>` and report a
        // null Variables placeholder after an inherited field was dynamic.
        // The optional source annotation restores Dream Maker's class value.
        for (type_id, typ) in self.input.types.iter().enumerate() {
            let class_id = self.ids.classes[type_id];
            if class_id == NONE || typ.constant_initializer_fields.is_empty() {
                continue;
            }
            let mut annotated: Vec<_> = typ.constant_initializer_fields.iter().collect();
            annotated.sort_by_key(|(name, _)| *name);
            let mut values = self
                .dmb
                .class_initial_values(class_id as usize)
                .unwrap_or_default();
            for (name, json) in annotated {
                let var_id = self.inherited_variable(class_id, name).ok_or_else(|| {
                    EmitError::Unsupported(format!(
                        "constant initializer {}.{name} has no DMB variable declaration",
                        typ.path
                    ))
                })?;
                let value = self.constant(json)?;
                values.retain(|entry| entry.variable_id != var_id);
                values.push(crate::dmb::ClassInitialValue {
                    variable_id: var_id,
                    value,
                });
            }
            let mut words = Vec::new();
            for entry in values {
                words.push(entry.variable_id);
                words.extend(entry.value.encode());
            }
            let id = self.list(words);
            self.dmb.classes[class_id as usize].lists_and_procs[3] = id;
        }
        Ok(())
    }
    pub(super) fn mark_class_dynamic_initials(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn assign_class_initializer_markers(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn initializer_identity_key(
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

    pub(super) fn intern_initializer_identities(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn variable_reindex_order(&self) -> Result<Vec<usize>, EmitError> {
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
    pub(super) fn preview_variable_ids(&mut self) -> Result<(), EmitError> {
        let order = self.variable_reindex_order()?;
        self.predicted_variable_ids = vec![0; order.len()];
        for (new, &old) in order.iter().enumerate() {
            self.predicted_variable_ids[old] = new as u32;
        }
        Ok(())
    }
    pub(super) fn resolve_modified_type_constants(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn reindex_variables(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn reindex_classes(&mut self) -> Result<(), EmitError> {
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
            let instructions = crate::bytecode::decode(words)
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
    pub(super) fn resolve_pending_proc_constants(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn resolve_mob_type_constants(&mut self) -> Result<(), EmitError> {
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
    pub(super) fn reindex_procs(&mut self) -> Result<(), EmitError> {
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
            let decoded = crate::bytecode::decode(words)
                .map_err(|e| EmitError::Invalid(format!("procedure code: {}", e.reason)))?;
            for instruction in decoded {
                let typed = instruction.typed_operands().map_err(|error| {
                    EmitError::Invalid(format!("procedure operands: {}", error.reason))
                })?;
                let mut operand_offset = instruction.offset + 1;
                for operand in typed {
                    use crate::bytecode::Operand;
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
    pub(super) fn reindex_instances(&mut self) -> Result<(), EmitError> {
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
            for instruction in crate::bytecode::decode(words)
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
