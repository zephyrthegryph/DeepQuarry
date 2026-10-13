use super::*;

impl Builder<'_> {
    pub(in crate::od_emit) fn constant(&mut self, value: &JsonValue) -> Result<Value, EmitError> {
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
    pub(in crate::od_emit) fn native_baseline_global_id(
        &self,
        id: usize,
        name: &str,
    ) -> Option<usize> {
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

    pub(in crate::od_emit) fn build_globals(&mut self) -> Result<(), EmitError> {
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
    pub(in crate::od_emit) fn global_init_is_encoded_literals(
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
    pub(in crate::od_emit) fn global_init_float_assignment(&self, target: usize) -> Option<u32> {
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
    pub(in crate::od_emit) fn mark_initializer_variables(&mut self) -> Result<(), EmitError> {
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
            values.push(byond_dmb::dmb::ClassInitialValue {
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
                values.push(byond_dmb::dmb::ClassInitialValue {
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
}
