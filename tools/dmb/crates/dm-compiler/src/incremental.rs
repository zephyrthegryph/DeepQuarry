//! Guarded incremental emission from an immutable linked world checkpoint.
//! Body edits preserve table IDs; declaration or semantic-context edits fall back.
use dm_codegen_byond::{LowerBindings, SharedLowerBindings, Symbol};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ProcedureCheckpoint {
    pub proc_id: u32,
    pub owner_path: String,
    pub source_digest: String,
    /// Inherited fields/types and shared project bindings are restored on demand.
    pub bindings: LowerBindings,
    pub patchable: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EmissionCheckpoint {
    pub abi_digest: String,
    pub procedures: BTreeMap<String, ProcedureCheckpoint>,
    pub shared: SharedLowerBindings,
    pub symbols: Vec<(Symbol, u32)>,
}
#[derive(Clone, Debug)]
pub struct ProcedureSource {
    pub source: std::sync::Arc<str>,
    pub digest: String,
    pub patchable: bool,
}
#[derive(Clone, Debug)]
pub struct SourceOutline {
    pub abi_digest: String,
    pub procedures: BTreeMap<String, ProcedureSource>,
}

use byond_dmb::dmb::{DmString, Dmb, Variable};
use dm_codegen_byond::{link_proc, Ledger, SimpleProc, Table};
use salsa::Setter;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::Arc;

const MAX_CHECKPOINT_BYTES: usize = 64 * 1024 * 1024;
const MAX_CHANGED_PROCS: usize = 128;
const MAX_QUERY_PROCS: usize = 32;
const MAX_QUERY_BYTES: usize = 16 * 1024 * 1024;

#[salsa::input]
struct ProcedureInput {
    #[returns(ref)]
    source: String,
    #[returns(ref)]
    bindings: LowerBindings,
    #[returns(ref)]
    shared: Arc<SharedLowerBindings>,
    #[returns(ref)]
    cache_root: Option<PathBuf>,
}

#[salsa::tracked(no_eq)]
fn lower_changed(db: &dyn crate::Db, input: ProcedureInput) -> Result<SimpleProc, String> {
    let source = input.source(db);
    let item = dm_syntax::parse_proc_at_span(
        source,
        dm_syntax::Span {
            start: 0,
            end: source.len(),
        },
    )
    .map_err(|error| format!("incremental procedure syntax: {error:?}"))?;
    let mut bindings = input.bindings(db).clone();
    bindings.shared = Some(Arc::clone(input.shared(db)));
    input
        .cache_root(db)
        .clone()
        .map(crate::lower_cache::ProcLoweringCache::open)
        .unwrap_or_else(crate::lower_cache::ProcLoweringCache::disabled)
        .compile(&item.children, &bindings)
        .map_err(|errors| format!("incremental lowering: {errors:?}"))
}

/// Bounded Salsa identities retained across body edits, never shared as disk keys.
#[derive(Default)]
pub struct IncrementalSession {
    db: crate::Database,
    inputs: BTreeMap<String, ProcedureInput>,
    bytes: usize,
    cache_root: Option<PathBuf>,
    baseline_identity: Option<String>,
    reference_counts: Option<(String, Vec<usize>)>,
}
impl IncrementalSession {
    /// The caller supplies the exact immutable DMB content digest, never an ABI
    /// digest or table count. Different full builds may share ABI and counts.
    pub fn set_baseline_identity(&mut self, identity: String) {
        if self.baseline_identity.as_ref() != Some(&identity) {
            self.reference_counts = None;
        }
        self.baseline_identity = Some(identity);
    }

    fn list_reference_counts(&mut self, dmb: &Dmb) -> Vec<usize> {
        if let Some((identity, counts)) = &self.reference_counts {
            if Some(identity) == self.baseline_identity.as_ref() && counts.len() == dmb.lists.len()
            {
                return counts.clone();
            }
        }
        let counts = list_reference_counts(dmb);
        if let Some(identity) = &self.baseline_identity {
            self.reference_counts = Some((identity.clone(), counts.clone()));
        }
        counts
    }
    pub fn set_cache_root(&mut self, root: PathBuf) {
        self.cache_root = Some(root);
    }
    fn compile(
        &mut self,
        path: &str,
        source: &str,
        mut bindings: LowerBindings,
        shared: Arc<SharedLowerBindings>,
    ) -> Result<SimpleProc, String> {
        bindings.shared = None;
        let bytes = source.len()
            + serde_json::to_vec(&bindings)
                .map_err(|error| error.to_string())?
                .len();
        if self.inputs.len() >= MAX_QUERY_PROCS
            || self.bytes.saturating_add(bytes) > MAX_QUERY_BYTES
        {
            let root = self.cache_root.clone();
            *self = Self::default();
            self.cache_root = root;
        }
        let input = if let Some(input) = self.inputs.get(path).copied() {
            input.set_source(&mut self.db).to(source.to_owned());
            input.set_bindings(&mut self.db).to(bindings);
            input.set_shared(&mut self.db).to(shared);
            input
                .set_cache_root(&mut self.db)
                .to(self.cache_root.clone());
            input
        } else {
            let input = ProcedureInput::new(
                &self.db,
                source.to_owned(),
                bindings,
                shared,
                self.cache_root.clone(),
            );
            self.inputs.insert(path.to_owned(), input);
            input
        };
        self.bytes = self.bytes.saturating_add(bytes);
        lower_changed(&self.db, input).clone()
    }
}

#[derive(Serialize, Deserialize)]
struct CheckpointEnvelope {
    version: u32,
    compiler: String,
    checksum: String,
    payload: String,
}
pub fn encode_checkpoint(checkpoint: &EmissionCheckpoint) -> Result<Vec<u8>, String> {
    let payload = serde_json::to_string(checkpoint).map_err(|error| error.to_string())?;
    if payload.len() > MAX_CHECKPOINT_BYTES {
        return Err("incremental checkpoint exceeds 64 MiB".into());
    }
    let envelope = CheckpointEnvelope {
        version: 1,
        compiler: env!("DM_LOWERING_FINGERPRINT").into(),
        checksum: digest(payload.as_bytes()),
        payload,
    };
    let bytes = serde_json::to_vec(&envelope).map_err(|error| error.to_string())?;
    if bytes.len() > MAX_CHECKPOINT_BYTES {
        return Err("incremental checkpoint envelope exceeds 64 MiB".into());
    }
    Ok(bytes)
}
pub fn decode_checkpoint(bytes: &[u8]) -> Option<EmissionCheckpoint> {
    if bytes.len() > MAX_CHECKPOINT_BYTES {
        return None;
    }
    let envelope: CheckpointEnvelope = serde_json::from_slice(bytes).ok()?;
    if envelope.version != 1
        || envelope.compiler != env!("DM_LOWERING_FINGERPRINT")
        || digest(envelope.payload.as_bytes()) != envelope.checksum
    {
        return None;
    }
    let mut checkpoint: EmissionCheckpoint = serde_json::from_str(&envelope.payload).ok()?;
    crate::lower_cache::prepare_member_type_fingerprints(&mut checkpoint.shared);
    checkpoint.shared.fingerprint =
        crate::lower_cache::shared_binding_fingerprint(&checkpoint.shared);
    Some(checkpoint)
}
pub fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

pub struct IncrementalEmission {
    pub dmb: Dmb,
    pub checkpoint: EmissionCheckpoint,
    pub changed_procs: usize,
    /// Every list record mutated by this emission, including appended records.
    pub changed_lists: Vec<u32>,
    pub total_procs: usize,
}

/// Returns None on any declaration/layout guard mismatch. The caller then performs a full build.
pub fn try_emit(
    source: &str,
    dmb: Dmb,
    checkpoint: EmissionCheckpoint,
    session: &mut IncrementalSession,
) -> Result<Option<IncrementalEmission>, String> {
    let outline = crate::bootstrap::incremental_source_outline(source)?;
    try_emit_outline(outline, dmb, checkpoint, session)
}

pub fn try_emit_outline(
    outline: SourceOutline,
    mut dmb: Dmb,
    mut checkpoint: EmissionCheckpoint,
    session: &mut IncrementalSession,
) -> Result<Option<IncrementalEmission>, String> {
    if outline.abi_digest != checkpoint.abi_digest
        || outline.procedures.len() != checkpoint.procedures.len()
    {
        return Ok(None);
    }
    let mut changes = Vec::new();
    for (path, proc_source) in &outline.procedures {
        let Some(old) = checkpoint.procedures.get(path) else {
            return Ok(None);
        };
        if old.source_digest != proc_source.digest {
            if !old.patchable || !proc_source.patchable {
                return Ok(None);
            }
            changes.push(path.clone());
        }
    }
    if changes.len() > MAX_CHANGED_PROCS {
        return Ok(None);
    }
    let shared = Arc::new(checkpoint.shared.clone());
    let mut base = checkpoint
        .symbols
        .iter()
        .cloned()
        .collect::<BTreeMap<_, _>>();
    // Existing procedure and class IDs stay fixed. New references may target any prior declaration.
    for (id, proc_) in dmb.procs.iter().enumerate() {
        if id == 0xffff {
            continue;
        }
        if let Some(path) = dmb
            .string(proc_.strings[0])
            .and_then(|bytes| std::str::from_utf8(bytes).ok())
        {
            base.entry(Symbol::new(Table::Proc, path))
                .or_insert(id as u32);
        }
    }
    let mut changed_lists = std::collections::BTreeSet::new();
    let mut references = session.list_reference_counts(&dmb);
    let cache_root = session.cache_root.clone();
    let mut emit_changes = |mut pool: Option<
        &mut crate::bootstrap::procedure_pipeline::LoweringPool,
    >|
     -> Result<(), String> {
        for batch in changes.chunks(2) {
            let mut prepared = Vec::with_capacity(2);
            let mut serial = Vec::with_capacity(2);
            for (ordinal, path) in batch.iter().enumerate() {
                let old = checkpoint.procedures.get(path).unwrap();
                let source = outline.procedures.get(path).unwrap();
                let mut bindings = old.bindings.clone();
                bindings.shared = Some(Arc::clone(&shared));
                crate::bootstrap::restore_owner_bindings(&dmb, &old.owner_path, &mut bindings)?;
                if let Some(pool) = pool.as_deref_mut() {
                    let item = dm_syntax::parse_proc_at_span(
                        &source.source,
                        dm_syntax::Span::new(0, source.source.len()),
                    )
                    .map_err(|error| format!("incremental procedure syntax: {error:?}"))?;
                    pool.submit(ordinal, item.children, bindings);
                } else {
                    serial.push(crate::bootstrap::procedure_pipeline::LoweringResult {
                        ordinal,
                        compiled: session
                            .compile(path, &source.source, bindings.clone(), Arc::clone(&shared))
                            .map_err(|reason| {
                                vec![dm_codegen_byond::LowerError {
                                    statement: path.clone(),
                                    reason,
                                }]
                            }),
                        bindings,
                    });
                }
                prepared.push(path);
            }
            let results = if let Some(pool) = pool.as_deref_mut() {
                pool.receive_batch(prepared.len())
            } else {
                serial
            };
            for (path, result) in prepared.into_iter().zip(results) {
                let old = checkpoint.procedures.get(path).unwrap();
                let source = outline.procedures.get(path).unwrap();
                let compiled = result
                    .compiled
                    .map_err(|errors| format!("incremental lowering {path}: {errors:?}"))?;
                let mut ledger = Ledger::default();
                bind_referenced_baseline_symbols(&compiled.code, &base, &mut ledger)?;
                for key in &compiled.strings {
                    let id = intern(&mut dmb, compiled.string_bytes(key));
                    ledger
                        .bind_alias(Symbol::new(Table::String, key), id)
                        .map_err(|error| error.to_string())?;
                }
                for class in &compiled.class_paths {
                    let symbol = Symbol::new(Table::Class, class);
                    if ledger.id(&symbol).is_none() {
                        let id = crate::bootstrap::incremental_class_link_id(&dmb, class)
                            .ok_or_else(|| format!("incremental type unavailable: {class}"))?;
                        ledger
                            .bind_alias(symbol, id)
                            .map_err(|error| error.to_string())?;
                    }
                }
                let linked =
                    link_proc(&compiled.code, &ledger).map_err(|error| error.to_string())?;
                if linked.words.len() > u16::MAX as usize {
                    return Err(format!("{path}: code exceeds DMB list limit"));
                }
                let proc_id = old.proc_id as usize;
                let proc_ = dmb
                    .procs
                    .get(proc_id)
                    .ok_or("checkpoint procedure ID missing")?;
                let old_code = proc_.code_locals_args[0];
                let old_locals = proc_.code_locals_args[1];
                let same_locals = dmb.lists.get(old_locals as usize).is_some_and(|locals| {
                    locals.len() == compiled.local_names.len()
                        && locals.iter().zip(&compiled.local_names).all(|(id, name)| {
                            dmb.variables
                                .get(*id as usize)
                                .and_then(|variable| dmb.string(variable.name))
                                == Some(name.as_bytes())
                        })
                });
                let locals = if same_locals {
                    old_locals
                } else {
                    let mut ids = Vec::new();
                    for local in &compiled.local_names {
                        let name = intern(&mut dmb, local.as_bytes());
                        let id = u32::try_from(dmb.variables.len())
                            .map_err(|_| "variable table exceeds 32 bits")?;
                        dmb.variables.push(Variable {
                            kind: 0,
                            value: 0,
                            name,
                        });
                        ids.push(id);
                    }
                    append_list(&mut dmb, ids)
                };
                // Unshared code retains its table ID even when its word count changes.
                // The indexed output writer can splice this position-independent record.
                let shared_code = references.get(old_code as usize).copied().unwrap_or(0) != 1;
                let code = if !shared_code && dmb.lists.get(old_code as usize).is_some() {
                    dmb.lists[old_code as usize] = linked.words;
                    old_code
                } else {
                    append_list(&mut dmb, linked.words)
                };
                changed_lists.insert(code);
                if locals != old_locals {
                    changed_lists.insert(locals);
                }
                let proc_ = &mut dmb.procs[proc_id];
                proc_.code_locals_args[0] = code;
                proc_.code_locals_args[1] = locals;
                if code != old_code {
                    replace_list_reference(&mut references, old_code, code);
                }
                if locals != old_locals {
                    replace_list_reference(&mut references, old_locals, locals);
                }
                checkpoint.procedures.get_mut(path).unwrap().source_digest = source.digest.clone();
            }
        }
        Ok(())
    };
    if changes.len() > 1 {
        let (result, _) = crate::bootstrap::procedure_pipeline::with_lowering_pool(
            cache_root.as_deref(),
            crate::bootstrap::procedure_pipeline::worker_count(),
            |pool| emit_changes(Some(pool)),
        );
        result?;
    } else {
        emit_changes(None)?;
    }
    crate::promote_object_ids(&mut dmb);
    dmb.validate_references()
        .map_err(|error| error.to_string())?;
    let total_procs = checkpoint.procedures.len();
    Ok(Some(IncrementalEmission {
        dmb,
        checkpoint,
        changed_procs: changes.len(),
        changed_lists: changed_lists.into_iter().collect(),
        total_procs,
    }))
}
fn bind_referenced_baseline_symbols(
    code: &dm_codegen_byond::SymbolicProc,
    baseline: &BTreeMap<Symbol, u32>,
    ledger: &mut Ledger,
) -> Result<(), String> {
    let mut used = std::collections::BTreeSet::new();
    code.for_each_reference(|table, name| {
        if table != Table::String {
            used.insert(Symbol::new(table, name));
        }
    });
    for symbol in used {
        if let Some(id) = baseline.get(&symbol) {
            ledger
                .bind_alias(symbol, *id)
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

fn list_reference_counts(dmb: &Dmb) -> Vec<usize> {
    let mut counts = vec![0usize; dmb.lists.len()];
    let mut mark = |id: u32| {
        if id != 0xffff {
            if let Some(count) = counts.get_mut(id as usize) {
                *count += 1;
            }
        }
    };
    for proc in &dmb.procs {
        for &id in &proc.code_locals_args {
            mark(id);
        }
    }
    for class in &dmb.classes {
        for id in [
            class.verb_list_id(),
            class.proc_list_id(),
            class.initialized_variable_list_id(),
            class.defining_variable_list_id(),
            class.overriding_variable_list_id(),
        ] {
            mark(id);
        }
    }
    for run in &dmb.grid {
        mark(run.contents);
    }
    mark(dmb.world.ids[3]);
    mark(dmb.variable_footer);
    counts
}

fn replace_list_reference(counts: &mut Vec<usize>, previous: u32, next: u32) {
    if previous != 0xffff {
        if let Some(count) = counts.get_mut(previous as usize) {
            *count = count.saturating_sub(1);
        }
    }
    if next != 0xffff {
        counts.resize(counts.len().max(next as usize + 1), 0);
        counts[next as usize] += 1;
    }
}

fn append_list(dmb: &mut Dmb, words: Vec<u32>) -> u32 {
    if dmb.lists.len() == 0xffff {
        dmb.lists.push(Vec::new());
    }
    let id = dmb.lists.len() as u32;
    dmb.lists.push(words);
    id
}
fn intern(dmb: &mut Dmb, bytes: &[u8]) -> u32 {
    if let Some(id) = dmb.strings.iter().enumerate().find_map(|(id, string)| {
        (!crate::native_reserved_string_id(id as u32) && string.data == bytes).then_some(id as u32)
    }) {
        return id;
    }
    while crate::native_reserved_string_id(dmb.strings.len() as u32) {
        dmb.strings.push(DmString {
            data: Vec::new(),
            long_chunks: 0,
        });
    }
    let id = dmb.strings.len() as u32;
    dmb.strings.push(DmString {
        data: bytes.to_vec(),
        long_chunks: u16::try_from(bytes.len() / 65535).unwrap_or(u16::MAX),
    });
    id
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn incremental_ledger_binds_only_referenced_baseline_symbols() {
        let ast = dm_syntax::parse("/proc/changed()\n    return answer()\n");
        let compiled = dm_codegen_byond::compile_simple_proc_with_bindings(
            &ast.items[0].children,
            &LowerBindings {
                global_procs: std::collections::BTreeSet::from(["answer".into()]),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let mut baseline = BTreeMap::new();
        compiled.code.for_each_reference(|table, name| {
            if table != Table::String {
                baseline.insert(Symbol::new(table, name), 7);
            }
        });
        let unused = Symbol::new(Table::Proc, "/proc/unrelated");
        baseline.insert(unused.clone(), 9);
        let mut selective = Ledger::default();
        bind_referenced_baseline_symbols(&compiled.code, &baseline, &mut selective).unwrap();
        assert!(selective.id(&unused).is_none());
        let mut exhaustive = Ledger::default();
        for (symbol, id) in baseline {
            exhaustive.bind_alias(symbol, id).unwrap();
        }
        assert_eq!(
            link_proc(&compiled.code, &selective).unwrap().words,
            link_proc(&compiled.code, &exhaustive).unwrap().words
        );
    }

    #[test]
    fn multiple_dirty_bodies_lower_and_commit_without_changing_other_ids() {
        let old = "/proc/first()\n    return 1\n/proc/second()\n    return 2\n/proc/unchanged()\n    return 7\n";
        let base = baseline(old);
        let checkpoint = base.checkpoint.unwrap();
        let unchanged = checkpoint.procedures["/proc/unchanged"].proc_id as usize;
        let old_unchanged = base.dmb.procs[unchanged].clone();
        let first = checkpoint.procedures["/proc/first"].proc_id as usize;
        let second = checkpoint.procedures["/proc/second"].proc_id as usize;
        let old_first_code = base.dmb.procs[first].code_locals_args[0];
        let old_second_code = base.dmb.procs[second].code_locals_args[0];
        let new = old
            .replace("return 1", "return 11")
            .replace("return 2", "return 22");
        let mut session = IncrementalSession::default();
        session.set_baseline_identity(digest(&base.dmb.to_bytes().unwrap()));
        let result = try_emit(&new, base.dmb, checkpoint, &mut session)
            .unwrap()
            .unwrap();
        assert_eq!(result.changed_procs, 2);
        assert_eq!(result.dmb.procs[unchanged], old_unchanged);
        assert_eq!(result.dmb.procs[first].code_locals_args[0], old_first_code);
        assert_eq!(
            result.dmb.procs[second].code_locals_args[0],
            old_second_code
        );
        assert!(result.changed_lists.contains(&old_first_code));
        assert!(result.changed_lists.contains(&old_second_code));
        result.dmb.validate_references().unwrap();
    }

    #[test]
    fn reference_count_cache_requires_exact_baseline_identity() {
        let base = baseline("/proc/first()\n    return 1\n");
        let mut session = IncrementalSession::default();
        session.set_baseline_identity("first-content-digest".into());
        let expected = session.list_reference_counts(&base.dmb);
        assert!(session.reference_counts.is_some());
        assert_eq!(session.list_reference_counts(&base.dmb), expected);
        session.set_baseline_identity("different-content-digest".into());
        assert!(session.reference_counts.is_none());
        assert_eq!(session.list_reference_counts(&base.dmb), expected);
    }
    use std::path::Path;
    const SCHEMA: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
    fn baseline(source: &str) -> crate::bootstrap::CompiledProject {
        let source = dm_preprocess::PreprocessedProject {
            text: source.into(),
            ..Default::default()
        };
        crate::bootstrap::compile_preprocessed_project_with_resources(
            Path::new("incremental-test.dme"),
            &source,
            SCHEMA,
            "incremental-test",
        )
        .unwrap()
    }
    #[test]
    fn body_edit_preserves_other_procs_and_supports_new_locals_and_strings() {
        let old = "/proc/edited()\n    return 1\n/proc/unchanged(a=7)\n    return a\n";
        let base = baseline(old);
        let checkpoint = base.checkpoint.unwrap();
        let unchanged = checkpoint.procedures["/proc/unchanged"].proc_id as usize;
        let edited = checkpoint.procedures["/proc/edited"].proc_id as usize;
        let old_unchanged = base.dmb.procs[unchanged].clone();
        let old_args = base.dmb.procs[edited].code_locals_args[2];
        let updated="/proc/edited()\n    var/value = \"new string\"\n    return value\n/proc/unchanged(a=7)\n    return a\n";
        let encoded = encode_checkpoint(&checkpoint).unwrap();
        let checkpoint = decode_checkpoint(&encoded).unwrap();
        let result = try_emit(
            updated,
            base.dmb,
            checkpoint,
            &mut IncrementalSession::default(),
        )
        .unwrap()
        .unwrap();
        assert_eq!(result.changed_procs, 1);
        assert_eq!(result.dmb.procs[unchanged], old_unchanged);
        assert_eq!(result.dmb.procs[edited].code_locals_args[2], old_args);
        let locals = result.dmb.procs[edited].code_locals_args[1] as usize;
        assert_eq!(result.dmb.lists[locals].len(), 1);
        assert!(result
            .dmb
            .strings
            .iter()
            .any(|string| string.data == b"new string"));
        Dmb::from_bytes(&result.dmb.to_bytes().unwrap())
            .unwrap()
            .validate_references()
            .unwrap();
    }
    #[test]
    fn changed_method_restores_inherited_field_types_and_new_proc_references() {
        let old="/datum/helper\n    var/value=1\n/datum/base\n    var/datum/helper/member\n/datum/child\n    parent_type=/datum/base\n/datum/child/proc/value()\n    return 1\n/proc/answer()\n    return 9\n";
        let base = baseline(old);
        let new = old.replace(
            "/datum/child/proc/value()\n    return 1",
            "/datum/child/proc/value()\n    return member.value + answer()",
        );
        let result = try_emit(
            &new,
            base.dmb,
            base.checkpoint.unwrap(),
            &mut IncrementalSession::default(),
        )
        .unwrap()
        .unwrap();
        assert_eq!(result.changed_procs, 1);
        result.dmb.validate_references().unwrap();
    }

    #[test]
    fn declaration_default_static_and_resource_edits_fall_back() {
        for (old, new) in [
            (
                "var/global/value=1\n/proc/f()\n    return value\n",
                "var/global/value=2\n/proc/f()\n    return value\n",
            ),
            (
                "/proc/f(a=1)\n    return a\n",
                "/proc/f(a=2)\n    return a\n",
            ),
            (
                "/proc/f()\n    var/static/value=1\n    return value\n",
                "/proc/f()\n    var/static/value=2\n    return value\n",
            ),
        ] {
            let base = baseline(old);
            assert!(try_emit(
                new,
                base.dmb,
                base.checkpoint.unwrap(),
                &mut IncrementalSession::default()
            )
            .unwrap()
            .is_none());
        }
        let outline =
            crate::bootstrap::incremental_source_outline("/proc/f()\n    return 'new.txt'\n")
                .unwrap();
        assert!(!outline.procedures["/proc/f"].patchable);
    }
    #[test]
    fn checkpoint_corruption_and_format_changes_are_rejected() {
        let base = baseline("/proc/f()\n    return 1\n");
        let bytes = encode_checkpoint(&base.checkpoint.unwrap()).unwrap();
        let mut envelope: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        envelope["version"] = 2.into();
        assert!(decode_checkpoint(&serde_json::to_vec(&envelope).unwrap()).is_none());
        let mut damaged = bytes;
        let middle = damaged.len() / 2;
        damaged[middle] ^= 1;
        assert!(decode_checkpoint(&damaged).is_none());
    }
}
