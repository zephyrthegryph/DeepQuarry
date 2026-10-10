//! Encoded executable ownership. Current provenance and table certificates are absent.
use super::*;
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
pub(crate) fn plain_instance_licensed(
    alias: SymbolId,
    plain: &[(SymbolId, SymbolId)],
    bindings: crate::lowering::DiskReplayBindings<'_>,
) -> bool {
    let reference = SymRef::Instance(alias);
    plain
        .binary_search_by_key(&alias, |(alias, _)| *alias)
        .is_ok()
        && (bindings.source.contains(&reference)
            || bindings.external.references.contains(&reference))
}

#[derive(Serialize, Deserialize)]
struct StringWire<'a> {
    id: SymbolId,
    #[serde(borrow)]
    bytes: Cow<'a, [u8]>,
}
#[derive(Serialize, Deserialize)]
pub(crate) struct Encoded<'a> {
    warnings: crate::lowering_memo_compact::BoundedVec<dm_codegen_byond::ProcedureWarning>,
    #[serde(borrow)]
    words: Cow<'a, [u8]>,
    relocations: crate::lowering_memo_compact::BoundedVec<(u32, SymRef, Option<u8>)>,
    #[serde(borrow)]
    labels: Cow<'a, [u8]>,
    local_count: u32,
    #[serde(borrow)]
    locals: crate::lowering_memo_compact::BoundedVec<Cow<'a, str>>,
    #[serde(borrow)]
    arguments: crate::lowering_memo_compact::BoundedVec<Cow<'a, str>>,
    flags: crate::lowering_memo_compact::BoundedVec<u32>,
    #[serde(borrow)]
    strings: crate::lowering_memo_compact::BoundedVec<StringWire<'a>>,
    slots: crate::lowering_memo_compact::BoundedVec<(SymbolId, SymbolId, SymbolId)>,
    #[serde(borrow)]
    prefix: Cow<'a, [u8]>,
    #[serde(borrow)]
    suffix: Cow<'a, [u8]>,
}
impl ReusableProcedureArtifact {
    pub(crate) fn disk_instances(&self) -> &[(SymbolId, SymbolId)] {
        &self.instances
    }
    pub(crate) fn disk_abi(&self) -> Option<Vec<u8>> {
        Some(self.abi.as_ref()?.canonical_bytes())
    }
    pub(crate) fn disk_encoded(&self) -> Option<Encoded<'_>> {
        Encoded::capture(
            &self.warnings,
            &self.frozen,
            &self.frame,
            self.inventory.strings(),
            self.inventory.slots(),
            &self.inventory.entry().content,
        )
    }
    pub(crate) fn disk_helpers(&self) -> Option<Vec<HelperWire<'_>>> {
        self.helpers
            .iter()
            .map(|helper| {
                Some(HelperWire {
                    argument: helper.argument,
                    code: Encoded::capture_helper(helper)?,
                    instances: crate::lowering_memo_compact::BoundedVec(helper.instances.clone()),
                })
            })
            .collect()
    }
    pub(crate) fn disk_type_requests_with_modified(
        &self,
        recipes: &[crate::modified_initializers::RecipeWire<'_>],
    ) -> Vec<SymbolId> {
        fn append(code: &FrozenProc, out: &mut Vec<SymbolId>) {
            out.extend(code.code().relocations().filter_map(|r| match r.reference {
                SymRef::Type(id) => Some(id),
                _ => None,
            }));
        }
        let mut requests = Vec::new();
        append(&self.frozen, &mut requests);
        requests.extend(self.instances.iter().map(|(_, runtime)| *runtime));
        let modified: std::collections::BTreeMap<_, _> = recipes
            .iter()
            .map(|r| (r.reference(), r.runtime_type()))
            .collect();
        requests.extend(modified.into_values());
        for helper in &self.helpers {
            append(&helper.frozen, &mut requests);
            requests.extend(helper.instances.iter().map(|(_, runtime)| *runtime));
        }
        requests
    }
}
#[derive(Serialize, Deserialize)]
pub(crate) struct HelperWire<'a> {
    pub(crate) argument: u32,
    #[serde(borrow)]
    code: Encoded<'a>,
    instances: crate::lowering_memo_compact::BoundedVec<(SymbolId, SymbolId)>,
}
impl HelperWire<'_> {
    pub(crate) fn instances(&self) -> &[(SymbolId, SymbolId)] {
        &self.instances.0
    }
    #[cfg(test)]
    pub(crate) fn corrupt_instance_runtime(&mut self) {
        self.instances.0[0].1 = SymbolId::of("/datum");
    }
}
impl<'a> Encoded<'a> {
    #[cfg(test)]
    pub(crate) fn corrupt_warning_ordinal(&mut self, ordinal: Option<u32>) {
        self.warnings.0[0].source_ordinal = ordinal;
    }
    #[cfg(test)]
    pub(crate) fn corrupt_warning_name(&mut self) {
        self.warnings.0[0].name = Some(SymbolId::of("absent warning name"));
    }

