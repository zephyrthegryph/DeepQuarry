use super::*;

impl Builder<'_> {
    pub(super) fn build_classes(&mut self) -> Result<(), EmitError> {
        // `parent_type` can refer to a class that occurs later in OpenDream's
        // Types array. Reserve all OD slots, then allocate in dependency order.
        self.ids.classes = vec![NONE; self.input.types.len()];
        let mut pending = Vec::new();
        let mut allocated_classes = std::collections::HashSet::new();
        for (od_id, typ) in self.input.types.iter().enumerate() {
            if typ.path == "/" || typ.path == "/world" {
                continue;
            }
            // OpenDream materializes paths from typed list declarations such
            // as `var/list/href_list`. Dream Maker has no /list class table,
            // and the matched native DMB has none of these four paths.
            if typ.path.starts_with("/list/") && typ.procs.is_empty() && typ.variables.is_empty() {
                continue;
            }
            if let Some(&id) = self.paths.get(&typ.path) {
                self.ids.classes[od_id] = id;
            } else if self
                .baseline
                .is_some_and(|base| base.types.iter().any(|native| native.path == typ.path))
            {
                // OpenDream-only native helper types have no Dream Maker class.
            } else {
                pending.push(od_id);
            }
        }
        let datum_class = *self
            .paths
            .get("/datum")
            .ok_or_else(|| EmitError::Invalid("native scaffold has no /datum class".into()))?;
        while !pending.is_empty() {
            let before = pending.len();
            pending.retain(|&od_id| {
                let typ = &self.input.types[od_id];
                let parent = typ.parent.and_then(|i| self.ids.classes.get(i)).copied();
                if parent.is_none() {
                    return true;
                }
                let mut parent = parent.unwrap();
                if parent == NONE {
                    let parent_path = typ.parent.and_then(|i| self.input.types.get(i));
                    if parent_path.is_some_and(|p| p.path != "/" && p.path != "/world") {
                        return true;
                    }
                    parent = datum_class;
                }
                let mut class = self.dmb.classes[parent as usize].clone();
                class.initial_ids[0] = self.string(&typ.path);
                class.initial_ids[1] = if typ.path == "/verb" { NONE } else { parent };
                let leaf = typ.path.rsplit('/').next().unwrap_or("");
                if !self.input.type_inherits_path(od_id, "/image")
                    && !self.input.type_inherits_path(od_id, "/mutable_appearance")
                {
                    class.initial_ids[2] = self.string(&leaf.replace('_', " "));
                    class.text = self.string(&leaf.chars().take(1).collect::<String>());
                }
                class.lists_and_procs = [NONE; 6];
                class.overrides = NONE;
                self.reserve_class_sentinel();
                let id = self.dmb.classes.len() as u32;
                self.dmb.classes.push(class);
                allocated_classes.insert(id);
                self.paths.insert(typ.path.clone(), id);
                self.ids.classes[od_id] = id;
                false
            });
            if pending.len() == before {
                let typ = &self.input.types[pending[0]];
                return Err(EmitError::Invalid(format!(
                    "type {} has unresolved or cyclic parent",
                    typ.path
                )));
            }
        }
        // BYOND permits `/client` to opt into datum inheritance. DeepQuarry
        // explicitly declares `parent_type = /datum`, while the native
        // scaffold's `/client` is a root class.
        if let Some((od_id, _)) = self
            .input
            .types
            .iter()
            .enumerate()
            .find(|(_, typ)| typ.path == "/client")
        {
            let client = self.ids.classes[od_id];
            let parent = self.input.types[od_id]
                .parent
                .and_then(|id| self.input.types.get(id))
                .map(|typ| typ.path.as_str());
            if client != NONE && parent == Some("/datum") {
                let datum = *self.paths.get("/datum").ok_or_else(|| {
                    EmitError::Invalid("native scaffold has no /datum class".into())
                })?;
                self.dmb.classes[client as usize].initial_ids[1] = datum;
            }
        }
        // OpenDream's Types array is not topological: DeepQuarry lists /obj
        // before /atom (indices 2 and 37706). Process parent declarations
        // first so inherited variables resolve to VariableIDs instead of
        // being misclassified as builtin string-key overrides.
        let mut declaration_order: Vec<_> = (0..self.input.types.len()).collect();
        declaration_order.sort_by_key(|&id| {
            let mut depth = 0usize;
            let mut parent = self.input.types[id].parent;
            while let Some(index) = parent {
                depth += 1;
                if depth > self.input.types.len() {
                    break;
                }
                parent = self.input.types[index].parent;
            }
            depth
        });
        for od_id in declaration_order {
            let typ = &self.input.types[od_id];
            if self.ids.classes[od_id] == NONE {
                continue;
            }
            let class_id = self.ids.classes[od_id];
            let appearance_type = self.input.type_inherits_path(od_id, "/atom")
                || self.input.type_inherits_path(od_id, "/image")
                || self.input.type_inherits_path(od_id, "/mutable_appearance");
            if allocated_classes.contains(&class_id) {
                let original = self.dmb.classes[class_id as usize].clone();
                let parent = original.parent_class_id();
                if parent != NONE {
                    // Appearance headers store effective inherited values. All
                    // slots were allocated before authored parent fields were
                    // applied; refresh in this parent-first declaration pass.
                    let mut inherited = self.dmb.classes[parent as usize].clone();
                    inherited.initial_ids[0] = original.initial_ids[0];
                    inherited.initial_ids[1] = original.initial_ids[1];
                    inherited.lists_and_procs = original.lists_and_procs;
                    inherited.overrides = original.overrides;
                    let authored_ancestor = |name: &str| {
                        if !appearance_type {
                            return false;
                        }
                        let mut ancestor = typ.parent;
                        while let Some(id) = ancestor {
                            let ancestor_type = &self.input.types[id];
                            if ancestor_type.explicit_type_fields.contains(name)
                                || !self.is_native_path(&ancestor_type.path)
                                    && ancestor_type.variables.contains_key(name)
                            {
                                return name != "name"
                                    || ancestor_type
                                        .variables
                                        .get(name)
                                        .is_none_or(|v| !v.is_null());
                            }
                            ancestor = ancestor_type.parent;
                        }
                        false
                    };
                    if !authored_ancestor("name") {
                        inherited.initial_ids[2] = original.initial_ids[2];
                    }
                    if !authored_ancestor("text") {
                        inherited.text = original.text;
                    }
                    self.dmb.classes[class_id as usize] = inherited;
                }
            }
            if !allocated_classes.contains(&class_id)
                && self.input.type_inherits_path(od_id, "/atom")
            {
                if let Some(parent_id) = typ.parent {
                    let parent_class = self.ids.classes[parent_id];
                    if parent_class != NONE {
                        let has_authored_parent = |field: &str| {
                            let mut at = Some(parent_id);
                            while let Some(id) = at {
                                if self.input.types[id].explicit_type_fields.contains(field) {
                                    return true;
                                }
                                at = self.input.types[id].parent;
                            }
                            false
                        };
                        let parent = self.dmb.classes[parent_class as usize].clone();
                        let child = &mut self.dmb.classes[class_id as usize];
                        if has_authored_parent("layer") {
                            child.layer_bits = parent.layer_bits;
                        }
                        if has_authored_parent("dir") {
                            child.direction = parent.direction;
                        }
                        if has_authored_parent("appearance_flags") {
                            child.set_appearance_flags(parent.appearance_flags());
                        }
                    }
                }
            }
            let retained_client_overrides = if self.input.type_inherits_path(od_id, "/client") {
                let class_id = self.ids.classes[od_id] as usize;
                // These settings are rebuilt even when removed. Preserve other
                // scaffold builtin overrides while replacing authored values.
                let retained = self
                    .dmb
                    .class_builtin_overrides(class_id)
                    .unwrap_or_default()
                    .into_iter()
                    .filter(|field| {
                        !matches!(
                            self.dmb.string(field.name_string_id),
                            Some(b"preload_rsc" | b"perspective")
                        )
                    })
                    .collect::<Vec<_>>();
                self.dmb.classes[class_id].overrides = NONE;
                retained
            } else {
                Vec::new()
            };
            let baseline_type = self.baseline.and_then(|base| {
                self.baseline_type_by_path
                    .get(typ.path.as_str())
                    .and_then(|&index| base.types.get(index))
            });
            let mut declarations = Vec::new();
            let mut initial = Vec::new();
            let mut overrides = Vec::new();
            let mut pending_initial = Vec::new();
            let mut pending_overrides = Vec::new();
            let mut keys: Vec<_> = typ.variables.keys().collect();
            if typ.variable_declaration_order.is_empty() && typ.variable_override_order.is_empty() {
                keys.sort();
            } else {
                let ranks: HashMap<_, _> = typ
                    .variable_declaration_order
                    .iter()
                    .chain(typ.variable_override_order.iter())
                    .enumerate()
                    .map(|(index, name)| (name.as_str(), index))
                    .collect();
                keys.sort_by_key(|name| {
                    (
                        ranks.get(name.as_str()).copied().unwrap_or(usize::MAX),
                        name.as_str(),
                    )
                });
            }
            for name in keys {
                if !typ.explicit_type_fields.contains(name)
                    && !typ.native_client_settings.contains_key(name)
                    && self
                        .baseline
                        .zip(baseline_type)
                        .and_then(|(program, base)| {
                            base.variables.get(name).map(|original| (program, original))
                        })
                        .is_some_and(|(program, original)| {
                            same_od_constant(&typ.variables[name], original, self.input, program)
                        })
                {
                    continue;
                }
                if baseline_type.is_none() && self.is_native_path(&typ.path) {
                    continue;
                }
                if self.input.type_inherits_path(od_id, "/client") && name == "perspective" {
                    if typ.explicit_type_fields.contains(name)
                        || typ.native_client_settings.contains_key(name)
                    {
                        let perspective = typ.variables[name]
                            .as_f64()
                            .filter(|value| (0.0..=3.0).contains(value))
                            .ok_or_else(|| {
                                EmitError::Unsupported(
                                    "client.perspective must be between 0 and 3".into(),
                                )
                            })?;
                        overrides.push(self.string(name));
                        overrides.extend(
                            self.constant(&JsonValue::from(perspective as u32))?
                                .encode(),
                        );
                    }
                    continue;
                }
                if self.input.type_inherits_path(od_id, "/client")
                    && matches!(
                        name.as_str(),
                        "control_freak"
                            | "preload_rsc"
                            | "script"
                            | "show_verb_panel"
                            | "lazy_eye"
                            | "authenticate"
                            | "show_popup_menus"
                            | "show_map"
                            | "macro_mode"
                    )
                {
                    if name == "preload_rsc" && typ.variables[name].is_string() {
                        // Native retains an authored resource-download URL or
                        // filename as a builtin class override, unlike modes.
                        overrides.push(self.string(name));
                        overrides.extend(self.constant(&typ.variables[name])?.encode());
                    }
                    // These builtins live in the DMB world record/header,
                    // not in /client's class declaration table.
                    continue;
                }
                let json = &typ.variables[name];
                if name == "transform"
                    && [
                        "/atom",
                        "/obj",
                        "/mob",
                        "/turf",
                        "/area",
                        "/image",
                        "/mutable_appearance",
                    ]
                    .iter()
                    .any(|base| typ.path == *base || typ.path.starts_with(&format!("{base}/")))
                {
                    let bits = self.matrix_transform_initializer(od_id).ok_or_else(|| {
                        EmitError::Unsupported(format!(
                            "type {} transform initializer is not a verified six-number matrix",
                            typ.path
                        ))
                    })?;
                    let class = &mut self.dmb.classes[self.ids.classes[od_id] as usize];
                    class.transform_flag = 1;
                    class.transform = Some(bits);
                    continue;
                }
                if name == "color" {
                    if let Some(bits) = self.matrix_color_initializer(od_id) {
                        let class = &mut self.dmb.classes[self.ids.classes[od_id] as usize];
                        class.color_matrix_flag = 1;
                        class.color_matrix = Some(bits);
                        continue;
                    }
                }
                let pending_proc = if json.get("type").and_then(JsonValue::as_u64) == Some(2) {
                    Some(
                        json.get("value")
                            .and_then(JsonValue::as_u64)
                            .ok_or_else(|| EmitError::Invalid("proc constant lacks ID".into()))?
                            as usize,
                    )
                } else {
                    None
                };
                let value = if typ.modified_type_override_values.contains_key(name) {
                    Value {
                        tag_word: 41,
                        data_word: 0,
                        extra_word: None,
                    }
                } else {
                    self.constant(json)?
                };
                if self.input.native_type_tag(od_id) == Some(8)
                    && matches!(name.as_str(), "sight" | "see_in_dark" | "see_invisible")
                {
                    continue;
                }
                if self.input.native_type_tag(od_id) == Some(11) && name == "luminosity" {
                    overrides.push(self.string(name));
                    overrides.extend(value.encode());
                    if value.tag() == 42 {
                        self.apply_class_field(self.ids.classes[od_id], name, &value)?;
                    }
                    continue;
                }
                if matches!(name.as_str(), "luminosity" | "invisibility")
                    && self.input.type_inherits_path(od_id, "/atom")
                {
                    overrides.push(self.string(name));
                    overrides.extend(value.encode());
                }
                let value = if self.input.type_inherits_path(od_id, "/atom")
                    && name == "name"
                    && value.tag() == 0
                {
                    let leaf = typ.path.rsplit('/').next().unwrap_or("").replace('_', " ");
                    let leaf_id = self.string(&leaf);
                    Value {
                        tag_word: 6 | ((leaf_id >> 16) << 8),
                        data_word: leaf_id & 0xffff,
                        extra_word: None,
                    }
                } else {
                    value
                };
                if self.apply_class_field(self.ids.classes[od_id], name, &value)? {
                    if pending_proc.is_some() {
                        return Err(EmitError::Unsupported(format!(
                            "class field {name} cannot hold a proc reference"
                        )));
                    }
                    continue;
                }
                if name == "glide_size" {
                    overrides.push(self.string(name));
                    overrides.extend(value.encode());
                    continue;
                }
                let parent = self.dmb.classes[self.ids.classes[od_id] as usize].parent_class_id();
                if let Some(var) = self.inherited_variable(parent, name) {
                    initial.push(var);
                    if let Some(old) = pending_proc {
                        pending_initial.push((initial.len() + 1, old));
                    }
                    initial.extend(value.encode());
                } else if self.inherited_od_field(od_id, name) {
                    overrides.push(self.string(name));
                    if let Some(old) = pending_proc {
                        pending_overrides.push((overrides.len() + 1, old));
                    }
                    overrides.extend(value.encode());
                } else {
                    let declaration_json =
                        typ.variable_declaration_values.get(name).unwrap_or(json);
                    let declaration_value =
                        if typ.modified_type_declaration_values.contains_key(name) {
                            Value {
                                tag_word: 41,
                                data_word: 0,
                                extra_word: None,
                            }
                        } else if std::ptr::eq(declaration_json, json) {
                            value
                        } else {
                            self.constant(declaration_json)?
                        };
                    let declaration_pending_proc = declaration_json
                        .get("type")
                        .and_then(JsonValue::as_u64)
                        .filter(|&kind| kind == 2)
                        .and_then(|_| declaration_json.get("value"))
                        .and_then(JsonValue::as_u64)
                        .map(|id| id as usize);
                    let var = if typ.modified_type_declaration_values.contains_key(name) {
                        self.variable(name, &declaration_value)
                    } else if typ.dynamic_declaration_fields.contains(name)
                        && !typ.global_variables.contains_key(name)
                    {
                        // A declaration initializer gets its own allocator
                        // identity. Construct it directly rather than first
                        // interning an ordinary default and cloning later.
                        self.variable(
                            name,
                            &Value {
                                tag_word: 62,
                                data_word: 0,
                                extra_word: None,
                            },
                        )
                    } else {
                        self.class_variable(name, &declaration_value)
                    };
                    if let Some(old) = declaration_pending_proc {
                        self.pending_proc_vars.push((var, old));
                    }
                    self.new_fields.push(var);
                    // Dream Maker keeps a separate class initial value when
                    // a field is declared and later explicitly overridden in
                    // the same type block. The final OpenDream Variables map
                    // alone loses that authorship distinction.
                    if typ.explicit_type_fields.contains(name)
                        && (!json.is_null()
                            || typ
                                .variable_override_order
                                .iter()
                                .any(|field| field == name))
                        && !self.is_native_path(&typ.path)
                    {
                        initial.push(var);
                        if let Some(old) = pending_proc {
                            pending_initial.push((initial.len() + 1, old));
                        }
                        initial.extend(value.encode());
                    }
                    let mut flags = 0;
                    if typ.const_variables.contains(name.as_str()) {
                        flags |= 3;
                    }
                    if typ.tmp_variables.contains(name.as_str()) {
                        flags |= 4;
                    }
                    declarations.extend([var, flags]);
                }
            }
            // Without an authored text setting, native derives the display
            // character from the effective name, including inherited names and
            // a local null-name reset to the type leaf.
            if !self.input.type_inherits_path(od_id, "/image")
                && !self.input.type_inherits_path(od_id, "/mutable_appearance")
                && (allocated_classes.contains(&self.ids.classes[od_id]) || appearance_type)
            {
                let mut ancestor = Some(od_id);
                let mut authored_text = false;
                while let Some(id) = ancestor {
                    let ancestor_type = &self.input.types[id];
                    if appearance_type
                        && (ancestor_type.explicit_type_fields.contains("text")
                            || !self.is_native_path(&ancestor_type.path)
                                && ancestor_type.variables.contains_key("text"))
                    {
                        authored_text = true;
                        break;
                    }
                    ancestor = ancestor_type.parent;
                }
                if !authored_text {
                    let name = self.dmb.classes[self.ids.classes[od_id] as usize].initial_ids[2];
                    let text = if let Some(mut name) = self.dmb.string(name) {
                        while name.starts_with(&[0xff, 0x15]) || name.starts_with(&[0xff, 0x16]) {
                            name = &name[2..];
                        }
                        // Native uses the first raw byte, including a UTF-8
                        // lead byte, rather than decoding a Unicode character.
                        self.string_bytes(name.first().copied().into_iter().collect())
                    } else {
                        NONE
                    };
                    self.dmb.classes[self.ids.classes[od_id] as usize].text = text;
                }
            }
            if !retained_client_overrides.is_empty() {
                let mut names = HashSet::new();
                let mut at = 0;
                while at < overrides.len() {
                    names.insert(overrides[at]);
                    let (_, count) = Value::decode(&overrides[at + 1..]).map_err(|error| {
                        EmitError::Invalid(format!("malformed authored client builtin: {error:?}"))
                    })?;
                    at += count + 1;
                }
                for field in retained_client_overrides {
                    if !names.contains(&field.name_string_id) {
                        overrides.push(field.name_string_id);
                        overrides.extend(field.value.encode());
                    }
                }
            }
            let declaration_list = (!declarations.is_empty()).then(|| self.list(declarations));
            let initial_list = (!initial.is_empty()).then(|| self.list(initial));
            let override_list = (!overrides.is_empty()).then(|| self.list(overrides));
            if let Some(list) = initial_list {
                self.pending_proc_lists.extend(
                    pending_initial
                        .into_iter()
                        .map(|(offset, old)| (list, offset, old)),
                );
            }
            if let Some(list) = override_list {
                self.pending_proc_lists.extend(
                    pending_overrides
                        .into_iter()
                        .map(|(offset, old)| (list, offset, old)),
                );
            }
            let class = &mut self.dmb.classes[self.ids.classes[od_id] as usize];
            if let Some(id) = declaration_list {
                class.lists_and_procs[4] = id;
            }
            if let Some(id) = initial_list {
                class.lists_and_procs[3] = id;
            }
            if let Some(id) = override_list {
                class.overrides = id;
            }
        }
        // Authored atom callbacks enable native mouse dispatch on descendants.
        let mut callback_counts = HashMap::<(usize, String), usize>::new();
        let mut callback_code = std::collections::HashSet::new();
        for p in &self.input.procs {
            if matches!(
                p.name.as_str(),
                "MouseDown"
                    | "MouseDrag"
                    | "MouseDrop"
                    | "MouseEntered"
                    | "MouseExited"
                    | "MouseMove"
                    | "MouseUp"
                    | "MouseWheel"
            ) {
                *callback_counts
                    .entry((p.owning_type_id, p.name.clone()))
                    .or_default() += 1;
                if p.bytecode.as_ref().is_some_and(|c| !c.is_empty()) {
                    callback_code.insert((p.owning_type_id, p.name.clone()));
                }
            }
        }
        let mut base_counts = HashMap::<(String, String), usize>::new();
        if let Some(base) = self.baseline {
            for p in &base.procs {
                *base_counts
                    .entry((base.types[p.owning_type_id].path.clone(), p.name.clone()))
                    .or_default() += 1;
            }
        }
        let mut local_bits = vec![0u64; self.input.types.len()];
        for ((owner, name), count) in callback_counts {
            if count
                > base_counts
                    .get(&(self.input.types[owner].path.clone(), name.clone()))
                    .copied()
                    .unwrap_or(0)
                || callback_code.contains(&(owner, name.clone()))
            {
                local_bits[owner] |= match name.as_str() {
                    "MouseMove" => 0x80000,
                    "MouseWheel" => 0x100000,
                    "MouseEntered" | "MouseExited" => 0x800,
                    _ => 0,
                };
            }
        }
        for (type_id, _typ) in self.input.types.iter().enumerate() {
            if !self.input.type_inherits_path(type_id, "/atom") {
                continue;
            }
            let class_id = self.ids.classes[type_id];
            if class_id == NONE {
                continue;
            }
            let mut at = Some(type_id);
            let mut bits = 0;
            while let Some(owner) = at {
                bits |= local_bits[owner];
                at = self.input.types[owner].parent;
            }
            self.dmb.classes[class_id as usize].flags |= bits;
        }
        // Dream Maker serializes builtin override values cumulatively on each
        // descendant. Ordinary initialized variables are different: their
        // assignments remain on the defining class and are not copied down.
        let mut pending: Vec<_> = (0..self.dmb.classes.len()).collect();
        let mut complete = vec![false; self.dmb.classes.len()];
        while !pending.is_empty() {
            let before = pending.len();
            pending.retain(|&class_id| {
                let parent = self.dmb.classes[class_id].parent_class_id();
                if parent != NONE && !complete[parent as usize] {
                    return true;
                }
                if parent != NONE {
                    let parent_overrides = self
                        .dmb
                        .class_builtin_overrides(parent as usize)
                        .unwrap_or_default();
                    let own_overrides = self
                        .dmb
                        .class_builtin_overrides(class_id)
                        .unwrap_or_default();
                    if !parent_overrides.is_empty() {
                        let mut merged = parent_overrides;
                        for own in own_overrides {
                            if let Some(existing) = merged
                                .iter_mut()
                                .find(|item| item.name_string_id == own.name_string_id)
                            {
                                *existing = own;
                            } else {
                                merged.push(own);
                            }
                        }
                        let mut words = Vec::new();
                        for item in merged {
                            words.push(item.name_string_id);
                            words.extend(item.value.encode());
                        }
                        let id = self.list(words);
                        self.dmb.classes[class_id].overrides = id;
                    }
                }
                complete[class_id] = true;
                false
            });
            if pending.len() == before {
                return Err(EmitError::Invalid(
                    "class builtin override inheritance cycle".into(),
                ));
            }
        }
        Ok(())
    }
    pub(super) fn is_native_path(&self, path: &str) -> bool {
        matches!(
            path,
            "/" | "/world"
                | "/datum"
                | "/atom"
                | "/atom/movable"
                | "/obj"
                | "/mob"
                | "/turf"
                | "/area"
                | "/client"
                | "/list"
                | "/image"
                | "/sound"
                | "/icon"
                | "/matrix"
                | "/regex"
                | "/savefile"
                | "/database"
                | "/database/query"
                | "/exception"
                | "/generator"
                | "/mutable_appearance"
        )
    }
    pub(super) fn inherited_variable(&self, mut class_id: u32, name: &str) -> Option<u32> {
        while class_id != NONE {
            let class = self.dmb.classes.get(class_id as usize)?;
            let list_id = class.defining_variable_list_id();
            if list_id != NONE {
                for pair in self.dmb.lists.get(list_id as usize)?.chunks_exact(2) {
                    let var = self.dmb.variables.get(pair[0] as usize)?;
                    if self.dmb.string(var.name) == Some(name.as_bytes()) {
                        return Some(pair[0]);
                    }
                }
            }
            class_id = class.parent_class_id();
        }
        None
    }
    pub(super) fn inherited_od_field(&self, od_type_id: usize, name: &str) -> bool {
        let mut parent = self.input.types[od_type_id].parent;
        while let Some(id) = parent {
            let Some(typ) = self.input.types.get(id) else {
                return false;
            };
            if typ.variables.contains_key(name) {
                return true;
            }
            parent = typ.parent;
        }
        false
    }
    pub(super) fn matrix_transform_initializer(&self, type_id: usize) -> Option<[u32; 6]> {
        let typ = self.input.types.get(type_id)?;
        let code = self.input.procs.get(typ.init_proc?)?.bytecode.as_deref()?;
        if !matches!(code.len(), 53 | 144)
            || code[..7] != [0x0a, 0x06, 0, 0, 0, 0, 0]
            || code[7..12] != [0x88, 6, 0, 0, 0]
            || code[36..38] != [0x0a, 0x0b]
            || code[42..49] != [1, 6, 0, 0, 0, 0x85, 0x0d]
        {
            return None;
        }
        let proc_id = u32::from_le_bytes(code[38..42].try_into().ok()?) as usize;
        if self.input.procs.get(proc_id)?.name != "matrix" {
            return None;
        }
        let field_id = u32::from_le_bytes(code[49..53].try_into().ok()?) as usize;
        if self.input.strings.get(field_id)?.as_str() != "transform" {
            return None;
        }
        if code.len() == 144 {
            let tail = &code[53..];
            if tail[..5] != [0x8f, 20, 0, 0, 0] || tail[85..87] != [0x85, 0x0d] {
                return None;
            }
            let color_field = u32::from_le_bytes(tail[87..91].try_into().ok()?) as usize;
            if self.input.strings.get(color_field)?.as_str() != "color" {
                return None;
            }
        }
        let mut bits = [0; 6];
        for (index, slot) in bits.iter_mut().enumerate() {
            *slot = u32::from_le_bytes(code[12 + index * 4..16 + index * 4].try_into().ok()?);
        }
        Some(bits)
    }
    pub(super) fn matrix_color_initializer(&self, type_id: usize) -> Option<[u32; 20]> {
        let typ = self.input.types.get(type_id)?;
        let code = self.input.procs.get(typ.init_proc?)?.bytecode.as_deref()?;
        let offset = if self.matrix_transform_initializer(type_id).is_some() {
            53
        } else {
            7
        };
        let tail = code.get(offset..)?;
        if tail.len() != 91 || tail[..5] != [0x8f, 20, 0, 0, 0] || tail[85..87] != [0x85, 0x0d] {
            return None;
        }
        let field = u32::from_le_bytes(tail[87..91].try_into().ok()?) as usize;
        if self.input.strings.get(field)?.as_str() != "color" {
            return None;
        }
        let mut bits = [0; 20];
        for (i, slot) in bits.iter_mut().enumerate() {
            *slot = u32::from_le_bytes(tail[5 + i * 4..9 + i * 4].try_into().ok()?);
        }
        Some(bits)
    }
}
