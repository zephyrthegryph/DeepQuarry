//! Numeric procedure frame contributions on the existing admitted recipe owner.
use super::procedure_plan::{PreparedMetadata, ProcedureMetadata};
use super::*;
use crate::symbolic::FrozenUnit;
use std::sync::Arc;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Frontier {
    variables: usize,
}
impl Frontier {
    fn current(dmb: &Dmb) -> Self {
        Self {
            variables: dmb.variables.len(),
        }
    }
}
struct StringAssignment {
    bytes: Arc<[u8]>,
    index: u32,
}
pub(super) struct FrameContribution {
    start: Frontier,
    declared: bool,
    identity: crate::lowering::UnitIdentity,
    local_count: u32,
    locals_names: Vec<String>,
    argument_names: Vec<String>,
    argument_flags: Vec<u32>,
    abi: Arc<crate::procedure_policy::PreparedAbi>,
    path: Arc<str>,
    display: Arc<str>,
    strings: Vec<StringAssignment>,
    variables: Vec<Variable>,
    locals: Arc<Vec<u32>>,
    arguments: Arc<Vec<u32>>,
    procedure: Proc,
}
impl FrameContribution {
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        let owner = "procedure_metadata.frame";
        census.vec_payload(owner, &self.locals_names);
        census.vec_payload(owner, &self.argument_names);
        for name in self.locals_names.iter().chain(&self.argument_names) {
            census.exposed_buffer(owner, name.as_ptr() as usize, name.len(), name.capacity());
        }
        census.vec_payload(owner, &self.argument_flags);
        census.vec_payload(owner, &self.variables);
        census.vec_payload(owner, &self.strings);
        for request in &self.strings {
            census.slice(owner, &request.bytes, true);
        }
        census.arc_text(owner, &self.path);
        census.arc_text(owner, &self.display);
        for words in [&self.locals, &self.arguments] {
            if census.arc_object(owner, words) {
                census.vec_payload(owner, words);
            }
        }
        census.abi(&self.abi);
    }
    pub(super) fn admit_current_metadata(
        &self,
        unit: &FrozenUnit,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &dm_link::ArgumentSourceReferences,
    ) -> bool {
        let Some(abi) = unit.lowered.abi.as_ref() else {
            return false;
        };
        let frame = &unit.lowered.frame;
        let declared = projection.map_or(Some(true), |plan| {
            plan.procedure_declarations
                .get(&crate::symbolic::unit_key(unit.lowered.identity))
                .copied()
        });
        if declared != Some(self.declared)
            || symbols.text(unit.lowered.identity.owner).is_none()
            || symbols.text(unit.lowered.identity.name).is_none()
            || self.identity != unit.lowered.identity
            || self.local_count != frame.local_count
            || self.locals_names != frame.local_names
            || self.argument_names != frame.argument_names
            || self.argument_flags != frame.argument_type_flags
            || **abi != *self.abi
            || frame.argument_names.len() != frame.argument_type_flags.len()
            || frame.argument_names.len() != abi.argument_sources.len()
            || frame.local_count as usize != frame.local_names.len()
        {
            return false;
        }
        abi.argument_sources
            .iter()
            .zip(self.arguments.chunks_exact(4))
            .all(|(source, row)| {
                use dm_codegen_byond::procedure_abi::ArgumentSource;
                let value = match source {
                    ArgumentSource::Builtin { kind, parameter } => {
                        Some(u32::from(*kind) | (u32::from(*parameter) << 8))
                    }
                    ArgumentSource::Helper { argument } => u32::try_from(*argument)
                        .ok()
                        .and_then(|argument| {
                            references
                                .index(crate::symbolic::helper_key(unit.lowered.identity, argument))
                        })
                        .map(|position| 0x40 | (u32::from(position) << 8)),
                };
                value == Some(row[1])
            })
    }
    fn metadata(&self) -> ProcedureMetadata {
        ProcedureMetadata {
            declared: Some(self.declared),
            path: Ok(Arc::clone(&self.path)),
            default_display: Ok(Arc::clone(&self.display)),
            value_sources: self
                .arguments
                .chunks_exact(4)
                .map(|row| Ok(row[1]))
                .collect(),
        }
    }
    fn output_matches(&self, dmb: &Dmb, index: &StringIndex) -> bool {
        // Procedure/list IDs are rebound during emission. Only local/argument
        // rows embed append-position VarIDs; string bindings are checked below.
        if !self.variables.is_empty() && self.start.variables != dmb.variables.len() {
            return false;
        }
        let mut next = dmb.strings.len();
        for (position, request) in self.strings.iter().enumerate() {
            let actual = index.lookup(dmb, &request.bytes).or_else(|| {
                self.strings[..position]
                    .iter()
                    .find(|prior| prior.bytes == request.bytes)
                    .map(|prior| prior.index)
            });
            let actual = match actual {
                Some(id) => id,
                None => {
                    while u32::try_from(next)
                        .ok()
                        .is_some_and(dm_link::is_reserved_string_index)
                    {
                        next += 1;
                    }
                    let Ok(id) = u32::try_from(next) else {
                        return false;
                    };
                    next += 1;
                    id
                }
            };
            if actual != request.index {
                return false;
            }
        }
        true
    }
    fn admits(
        &self,
        dmb: &Dmb,
        unit: &FrozenUnit,
        metadata: &ProcedureMetadata,
        index: &StringIndex,
    ) -> bool {
        let frame = &unit.lowered.frame;
        if metadata.declared != Some(self.declared)
            || self.identity != unit.lowered.identity
            || self.local_count != frame.local_count
            || self.locals_names != frame.local_names
            || self.argument_names != frame.argument_names
            || self.argument_flags != frame.argument_type_flags
            || unit
                .lowered
                .abi
                .as_ref()
                .is_none_or(|abi| **abi != *self.abi)
            || !metadata
                .path
                .as_ref()
                .is_ok_and(|x| x.as_ref() == self.path.as_ref())
            || !metadata
                .default_display
                .as_ref()
                .is_ok_and(|x| x.as_ref() == self.display.as_ref())
            || metadata.value_sources.len() != self.argument_names.len()
            || metadata
                .value_sources
                .iter()
                .zip(self.arguments.chunks_exact(4))
                .any(|(source, row)| !source.as_ref().is_ok_and(|x| *x == row[1]))
        {
            return false;
        }
        self.output_matches(dmb, index)
    }
}
fn record_string(
    rows: &mut Option<Vec<StringAssignment>>,
    index: &mut StringIndex,
    dmb: &mut Dmb,
    bytes: &[u8],
) -> Result<u32, CompositionError> {
    let id = index.intern(dmb, bytes)?;
    if let Some(rows) = rows {
        rows.push(StringAssignment {
            bytes: bytes.into(),
            index: id,
        });
    }
    Ok(id)
}
pub(super) fn emit(
    dmb: &mut Dmb,
    string_index: &mut StringIndex,
    unit: &FrozenUnit,
    linked_words: Arc<Vec<u32>>,
    metadata: impl Into<PreparedMetadata>,
    retain_frames: bool,
) -> Result<(), CompositionError> {
    let abi = unit
        .lowered
        .abi
        .as_ref()
        .ok_or_else(|| unsupported("procedure ABI was not authoritative"))?;
    // Current code binding precedes frame admission and deferred metadata errors.
    let code_id = append_list(dmb, linked_words)?;
    let start = Frontier::current(dmb);
    let (hit, metadata) = match metadata.into() {
        PreparedMetadata::Retained(hit) => (Some(Arc::clone(&hit)), None),
        PreparedMetadata::Fresh(metadata) => (None, Some(metadata)),
    };
    let hit = hit.or_else(|| {
        retain_frames
            .then(|| {
                unit.metadata_recipe
                    .frame_owner()
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone()
            })
            .flatten()
    });
    if let Some(hit) = hit.as_ref().filter(|hit| {
        metadata.as_ref().map_or_else(
            || hit.output_matches(dmb, string_index),
            |metadata| hit.admits(dmb, unit, metadata, string_index),
        )
    }) {
        for request in &hit.strings {
            let id = string_index.intern(dmb, &request.bytes)?;
            debug_assert_eq!(id, request.index);
        }
        dmb.variables.extend(hit.variables.iter().cloned());
        let locals = append_list(dmb, Arc::clone(&hit.locals))?;
        let arguments = append_list(dmb, Arc::clone(&hit.arguments))?;
        let mut procedure = hit.procedure.clone();
        procedure.code_locals_args = [code_id, locals, arguments];
        dmb.procs.push(procedure);
        return Ok(());
    }
    let metadata = metadata.unwrap_or_else(|| hit.expect("retained metadata owner").metadata());
    let declared = metadata.declared;
    let admitted_path = retain_frames
        .then(|| metadata.path.as_ref().ok().cloned())
        .flatten();
    let admitted_display = retain_frames
        .then(|| metadata.default_display.as_ref().ok().cloned())
        .flatten();
    let mut strings = retain_frames.then(Vec::new);

    let proc = &unit.lowered.frame;

    let mut first_local = 0;
    for (local, name) in proc.local_names.iter().enumerate() {
        let name_id = record_string(&mut strings, string_index, dmb, name.as_bytes())?;
        let variable_id = u32::try_from(dmb.variables.len())
            .map_err(|_| unsupported("variable record overflow"))?;
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name: name_id,
        });
        if local == 0 {
            first_local = variable_id;
        }
    }
    let locals = unit
        .metadata_recipe
        .local_list(first_local, proc.local_names.len());
    let locals_id = append_list(dmb, Arc::clone(&locals))?;
    let mut first_argument = 0;
    let mut resolved_sources = Vec::with_capacity(proc.argument_names.len());
    let mut value_sources = metadata.value_sources.into_iter();
    for (argument, name) in proc.argument_names.iter().enumerate() {
        let name_id = record_string(&mut strings, string_index, dmb, name.as_bytes())?;
        let variable_id = u32::try_from(dmb.variables.len())
            .map_err(|_| unsupported("argument record overflow"))?;
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name: name_id,
        });
        let value_source = value_sources
            .next()
            .expect("prepared argument count checked")?;
        if argument == 0 {
            first_argument = variable_id;
        }
        resolved_sources.push(value_source);
    }
    let args = unit.metadata_recipe.argument_list(
        first_argument,
        &proc.argument_type_flags,
        resolved_sources,
    );
    let args_id = append_list(dmb, Arc::clone(&args))?;
    let path = metadata.path?;
    let path_id = record_string(&mut strings, string_index, dmb, path.as_bytes())?;
    let default_display = metadata.default_display?;
    let display = abi
        .layout
        .display_name
        .as_deref()
        .unwrap_or(default_display.as_bytes());
    let display_id = record_string(&mut strings, string_index, dmb, display)?;
    let description_id = match &abi.layout.description {
        Some(value) => record_string(&mut strings, string_index, dmb, value)?,
        None => NONE,
    };
    let category_id = match &abi.layout.category {
        Category::Text(value) => record_string(&mut strings, string_index, dmb, value)?,
        Category::Default | Category::Null => NONE,
    };
    let (flags, extended_flags) = abi.layout.encoded_flags();
    let procedure = Proc {
        strings: [path_id, display_id, description_id, category_id],
        source_parameter: abi.layout.source_parameter,
        source_kind: abi.layout.source_kind,
        flags,
        extended_flags,
        code_locals_args: [code_id, locals_id, args_id],
    };
    if !retain_frames {
        dmb.procs.push(procedure);
        return Ok(());
    }
    dmb.procs.push(procedure.clone());
    let retained = Arc::new(FrameContribution {
        start,
        declared: declared.expect("successful declaration admission"),
        identity: unit.lowered.identity,
        local_count: proc.local_count,
        locals_names: proc.local_names.clone(),
        argument_names: proc.argument_names.clone(),
        argument_flags: proc.argument_type_flags.clone(),
        abi: Arc::clone(abi),
        path: admitted_path.expect("successful path"),
        display: admitted_display.expect("successful display"),
        strings: strings.expect("retained string recorder"),
        variables: dmb.variables[start.variables..].to_vec(),
        locals,
        arguments: args,
        procedure,
    });
    *unit
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap_or_else(|e| e.into_inner()) = Some(retained);
    Ok(())
}