    fn capture_helper(helper: &'a HelperArtifact) -> Option<Self> {
        if helper
            .frozen
            .code()
            .relocations()
            .any(|r| matches!(r.reference, SymRef::Instance(alias) if helper.instances.binary_search_by_key(&alias, |(id, _)| *id).is_err()))
        {
            return None;
        }
        Self::capture_fields(
            &helper.warnings,
            &helper.frozen,
            helper.local_names.len().try_into().ok()?,
            &helper.local_names,
            &[],
            &[],
            helper.inventory.strings(),
            helper.inventory.slots(),
            &helper.inventory.entry().content,
        )
    }
    fn capture(
        warnings: &[dm_codegen_byond::ProcedureWarning],
        frozen: &'a FrozenProc,
        frame: &'a FrozenFrame,
        strings: &'a [dm_ir::StringPayload],
        slots: &'a [SlotAlias],
        content: &'a dm_link::EntryContent,
    ) -> Option<Self> {
        Self::capture_fields(
            warnings,
            frozen,
            frame.local_count,
            &frame.local_names,
            &frame.argument_names,
            &frame.argument_type_flags,
            strings,
            slots,
            content,
        )
    }
    #[allow(clippy::too_many_arguments)]
    fn capture_fields(
        warnings: &[dm_codegen_byond::ProcedureWarning],
        frozen: &'a FrozenProc,
        local_count: u32,
        locals: &'a [String],
        arguments: &'a [String],
        flags: &[u32],
        strings: &'a [dm_ir::StringPayload],
        slots: &'a [SlotAlias],
        content: &'a dm_link::EntryContent,
    ) -> Option<Self> {
        let dm_link::EntryContent::Symbolic(content) = content else {
            return None;
        };
        let (prefix, _, suffix) = content.parts();
        let mut words = Vec::with_capacity(frozen.code().words().len().checked_mul(4)?);
        for word in frozen.code().words() {
            words.extend_from_slice(&word.to_le_bytes());
        }
        let mut labels = Vec::with_capacity(frozen.labels().len().checked_mul(5)?);
        for label in frozen.labels() {
            labels.push(u8::from(label.is_some()));
            labels.extend_from_slice(&label.unwrap_or(0).to_le_bytes());
        }
        Some(Encoded {
            warnings: crate::lowering_memo_compact::BoundedVec(warnings.to_vec()),
            words: Cow::Owned(words),
            labels: Cow::Owned(labels),
            relocations: crate::lowering_memo_compact::BoundedVec(
                frozen
                    .code()
                    .relocations()
                    .map(|r| {
                        (
                            r.offset,
                            r.reference,
                            match r.encoding {
                                dm_ir::RelocationEncoding::Direct => None,
                                dm_ir::RelocationEncoding::PackedValue24 { tag } => Some(tag),
                            },
                        )
                    })
                    .collect(),
            ),
            local_count,
            locals: crate::lowering_memo_compact::BoundedVec(
                locals.iter().map(|s| Cow::Borrowed(s.as_str())).collect(),
            ),
            arguments: crate::lowering_memo_compact::BoundedVec(
                arguments
                    .iter()
                    .map(|s| Cow::Borrowed(s.as_str()))
                    .collect(),
            ),
            flags: crate::lowering_memo_compact::BoundedVec(flags.to_vec()),
            strings: crate::lowering_memo_compact::BoundedVec(
                strings
                    .iter()
                    .map(|s| StringWire {
                        id: s.id,
                        bytes: Cow::Borrowed(s.bytes.as_ref()),
                    })
                    .collect(),
            ),
            slots: crate::lowering_memo_compact::BoundedVec(
                slots.iter().map(|s| (s.symbol, s.owner, s.name)).collect(),
            ),
            prefix: Cow::Borrowed(prefix),
            suffix: Cow::Borrowed(suffix),
        })
    }
}
impl Encoded<'_> {
    #[cfg(test)]
    pub(crate) fn corrupt_string(&mut self) {
        self.strings.0[0].id = SymbolId::of("forged string payload");
    }
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn restore(
        self,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        prepared: &crate::procedure_policy::PreparedUnit,
        bindings: crate::lowering::DiskReplayBindings<'_>,
        debug_count: usize,
        instances: &std::collections::BTreeSet<SymRef>,
        plain: &[(SymbolId, SymbolId)],
    ) -> Option<Arc<ReusableProcedureArtifact>> {
        self.restore_mode(
            frontend,
            body,
            prepared,
            bindings,
            debug_count,
            false,
            instances,
            plain,
        )
    }
    #[allow(clippy::too_many_arguments)]
    fn restore_mode(
        self,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        prepared: &crate::procedure_policy::PreparedUnit,
        bindings: crate::lowering::DiskReplayBindings<'_>,
        debug_count: usize,
        helper: bool,
        instances: &std::collections::BTreeSet<SymRef>,
        plain: &[(SymbolId, SymbolId)],
    ) -> Option<Arc<ReusableProcedureArtifact>> {
        if self.warnings.0.iter().any(|warning| {
            !crate::procedure_warnings::valid_receipt(warning, debug_count, |id| {
                self.locals
                    .0
                    .iter()
                    .any(|name| !name.is_empty() && SymbolId::of(name.as_ref()) == id)
            })
        }) {
            return None;
        }
        let source_len = body
            .expanded_span
            .end
            .checked_sub(body.expanded_span.start)?;
        let word_limit = source_len
            .checked_mul(64)?
            .checked_add(4096)?
            .min(2 * 1024 * 1024);
        if self.words.len() % 4 != 0
            || self.words.len() / 4 > word_limit
            || self.labels.len() % 5 != 0
            || self.labels.len() / 5 > word_limit
            || self.relocations.0.len() > self.words.len() / 4
        {
            return None;
        }
        let identity = crate::lowering::source_unit_identity(frontend, body)
            .ok()?
            .identity;
        let metadata = frontend
            .snapshot
            .tree
            .member(body.member)?
            .metadata
            .procedure
            .as_ref()?;
        if helper && (!self.arguments.0.is_empty() || !self.flags.0.is_empty()) {
            return None;
        }
        if !helper
            && (self.arguments.0.iter().map(|s| s.as_ref()).ne(prepared
                .inputs
                .parameters
                .iter()
                .map(String::as_str))
                || self.flags.0 != prepared.inputs.parameter_type_flags)
        {
            return None;
        }
        let strings: Vec<_> = self
            .strings
            .0
            .into_iter()
            .map(|s| dm_ir::StringPayload {
                id: s.id,
                bytes: s.bytes.into_owned().into(),
            })
            .collect();
        if strings.iter().any(|s| SymbolId::of_bytes(&s.bytes) != s.id) {
            return None;
        }
        let slots: Vec<_> = self
            .slots
            .0
            .into_iter()
            .map(|(symbol, owner, name)| SlotAlias {
                symbol,
                owner,
                name,
            })
            .collect();
        let mut licensed = std::collections::BTreeSet::new();
        licensed.insert(SymRef::BuiltinGlobalVars);
        licensed.extend(strings.iter().map(|s| SymRef::String(s.id)));
        licensed.extend(slots.iter().map(|s| SymRef::VariableSlot(s.symbol)));
        let mut selected_instances = std::collections::BTreeSet::new();
        let mut relocations = Vec::with_capacity(self.relocations.0.len());
        for (offset, reference, tag) in self.relocations.0 {
            let valid = match reference {
                SymRef::SourceFile(at) | SymRef::SourceLine(at) => (at as usize) < debug_count,
                SymRef::Instance(alias) => {
                    if instances.contains(&reference) {
                        selected_instances.insert(reference);
                        !helper
                    } else {
                        plain_instance_licensed(alias, plain, bindings)
                    }
                }
                _ => {
                    licensed.contains(&reference)
                        || bindings.source.contains(&reference)
                        || bindings.external.references.contains(&reference)
                }
            };
            if !valid {
                return None;
            }
            relocations.push(dm_ir::Relocation {
                offset,
                reference,
                encoding: tag.map_or(dm_ir::RelocationEncoding::Direct, |tag| {
                    dm_ir::RelocationEncoding::PackedValue24 { tag }
                }),
            });
        }
        // A current recipe licenses exactly the emitted descriptor roster. Extra
        // recipes would otherwise manufacture unused initializer contributions.
        if &selected_instances != instances {
            return None;
        }
        let words = self
            .words
            .chunks_exact(4)
            .map(|b| u32::from_le_bytes(b.try_into().unwrap()))
            .collect();
        let code = dm_ir::SymbolicCode::new(words, relocations).ok()?;
        let labels = self
            .labels
            .chunks_exact(5)
            .map(|b| match b[0] {
                0 if b[1..] == [0; 4] => Some(None),
                1 => Some(Some(u32::from_le_bytes(b[1..].try_into().unwrap()))),
                _ => None,
            })
            .collect::<Option<Vec<_>>>()?;
        let frozen = Arc::new(FrozenProc::restore(code, labels).ok()?);
        let frame = FrozenFrame {
            local_count: self.local_count,
            local_names: self.locals.0.into_iter().map(Cow::into_owned).collect(),
            argument_names: self.arguments.0.into_iter().map(Cow::into_owned).collect(),
            argument_type_flags: self.flags.0,
        };
        let expected = if helper {
            let mut prefix = b"dm-argument-source-v1\0".to_vec();
            prefix.extend_from_slice(&(frozen.code().canonical_len() as u64).to_le_bytes());
            let mut suffix = Vec::new();
            for name in &frame.local_names {
                suffix.extend_from_slice(&(name.len() as u64).to_le_bytes());
                suffix.extend_from_slice(name.as_bytes());
            }
            dm_link::EntryContent::symbolic(prefix.into(), frozen.shared_code(), suffix.into())
        } else {
            super::super::procedure_content_fields(
                prepared.abi.as_deref(),
                metadata,
                frame.local_count,
                &frame.local_names,
                &frame.argument_names,
                &frame.argument_type_flags,
                &prepared.inputs.parameter_value_sources,
                frozen.shared_code(),
            )
        };
        let dm_link::EntryContent::Symbolic(expected_parts) = &expected else {
            return None;
        };
        let (prefix, _, suffix) = expected_parts.parts();
        if self.prefix.as_ref() != prefix.as_ref() || self.suffix.as_ref() != suffix.as_ref() {
            return None;
        }
        let linked = frozen.code().link(|_| Some(0)).ok()?;
        let mut features = BytecodeFeatures::default();
        byond_dmb::bytecode::visit_instructions(
            &linked,
            |instruction| {
                use byond_dmb::bytecode::opcode;
                features.external |=
                    matches!(instruction.opcode, opcode::LOAD_EXT | opcode::CALL_EXT);
                features.debug |= matches!(instruction.opcode, opcode::DBG_FILE | opcode::DBG_LINE);
            },
            |_| {},
        )
        .ok()?;
        let recipe = crate::composition::ProcedureMetadataRecipe::capture(
            identity,
            frontend.snapshot.tree.symbols(),
            prepared.abi.as_deref(),
        )
        .ok()?;
        Some(Arc::new(ReusableProcedureArtifact {
            warnings: self.warnings.0.into(),
            identity,
            frozen,
            metadata_recipe: Arc::new(recipe),
            image_owner: Arc::new(Default::default()),
            features,
            frame: Arc::new(frame),
            abi: prepared.abi.clone(),
            inventory: Arc::new(
                dm_link::InventoryContribution::new(unit_key(identity), expected, slots)
                    .with_strings(strings),
            ),
            instances: plain.to_vec(),
            helpers: Vec::new(),
        }))
    }
}

