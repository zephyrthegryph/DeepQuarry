use super::*;

impl Builder<'_> {
    pub(super) fn build_procs(&mut self) -> Result<(), EmitError> {
        let argument_source_positions: HashMap<usize, usize> = self
            .input
            .procs
            .iter()
            .flat_map(|proc| {
                proc.arguments
                    .iter()
                    .enumerate()
                    .filter_map(|(position, arg)| arg.possible_values_proc.map(|id| (id, position)))
            })
            .collect();
        let argument_source_procs: HashSet<usize> =
            argument_source_positions.keys().copied().collect();
        let direct_argument_sources: HashMap<usize, u32> = argument_source_procs
            .iter()
            .filter_map(|&index| {
                self.direct_argument_source(index)
                    .map(|source| (index, source))
            })
            .collect();
        for &index in &argument_source_procs {
            let companion = self.input.procs.get(index).ok_or_else(|| {
                EmitError::Invalid(format!("argument source procedure {index} is out of range"))
            })?;
            if companion.bytecode.is_none() {
                return Err(EmitError::Unsupported(format!(
                    "argument source procedure {index} lacks isolated bytecode"
                )));
            }
        }
        self.ids.argument_source_procs = argument_source_procs
            .difference(&direct_argument_sources.keys().copied().collect())
            .copied()
            .collect();
        let mut pending_argument_sources = Vec::new();
        // Native OpenDream procedures are identified against a compiler-only
        // baseline. A matching procedure must not be copied into DreamDaemon:
        // the Dream Maker scaffold already provides its own implementation.
        for (od_index, proc) in self.input.procs.iter().enumerate() {
            if argument_source_procs.contains(&od_index) {
                if direct_argument_sources.contains_key(&od_index) {
                    self.ids.procs.push(NONE);
                    continue;
                }
                let code = self.list(vec![12, 0]);
                let locals = self.list(Vec::new());
                let mut args = Vec::new();
                let preceding = *argument_source_positions.get(&od_index).ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "argument source procedure {od_index} has no owner argument"
                    ))
                })?;
                let current = u8::try_from(preceding).map_err(|_| {
                    EmitError::Unsupported(format!(
                        "argument source procedure {od_index} has argument index above 255"
                    ))
                })?;
                let referenced = crate::od_lower::referenced_argument_indices(
                    proc.bytecode.as_deref().ok_or_else(|| {
                        EmitError::Invalid(format!(
                            "argument source procedure {od_index} has no bytecode"
                        ))
                    })?,
                )
                .map_err(|error| {
                    EmitError::Unsupported(format!(
                        "argument source procedure {od_index} reference scan: {error:?}"
                    ))
                })?;
                let count = preceding + usize::from(referenced.contains(&current));
                for argument in proc.arguments.iter().take(count) {
                    let variable = self.procedure_variable(&argument.name);
                    self.new_args.push(variable);
                    args.extend([0, 0, variable, 0]);
                }
                let args = self.list(args);
                self.reserve_proc_sentinel();
                let id = self.dmb.procs.len() as u32;
                self.dmb.procs.push(Proc {
                    strings: [NONE; 4],
                    source_parameter: 255,
                    source_kind: 0,
                    flags: 4,
                    extended_flags: None,
                    code_locals_args: [code, locals, args],
                });
                self.ids.procs.push(id);
                continue;
            }
            if proc.name == "<init>"
                && self
                    .input
                    .types
                    .get(proc.owning_type_id)
                    .is_some_and(|owner| {
                        owner.init_proc == Some(od_index)
                            && owner.initializer_assignment_count > 0
                            && owner.initializer_assignment_count
                                == owner.constant_initializer_assignments.len()
                            && owner
                                .constant_initializer_assignments
                                .iter()
                                .all(|name| owner.constant_initializer_fields.contains_key(name))
                    })
            {
                // The exporter proves every own initialization assignment is
                // a literal Dream Maker stores in class initial values.
                self.ids.procs.push(NONE);
                continue;
            }
            if proc.name == "<init>"
                && self
                    .input
                    .types
                    .get(proc.owning_type_id)
                    .is_some_and(|owner| {
                        owner.init_proc == Some(od_index)
                            && owner.variables.contains_key("transform")
                    })
                && self
                    .matrix_transform_initializer(proc.owning_type_id)
                    .is_some()
            {
                // The exact paired six-number matrix initializer is stored
                // in Class.transform, with no native class init procedure.
                self.ids.procs.push(NONE);
                continue;
            }
            let owner =
                self.input.types.get(proc.owning_type_id).ok_or_else(|| {
                    EmitError::Invalid("procedure owner type out of range".into())
                })?;
            if owner.path == "/"
                && proc.name == "load_ext"
                && proc.arguments.len() == 2
                && proc.arguments[0].name == "library"
                && proc.arguments[1].name == "function"
                && proc.bytecode.as_deref() == Some(&[0x11, 0x10][..])
                && proc.source_info.iter().any(|info| {
                    info.file
                        .and_then(|id| self.input.strings.get(id))
                        .is_some_and(|path| {
                            let path = path.replace('\\', "/");
                            path.contains("/od_probe_") && path.ends_with("/overlay.dm")
                        })
                })
            {
                // The isolated OpenDream compiler probe inserts this stub to
                // parse Dream Maker's intrinsic load_ext. It is not in source.
                self.ids.procs.push(NONE);
                continue;
            }
            let unchanged = self.baseline.is_some_and(|base| {
                let authored_source = proc
                    .source_info
                    .iter()
                    .filter_map(|info| info.file)
                    .filter_map(|id| self.input.strings.get(id))
                    .any(|path| !base.strings.contains(path));
                !authored_source
                    && base.procs.iter().any(|native| {
                        let same_owner = base
                            .types
                            .get(native.owning_type_id)
                            .is_some_and(|t| t.path == owner.path);
                        same_owner
                            && native.name == proc.name
                            && native.attributes == proc.attributes
                            && native.is_verb == proc.is_verb
                            && native.verb_src == proc.verb_src
                            && native.verb_range == proc.verb_range
                            && native.verb_name == proc.verb_name
                            && native.verb_category == proc.verb_category
                            && native.verb_desc == proc.verb_desc
                            && native.invisibility == proc.invisibility
                            && native.explicit_invisibility == proc.explicit_invisibility
                            && native
                                .arguments
                                .iter()
                                .map(|a| (&a.name, a.r#type, a.explicit_anything))
                                .eq(proc
                                    .arguments
                                    .iter()
                                    .map(|a| (&a.name, a.r#type, a.explicit_anything)))
                    })
            });
            if unchanged || (self.baseline.is_none() && self.is_native_path(&owner.path)) {
                self.ids.procs.push(NONE);
                continue;
            }
            if self.input.type_inherits_path(proc.owning_type_id, "/atom")
                || self
                    .input
                    .type_inherits_path(proc.owning_type_id, "/client")
            {
                let (flags, extended) = match proc.name.as_str() {
                    "Click" => (0x4, 0),
                    "DblClick" => (0x8, 0),
                    "MouseUp" => (0x0020_0000, 0),
                    "MouseDown" => (0x0040_0000, 0),
                    "MouseDrop" => (0x0080_0000, 0),
                    "MouseDrag" => (0x0100_0000, 0),
                    "MouseEntered" | "MouseExited"
                        if self
                            .input
                            .type_inherits_path(proc.owning_type_id, "/client") =>
                    {
                        (0x0200_0000, 0)
                    }
                    "MouseMove"
                        if self
                            .input
                            .type_inherits_path(proc.owning_type_id, "/client") =>
                    {
                        (0x8200_0000, 1)
                    }
                    "MouseWheel"
                        if self
                            .input
                            .type_inherits_path(proc.owning_type_id, "/client") =>
                    {
                        (0x8000_0000, 2)
                    }
                    "Command"
                        if self
                            .input
                            .type_inherits_path(proc.owning_type_id, "/client") =>
                    {
                        (0x4000, 0)
                    }
                    "IsByondMember"
                        if self
                            .input
                            .type_inherits_path(proc.owning_type_id, "/client") =>
                    {
                        (0x0004_0000, 0)
                    }
                    _ => (0, 0),
                };
                self.dmb.header.flags |= flags;
                if extended != 0 {
                    self.dmb.header.extended_flags =
                        Some(self.dmb.header.extended_flags.unwrap_or(0) | extended);
                }
            }
            if proc.bytecode.is_none() {
                return Err(EmitError::Unsupported(format!(
                    "authored procedure {}{} has no OpenDream bytecode",
                    owner.path, proc.name
                )));
            }
            if proc.attributes & !(0x2 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80) != 0 {
                return Err(EmitError::Unsupported(format!(
                    "procedure {} has unsupported OpenDream attributes {:#x}",
                    proc.name, proc.attributes
                )));
            }
            if proc.name != "<init>" {
                let bound = if owner.path == "/" {
                    self.input.global_procs.contains(&od_index)
                } else {
                    owner.procs.iter().flatten().any(|&id| id == od_index)
                };
                if !bound {
                    if owner.path == "/" && proc.attributes & 2 != 0 {
                        // These bodies do not replace the named global binding,
                        // but authored unqualified paths can reference them.
                        if unchanged {
                            self.ids.procs.push(NONE);
                            continue;
                        }
                    } else {
                        return Err(EmitError::Invalid(format!(
                            "procedure {} is absent from owner table",
                            proc.name
                        )));
                    }
                }
                // `Type.Verbs` describes the exposed verb set, not the
                // syntactic declaration kind. Datum verbs may be absent from
                // it, while overridden client movement commands appear in it
                // as ordinary procs. `Proc.IsVerb` drives DMB binding.
            }
            let path = if owner.path == "/"
                && proc.attributes & 2 != 0
                && !self.input.global_procs.contains(&od_index)
            {
                format!("/{}", proc.name)
            } else if owner.path == "/" {
                format!(
                    "/{}/{}",
                    if proc.is_verb { "verb" } else { "proc" },
                    proc.name
                )
            } else if (proc.attributes & 2 != 0
                && self.baseline.is_some_and(|base| {
                    base.procs.iter().any(|native| {
                        native.name == proc.name
                            && base
                                .types
                                .get(native.owning_type_id)
                                .is_some_and(|typ| typ.path == owner.path)
                    })
                }))
                || proc.name == "New"
                || proc.name == "Del"
                || self.inherits_proc(proc.owning_type_id, &proc.name)
                || owner.procs.iter().flatten().any(|&earlier| {
                    earlier < od_index
                        && self.input.procs.get(earlier).is_some_and(|previous| {
                            previous.name == proc.name && previous.is_verb == proc.is_verb
                        })
                })
            {
                format!("{}/{}", owner.path, proc.name)
            } else if proc.is_verb {
                format!("{}/verb/{}", owner.path, proc.name)
            } else {
                format!("{}/proc/{}", owner.path, proc.name)
            };
            let metadata = self.resolved_verb_metadata(od_index);
            let is_initializer = proc.name == "<init>";
            let path_id = if is_initializer {
                NONE
            } else {
                self.string(&path)
            };
            let display = if is_initializer {
                NONE
            } else {
                self.string(
                    &metadata
                        .name
                        .as_deref()
                        .map(str::to_owned)
                        .unwrap_or_else(|| proc.name.replace('_', " ")),
                )
            };
            let category = metadata
                .category
                .as_deref()
                .map(|s| self.string(s))
                .unwrap_or(NONE);
            let desc = metadata
                .desc
                .as_deref()
                .map(|s| self.string(s))
                .unwrap_or(NONE);
            let code = self.list(vec![12, 0]); // Ret; End, replaced by bytecode lowering.
            let mut locals_by_add = Vec::new();
            let mut compile_time_consts: HashMap<&str, usize> = HashMap::new();
            if let Some(globals) = &self.input.globals {
                for declaration in &globals.compile_time_const_declarations {
                    if declaration.proc_id == od_index {
                        *compile_time_consts.entry(&declaration.name).or_default() += 1;
                    }
                }
            }
            for event in &proc.locals {
                if let Some(name) = &event.add {
                    if let Some(remaining) = compile_time_consts.get_mut(name.as_str()) {
                        if *remaining > 0 {
                            *remaining -= 1;
                            locals_by_add.push(None);
                            continue;
                        }
                    }
                    let variable = self.procedure_variable(name);
                    locals_by_add.push(Some(variable));
                }
            }
            let mut locals = Vec::new();
            let mut seen = HashSet::new();
            for &ordinal in &proc.lexical_local_add_indices {
                if !seen.insert(ordinal) {
                    return Err(EmitError::Invalid(format!(
                        "procedure {} repeats lexical local Add ordinal {ordinal}",
                        proc.name
                    )));
                }
                let slot = locals_by_add.get_mut(ordinal).ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "procedure {} has lexical local Add ordinal {ordinal} out of range",
                        proc.name
                    ))
                })?;
                if let Some(variable) = slot.take() {
                    locals.push(variable);
                }
            }
            locals.extend(locals_by_add.into_iter().flatten());
            let locals = self.list(locals);
            let mut args = Vec::new();
            for argument in &proc.arguments {
                if argument.native_omit {
                    continue;
                }
                let mut type_flags = argument_type_flags(argument, self.input)?;
                if argument.has_default
                    && (proc.is_verb || self.inherits_verb(proc.owning_type_id, &proc.name))
                {
                    // Native verb prompts permit cancellation for optional
                    // formals, including defaults other than null.
                    type_flags |= 0x80;
                }
                if type_flags == 0
                    && argument
                        .possible_values_proc
                        .and_then(|id| direct_argument_sources.get(&id))
                        == Some(&0x7f10)
                {
                    // `in world` supplies the atom selector for an untyped
                    // or `/datum` argument in Dream Maker.
                    type_flags = 0x123;
                }
                let variable = self.procedure_variable(&argument.name);
                self.new_args.push(variable);
                let value_source = if let Some(companion) = argument.possible_values_proc {
                    if let Some(&direct) = direct_argument_sources.get(&companion) {
                        args.extend([type_flags, direct, variable, 0]);
                        continue;
                    }
                    let reference_index = self.dmb.proc_references.len();
                    if reference_index > u8::MAX as usize {
                        return Err(EmitError::Unsupported(
                            "more than 256 argument source procedures".into(),
                        ));
                    }
                    self.dmb.proc_references.push(NONE);
                    pending_argument_sources.push((reference_index, companion));
                    ((reference_index as u32) << 8) | 0x40
                } else {
                    0x7d01
                };
                args.extend([type_flags, value_source, variable, 0]);
            }
            let args = self.list(args);
            // OpenDream's VerbSrc enum differs from Dream Maker's compact
            // source-kind byte. The paired `set src` fixture also shows that
            // explicit forms carry proc flag 0x2; `in` forms do not.
            let (source_kind, explicit_source) = match metadata.source {
                None => (0, false),
                Some(0) => (1, true),
                Some(1) => (1, false),
                Some(2) => (2, true),
                Some(3) => (2, false),
                Some(4) => (5, true),
                Some(5) => (5, false),
                Some(6) => (6, true),
                Some(7) => (6, false),
                Some(8) => (16, true),
                Some(9) => (16, false),
                Some(10) => (32, true),
                Some(11) => (8, false),
                Some(12) => (3, true),
                Some(13) => (4, true),
                Some(other) => {
                    return Err(EmitError::Unsupported(format!(
                        "procedure {} has unpaired verb source {other}",
                        proc.name
                    )))
                }
            };
            let explicit_source = proc
                .explicit_verb_source_was_in
                .map(|was_in| !was_in)
                .unwrap_or(explicit_source);
            let source_parameter = metadata.range.unwrap_or(match metadata.source {
                Some(0..=7) => 125,
                Some(8 | 9 | 11 | 13) => 127,
                _ => 255,
            });
            if !(0..=255).contains(&source_kind) || !(0..=255).contains(&source_parameter) {
                return Err(EmitError::Unsupported(format!(
                    "procedure {} has unsupported verb source/range",
                    proc.name
                )));
            }
            if metadata.invisibility < 0 {
                return Err(EmitError::Unsupported(format!(
                    "procedure {} has negative invisibility metadata",
                    proc.name
                )));
            }
            let mut flags = 4u32;
            if explicit_source {
                flags |= 2;
            }
            if metadata.attributes & 0x20 != 0 {
                flags &= !4; // set waitfor = FALSE
            }
            if metadata.attributes & 0x8 != 0 {
                flags |= 1; // set hidden = TRUE
            }
            if metadata.attributes & 0x10 != 0 {
                flags |= 0x40; // set popup_menu = FALSE
            }
            if metadata.category.is_none() && proc.explicit_verb_fields.contains("category") {
                flags |= 0x20; // set category = null
            }
            if metadata.attributes & 0x40 != 0 {
                flags |= 0x200; // set instant = TRUE
            }
            if metadata.attributes & 0x80 != 0 {
                flags |= 0x100; // set background = TRUE
            }
            let visibility_byte = if metadata.invisibility > 0 {
                flags |= 0x18;
                metadata.invisibility as u8
            } else if metadata.explicit_invisibility {
                // Authored zero still uses the extended form and sentinel 255.
                flags |= 0x8;
                255
            } else {
                0
            };
            let extended_flags =
                (flags > 0x7f || visibility_byte != 0).then_some((flags | 0x80, visibility_byte));
            self.reserve_proc_sentinel();
            let id = self.dmb.procs.len() as u32;
            self.dmb.procs.push(Proc {
                strings: [path_id, display, desc, category],
                source_parameter: source_parameter as u8,
                source_kind: source_kind as u8,
                flags: if extended_flags.is_some() {
                    0x80
                } else {
                    flags as u8
                },
                extended_flags,
                code_locals_args: [code, locals, args],
            });
            self.ids.procs.push(id);
        }
        for (reference_index, companion) in pending_argument_sources {
            self.dmb.proc_references[reference_index] =
                *self.ids.procs.get(companion).ok_or_else(|| {
                    EmitError::Invalid(format!(
                        "argument source procedure {companion} is out of range"
                    ))
                })?;
        }
        let implicit_empty_types: Vec<_> = self
            .input
            .types
            .iter()
            .enumerate()
            .filter_map(|(type_id, typ)| {
                (typ.implicit_empty_init_proc && typ.init_proc.is_none()).then_some(type_id)
            })
            .collect();
        for type_id in implicit_empty_types {
            let class_id = self.ids.classes[type_id];
            if class_id == NONE {
                return Err(EmitError::Invalid(format!(
                    "implicit empty initializer for {} has no DMB class",
                    self.input.types[type_id].path
                )));
            }
            let code = self.list(vec![0]);
            let locals = self.list(Vec::new());
            let args = self.list(Vec::new());
            self.reserve_proc_sentinel();
            let proc_id = self.dmb.procs.len() as u32;
            self.dmb.procs.push(Proc {
                strings: [NONE; 4],
                source_parameter: 255,
                source_kind: 0,
                flags: 4,
                extended_flags: None,
                code_locals_args: [code, locals, args],
            });
            self.dmb.classes[class_id as usize].lists_and_procs[2] = proc_id;
        }
        let mut world_procs = Vec::new();
        for (od_index, proc) in self.input.procs.iter().enumerate() {
            let id = self.ids.procs[od_index];
            if id == NONE {
                continue;
            }
            if argument_source_procs.contains(&od_index) {
                continue;
            }
            let owner = &self.input.types[proc.owning_type_id].path;
            if proc.name == "<init>" {
                let class_id = self.ids.classes[proc.owning_type_id];
                if class_id == NONE {
                    return Err(EmitError::Invalid(format!(
                        "initializer for {owner} has no class"
                    )));
                }
                self.dmb.classes[class_id as usize].lists_and_procs[2] = id;
                continue;
            }
            if owner == "/" {
                // Global procedures remain callable by ProcID; they are not
                // members of world.procs, including root-level verbs.
                continue;
            }
            if owner == "/world" {
                world_procs.push(id);
                continue;
            }
            let class_id = self.ids.classes[proc.owning_type_id];
            if class_id == NONE {
                return Err(EmitError::Invalid(format!(
                    "procedure {} has no class",
                    proc.name
                )));
            }
            let slot = if proc.is_verb || self.inherits_verb(proc.owning_type_id, &proc.name) {
                0
            } else {
                1
            };
            let old = self.dmb.classes[class_id as usize].lists_and_procs[slot];
            let mut values = if old == NONE {
                Vec::new()
            } else {
                self.dmb.lists[old as usize].clone()
            };
            values.push(id);
            let new = self.list(values);
            self.dmb.classes[class_id as usize].lists_and_procs[slot] = new;
        }
        if !world_procs.is_empty() {
            let old = self.dmb.world.ids[3];
            let mut values = if old == NONE {
                Vec::new()
            } else {
                self.dmb.lists[old as usize].clone()
            };
            values.extend(world_procs);
            self.dmb.world.ids[3] = self.list(values);
        }
        // Native allocates override bodies after declarations, then stores
        // each owner's method chain in descending allocation order.
        let membership_order = self
            .input
            .procs
            .iter()
            .enumerate()
            .filter_map(|(ordinal, proc_)| {
                let id = self.ids.procs[ordinal];
                (id != NONE).then_some((id, (proc_.attributes & 2 != 0, ordinal)))
            })
            .collect::<HashMap<_, _>>();
        let mut membership_lists = self
            .dmb
            .classes
            .iter()
            .flat_map(|class| [class.lists_and_procs[0], class.lists_and_procs[1]])
            .filter(|&id| id != NONE)
            .collect::<std::collections::BTreeSet<_>>();
        if self.dmb.world.ids[3] != NONE {
            membership_lists.insert(self.dmb.world.ids[3]);
        }
        let mut membership_remap = HashMap::new();
        for list in membership_lists {
            let mut values = self.dmb.lists[list as usize].clone();
            values.sort_by_key(|id| {
                std::cmp::Reverse(membership_order.get(id).copied().unwrap_or((false, 0)))
            });
            membership_remap.insert(list, self.list(values));
        }
        for class in &mut self.dmb.classes {
            for slot in 0..2 {
                if let Some(&new) = membership_remap.get(&class.lists_and_procs[slot]) {
                    class.lists_and_procs[slot] = new;
                }
            }
        }
        if let Some(&new) = membership_remap.get(&self.dmb.world.ids[3]) {
            self.dmb.world.ids[3] = new;
        }
        Ok(())
    }
    pub(super) fn inherits_proc(&self, owner_type_id: usize, name: &str) -> bool {
        let mut parent = self.input.types[owner_type_id].parent;
        while let Some(type_id) = parent {
            let typ = &self.input.types[type_id];
            if typ.procs.iter().flatten().any(|&id| {
                self.input
                    .procs
                    .get(id)
                    .is_some_and(|proc| proc.name == name)
            }) {
                return true;
            }
            parent = typ.parent;
        }
        false
    }
    pub(super) fn inherits_verb(&self, owner_type_id: usize, name: &str) -> bool {
        let mut parent = self.input.types[owner_type_id].parent;
        while let Some(type_id) = parent {
            let typ = &self.input.types[type_id];
            if typ.procs.iter().flatten().any(|&id| {
                self.input
                    .procs
                    .get(id)
                    .is_some_and(|proc| proc.name == name && proc.is_verb)
            }) {
                return true;
            }
            parent = typ.parent;
        }
        false
    }
    pub(super) fn previous_proc_definition(&self, index: usize) -> Option<usize> {
        let proc = self.input.procs.get(index)?;
        let owner = self.input.types.get(proc.owning_type_id)?;
        if let Some(previous) = owner
            .procs
            .iter()
            .flatten()
            .copied()
            .filter(|&candidate| {
                candidate < index
                    && self
                        .input
                        .procs
                        .get(candidate)
                        .is_some_and(|other| other.name == proc.name)
            })
            .max()
        {
            return Some(previous);
        }
        let mut parent = owner.parent;
        while let Some(type_id) = parent {
            let typ = self.input.types.get(type_id)?;
            if let Some(previous) = typ
                .procs
                .iter()
                .flatten()
                .copied()
                .filter(|&candidate| {
                    self.input
                        .procs
                        .get(candidate)
                        .is_some_and(|other| other.name == proc.name)
                })
                .max()
            {
                return Some(previous);
            }
            parent = typ.parent;
        }
        None
    }
    pub(super) fn original_proc_definition(&self, index: usize) -> usize {
        let mut original = index;
        while let Some(previous) = self.previous_proc_definition(original) {
            original = previous;
        }
        original
    }
    pub(super) fn resolved_verb_metadata(&self, index: usize) -> ResolvedVerbMetadata {
        let proc = &self.input.procs[index];
        let mut resolved = ResolvedVerbMetadata {
            attributes: proc.attributes | if proc.nested_background { 0x80 } else { 0 },
            name: proc
                .explicit_verb_text_values
                .get("name")
                .cloned()
                .unwrap_or_else(|| proc.verb_name.clone()),
            category: proc
                .explicit_verb_text_values
                .get("category")
                .cloned()
                .unwrap_or_else(|| proc.verb_category.clone()),
            desc: proc
                .explicit_verb_text_values
                .get("desc")
                .cloned()
                .unwrap_or_else(|| proc.verb_desc.clone()),
            source: proc.explicit_verb_source.or(proc.verb_src),
            range: proc.explicit_verb_range.or(proc.verb_range),
            invisibility: proc.invisibility,
            explicit_invisibility: proc.explicit_invisibility,
        };
        if let Some(previous) = self.previous_proc_definition(index) {
            let inherited = self.resolved_verb_metadata(previous);
            for (field, bit) in [
                ("hidden", 0x8),
                ("popup_menu", 0x10),
                ("waitfor", 0x20),
                ("instant", 0x40),
                ("background", 0x80),
            ] {
                if let Some(&enabled) = proc.explicit_verb_field_values.get(field) {
                    let flag_set = if field == "popup_menu" || field == "waitfor" {
                        !enabled
                    } else {
                        enabled
                    };
                    if flag_set {
                        resolved.attributes |= bit;
                    } else {
                        resolved.attributes &= !bit;
                    }
                } else if !proc.explicit_verb_fields.contains(field) {
                    resolved.attributes |= inherited.attributes & bit;
                }
            }
            // Dream Maker takes waitfor's default from the original proc
            // declaration, even when an intermediate subtype override sets
            // waitfor differently. The current proc's explicit set wins.
            if !proc.explicit_verb_fields.contains("waitfor")
                && !proc.explicit_verb_field_values.contains_key("waitfor")
            {
                let original = self.original_proc_definition(index);
                let original_waitfor = self.input.procs[original].attributes & 0x20;
                resolved.attributes = (resolved.attributes & !0x20) | original_waitfor;
            }
            if !proc.explicit_verb_fields.contains("name") && resolved.name.is_none() {
                resolved.name = inherited.name;
            }
            if !proc.explicit_verb_fields.contains("category") && resolved.category.is_none() {
                resolved.category = inherited.category;
            }
            if !proc.explicit_verb_fields.contains("desc") && resolved.desc.is_none() {
                resolved.desc = inherited.desc;
            }
            if resolved.source.is_none() && proc.explicit_verb_source.is_none() {
                resolved.source = inherited.source;
            }
            if resolved.range.is_none() && proc.explicit_verb_range.is_none() {
                resolved.range = inherited.range;
            }
            if !proc.explicit_verb_fields.contains("invisibility")
                && !resolved.explicit_invisibility
            {
                resolved.invisibility = inherited.invisibility;
                resolved.explicit_invisibility = inherited.explicit_invisibility;
            }
        }
        resolved
    }
}