impl ReusableProcedureArtifact {
    pub(crate) fn disk_bind_helpers(
        artifact: &mut Arc<Self>,
        helpers: Vec<HelperWire<'_>>,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        prepared: &crate::procedure_policy::PreparedUnit,
        bindings: crate::lowering::DiskReplayBindings<'_>,
    ) -> Option<()> {
        let abi = prepared.abi.as_ref()?;
        if helpers.len() != abi.source_helpers.len() {
            return None;
        }
        let identity = artifact.identity;
        let parsed = frontend.compact_body(body).ok()?;
        let metadata = frontend
            .snapshot
            .tree
            .member(body.member)?
            .metadata
            .procedure
            .as_ref()?;
        let context = crate::argument_sources::HelperInputs {
            frontend,
            parsed: parsed.into(),
            metadata,
            owner: identity,
            inputs: &prepared.inputs,
            helpers: &abi.source_helpers,
            symbols: frontend.snapshot.tree.symbols(),
        };
        let mut restored = Vec::with_capacity(helpers.len());
        for (helper, current) in helpers.into_iter().zip(&abi.source_helpers) {
            if helper.argument as usize != current.argument
                || helper.code.local_count as usize != helper.code.locals.0.len()
            {
                return None;
            }
            let debug =
                crate::argument_sources::current_helper_origins(&context, helper.argument).ok()?;
            let code = helper.code.restore_mode(
                frontend,
                body,
                prepared,
                bindings,
                debug.entries.len(),
                true,
                &std::collections::BTreeSet::new(),
                &helper.instances.0,
            )?;
            let code = Arc::try_unwrap(code).ok()?;
            restored.push(HelperArtifact {
                warnings: Arc::clone(&code.warnings),
                argument: helper.argument,
                frozen: code.frozen,
                image_owner: code.image_owner,
                features: code.features,
                local_names: Arc::new(Arc::try_unwrap(code.frame).ok()?.local_names),
                inventory: {
                    let (entry, slots, strings) = Arc::unwrap_or_clone(code.inventory).into_parts();
                    Arc::new(
                        dm_link::InventoryContribution::new(
                            helper_key(identity, helper.argument),
                            entry.content,
                            slots,
                        )
                        .with_strings(strings),
                    )
                },
                instances: code.instances,
            });
        }
        Arc::get_mut(artifact)?.helpers = restored;
        Some(())
    }
}
