//! Direct Rust emission of world, declaration, procedure, and resource metadata.
//!
//! The builtin schema seeds native runtime types. Project declarations are
//! retained separately from bounded, lazily parsed procedure bodies.

#[path = "const_eval.rs"]
mod const_eval;
#[path = "native_constants.rs"]
mod native_constants;
#[path = "default_plans.rs"]
mod default_plans;
#[path = "semantic_declarations.rs"]
mod semantic_declarations;
#[path = "wire_declarations.rs"]
mod wire_declarations;
#[path = "declaration_operations.rs"]
mod declaration_operations;
#[path = "procedure_pipeline.rs"]
pub(crate) mod procedure_pipeline;
#[path = "resource_scan.rs"]
pub(crate) mod resource_scan;
#[path = "procedure_fragments.rs"]
mod procedure_fragments;
#[path = "emission_plans.rs"]
mod emission_plans;
#[path = "canonical.rs"]
pub(crate) mod canonical;
#[path = "initializer_pipeline.rs"]
mod initializer_pipeline;

use byond_dmb::bytecode::opcode;
use byond_dmb::dmb::{DmString, Dmb, Instance, MobType, Proc, Variable};
use dm_codegen_byond::{
    compile_simple_proc_with_bindings, link_proc, Instruction as CodeInstruction, Item as CodeItem,
    Ledger, LowerBindings, PreparedMemberGlobals, SharedLowerBindings, Symbol, Table, ValueWord, VariableWord, Word,
};
use dm_preprocess::PreprocessedProject;
use dm_resources::{ResourceRequest, ResourceSet};
#[cfg(test)]
use dm_syntax::lex;
use dm_syntax::{parse, Item, ItemKind, TokenKind};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

pub(crate) fn analysis_resolved_model(
    session:&mut canonical::CanonicalSession,fragments:&[dm_analysis::FrontendFragment],
    source:&dm_syntax::SegmentedSource,builtin_image:&[u8],cache_root:Option<&Path>,
) -> Result<Arc<dyn dm_analysis::ResolvedModel>,String> {
    if let Some(root)=cache_root {semantic_declarations::bind_cache(root);}
    let modified=collect_modified_types_segmented(source)?;
    // Only fragments containing modified-type aliases need a header projection.
    fn aliases_present(items:&[Item],modified:&ModifiedTypes)->bool {
        items.iter().any(|item|modified_spans(&item.header).into_iter().any(|span|modified.aliases.contains_key(&modified_key(&item.header[span.range()]))) || aliases_present(&item.children,modified))
    }
    let mut normalized=fragments.to_vec();
    if !modified.aliases.is_empty() {
        for fragment in &mut normalized {
            if aliases_present(&fragment.ast.items,&modified) {
                let mut ast=fragment.ast.as_ref().clone();rewrite_modified_items(&mut ast.items,&modified);fragment.ast=Arc::new(ast);
            }
        }
    }
    let builtin=Dmb::from_bytes(builtin_image).map_err(|error|error.to_string())?;
    let model=semantic_declarations::analysis_model::build_fragments(&normalized,&modified.declarations,&builtin,builtin_image,session.semantic_declarations.as_ref(),dm_work::WorkLimits::configured().workers);
    session.semantic_declarations=Some(Arc::clone(&model));session.semantic_base_revision=None;semantic_declarations::flush_cache();
    Ok(model)
}

/// Immutable linked fragments shared by emission reports and output caches.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OutputWords(Arc<[u32]>);
impl OutputWords { pub fn as_slice(&self) -> &[u32] { &self.0 } }
impl std::ops::Deref for OutputWords {
    type Target = [u32];
    fn deref(&self) -> &[u32] { &self.0 }
}
impl From<Vec<u32>> for OutputWords {
    fn from(words: Vec<u32>) -> Self { Self(words.into()) }
}
impl From<Arc<[u32]>> for OutputWords {
    fn from(words: Arc<[u32]>) -> Self { Self(words) }
}
impl PartialEq<Vec<u32>> for OutputWords {
    fn eq(&self, words: &Vec<u32>) -> bool { self.as_slice() == words.as_slice() }
}
impl PartialEq<OutputWords> for Vec<u32> {
    fn eq(&self, words: &OutputWords) -> bool { self.as_slice() == words.as_slice() }
}
impl PartialEq<&[u32]> for OutputWords {
    fn eq(&self, words: &&[u32]) -> bool { self.as_slice() == *words }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EmittedProc {
    pub path: String,
    pub proc_index: usize,
    pub words: OutputWords,
}

struct PendingProc<'a> {
    item: &'a Item,
    source_offset: usize,
    owner: Option<u32>,
    owner_path: String,
    verb: bool,
}

impl PendingProc<'_> {
    fn span(&self) -> dm_syntax::Span {
        dm_syntax::Span::new(self.source_offset+self.item.span.start, self.source_offset+self.item.span.end)
    }
    fn header_span(&self) -> dm_syntax::Span {
        dm_syntax::Span::new(self.source_offset+self.item.header_span.start, self.source_offset+self.item.header_span.end)
    }
}

fn rebase_declaration_item(item: &mut Item, offset: usize) {
    item.span.start += offset; item.span.end += offset;
    item.header_span.start += offset; item.header_span.end += offset;
    for child in &mut item.children { rebase_declaration_item(child, offset); }
}

/// This cache belongs to one completed declaration snapshot. Class variable
/// declarations and shared member types are immutable during proc emission.
/// Retain at most 64 owner frames and 4 MiB of conservative resident estimates.
struct OwnerBindingCache {
    queries: Option<Arc<std::sync::Mutex<canonical::OwnerFrameQueries>>>,
    frames: HashMap<u32, Arc<dm_codegen_byond::OwnerLowerBindings>>,
    bytes: usize,
    byte_limit: usize,
    entry_limit: usize,
}

impl OwnerBindingCache {
    fn new(byte_limit: usize, entry_limit: usize) -> Self {
        Self {
            queries: None,
            frames: HashMap::new(),
            bytes: 0,
            byte_limit,
            entry_limit,
        }
    }

    fn with_queries(byte_limit: usize, entry_limit: usize, queries: Arc<std::sync::Mutex<canonical::OwnerFrameQueries>>) -> Self {
        let mut cache=Self::new(byte_limit,entry_limit);cache.queries=Some(queries);cache
    }

    fn populate(
        &mut self,
        owner: u32,
        dmb: &Dmb,
        shared: &SharedLowerBindings,
        bindings: &mut LowerBindings,
    ) {
        if let Some(frame) = self.frames.get(&owner) {
            bindings.owner = Some(Arc::clone(frame));
            return;
        }
        let mut frame = LowerBindings::default();
        if let Some(queries)=&self.queries {
            let resolved=queries.lock().unwrap_or_else(|e|e.into_inner()).resolve(owner,dmb,shared);
            // This request-local owner cache holds Arc values; inherited sets
            // are re-derived only when a declaration query's inputs change.
            let bytes=resolved.fields.iter().map(|name|name.len()+64).sum::<usize>()+
                resolved.field_types.iter().map(|(name,ty)|name.len()+ty.len()+96).sum::<usize>()+512;
            if bytes<=self.byte_limit && self.entry_limit>0 {
                if self.frames.len()>=self.entry_limit || self.bytes.saturating_add(bytes)>self.byte_limit {self.frames.clear();self.bytes=0;}
                self.bytes+=bytes;self.frames.insert(owner,Arc::clone(&resolved));
            }
            bindings.owner=Some(resolved);return;
        }
        collect_owner_fields(owner, dmb, shared, &mut frame);
        let bytes = frame
            .fields
            .iter()
            .map(|name| name.len() * 2 + 96)
            .sum::<usize>()
            + frame
                .field_types
                .iter()
                .map(|(name, ty)| (name.len() + ty.len()) * 2 + 160)
                .sum::<usize>()
            + 512;
        let frame = Arc::new(dm_codegen_byond::OwnerLowerBindings { fields: frame.fields.into_iter().collect(), field_types: frame.field_types.into_iter().collect() });
        if bytes <= self.byte_limit && self.entry_limit > 0 {
            if self.frames.len() >= self.entry_limit || self.bytes.saturating_add(bytes) > self.byte_limit {
                self.frames.clear(); self.bytes = 0;
            }
            self.bytes += bytes;
            self.frames.insert(owner, Arc::clone(&frame));
        }
        bindings.owner = Some(frame);
    }
}

fn collect_owner_fields(
    mut class_id: u32,
    dmb: &Dmb,
    shared: &SharedLowerBindings,
    bindings: &mut LowerBindings,
) {
    loop {
        if let Some(path) = dmb.string(dmb.classes[class_id as usize].path_string_id()) {
            seed_builtin_fields(&String::from_utf8_lossy(path), bindings);
            if let Some(types) = shared
                .member_types
                .get(String::from_utf8_lossy(path).as_ref())
            {
                for (name, path) in types {
                    bindings
                        .field_types
                        .entry(name.clone())
                        .or_insert_with(|| path.clone());
                }
            }
        }
        if let Some(declarations) = dmb.class_variable_declarations(class_id as usize) {
            for (id, _) in declarations {
                if let Some(name) = dmb.string(dmb.variables[id as usize].name) {
                    bindings
                        .fields
                        .insert(String::from_utf8_lossy(name).into_owned());
                }
            }
        }
        let parent = dmb.classes[class_id as usize].parent_class_id();
        if parent == 0xffff {
            break;
        }
        class_id = parent;
    }
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
struct TypeMetadataState {
    first_generated_class: usize,
    emitted: HashSet<u32>,
    authored_names: HashSet<u32>,
    authored_texts: HashSet<u32>,
    static_ids: HashMap<String, u32>,
    dynamic_static_scopes: HashMap<String, u32>,
}

/// Recognize the setting by tokens rather than formatting around its assignment.
fn is_proc_name_setting(header: &str) -> bool {
    let scanned = dm_syntax::lex_spans(header);
    let mut tokens = scanned.tokens.iter().filter(|token| {
        !matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        )
    });
    ["set", "name", "="].into_iter().all(|expected| {
        tokens
            .next()
            .is_some_and(|token| token.text(header) == expected)
    })
}

fn has_proc_name_setting(items: &[Item]) -> bool {
    items.iter().any(|item| {
        is_proc_name_setting(&item.header) || has_proc_name_setting(&item.children)
    })
}

fn apply_mouse_proc_flags(
    dmb: &mut Dmb,
    pending: &[PendingProc<'_>],
    plans: &[canonical::InvocationPlan],
) {
    let mut own_bits = HashMap::<u32, u64>::new();
    for (proc, plan) in pending.iter().zip(plans) {
        let Some(owner) = proc.owner else { continue; };
        let bit = match plan.path.rsplit('/').next().unwrap_or("") {
            "MouseEntered" | "MouseExited" => 0x800,
            "MouseMove" => 0x80000,
            "MouseWheel" => 0x100000,
            _ => 0,
        };
        if bit != 0 && class_inherits(dmb, owner, b"/atom") {
            *own_bits.entry(owner).or_default() |= bit;
        }
    }
    // Memoize inherited flags so a deep type tree is traversed once.
    let mut inherited = HashMap::<u32, u64>::new();
    for id in 0..dmb.classes.len() {
        let mut ancestor = id as u32;
        let mut chain = Vec::new();
        let mut bits = 0;
        while ancestor != 0xffff {
            if let Some(&cached) = inherited.get(&ancestor) { bits = cached; break; }
            chain.push(ancestor);
            ancestor = dmb.classes[ancestor as usize].parent_class_id();
        }
        for ancestor in chain.into_iter().rev() {
            bits |= own_bits.get(&ancestor).copied().unwrap_or(0);
            inherited.insert(ancestor, bits);
        }
        dmb.classes[id].flags |= inherited[&(id as u32)];
    }
}

fn collect_type_items<'a>(items: &'a [Item], output: &mut Vec<&'a Item>) {
    for item in items {
        if item.kind == ItemKind::Type && item.header.trim() != "/world" {
            output.push(item);
            collect_type_items(&item.children, output);
        }
    }
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
struct PendingDynamic {
    owner: Option<u32>,
    name: String,
    expression: String,
    sized_array: bool,
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
#[serde(into = "ParameterWire", from = "ParameterWire")]
struct ParsedParameter {
    name: String,
    type_flags: u32,
    type_path: Option<String>,
    value_source: u32,
    source_expression: Option<String>,
    default: Option<String>,
}

type ParameterWire = (String, u32, Option<String>, u32, Option<String>, Option<String>);
impl From<ParsedParameter> for ParameterWire {
    fn from(p: ParsedParameter) -> Self { (p.name,p.type_flags,p.type_path,p.value_source,p.source_expression,p.default) }
}
impl From<ParameterWire> for ParsedParameter {
    fn from(p: ParameterWire) -> Self { Self { name:p.0,type_flags:p.1,type_path:p.2,value_source:p.3,source_expression:p.4,default:p.5 } }
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
#[serde(into = "ProcMetadataWire", from = "ProcMetadataWire")]
struct ProcMetadata {
    name: Option<Vec<u8>>,
    description: Option<Vec<u8>>,
    category: Option<Vec<u8>>,
    source_parameter: u8,
    source_kind: u8,
    flags: u32,
    invisibility: Option<u8>,
}

type ProcMetadataWire = (Option<Vec<u8>>, Option<Vec<u8>>, Option<Vec<u8>>, u8, u8, u32, Option<u8>);
impl From<ProcMetadata> for ProcMetadataWire {
    fn from(p: ProcMetadata) -> Self { (p.name,p.description,p.category,p.source_parameter,p.source_kind,p.flags,p.invisibility) }
}
impl From<ProcMetadataWire> for ProcMetadata {
    fn from(p: ProcMetadataWire) -> Self { Self { name:p.0,description:p.1,category:p.2,source_parameter:p.3,source_kind:p.4,flags:p.5,invisibility:p.6 } }
}

fn proc_metadata(
    body: &[Item],
    base: Option<(&Dmb, &Proc)>,
) -> Result<(ProcMetadata, Vec<Item>), String> {
    let inherited = base.map(|(_, proc)| proc);
    let metadata = ProcMetadata {
        name: base
            .and_then(|(dmb, proc)| dmb.string(proc.strings[1]))
            .map(<[u8]>::to_vec),
        description: base
            .and_then(|(dmb, proc)| dmb.string(proc.strings[2]))
            .map(<[u8]>::to_vec),
        category: base
            .and_then(|(dmb, proc)| dmb.string(proc.strings[3]))
            .map(<[u8]>::to_vec),
        source_parameter: inherited.map_or(255, |proc| proc.source_parameter),
        source_kind: inherited.map_or(0, |proc| proc.source_kind),
        flags: inherited.map_or(4, Proc::effective_flags),
        invisibility: inherited.and_then(Proc::invisibility_setting),
    };
    proc_metadata_from_base(body, metadata)
}

fn proc_metadata_from_base(
    body: &[Item],
    mut metadata: ProcMetadata,
) -> Result<(ProcMetadata, Vec<Item>), String> {
    let mut code = body.to_vec();
    let mut settings = Vec::new();
    fn extract_settings(items: &mut Vec<Item>, settings: &mut Vec<Item>, reachable: bool) {
        items.retain_mut(|item| {
            if item.header.trim_start().starts_with("set ") { if reachable { settings.push(item.clone()); } false }
            else {
                let header = item.header.trim();
                let condition = header.strip_prefix("if").map(str::trim).and_then(|value| value.strip_prefix('(')).and_then(|value| value.strip_suffix(')'));
                let dead = condition.and_then(|condition| const_eval::evaluate(condition, builtin_constant)).is_some_and(|value| matches!(value, const_eval::Constant::Null) || matches!(value, const_eval::Constant::Number(number) if number == 0.0));
                extract_settings(&mut item.children, settings, reachable && !dead);
                true
            }
        });
    }
    extract_settings(&mut code, &mut settings, true);
    for item in &settings {
        let header = item.header.trim();
        let Some(setting) = header.strip_prefix("set ") else {
            code.push(item.clone());
            continue;
        };
        let (key, value) = setting
            .split_once('=')
            .map(|(key, value)| (key.trim(), value.trim()))
            .or_else(|| {
                setting
                    .split_once(" in ")
                    .map(|(key, value)| (key.trim(), value.trim()))
            })
            .ok_or_else(|| format!("unsupported procedure setting: {header}"))?;
        let boolean = match value {
            "TRUE" | "1" => Some(true),
            "FALSE" | "0" => Some(false),
            _ => None,
        };
        match key {
            "name" | "category" | "desc" if value != "null" => {
                let text = match const_eval::evaluate(value, builtin_constant) {
                    Some(const_eval::Constant::Text(text)) => text.into_bytes(),
                    Some(const_eval::Constant::EncodedText(text)) => text,
                    _ => return Err(format!("unsupported procedure setting: {header}")),
                };
                if key == "name" {
                    metadata.name = Some(text);
                } else if key == "desc" {
                    metadata.description = Some(text);
                } else {
                    metadata.category = Some(text);
                }
            }
            "category" if value == "null" => metadata.category = None,
            "waitfor" | "hidden" | "background" | "instant" | "popup_menu" => {
                let enabled =
                    boolean.ok_or_else(|| format!("unsupported procedure setting: {header}"))?;
                let (bit, active) = match key {
                    "waitfor" => (4, enabled),
                    "hidden" => (1, enabled),
                    "background" => (0x100, enabled),
                    "instant" => (0x200, enabled),
                    _ => (0x40, !enabled),
                };
                if active {
                    metadata.flags |= bit;
                } else {
                    metadata.flags &= !bit;
                }
            }
            "src" => {
                let (kind, parameter) = if value == "usr" {
                    if setting.contains('=') {
                        (32, 255)
                    } else {
                        (8, 127)
                    }
                } else if value == "usr.contents" {
                    (8, 127)
                } else if value == "usr.loc" {
                    (3, 255)
                } else if value == "world" {
                    (0, 255)
                } else if let Some(radius) = value
                    .strip_prefix("view(")
                    .and_then(|v| v.strip_suffix(')'))
                {
                    let radius = radius.strip_prefix("usr,").map(str::trim).unwrap_or(radius);
                    (
                        1,
                        if radius.is_empty() {
                            125
                        } else {
                            radius
                                .parse()
                                .map_err(|_| format!("unsupported procedure setting: {header}"))?
                        },
                    )
                } else if let Some(radius) = value
                    .strip_prefix("oview(")
                    .and_then(|v| v.strip_suffix(')'))
                {
                    (
                        2,
                        radius
                            .parse()
                            .map_err(|_| format!("unsupported procedure setting: {header}"))?,
                    )
                } else if let Some(radius) = value
                    .strip_prefix("range(")
                    .and_then(|v| v.strip_suffix(')'))
                {
                    (
                        5,
                        radius
                            .parse()
                            .map_err(|_| format!("unsupported procedure setting: {header}"))?,
                    )
                } else {
                    return Err(format!("unsupported procedure setting: {header}"));
                };
                metadata.source_kind = kind;
                metadata.source_parameter = parameter;
                // '=' restricts src; 'in' only selects its search scope.
                if setting.contains('=') {
                    metadata.flags |= 2;
                } else {
                    metadata.flags &= !2;
                }
            }
            "invisibility" => {
                let level: u8 = value
                    .parse()
                    .map_err(|_| format!("unsupported procedure setting: {header}"))?;
                if level > 127 {
                    return Err(format!("unsupported procedure setting: {header}"));
                }
                metadata.invisibility = Some(level);
                metadata.flags |= 8;
                if level > 0 {
                    metadata.flags |= 0x10;
                } else {
                    metadata.flags &= !0x10;
                }
            }
            _ => return Err(format!("unsupported procedure setting: {header}")),
        }
    }
    Ok((metadata, code))
}

/// Compile a DME project with the currently supported direct-emission subset.
/// The preprocessor follows the manifest's includes and macros; unsupported
/// declarations or bodies are errors rather than copied native code.
/// Callers caching the DMB must include referenced asset bytes in their key.
pub fn compile_project(
    dme_path: &Path,
    builtin_image: &[u8],
    world_name: &str,
) -> Result<(Dmb, Vec<EmittedProc>), String> {
    let project = crate::ProjectSession::from_disk(dme_path.to_path_buf(), Default::default());
    let preprocessed = bounded_project_snapshot(&project)?;
    if !preprocessed.diagnostics.is_empty() {
        return Err(format!(
            "preprocessing failed: {:?}",
            preprocessed.diagnostics
        ));
    }
    let (mut dmb, emitted) = emit_global_procs(&preprocessed.text, builtin_image, world_name)?;
    let maps = crate::maps::load_map_set_from_paths(dme_path, &preprocessed.map_includes)?;
    crate::maps::emit_maps(&mut dmb, &maps)?;
    Ok((dmb, emitted))
}

/// Compile the DMB and its paired RSC. `resource_fingerprint` covers every
/// literal resource's authored name and bytes; daemon CAS keys must include it.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ArtifactReuseStats {
    pub authored_prepared_reused: usize,
    pub authored_cache_reused: usize,
    pub authored_lowered: usize,
    pub generated_prepared_reused: usize,
    pub generated_cache_reused: usize,
    pub generated_lowered: usize,
}
impl ArtifactReuseStats {
    pub fn authored_reused(&self) -> usize {
        self.authored_prepared_reused.saturating_add(self.authored_cache_reused)
    }
}

pub struct CompiledProject {
    pub dmb: Dmb,
    pub emitted: Vec<EmittedProc>,
    pub rsc_bytes: Vec<u8>,
    pub resource_fingerprint: [u8; 32],
    pub resource_catalog: dm_resources::ResourceCatalog,
    pub map_fingerprint: [u8; 32],
    pub lowering_cache_stats: crate::lower_cache::CacheStats,
    pub artifact_reuse: ArtifactReuseStats,
    pub checkpoint: Option<crate::incremental::EmissionCheckpoint>,
}

fn bounded_project_snapshot(
    project: &crate::ProjectSession,
) -> Result<PreprocessedProject, String> {
    const DEFAULT_LIMIT: usize = 32 * 1024 * 1024;
    let limit = std::env::var("DM_BUILD_MAX_SOURCE_BYTES")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(DEFAULT_LIMIT);
    if let Some(size) = project.preprocessed_byte_len().filter(|size| *size > limit) {
        return Err(format!(
            "preprocessed project is {size} bytes, above the build limit of {limit}; set DM_BUILD_MAX_SOURCE_BYTES to raise it"
        ));
    }
    let preprocessed = project.preprocess_incremental();
    if preprocessed.text.len() > limit {
        return Err(format!(
            "preprocessed project is {} bytes, above the build limit of {limit}; set DM_BUILD_MAX_SOURCE_BYTES to raise it",
            preprocessed.text.len()
        ));
    }
    Ok(preprocessed)
}

pub fn compile_project_with_resources(
    dme_path: &Path,
    builtin_image: &[u8],
    world_name: &str,
) -> Result<CompiledProject, String> {
    compile_project_with_resources_and_defines(
        dme_path,
        builtin_image,
        world_name,
        &BTreeMap::new(),
    )
}

pub fn compile_project_with_resources_and_defines(
    dme_path: &Path,
    builtin_image: &[u8],
    world_name: &str,
    defines: &BTreeMap<String, String>,
) -> Result<CompiledProject, String> {
    let project = crate::ProjectSession::from_disk(dme_path.to_path_buf(), defines.clone());
    let preprocessed = bounded_project_snapshot(&project)?;
    compile_preprocessed_project_with_resources(dme_path, &preprocessed, builtin_image, world_name)
}

/// Compile a source snapshot already discovered and verified by a caller.
/// The caller must recheck source, map, and resource bytes before publishing
/// the result; this entry point avoids a second preprocessing pass in the daemon.
pub fn compile_preprocessed_project_with_resources(
    dme_path: &Path,
    preprocessed: &PreprocessedProject,
    builtin_image: &[u8],
    world_name: &str,
) -> Result<CompiledProject, String> {
    let mut frontend = crate::frontend::OutlineSession::new(Some(
        crate::lower_cache::project_cache_root(dme_path),
    ));
    compile_preprocessed_project_with_resources_cached(
        dme_path,
        preprocessed,
        builtin_image,
        world_name,
        &mut frontend,
    )
}

/// Reuse bounded content-addressed syntax fragments and seed the same frontend
/// session that later incremental body edits consult.
pub fn compile_preprocessed_project_with_resources_cached(
    dme_path: &Path,
    preprocessed: &PreprocessedProject,
    builtin_image: &[u8],
    world_name: &str,
    frontend: &mut crate::frontend::OutlineSession,
) -> Result<CompiledProject, String> {
    let pipeline_started = std::time::Instant::now();
    if !preprocessed.diagnostics.is_empty() {
        return Err(format!(
            "preprocessing failed: {:?}",
            preprocessed.diagnostics
        ));
    }
    let maps = crate::maps::load_map_set_from_paths(dme_path, &preprocessed.map_includes)?;
    let resources = load_resource_set_with_maps_skins_and_dirs(
        dme_path,
        &preprocessed.text,
        &maps,
        &preprocessed.skin_includes,
        &preprocessed.file_dirs,
    )?;
    compile_preprocessed_project_with_loaded_resources(
        dme_path,
        preprocessed,
        builtin_image,
        world_name,
        frontend,
        &maps,
        &resources,
        pipeline_started,
        true,
    )
}

/// Compile caller-verified map and resource inventories without rediscovering them.
/// The caller must verify the same inputs again before publishing the output.
pub fn compile_preprocessed_project_with_resources_prepared(
    dme_path: &Path,
    preprocessed: &PreprocessedProject,
    builtin_image: &[u8],
    world_name: &str,
    frontend: &mut crate::frontend::OutlineSession,
    maps: &crate::maps::MapSet,
    resource_requests: &[ResourceRequest],
) -> Result<CompiledProject, String> {
    compile_preprocessed_project_with_resources_prepared_mode(dme_path, preprocessed,
        builtin_image, world_name, frontend, maps, resource_requests, true)
}

/// Canonical project assembly reuses symbolic code but never a previous wire
/// allocation history. Checkpoints are optional and unnecessary for this path.
pub fn compile_preprocessed_project_with_resources_prepared_mode(
    dme_path: &Path,
    preprocessed: &PreprocessedProject,
    builtin_image: &[u8],
    world_name: &str,
    frontend: &mut crate::frontend::OutlineSession,
    maps: &crate::maps::MapSet,
    resource_requests: &[ResourceRequest],
    capture_checkpoint: bool,
) -> Result<CompiledProject, String> {
    let pipeline_started = std::time::Instant::now();
    if !preprocessed.diagnostics.is_empty() {
        return Err(format!(
            "preprocessing failed: {:?}",
            preprocessed.diagnostics
        ));
    }
    let resources =
        ResourceSet::load(resource_requests.iter().cloned()).map_err(|error| error.to_string())?;
    compile_preprocessed_project_with_loaded_resources(
        dme_path,
        preprocessed,
        builtin_image,
        world_name,
        frontend,
        maps,
        &resources,
        pipeline_started,
        capture_checkpoint,
    )
}

fn compile_preprocessed_project_with_loaded_resources(
    dme_path: &Path,
    preprocessed: &PreprocessedProject,
    builtin_image: &[u8],
    world_name: &str,
    frontend: &mut crate::frontend::OutlineSession,
    maps: &crate::maps::MapSet,
    resources: &ResourceSet,
    pipeline_started: std::time::Instant,
    capture_checkpoint: bool,
) -> Result<CompiledProject, String> {
    let cache_root = frontend.cache_root().map(Path::to_path_buf)
        .unwrap_or_else(|| crate::lower_cache::default_cache_root(dme_path));
    frontend.canonical.bind_project(dme_path, &cache_root);
    let mut lowering_cache = crate::lower_cache::ProcLoweringCache::open(cache_root);
    if std::env::var_os("DM_BUILD_TRACE").is_some() {
        eprintln!(
            "DM_BUILD_TRACE project map/resource loading {:.3}s",
            pipeline_started.elapsed().as_secs_f64()
        );
    }
    let mut checkpoint = None;
    let segmented = frontend.segmented_source().cloned();
    let source_debug = (!capture_checkpoint && preprocessed.origin_count() != 0).then(||
        if let Some(source) = &segmented { crate::source_debug::SourceDebugIndex::new_segmented(preprocessed, dme_path.parent().unwrap_or_else(|| Path::new(".")), source) }
        else { crate::source_debug::SourceDebugIndex::new(preprocessed, dme_path.parent().unwrap_or_else(|| Path::new("."))) });
    let (mut dmb, emitted, rsc_bytes) = emit_global_procs_mode_with_frontend_catalog(
        &preprocessed.text,
        builtin_image,
        world_name,
        Some(resources),
        &mut lowering_cache,
        None,
        capture_checkpoint.then_some(&mut checkpoint),
        procedure_pipeline::worker_count(),
        Some(&mut *frontend),
        None,
        source_debug.as_ref(),
        None,
    )?;
    if let Some(skin) = preprocessed.skin_includes.last() {
        let root = dme_path.parent().unwrap_or_else(|| Path::new("."));
        let archive_name = skin_archive_name(root, skin)?;
        let input = resources
            .inputs
            .iter()
            .find(|input| input.archive_name == archive_name)
            .ok_or_else(|| format!("selected skin missing from resources: {archive_name}"))?;
        dmb.world.hub_channel_skin[2] = dmb
            .resources
            .iter()
            .position(|resource| resource.id == input.named.id && resource.kind == input.named.kind)
            .ok_or_else(|| format!("selected skin not attached: {archive_name}"))?
            as u32;
    }
    let map_started = std::time::Instant::now();
    crate::maps::emit_maps_with_resources_cached(&mut dmb, maps, resources, &mut frontend.canonical.maps)?;
    if std::env::var_os("DM_BUILD_TRACE").is_some() {
        eprintln!(
            "DM_BUILD_TRACE project map emission {:.3}s; total {:.3}s",
            map_started.elapsed().as_secs_f64(),
            pipeline_started.elapsed().as_secs_f64()
        );
    }
    Ok(CompiledProject {
        dmb,
        emitted,
        rsc_bytes,
        resource_fingerprint: resources.fingerprint,
        resource_catalog: resources.catalog().map_err(|error| error.to_string())?,
        map_fingerprint: maps.fingerprint,
        lowering_cache_stats: lowering_cache.stats(),
        artifact_reuse: frontend.canonical.emission_stats,
        checkpoint,
    })
}

/// Canonical assembly with an unchanged, independently verified archive. This
/// returns no archive payload: callers must publish the paired verified RSC.
pub fn compile_preprocessed_project_with_resource_catalog(
    dme_path: &Path, preprocessed: &PreprocessedProject, builtin_image: &[u8], world_name: &str,
    frontend: &mut crate::frontend::OutlineSession, maps: &crate::maps::MapSet,
    resources: &dm_resources::ResourceCatalog,
) -> Result<CompiledProject, String> {
    let cache_root = frontend.cache_root().map(Path::to_path_buf)
        .unwrap_or_else(|| crate::lower_cache::default_cache_root(dme_path));
    frontend.canonical.bind_project(dme_path, &cache_root);
    if !preprocessed.diagnostics.is_empty() { return Err("preprocessing diagnostics prevent emission".into()); }
    resources.validate().map_err(|error| error.to_string())?;
    let mut lowering_cache = crate::lower_cache::ProcLoweringCache::open(cache_root);
    let segmented = frontend.segmented_source().cloned();
    let source_debug = (preprocessed.origin_count() != 0).then(||
        if let Some(source) = &segmented { crate::source_debug::SourceDebugIndex::new_segmented(preprocessed, dme_path.parent().unwrap_or_else(|| Path::new(".")), source) }
        else { crate::source_debug::SourceDebugIndex::new(preprocessed, dme_path.parent().unwrap_or_else(|| Path::new("."))) });
    let (mut dmb, emitted, rsc_bytes) = emit_global_procs_mode_with_frontend_catalog(
        &preprocessed.text, builtin_image, world_name, None, &mut lowering_cache, None, None,
        procedure_pipeline::worker_count(), Some(&mut *frontend), Some(resources), source_debug.as_ref(), None)?;
    if let Some(skin) = preprocessed.skin_includes.last() {
        let root = dme_path.parent().unwrap_or_else(|| Path::new("."));
        let name = skin_archive_name(root, skin)?;
        let resource = resources.entries.iter().find(|entry| entry.archive_name == name)
            .ok_or_else(|| format!("selected skin missing from resource catalog: {name}"))?;
        dmb.world.hub_channel_skin[2] = dmb.resources.iter()
            .position(|entry| entry.id == resource.id && entry.kind == resource.kind)
            .ok_or_else(|| format!("selected skin not attached: {name}"))? as u32;
    }
    crate::maps::emit_maps_with_catalog_cached(&mut dmb, maps, resources, &mut frontend.canonical.maps)?;
    Ok(CompiledProject { dmb, emitted, rsc_bytes, resource_fingerprint: resources.fingerprint,
        resource_catalog: resources.clone(), map_fingerprint: maps.fingerprint,
        lowering_cache_stats: lowering_cache.stats(), artifact_reuse: frontend.canonical.emission_stats, checkpoint: None })
}

/// Resolve and hash literal resources before a daemon cache lookup.
pub fn load_resource_set(
    dme_path: &Path,
    preprocessed_source: &str,
) -> Result<ResourceSet, String> {
    let maps = crate::maps::load_map_set(dme_path)?;
    load_resource_set_with_maps(dme_path, preprocessed_source, &maps)
}

pub fn load_resource_set_with_maps(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
) -> Result<ResourceSet, String> {
    load_resource_set_with_maps_and_skins(dme_path, preprocessed_source, maps, &[])
}

pub fn load_resource_set_with_maps_and_skins(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
) -> Result<ResourceSet, String> {
    load_resource_set_with_maps_skins_and_dirs(dme_path, preprocessed_source, maps, skins, &[])
}

pub fn load_resource_set_with_maps_skins_and_dirs(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
) -> Result<ResourceSet, String> {
    ResourceSet::load(resource_requests(
        dme_path,
        preprocessed_source,
        maps,
        skins,
        file_dirs,
    )?)
    .map_err(|error| error.to_string())
}

pub fn fingerprint_resources_with_maps_and_skins(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
) -> Result<[u8; 32], String> {
    fingerprint_resources_with_maps_skins_and_dirs(dme_path, preprocessed_source, maps, skins, &[])
}

pub fn fingerprint_resources_with_maps_skins_and_dirs(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
) -> Result<[u8; 32], String> {
    ResourceSet::fingerprint_requests(resource_requests(
        dme_path,
        preprocessed_source,
        maps,
        skins,
        file_dirs,
    )?)
    .map_err(|error| error.to_string())
}

pub struct ResourceAudit {
    pub resources: usize,
    pub total_bytes: u64,
    pub missing_count: usize,
    pub errors: Vec<String>,
}

/// Check file availability without retaining asset payloads or creating output.
pub fn audit_resource_files(dme_path: &Path, source: &str) -> Result<ResourceAudit, String> {
    audit_resource_files_with_dirs(dme_path, source, &[])
}

pub fn audit_resource_files_with_dirs(
    dme_path: &Path,
    source: &str,
    file_dirs: &[std::path::PathBuf],
) -> Result<ResourceAudit, String> {
    let maps = crate::maps::MapSet {
        files: Vec::new(),
        fingerprint: [0; 32],
    };
    let requests = resource_requests(dme_path, source, &maps, &[], file_dirs)?;
    let mut seen = HashSet::new();
    let mut audit = ResourceAudit {
        resources: 0,
        total_bytes: 0,
        missing_count: 0,
        errors: Vec::new(),
    };
    for request in requests {
        if !seen.insert(request.archive_name) {
            continue;
        }
        audit.resources += 1;
        match std::fs::metadata(&request.disk_path) {
            Ok(metadata) if metadata.is_file() => audit.total_bytes += metadata.len(),
            result => {
                audit.missing_count += 1;
                if audit.errors.len() < 50 {
                    let reason = result
                        .err()
                        .map_or("not a file".to_owned(), |error| error.to_string());
                    audit
                        .errors
                        .push(format!("{}: {reason}", request.disk_path.display()));
                }
            }
        }
    }
    Ok(audit)
}

fn resource_requests(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
) -> Result<Vec<ResourceRequest>, String> {
    resource_requests_with_hints(dme_path, preprocessed_source, maps, skins, file_dirs, &[])
}

fn resource_requests_with_hints(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
    verified_hints: &[ResourceRequest],
) -> Result<Vec<ResourceRequest>, String> {
    resource_requests_with_optional_literals(
        dme_path,
        preprocessed_source,
        maps,
        skins,
        file_dirs,
        verified_hints,
        None,
    )
}

/// Resolve the ordered inventory collected by a verified frontend snapshot.
/// Hints require the same current-file proof as the source-scanning variant.
pub fn resolved_resource_requests_with_literals(
    dme_path: &Path,
    literals: &[String],
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
    verified_hints: &[ResourceRequest],
) -> Result<Vec<ResourceRequest>, String> {
    resource_requests_with_optional_literals(
        dme_path,
        "",
        maps,
        skins,
        file_dirs,
        verified_hints,
        Some(literals),
    )
}

fn resource_requests_with_optional_literals<'src>(
    dme_path: &Path,
    preprocessed_source: &'src str,
    maps: &'src crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
    verified_hints: &[ResourceRequest],
    literals: Option<&'src [String]>,
) -> Result<Vec<ResourceRequest>, String> {
    let root = dme_path.parent().unwrap_or_else(|| Path::new("."));
    // Only the direct project path outranks every FILE_DIR candidate. Reusing
    // fallback paths would hide newly introduced higher-priority candidates.
    let direct_hints: HashMap<_, _> = verified_hints
        .iter()
        .filter(|hint| hint.disk_path == root.join(hint.archive_name.replace('\\', "/")))
        .map(|hint| (hint.archive_name.replace('\\', "/"), &hint.disk_path))
        .collect();
    let resolve = |archive_name: &str| {
        direct_hints.get(archive_name).map_or_else(
            || resolve_resource_path(root, archive_name, file_dirs),
            |path| (**path).clone(),
        )
    };
    let mut requests = Vec::new();
    // Resolution depends only on the normalized authored name and this snapshot's
    // FILE_DIR stack. Repeated literals need neither another filesystem search
    // nor another retained request. Distinct aliases remain distinct RSC names.
    let mut literal_names = std::collections::HashSet::new();
    // Repeated authored literals need no normalized String allocation. Keep
    // borrowed source slices; aliases still deduplicate by normalized RSC name.
    let mut authored_literals = std::collections::HashSet::new();
    let mut record_literal = |literal: &'src str| {
        if !authored_literals.insert(literal) {
            return;
        }
        let archive_name = literal.trim_matches('\'').replace('\\', "/");
        if !literal_names.insert(archive_name.clone()) {
            return;
        }
        requests.push(ResourceRequest {
            disk_path: resolve(&archive_name),
            archive_name,
        });
    };
    if let Some(literals) = literals {
        for literal in literals {
            record_literal(literal);
        }
    } else {
        resource_scan::visit_resources(preprocessed_source, &mut record_literal);
    }
    for (_, source) in &maps.files {
        resource_scan::visit_literal_resources(source, &mut |literal| {
            if !authored_literals.insert(literal) {
                return;
            }
            let archive_name = literal.trim_matches('\'').replace('\\', "/");
            if !literal_names.insert(archive_name.clone()) {
                return;
            }
            requests.push(ResourceRequest {
                disk_path: resolve(&archive_name),
                archive_name,
            });
        });
    }
    for skin in skins {
        let archive_name = skin_archive_name(root, skin)?;
        let disk_path = if skin.is_absolute() || skin.starts_with(root) {
            skin.clone()
        } else {
            root.join(skin)
        };
        let text = std::fs::read_to_string(&disk_path)
            .map_err(|error| format!("{}: {error}", disk_path.display()))?;
        requests.push(ResourceRequest {
            disk_path,
            archive_name,
        });
        for line in text.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            if key.trim() != "icon" {
                continue;
            }
            let Some(path) = value
                .trim()
                .strip_prefix('\'')
                .and_then(|value| value.split_once('\'').map(|(path, _)| path))
            else {
                continue;
            };
            let archive_name = path.replace('\\', "/");
            if !literal_names.insert(archive_name.clone()) {
                continue;
            }
            requests.push(ResourceRequest {
                disk_path: resolve(&archive_name),
                archive_name,
            });
        }
    }
    Ok(requests)
}

/// Resolve resource names once for a verified preprocessed source snapshot.
/// Daemon consistency checks can rehash these requests without rescanning DM.
pub fn resolved_resource_requests(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
) -> Result<Vec<ResourceRequest>, String> {
    resource_requests(dme_path, preprocessed_source, maps, skins, file_dirs)
}

/// Resolve a new source inventory using resource paths already verified current
/// by the caller's asset proof. Only direct project paths skip filesystem probes;
/// FILE_DIR fallbacks always resolve afresh to detect newly shadowing files.
///
/// The caller must verify the hinted files still exist before invoking this API.
/// Use `resolved_resource_requests` when no current asset proof is available.
pub fn resolved_resource_requests_with_hints(
    dme_path: &Path,
    preprocessed_source: &str,
    maps: &crate::maps::MapSet,
    skins: &[std::path::PathBuf],
    file_dirs: &[std::path::PathBuf],
    verified_hints: &[ResourceRequest],
) -> Result<Vec<ResourceRequest>, String> {
    resource_requests_with_hints(
        dme_path,
        preprocessed_source,
        maps,
        skins,
        file_dirs,
        verified_hints,
    )
}

#[cfg(test)]
mod resource_resolution_hint_tests {
    use super::*;

    #[test]
    fn verified_direct_hints_preserve_inventory_and_new_fallback_shadowing() {
        let root = std::env::temp_dir().join(format!(
            "dm-resource-hints-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(root.join("low")).unwrap();
        std::fs::create_dir_all(root.join("high")).unwrap();
        std::fs::write(root.join("old.png"), "old").unwrap();
        std::fs::write(root.join("low/fallback.png"), "low").unwrap();
        std::fs::write(root.join("test.dmf"), "icon = 'old.png'\n").unwrap();
        let dme = root.join("test.dme");
        let maps = crate::maps::MapSet {
            files: vec![(root.join("test.dmm"),
                r#"'old.png' 'mapped.png' "[f('not-a-map-resource.png')]" @'raw.png' /* 'comment.png' */"#.into())],
            fingerprint: [0; 32],
        };
        std::fs::write(root.join("mapped.png"), "map").unwrap();
        let dirs = vec!["low".into(), "high".into()];
        let skins = vec![root.join("test.dmf")];
        let hints =
            resolved_resource_requests(&dme, "'old.png' 'fallback.png'", &maps, &skins, &dirs)
                .unwrap();
        assert_eq!(hints[1].disk_path, root.join("low/fallback.png"));
        std::fs::write(root.join("high/fallback.png"), "new higher priority").unwrap();
        std::fs::write(root.join("new.png"), "new").unwrap();
        let source = "'old.png' 'new.png' 'old.png' 'fallback.png'";
        let expected = resolved_resource_requests(&dme, source, &maps, &skins, &dirs).unwrap();
        let actual =
            resolved_resource_requests_with_hints(&dme, source, &maps, &skins, &dirs, &hints)
                .unwrap();
        assert_eq!(actual, expected);
        let mut literals = Vec::new();
        resource_scan::visit_resources(source, &mut |literal| literals.push(literal.to_owned()));
        assert_eq!(
            resolved_resource_requests_with_literals(&dme, &literals, &maps, &skins, &dirs, &hints)
                .unwrap(),
            expected
        );
        assert_eq!(actual[2].disk_path, root.join("high/fallback.png"));
        assert_eq!(
            actual
                .iter()
                .map(|request| request.archive_name.as_str())
                .collect::<Vec<_>>(),
            [
                "old.png",
                "new.png",
                "fallback.png",
                "mapped.png",
                "test.dmf"
            ]
        );
        // A direct project resource supersedes every old fallback hint too.
        std::fs::write(root.join("fallback.png"), "direct").unwrap();
        let actual =
            resolved_resource_requests_with_hints(&dme, source, &maps, &skins, &dirs, &hints)
                .unwrap();
        assert_eq!(actual[2].disk_path, root.join("fallback.png"));
        std::fs::remove_dir_all(root).unwrap();
    }
}

/// Re-resolve an archived name to detect a new file that shadows a previously
/// selected FILE_DIR candidate between snapshot and output publication.
pub fn resolved_resource_disk_path(
    dme_path: &Path,
    archive_name: &str,
    file_dirs: &[std::path::PathBuf],
) -> std::path::PathBuf {
    resolve_resource_path(
        dme_path.parent().unwrap_or_else(|| Path::new(".")),
        archive_name,
        file_dirs,
    )
}

fn resolve_resource_path(
    root: &Path,
    archive_name: &str,
    file_dirs: &[std::path::PathBuf],
) -> std::path::PathBuf {
    let direct = root.join(archive_name);
    if direct.is_file() {
        return direct;
    }
    for directory in file_dirs.iter().rev() {
        let candidate = root.join(directory).join(archive_name);
        if candidate.is_file() {
            return candidate;
        }
    }
    direct
}

fn skin_archive_name(root: &Path, skin: &Path) -> Result<String, String> {
    let root = std::fs::canonicalize(root).map_err(|error| error.to_string())?;
    let disk = if skin.is_absolute() {
        skin.to_path_buf()
    } else if skin.exists() {
        skin.to_path_buf()
    } else {
        root.join(skin)
    };
    let disk = std::fs::canonicalize(disk).map_err(|error| error.to_string())?;
    let relative = disk
        .strip_prefix(&root)
        .map_err(|_| format!("skin outside project root: {}", disk.display()))?;
    Ok(relative.to_string_lossy().replace('\\', "/"))
}
pub fn replace_existing_procs(
    source: &str,
    template: &[u8],
) -> Result<(Dmb, Vec<EmittedProc>), String> {
    let ast = parse(source);
    if !ast.diagnostics.is_empty() {
        return Err(format!("syntax diagnostics: {:?}", ast.diagnostics));
    }
    let mut dmb = Dmb::from_bytes(template).map_err(|error| error.to_string())?;
    let mut strings = StringIndex::new(&dmb);
    let mut emitted = Vec::new();
    for item in &ast.items {
        if item.kind != ItemKind::Proc {
            continue;
        }
        let (path, params) = proc_signature(item)?;
        let proc_index = dmb
            .procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
            .ok_or_else(|| format!("bootstrap DMB has no existing procedure {path}"))?;
        let bindings = LowerBindings {
            current_proc_path: Some(path.clone()),
            parameters: params.iter().map(|param| param.name.clone()).collect(),
            parameter_type_flags: params.iter().map(|param| param.type_flags).collect(),
            parameter_types: params
                .iter()
                .filter_map(|param| {
                    param
                        .type_path
                        .as_ref()
                        .map(|path| (param.name.clone(), path.clone()))
                })
                .collect(),
            parameter_value_sources: params.iter().map(|param| param.value_source).collect(),
            parameter_defaults: params.iter().map(|param| param.default.clone()).collect(),
            ..LowerBindings::default()
        };
        let (_, body) = proc_metadata(&item.children, None)?;
        let simple = compile_simple_proc_with_bindings(&body, &bindings)
            .map_err(|errors| format!("{path}: {errors:?}"))?;
        if simple.local_count != 0 {
            return Err(format!(
                "{path}: bootstrap emitter does not install local metadata"
            ));
        }
        let mut ledger = Ledger::default();
        bind_builtin_global_vars(&mut dmb, &mut strings, &mut ledger)?;

        for value in &simple.strings {
            let bytes = simple.string_bytes(value);
            let id = if let Some(index) = dmb.strings.iter().position(|entry| entry.data == bytes) {
                index as u32
            } else {
                let id = dmb.strings.len() as u32;
                dmb.strings.push(DmString {
                    data: bytes.to_vec(),
                    long_chunks: 0,
                });
                id
            };
            ledger
                .bind(Symbol::new(Table::String, value), id)
                .map_err(|error| error.to_string())?;
        }
        for path in &simple.class_paths {
            let id = dmb
                .classes
                .iter()
                .position(|class| dmb.string(class.path_string_id()) == Some(path.as_bytes()))
                .ok_or_else(|| format!("{path}: constructor type missing in template"))?;
            ledger
                .bind(Symbol::new(Table::Class, path), id as u32)
                .map_err(|error| error.to_string())?;
        }
        let linked =
            link_proc(&simple.code, &ledger).map_err(|error| format!("{path}: {error}"))?;
        let words = linked.words;
        if words.len() > u16::MAX as usize {
            return Err(format!("{path}: code exceeds DMB list limit"));
        }
        let list_id = dmb.lists.len() as u32;
        dmb.lists.push(words.clone());
        dmb.procs[proc_index].code_locals_args[0] = list_id;
        emitted.push(EmittedProc {
            path,
            proc_index,
            words: words.into(),
        });
    }
    crate::promote_object_ids(&mut dmb);
    dmb.validate_references()
        .map_err(|error| error.to_string())?;
    Ok((dmb, emitted))
}

/// Appends global procedures to a checked-in builtins-only DMB. This removes
/// the requirement for a project-specific native scaffold while the target
/// builtin schema and direct full-world writer are being constructed.
pub fn emit_global_procs(
    source: &str,
    builtin_image: &[u8],
    world_name: &str,
) -> Result<(Dmb, Vec<EmittedProc>), String> {
    let (dmb, emitted, _) = emit_global_procs_inner(
        source,
        builtin_image,
        world_name,
        None,
        &mut crate::lower_cache::ProcLoweringCache::disabled(),
    )?;
    Ok((dmb, emitted))
}

pub fn emit_global_procs_with_resources(
    source: &str,
    builtin_image: &[u8],
    world_name: &str,
    resources: &ResourceSet,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    emit_global_procs_inner(
        source,
        builtin_image,
        world_name,
        Some(resources),
        &mut crate::lower_cache::ProcLoweringCache::disabled(),
    )
}

/// Only an explicit class path conveys a concrete call-result type. Primitive
/// return restrictions such as `as anything` are not inferred as class paths.
fn declared_proc_return_type(header: &str) -> Result<Option<Option<String>>, String> {
    let Some((_, suffix)) = header.rsplit_once(')') else { return Ok(None); };
    let tokens = dm_syntax::lex_spans(suffix).tokens.into_iter().filter(|token| {
        !matches!(token.kind, TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment)
    }).collect::<Vec<_>>();
    if tokens.is_empty() { return Ok(None); }
    let failure = || "return type must be a type path or atomic restriction".to_owned();
    if tokens[0].text(suffix) != "as" || tokens.len() < 2 { return Err(failure()); }
    if tokens.len() == 2 && tokens[1].kind == TokenKind::Ident { return Ok(Some(None)); }
    let mut path = String::new();
    for (index, token) in tokens[1..].iter().enumerate() {
        if (index % 2 == 0 && token.text(suffix) != "/")
            || (index % 2 == 1 && token.kind != TokenKind::Ident)
        { return Err(failure()); }
        path.push_str(token.text(suffix));
    }
    if (tokens.len() - 1) % 2 != 0 { return Err(failure()); }
    Ok(Some(Some(path)))
}

fn inherited_return_annotation_error(shared: &SharedLowerBindings, owner: &str, name: &str) -> bool {
    let mut owner = owner;
    let mut visited = HashSet::new();
    while let Some(parent) = shared.parent_types.get(owner) {
        if !visited.insert(parent) { break; }
        if shared.known_member_procs.get(parent).is_some_and(|members| members.contains(name))
            || shared.member_procs.get(parent).is_some_and(|members| members.contains_key(name))
        { return true; }
        owner = parent;
    }
    false
}

fn declared_variable_type(header: &str) -> Option<(String, String)> {
    let raw = header
        .trim()
        .strip_prefix("/var/")
        .or_else(|| header.trim().strip_prefix("var/"))
        .or_else(|| {
            header
                .trim()
                .rsplit_once("/var/")
                .map(|(_, variable)| variable)
        })?;
    let declaration = raw.split_once('=').map_or(raw, |(name, _)| name).trim();
    let mut parts = declaration.split('/').collect::<Vec<_>>();
    let raw_name = parts.pop()?.trim();
    let name = raw_name.split('[').next()?;
    if raw_name.contains('[') {
        return Some((name.into(), "/list".into()));
    }
    let type_parts = parts
        .into_iter()
        .filter(|part| !matches!(*part, "global" | "static" | "const" | "tmp"))
        .collect::<Vec<_>>();
    (!name.is_empty() && !type_parts.is_empty())
        .then(|| (name.to_owned(), format!("/{}", type_parts.join("/"))))
}

fn builtin_field_names(path: &str) -> &'static [&'static str] {
    match path {
        "/datum" => &["type", "parent_type", "vars", "tag"],
        "/atom" | "/image" | "/mutable_appearance" => &[
            "name",
            "desc",
            "gender",
            "loc",
            "x",
            "y",
            "z",
            "suffix",
            "text",
            "render_source",
            "render_target",
            "contents",
            "icon",
            "icon_state",
            "dir",
            "layer",
            "plane",
            "density",
            "opacity",
            "mouse_opacity",
            "invisibility",
            "luminosity",
            "infra_luminosity",
            "mouse_drag_pointer",
            "mouse_over_pointer",
            "pixel_x",
            "pixel_y",
            "pixel_z",
            "pixel_w",
            "color",
            "alpha",
            "transform",
            "blend_mode",
            "appearance",
            "appearance_flags",
            "overlays",
            "underlays",
            "filters",
            "maptext",
            "maptext_width",
            "maptext_height",
            "maptext_x",
            "maptext_y",
            "verbs",
        ],
        "/atom/movable" => &[
            "bound_x",
            "bound_y",
            "bound_width",
            "bound_height",
            "step_size",
            "glide_size",
            "screen_loc",
            "animate_movement",
            "locs",
            "vis_contents",
            "vis_locs",
            "vis_flags",
            "particles",
        ],
        "/mob" => &[
            "client",
            "key",
            "ckey",
            "sight",
            "see_in_dark",
            "see_invisible",
            "group",
        ],
        "/client" => &[
            "gender",
            "dir",
            "byond_version",
            "byond_build",
            "address",
            "authentication",
            "ckey",
            "color",
            "computer_id",
            "connection",
            "eye",
            "images",
            "inactivity",
            "key",
            "lazy_eye",
            "mob",
            "perspective",
            "pixel_x",
            "pixel_y",
            "pixel_z",
            "screen",
            "show_map",
            "show_popup_menus",
            "show_verb_panel",
            "statobj",
            "view",
            "virtual_eye",
            "control_freak",
            "verbs",
        ],
        "/world" => &[
            "host",
            "params",
            "name",
            "status",
            "hub",
            "hub_password",
            "url",
            "address",
            "port",
            "time",
            "timeofday",
            "realtime",
            "tick_lag",
            "fps",
            "tick_usage",
            "cpu",
            "maxx",
            "maxy",
            "maxz",
            "view",
            "log",
            "contents",
            "system_type",
            "version",
            "byond_version",
            "byond_build",
            "params",
            "map_format",
            "icon_size",
            "mob",
            "turf",
            "area",
        ],
        "/list" => &["len"],
        "/turf" => &["vis_contents", "vis_locs", "vis_flags"],
        "/particles" => &[
            "width",
            "height",
            "count",
            "spawning",
            "lifespan",
            "fade",
            "fadein",
            "icon",
            "icon_state",
            "color",
            "color_change",
            "position",
            "velocity",
            "gravity",
            "drift",
            "scale",
            "grow",
            "rotation",
            "spin",
            "friction",
            "bound1",
            "bound2",
            "gradient",
            "transform",
        ],
        _ => &[],
    }
}

fn seed_builtin_fields(path: &str, bindings: &mut LowerBindings) {
    let names = builtin_field_names(path);
    bindings
        .fields
        .extend(names.iter().map(|name| (*name).to_owned()));
    for (name, ty) in [
        ("loc", "/atom"),
        ("contents", "/list"),
        ("overlays", "/list"),
        ("underlays", "/list"),
        ("filters", "/list"),
        ("verbs", "/list"),
        ("client", "/client"),
        ("mob", "/mob"),
        ("transform", "/matrix"),
    ] {
        if bindings.fields.contains(name) {
            bindings
                .field_types
                .entry(name.to_owned())
                .or_insert_with(|| ty.to_owned());
        }
    }
}

fn seed_builtin_constants(bindings: &mut SharedLowerBindings) {
    bindings.numeric_constants.extend(
        native_constants::NUMBERS
            .iter()
            .map(|(name, bits)| ((*name).to_owned(), *bits)),
    );
    bindings.string_constants.extend(
        native_constants::STRINGS
            .iter()
            .map(|(name, value)| ((*name).to_owned(), (*value).to_owned())),
    );
}

fn bind_builtin_global_vars(
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    ledger: &mut Ledger,
) -> Result<(), String> {
    let id = if let Some(id) = strings.5 {
        id
    } else {
        let name = strings.intern(dmb, "vars");
        let id = u32::try_from(dmb.variables.len()).map_err(|_| "variable table exceeds u32")?;
        dmb.variables.push(Variable {
            kind: 82,
            value: 0,
            name,
        });
        strings.5 = Some(id);
        id
    };
    ledger
        .bind(
            Symbol::new(
                Table::Variable,
                dm_codegen_byond::BUILTIN_GLOBAL_VARS_SYMBOL,
            ),
            id,
        )
        .map_err(|error| error.to_string())?;
    Ok(())
}

/// All executable sections use the same typed table relocation boundary.
fn bind_prepared_references(
    code: &dm_codegen_byond::relocatable::PreparedProc,
    strings: &StringIndex,
    ledger: &mut Ledger,
    globals: &HashMap<String, u32>,
    overrides: Option<&HashMap<String, u32>>,
    procedures: &HashMap<String, u32>,
) -> Result<(), String> {
    let mut result = Ok(());
    code.for_each_reference(|table, key| {
        if result.is_err() { return; }
        let id = match table {
            Table::Instance => strings.4.get(key),
            Table::Proc => procedures.get(key),
            Table::Variable => overrides.and_then(|map| map.get(key)).or_else(|| globals.get(key)),
            _ => None,
        };
        if let Some(id) = id {
            if ledger.id(&Symbol::new(table, key)).is_none() {
                result = ledger.bind(Symbol::new(table, key), *id).map_err(|error| error.to_string());
            }
        } else if table == Table::Instance {
            result = Err(format!("unresolved modified type: {key}"));
        }
    });
    result
}

#[derive(Default)]
struct ReplayScratch {
    strings: Vec<(u32, u32)>,
    debug: Vec<(String, u32)>,
    debug_ids: Vec<(u32, u32)>,
    assignments: Vec<Option<u32>>,
}
/// Recompose a cached authored node using only its explicit output dependencies.
/// No signature parsing, lower frame, symbolic body, or metadata reconstruction
/// enters this path. Dense IDs patch flat external slots and small record fields.
fn replay_procedure_fragment(
    fragment: &procedure_fragments::OutputFragment,
    semantic_identity:&str,
    scratch: &mut ReplayScratch,
    pending: &PendingProc<'_>,
    plan: &canonical::InvocationPlan,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    class_paths: &HashMap<String, u32>,
    resources: &HashMap<String, u32>,
    globals: &HashMap<String, u32>,
    procedures: &HashMap<String, u32>,
    source_debug: Option<&crate::source_debug::SourceDebugIndex<'_>>,
    graph: &mut crate::ProjectProcedureGraph,
    active: &mut BTreeSet<crate::ProcKey>,
    argument_indices: &mut HashMap<String, usize>,
    argument_sources: &mut Vec<(usize, Arc<dm_codegen_byond::prepared_cache::PreparedProcedureEnvelope>, HashMap<String, u32>)>,
) -> Result<Option<(usize, Arc<[u32]>, bool, bool)>, String> {
    if fragment.debug_enabled != source_debug.is_some() { return Ok(None); }
    let linked_start=procedure_fragments::AllocationCounts::from_dmb(dmb);
    let body_base = pending.span().start + fragment.body_base_relative;
    scratch.debug.clear(); scratch.debug_ids.clear(); scratch.strings.clear(); scratch.assignments.clear();
    if fragment.unresolved_debug.iter().any(|relative| source_debug
        .and_then(|source| source.resolve(body_base.checked_add(*relative)?)).is_some()) { return Ok(None); }
    for mark in &fragment.debug {
        let Some(origin) = source_debug.and_then(|source| source.resolve(body_base.checked_add(mark.relative)?)) else { return Ok(None); };
        scratch.debug.push(origin);
    }
    // Check semantic helper edges before performing any output allocation.
    let mut helpers = Vec::new();
    for helper in &fragment.helpers {
        if graph.probe_validity(&helper.key, &helper.descriptor).as_deref() != Some(helper.identity.as_str()) { return Ok(None); }
        let crate::ProcedureProbe::Resident(crate::ProcedureArtifact::Prepared(envelope)) = graph.probe(&helper.key, &helper.descriptor) else { return Ok(None); };
        helpers.push((helper, envelope));
    }
    scratch.assignments.reserve(fragment.relocations.len());
    for relocation in &fragment.relocations {
        let key = &relocation.symbol.key;
        let id = match relocation.symbol.table {
            Table::String => None, // The ordered string recipe supplies exact current IDs below.
            Table::Class => class_link_id(dmb, class_paths, key),
            Table::Resource => resources.get(key).copied(),
            Table::Variable if key == dm_codegen_byond::BUILTIN_GLOBAL_VARS_SYMBOL => strings.5,
            Table::Variable => plan.static_ids.get(key).or_else(|| globals.get(key)).copied(),
            Table::Proc => procedures.get(key).copied(),
            Table::Instance => strings.4.get(key).copied(),
            _ => None,
        };
        if id.is_none() && relocation.symbol.table != Table::String { return Ok(None); }
        scratch.assignments.push(id);
    }
    scratch.debug_ids.resize(fragment.debug.len(), (0, 0));
    for recipe in &fragment.strings {
        match recipe {
            procedure_fragments::StringRecipe::Bytes { old_id, bytes } => {
                scratch.strings.push((*old_id, strings.intern_bytes(dmb, bytes)));
            }
            procedure_fragments::StringRecipe::Debug { index } => {
                let Some((file, line)) = scratch.debug.get(*index) else { return Ok(None); };
                scratch.debug_ids[*index] = (strings.intern(dmb, file), *line);
            }
        }
    }
    scratch.strings.sort_unstable_by_key(|pair| pair.0);
    let string_id = |old: u32| -> Result<u32, String> {
        if old == 0xffff { return Ok(old); }
        scratch.strings.binary_search_by_key(&old, |pair| pair.0)
            .map(|index| scratch.strings[index].1).map_err(|_| "output DAG string dependency missing".into())
    };
    // Exact allocation and assignment projections authorize reuse of already
    // linked typed rows. Ordered interning above proves current string IDs;
    // debug, resources and all external dense operands remain explicit edges.
    let linked_reusable=fragment.linked.as_ref().is_some_and(|linked| {
        let Some(start)=linked_start.as_ref() else {return false;};
        linked.matches_optional(&procedure_fragments::WitnessObservation {
            semantic_identity,recipe_identity:&linked.recipe_identity,start:start.clone(),
            read_identities:&[],scalar_reads:&[],unresolved_debug:&fragment.unresolved_debug,
        },fragment.relocations.iter().zip(&scratch.assignments).map(|(relocation,current)| {
            if relocation.symbol.table==Table::String {
                let at=relocation.offset as usize;
                let expected=match relocation.packed_tag {None=>fragment.words[at],Some(_)=>((fragment.words[at]>>8)<<16)|fragment.words[at+1]};
                string_id(expected).ok()
            } else {*current}
        }),scratch.strings.iter().map(|(_,current)|*current),scratch.debug_ids.iter().copied())
    });
    if linked_reusable {
        let (locals,arguments,expected_lists)=if let Some(layout)=&fragment.allocated_rows {
            let base=linked_start.as_ref().ok_or("linked output allocation base exceeds u32")?;
            let locals=fragment.locals.iter().enumerate().map(|(index,&relative)|
                layout.resolve(procedure_fragments::SiteKind::LocalVariable(index as u32),relative,base)
                    .ok_or("linked local allocation reference missing")).collect::<Result<Vec<_>,_>>()?;
            let mut arguments=fragment.arguments.to_vec();
            for (index,argument) in arguments.chunks_exact_mut(4).enumerate() {
                argument[2]=layout.resolve(procedure_fragments::SiteKind::ArgumentVariable(index as u32),argument[2],base)
                    .ok_or("linked argument allocation reference missing")?;
            }
            let expected=[layout.resolve(procedure_fragments::SiteKind::ProcedureCode,0,base),
                layout.resolve(procedure_fragments::SiteKind::ProcedureLocals,1,base),
                layout.resolve(procedure_fragments::SiteKind::ProcedureArguments,2,base)];
            let [Some(code),Some(local),Some(args)]=expected else {return Err("linked list allocation overflow".into());};
            (Arc::<[u32]>::from(locals),Arc::<[u32]>::from(arguments),[code,local,args])
        } else {(Arc::clone(&fragment.locals),Arc::clone(&fragment.arguments),fragment.record.code_locals_args)};
        dmb.variables.extend(fragment.variables.iter().cloned());
        let code_id=dmb.append_shared_list(Arc::clone(&fragment.words)).map_err(|error|error.to_string())?;
        let locals_id=dmb.append_shared_list(locals).map_err(|error|error.to_string())?;
        let args_id=dmb.append_shared_list(arguments).map_err(|error|error.to_string())?;
        if expected_lists!=[code_id,locals_id,args_id] {
            return Err("linked output rows disagree with allocation witness".into());
        }
        crate::reserve_proc_sentinel(dmb);
        let proc_index=dmb.procs.len();
        let mut record=fragment.record.clone();record.code_locals_args=expected_lists;dmb.procs.push(record);
        attach_emitted_proc(dmb,pending.owner,&pending.owner_path,pending.verb,proc_index);
        return Ok(Some((proc_index,Arc::clone(&fragment.words),false,true)));
    }
    let mut words = Arc::clone(&fragment.words);
    let mut relocated = false;
    for (relocation, assigned) in fragment.relocations.iter().zip(scratch.assignments.iter().copied()) {
        let at = relocation.offset as usize;
        let old = match relocation.packed_tag {
            None => words[at], Some(_) => ((words[at] >> 8) << 16) | words[at + 1],
        };
        let id = if relocation.symbol.table == Table::String { string_id(old)? } else { assigned.unwrap() };
        if id != old {
            relocated = true;
            let output = Arc::make_mut(&mut words);
            match relocation.packed_tag {
                None => output[at] = id,
                Some(tag) => { output[at] = u32::from(tag) | ((id >> 16) << 8); output[at + 1] = id & 0xffff; }
            }
        }
    }
    for (mark, &(file, line)) in fragment.debug.iter().zip(&scratch.debug_ids) {
        if words[mark.file_offset as usize] != file || words[mark.line_offset as usize] != line {
            relocated = true;
            let output = Arc::make_mut(&mut words);
            output[mark.file_offset as usize] = file; output[mark.line_offset as usize] = line;
        }
    }
    let variable_base = dmb.variables.len() as u32;
    for variable in &fragment.variables {
        let mut variable = variable.clone(); variable.name = string_id(variable.name)?;
        dmb.variables.push(variable);
    }
    let variable_id = |site:procedure_fragments::SiteKind,old: u32| -> Result<u32, String> {
        if let Some(layout)=&fragment.allocated_rows {
            return layout.resolve(site,old,linked_start.as_ref().ok_or("output allocation base exceeds u32")?)
                .ok_or_else(||"output DAG relative variable dependency missing".into());
        }
        old.checked_sub(fragment.old_variable_base).filter(|offset| (*offset as usize) < fragment.variables.len())
            .and_then(|offset| variable_base.checked_add(offset)).ok_or_else(|| "output DAG local variable dependency missing".into())
    };
    let code_id = dmb.append_shared_list(Arc::clone(&words)).map_err(|error|error.to_string())?;
    let locals = fragment.locals.iter().enumerate().map(|(index,&id)| variable_id(procedure_fragments::SiteKind::LocalVariable(index as u32),id)).collect::<Result<Vec<_>, _>>()?;
    let locals_id = append_list(dmb, locals);
    let mut arguments = fragment.arguments.to_vec();
    for (index,argument) in arguments.chunks_exact_mut(4).enumerate() { argument[2] = variable_id(procedure_fragments::SiteKind::ArgumentVariable(index as u32),argument[2])?; }
    for (helper, envelope) in helpers {
        active.insert(helper.key.clone());
        let current_statics: BTreeMap<_, _> = helper.statics.keys()
            .filter_map(|name| plan.static_ids.get(name).map(|id| (name.clone(), *id))).collect();
        let dedup = if current_statics == helper.statics { helper.dedup.clone() } else {
            crate::lower_cache::shared_binding_fingerprint(&(envelope.section.encode().map_err(|e| e.to_string())?, current_statics))
        };
        let index = if let Some(&index) = argument_indices.get(&dedup) { index } else {
            let index = dmb.proc_references.len();
            if index > u8::MAX as usize { return Err("too many distinct argument source procedures".into()); }
            dmb.proc_references.push(0xffff);
            argument_sources.push((index, envelope, plan.static_ids.clone()));
            argument_indices.insert(dedup, index); index
        };
        let word = arguments.get_mut(helper.parameter * 4 + 1).ok_or("output DAG helper argument missing")?;
        *word = ((index as u32) << 8) | 0x40;
    }
    let args_id = append_list(dmb, arguments);
    let mut record = fragment.record.clone();
    for id in &mut record.strings { *id = string_id(*id)?; }
    record.code_locals_args = [code_id, locals_id, args_id];
    crate::reserve_proc_sentinel(dmb);
    let proc_index = dmb.procs.len(); dmb.procs.push(record);
    attach_emitted_proc(dmb, pending.owner, &pending.owner_path, pending.verb, proc_index);
    Ok(Some((proc_index, words, relocated,false)))
}

fn attach_emitted_proc(dmb: &mut Dmb, owner: Option<u32>, owner_path: &str, verb: bool, proc_index: usize) {
    if let Some(class_id) = owner {
        let slot = if verb { 0 } else { 1 };
        let list_id = dmb.classes[class_id as usize].lists_and_procs[slot];
        if list_id == 0xffff {
            let list = append_list(dmb, vec![proc_index as u32]);
            dmb.classes[class_id as usize].lists_and_procs[slot] = list;
        } else { dmb.lists[list_id as usize].push(proc_index as u32); }
    } else if owner_path == "/world" {
        let list_id = dmb.world.ids[3];
        if list_id == 0xffff { dmb.world.ids[3] = append_list(dmb, vec![proc_index as u32]); }
        else { dmb.lists[list_id as usize].insert(0, proc_index as u32); }
    }
}

fn static_symbol(prefix: &str, owner: &str, name: &str) -> String {
    format!("{prefix}{}", crate::lower_cache::shared_binding_fingerprint(&(owner, name)))
}

fn class_static_symbol(dmb: &Dmb, class: u32, name: &str) -> String {
    let owner = dmb.string(dmb.classes[class as usize].path_string_id()).unwrap_or_default();
    static_symbol("__dm_class_static_", &String::from_utf8_lossy(owner), name)
}

/// Typed global/static members belong to global storage, even for a null receiver.
fn seed_member_globals(shared: &mut SharedLowerBindings, dmb: &Dmb) -> HashMap<String, u32> {
    let mut aliases = HashMap::new();
    for (class_id, class) in dmb.classes.iter().enumerate() {
        let Some(owner) = dmb
            .string(class.path_string_id())
            .and_then(|path| std::str::from_utf8(path).ok())
        else {
            continue;
        };
        let mut builtin_fields = LowerBindings::default();
        seed_builtin_fields(owner, &mut builtin_fields);
        shared
            .known_member_fields
            .entry(owner.to_owned())
            .or_default()
            .extend(builtin_fields.fields);
        for (variable, flags) in dmb
            .class_variable_declarations(class_id)
            .unwrap_or_default()
        {
            if let Some(name) = dmb
                .variables
                .get(variable as usize)
                .and_then(|var| dmb.string(var.name))
                .and_then(|name| std::str::from_utf8(name).ok())
            {
                shared
                    .known_member_fields
                    .entry(owner.to_owned())
                    .or_default()
                    .insert(name.to_owned());
            }
            if flags & 1 == 0 {
                continue;
            }
            let Some(name) = dmb
                .variables
                .get(variable as usize)
                .and_then(|var| dmb.string(var.name))
                .and_then(|name| std::str::from_utf8(name).ok())
            else {
                continue;
            };
            let alias = static_symbol("__dm_class_static_", owner, name);
            shared
                .member_globals
                .entry(owner.to_owned())
                .or_default()
                .insert(name.to_owned(), alias.clone());
            shared.globals.insert(alias.clone());
            aliases.insert(alias, variable);
        }
    }
    aliases
}

fn seed_native_member_procs(shared: &mut SharedLowerBindings, dmb: &Dmb) {
    for class in &dmb.classes {
        let Some(owner) = dmb
            .string(class.path_string_id())
            .and_then(|value| std::str::from_utf8(value).ok())
        else {
            continue;
        };
        for slot in 0..2 {
            let Some(list) = dmb.lists.get(class.lists_and_procs[slot] as usize) else {
                continue;
            };
            for id in list {
                let Some(path) = dmb
                    .procs
                    .get(*id as usize)
                    .and_then(|proc| dmb.string(proc.strings[0]))
                    .and_then(|value| std::str::from_utf8(value).ok())
                else {
                    continue;
                };
                if let Some(name) = path.rsplit('/').next() {
                    shared
                        .known_member_procs
                        .entry(owner.to_owned())
                        .or_default()
                        .insert(name.to_owned());
                    let default_name = name.replace('_', " ");
                    if dmb.string(dmb.procs[*id as usize].strings[1])
                        != Some(default_name.as_bytes())
                    {
                        shared
                            .member_procs
                            .entry(owner.to_owned())
                            .or_default()
                            .insert(name.to_owned(), path.to_owned());
                    }
                }
            }
        }
    }
}

fn builtin_constant(name: &str) -> Option<const_eval::Constant> {
    native_constants::NUMBERS
        .iter()
        .find(|(key, _)| *key == name)
        .map(|(_, bits)| const_eval::Constant::Number(f32::from_bits(*bits)))
        .or_else(|| {
            native_constants::STRINGS
                .iter()
                .find(|(key, _)| *key == name)
                .map(|(_, value)| const_eval::Constant::Text((*value).to_owned()))
        })
}
#[derive(Default, Clone)]
struct ModifiedTypes {
    aliases: HashMap<String, String>,
    declarations: Vec<Item>,
    parents: HashMap<String, String>,
}

fn modified_key(text: &str) -> String {
    let mut key = String::new();
    dm_syntax::visit_tokens(text, |token| {
        if !matches!(
            token.kind,
            TokenKind::Comment | TokenKind::Newline | TokenKind::Whitespace
        ) {
            key.push_str(token.text(text));
        }
    });
    key
}

fn modified_spans(source: &str) -> Vec<dm_syntax::Span> {
    let mut spans = Vec::new();
    let mut active: Option<(usize, usize)> = None;
    dm_syntax::visit_tokens(source, |token| {
        if token.text(source) == "{" {
            if let Some((_, depth)) = &mut active {
                *depth += 1;
                return;
            }
            let mut end = token.span.start;
            while end > 0 && source.as_bytes()[end - 1].is_ascii_whitespace() {
                end -= 1;
            }
            let mut start = end;
            while start > 0
                && (source.as_bytes()[start - 1].is_ascii_alphanumeric()
                    || matches!(source.as_bytes()[start - 1], b'/' | b'_'))
            {
                start -= 1;
            }
            if source
                .get(start..end)
                .is_some_and(|path| path.starts_with('/') && path.len() > 1)
            {
                active = Some((start, 1));
            }
        } else if token.text(source) == "}" {
            if let Some((start, depth)) = &mut active {
                *depth -= 1;
                if *depth == 0 {
                    spans.push(dm_syntax::Span::new(*start, token.span.end));
                    active = None;
                }
            }
        }
    });
    spans
}

fn collect_modified_types(source: &str) -> Result<ModifiedTypes, String> {
    use sha2::{Digest, Sha256};
    let mut modified = ModifiedTypes::default();
    for span in modified_spans(source) {
        let text = &source[span.range()];
        let key = modified_key(text);
        if modified.aliases.contains_key(&key) {
            continue;
        }
        let parsed = dm_syntax::parse_expression(text);
        let Some(expr) = parsed.expr else {
            return Err(format!("modified type syntax: {:?}", parsed.diagnostics));
        };
        let dm_syntax::ExprKind::ObjectInitializer { object, fields } = expr.kind else {
            continue;
        };
        let dm_syntax::ExprKind::TypePath(parent) = object.kind else {
            return Err("modified type requires an explicit type path".into());
        };
        let parent = parent.trim_end_matches('/');
        let digest = Sha256::digest(key.as_bytes());
        let suffix = digest[..12]
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let path = format!("{parent}/__dm_modified_{suffix}");
        let mut children = Vec::new();
        for (name, value) in fields {
            let value = text
                .get(value.span.range())
                .ok_or("invalid modified type value span")?;
            children.push(Item {
                kind: ItemKind::Statement,
                header: format!("{name} = {value}"),
                span,
                header_span: span,
                indent: 1,
                children: Vec::new(),
            });
        }
        modified.declarations.push(Item {
            kind: ItemKind::Type,
            header: path.clone(),
            span,
            header_span: span,
            indent: 0,
            children,
        });
        modified.parents.insert(path.clone(), parent.to_owned());
        modified.aliases.insert(key, path);
    }
    Ok(modified)
}

/// Shared immutable declaration nodes are charged once by the coordinator,
/// rather than once for each worktree that borrows them.
pub fn shared_declaration_cache_bytes() -> usize {
    semantic_declarations::resident_bytes()+modified_memos().lock().unwrap_or_else(|e| e.into_inner()).bytes
        +modified_layout().lock().unwrap_or_else(|e| e.into_inner()).resident_bytes()
}
pub fn trim_shared_declaration_cache(max_bytes: usize) {
    if shared_declaration_cache_bytes() > max_bytes {
        *modified_memos().lock().unwrap_or_else(|e| e.into_inner()) = ModifiedMemoCache::default();
        modified_layout().lock().unwrap_or_else(|e| e.into_inner()).clear();
    }
    semantic_declarations::trim_to(max_bytes);
}

#[derive(Default)]
struct ModifiedMemoCache { entries: HashMap<String, Arc<ModifiedTypes>>, bytes: usize }
fn modified_memos() -> &'static std::sync::Mutex<ModifiedMemoCache> {
    static MEMOS: std::sync::OnceLock<std::sync::Mutex<ModifiedMemoCache>> = std::sync::OnceLock::new();
    MEMOS.get_or_init(Default::default)
}
fn modified_layout() -> &'static std::sync::Mutex<dm_syntax::SegmentedChunkSession> {
    static LAYOUT: std::sync::OnceLock<std::sync::Mutex<dm_syntax::SegmentedChunkSession>> = std::sync::OnceLock::new();
    LAYOUT.get_or_init(Default::default)
}
fn modified_bytes(value: &ModifiedTypes) -> usize {
    fn item(value: &Item) -> usize { value.header.capacity()+std::mem::size_of::<Item>()+value.children.iter().map(item).sum::<usize>() }
    value.aliases.iter().chain(&value.parents).map(|(a,b)| a.capacity()+b.capacity()+96).sum::<usize>()
        +value.declarations.iter().map(item).sum::<usize>()+192
}

fn collect_modified_types_segmented(source: &dm_syntax::SegmentedSource) -> Result<ModifiedTypes, String> {
    let memos = modified_memos();
    let mut layout = std::mem::take(&mut *modified_layout().lock().unwrap_or_else(|e| e.into_inner()));
    let limit = std::env::var("DM_BUILD_MAX_PARSE_CHUNK_BYTES").ok().and_then(|v| v.parse().ok()).unwrap_or(1024*1024);
    let mut result = ModifiedTypes::default();
    let mut failure = None;
    let scanned = source.for_each_chunk_cached(&mut layout, 32*1024, limit, |text, base| {
        if failure.is_some() { return; }
        let key = crate::incremental::digest(text.as_bytes());
        let cached = memos.lock().unwrap_or_else(|error| error.into_inner()).entries.get(&key).cloned();
        let collected = if let Some(cached) = cached { Ok((*cached).clone()) }
            else { collect_modified_types(text).map(|found| {
                let mut cache = memos.lock().unwrap_or_else(|error| error.into_inner());
                let bytes = modified_bytes(&found)+key.len();
                if cache.entries.len() >= 8192 || cache.bytes+bytes > 32*1024*1024 { *cache = ModifiedMemoCache::default(); }
                if bytes <= 32*1024*1024 {
                    cache.bytes += bytes;
                    cache.entries.insert(key, Arc::new(found.clone()));
                }
                found
            }) };
        match collected {
            Ok(mut found) => {
                fn rebase(item: &mut Item, base: usize) {
                    item.span.start += base; item.span.end += base;
                    item.header_span.start += base; item.header_span.end += base;
                    for child in &mut item.children { rebase(child, base); }
                }
                for mut declaration in found.declarations.drain(..) {
                    if result.parents.contains_key(&declaration.header) { continue; }
                    rebase(&mut declaration, base);
                    result.declarations.push(declaration);
                }
                result.parents.extend(found.parents);
                result.aliases.extend(found.aliases);
            }
            Err(error) => failure = Some(error),
        }
    });
    *modified_layout().lock().unwrap_or_else(|e| e.into_inner()) = layout;
    scanned?;
    if let Some(error) = failure { return Err(error); }
    Ok(result)
}

fn rewrite_modified_items(items: &mut [Item], modified: &ModifiedTypes) {
    if modified.aliases.is_empty() {
        return;
    }
    for item in items {
        let mut edits = Vec::new();
        for span in modified_spans(&item.header) {
            if let Some(path) = modified
                .aliases
                .get(&modified_key(&item.header[span.range()]))
            {
                edits.push((span, path));
            }
        }
        for (span, path) in edits.into_iter().rev() {
            item.header.replace_range(span.range(), path);
        }
        rewrite_modified_items(&mut item.children, modified);
    }
}

/// Retain declarations and source locations without retaining procedure bodies.
/// Bodies are parsed separately when their procedure is lowered.
fn compact_declaration_item(item: &Item, base_offset: usize) -> Item {
    compact_declaration_item_in(item, base_offset, "/")
}

fn canonical_declaration_owner(owner: &str, raw: &str) -> String {
    let raw = if raw == "/" {
        raw
    } else {
        raw.trim_end_matches('/')
    };
    if raw.starts_with('/') {
        raw.to_owned()
    } else if owner == "/" {
        format!("/{raw}")
    } else {
        format!("{owner}/{raw}")
    }
}

fn compact_declaration_item_in(item: &Item, base_offset: usize, containing_owner: &str) -> Item {
    if item.header.trim_start().starts_with('/') {
        if let Some(index) = dm_syntax::top_level_assignment_index(&item.header) {
            let (target, expression) = (&item.header[..index], &item.header[index + 1..]);
            if !target.contains("/var/") && !target.contains('(') {
                if let Some((owner, name)) = target.trim().rsplit_once('/') {
                    if !owner.is_empty() {
                        let mut child = item.clone();
                        child.kind = ItemKind::Statement;
                        child.header = format!("{name} = {}", expression.trim());
                        let mut wrapper = item.clone();
                        wrapper.kind = ItemKind::Type;
                        wrapper.header = owner.to_owned();
                        wrapper.children = vec![child];
                        return compact_declaration_item_in(
                            &wrapper,
                            base_offset,
                            containing_owner,
                        );
                    }
                }
            }
        }
    }
    if item.kind == ItemKind::Var {
        let normalized = normalize_variable_header(&item.header);
        if let Some((owner, variable)) = normalized.trim().split_once("/var/") {
            if !owner.is_empty() {
                let owner_path = canonical_declaration_owner(containing_owner, owner);
                let mut child = item.clone();
                child.header = format!("var/{variable}");
                return Item {
                    kind: ItemKind::Type,
                    header: owner_path.clone(),
                    span: dm_syntax::Span::new(
                        item.span.start + base_offset,
                        item.span.end + base_offset,
                    ),
                    header_span: dm_syntax::Span::new(
                        item.header_span.start + base_offset,
                        item.header_span.start + base_offset + owner.len(),
                    ),
                    indent: item.indent,
                    children: vec![compact_declaration_item_in(
                        &child,
                        base_offset,
                        &owner_path,
                    )],
                };
            }
        }
    }
    let mut compact = Item {
        kind: item.kind,
        header: if item.kind == ItemKind::Type {
            canonical_declaration_owner(containing_owner, item.header.trim())
        } else if item.kind == ItemKind::Var {
            normalize_variable_header(&item.header)
        } else {
            item.header.clone()
        },
        span: dm_syntax::Span {
            start: item.span.start + base_offset,
            end: item.span.end + base_offset,
        },
        header_span: dm_syntax::Span {
            start: item.header_span.start + base_offset,
            end: item.header_span.end + base_offset,
        },
        indent: item.indent,
        children: Vec::new(),
    };
    if !matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
        let owner = if compact.kind == ItemKind::Type {
            compact.header.as_str()
        } else {
            containing_owner
        };
        compact.children = item
            .children
            .iter()
            .map(|child| compact_declaration_item_in(child, base_offset, owner))
            .collect();
    } else {
        fn declaration_tree(item: &Item, base: usize, owner: &str) -> Option<Item> {
            let header = item.header.trim_start();
            let retained = header.starts_with("set ") || ["var/static/", "var/global/", "var/const/"]
                .iter().any(|prefix| header.starts_with(prefix));
            let children: Vec<_> = item.children.iter().filter_map(|child| declaration_tree(child, base, owner)).collect();
            if !retained && children.is_empty() { return None; }
            let mut result = compact_declaration_item_in(item, base, owner);
            result.children = children;
            Some(result)
        }
        compact.children = item.children.iter()
            .filter_map(|child| declaration_tree(child, base_offset, containing_owner)).collect();
    }
    compact
}

/// A portable declaration boundary for body-only incremental emission.
/// Exact non-procedure bytes and unsafe procedure bodies remain in the ABI hash.
pub fn incremental_source_outline(
    source: &str,
) -> Result<crate::incremental::SourceOutline, String> {
    let ast = declaration_snapshot(source)?;
    source_outline_from_snapshot(source, &ast)
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub(crate) struct OutlineDescriptor {
    pub start: usize,
    pub end: usize,
    pub header_end: usize,
    pub path: String,
    pub safe_signature: bool,
}

pub(crate) fn outline_descriptors(
    ast: &dm_syntax::AstFile,
) -> Result<Vec<OutlineDescriptor>, String> {
    fn collect<'a>(
        items: &'a [Item],
        owner: &str,
        output: &mut Vec<(&'a Item, String, String, bool)>,
    ) -> Result<(), String> {
        for item in items {
            if item.kind == ItemKind::Type {
                collect(&item.children, &item.header, output)?;
            } else if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
                let raw = item
                    .header
                    .split('(')
                    .next()
                    .unwrap_or("")
                    .trim()
                    .trim_end_matches('/');
                let verb = item.kind == ItemKind::Verb || raw.contains("/verb/");
                let actual_owner = if raw.starts_with('/') {
                    raw.rsplit_once(if verb { "/verb/" } else { "/proc/" })
                        .map(|(parent, _)| parent.to_owned())
                        .or_else(|| raw.rsplit_once('/').map(|(parent, _)| parent.to_owned()))
                        .unwrap_or_default()
                } else {
                    owner.to_owned()
                };
                let actual_owner = if matches!(actual_owner.as_str(), "/proc" | "/verb" | "/") {
                    String::new()
                } else {
                    actual_owner
                };
                let (path, params) = member_signature(item, &actual_owner, verb)?;
                let safe_signature = params
                    .iter()
                    .all(|p| p.default.is_none() && p.source_expression.is_none());
                output.push((item, path, actual_owner, safe_signature));
            } else {
                collect(&item.children, owner, output)?;
            }
        }
        Ok(())
    }
    let mut declarations = Vec::new();
    collect(&ast.items, "", &mut declarations)?;
    declarations.sort_by_key(|(item, _, _, _)| item.span.start);
    Ok(declarations
        .into_iter()
        .map(|(item, path, _, safe_signature)| OutlineDescriptor {
            start: item.span.start,
            end: item.span.end,
            header_end: item.header_span.end.min(item.span.end),
            path,
            safe_signature,
        })
        .collect())
}

fn source_outline_from_snapshot(
    source: &str,
    ast: &dm_syntax::AstFile,
) -> Result<crate::incremental::SourceOutline, String> {
    let declarations = outline_descriptors(ast)?;
    let mut counts = HashMap::<String, usize>::new();
    for declaration in &declarations {
        *counts.entry(declaration.path.clone()).or_default() += 1;
    }
    use sha2::Digest;
    let mut abi = sha2::Sha256::new();
    let mut previous = 0;
    let mut procedures = BTreeMap::new();
    for declaration in declarations {
        let OutlineDescriptor {
            start,
            end,
            header_end,
            path,
            safe_signature,
        } = declaration;
        if start < previous || end > source.len() {
            return Err("overlapping or invalid procedure spans in incremental outline".into());
        }
        abi.update(source[previous..start].as_bytes());
        let raw = &source[start..end];
        let unsafe_body = procedure_body_requires_full_emission(raw);
        let patchable = safe_signature && !unsafe_body && counts[&path] == 1;
        if patchable {
            abi.update(source[start..header_end].as_bytes());
            // Frame each omitted body, so adjacent declarations cannot alias.
            abi.update(b"\0BODY\0");
        } else {
            abi.update(raw.as_bytes());
        }
        procedures.insert(
            path,
            crate::incremental::ProcedureSource {
                source: std::sync::Arc::from(raw),
                digest: crate::incremental::digest(raw.as_bytes()),
                patchable,
            },
        );
        previous = end;
    }
    abi.update(source[previous..].as_bytes());
    Ok(crate::incremental::SourceOutline {
        abi_digest: format!("{:x}", abi.finalize()),
        procedures,
    })
}

pub(crate) fn procedure_body_requires_full_emission(source: &str) -> bool {
    let mut unsafe_body = false;
    dm_syntax::visit_tokens(source, |token| {
        unsafe_body |= token.kind == TokenKind::Resource
            || matches!(
                token.text(source),
                "static" | "const" | "set" | "global" | "{"
            );
    });
    unsafe_body
}

/// Recover inherited lexical fields without storing them for every procedure.
pub(crate) fn restore_owner_bindings(
    dmb: &Dmb,
    owner: &str,
    bindings: &mut LowerBindings,
) -> Result<(), String> {
    if owner.is_empty() {
        return Ok(());
    }
    if owner == "/world" {
        seed_builtin_fields(owner, bindings);
        return Ok(());
    }
    let mut class =
        dmb.classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(owner.as_bytes()))
            .ok_or_else(|| format!("incremental owner type missing: {owner}"))? as u32;
    let mut visited = HashSet::new();
    loop {
        if !visited.insert(class) {
            return Err(format!("incremental owner inheritance cycle: {owner}"));
        }
        let record = dmb
            .classes
            .get(class as usize)
            .ok_or_else(|| format!("invalid incremental owner class: {class}"))?;
        if let Some(bytes) = dmb.string(record.path_string_id()) {
            let path = String::from_utf8_lossy(bytes);
            seed_builtin_fields(&path, bindings);
            if let Some(types) = bindings
                .shared
                .as_ref()
                .and_then(|shared| shared.member_types.get(path.as_ref()))
            {
                for (name, ty) in types {
                    bindings
                        .field_types
                        .entry(name.clone())
                        .or_insert_with(|| ty.clone());
                }
            }
        }
        if let Some(declarations) = dmb.class_variable_declarations(class as usize) {
            for (id, _) in declarations {
                let variable = dmb
                    .variables
                    .get(id as usize)
                    .ok_or_else(|| format!("invalid incremental field variable: {id}"))?;
                if let Some(name) = dmb.string(variable.name) {
                    bindings
                        .fields
                        .insert(String::from_utf8_lossy(name).into_owned());
                }
            }
        }
        let parent = record.parent_class_id();
        if parent == 0xffff {
            break;
        }
        class = parent;
    }
    Ok(())
}

pub(crate) fn incremental_class_link_id(dmb: &Dmb, path: &str) -> Option<u32> {
    let classes = dmb
        .classes
        .iter()
        .enumerate()
        .filter_map(|(id, class)| {
            Some((
                String::from_utf8(dmb.string(class.path_string_id())?.to_vec()).ok()?,
                id as u32,
            ))
        })
        .collect();
    class_link_id(dmb, &classes, path)
}

fn normalize_variable_header(header: &str) -> String {
    let (declaration, initial) = header
        .split_once('=')
        .map_or((header, None), |(declaration, initial)| {
            (declaration, Some(initial))
        });
    let declaration = declaration
        .split_once(" as ")
        .map_or(declaration, |(name, _)| name)
        .trim();
    let mut declaration = declaration.to_owned();
    while declaration.contains("var/var/") {
        declaration = declaration.replace("var/var/", "var/");
    }
    if let Some(initial) = initial {
        format!("{declaration} = {}", initial.trim())
    } else {
        declaration
    }
}

pub(crate) fn declaration_snapshot(source: &str) -> Result<dm_syntax::AstFile, String> {
    let limit = std::env::var("DM_BUILD_MAX_PARSE_CHUNK_BYTES")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(1024 * 1024);
    declaration_snapshot_with_limit(source, limit)
}

/// The streaming frontend has already proven this fragment's complete
/// declaration boundaries and allocation limit. Do not scan them a second time.
pub(crate) fn declaration_snapshot_fragment(source: &str) -> Result<(dm_syntax::AstFile,Vec<usize>), String> {
    let (parsed,sensitive) = dm_syntax::parse_declarations_with_sensitive_offsets(source);
    if !parsed.diagnostics.is_empty() { return Err(format!("syntax diagnostics: {:?}", parsed.diagnostics)); }
    Ok((dm_syntax::AstFile { items: parsed.items.iter().map(|item|compact_declaration_item(item,0)).collect(), ..Default::default() },sensitive))
}

fn declaration_snapshot_with_limit(
    source: &str,
    limit: usize,
) -> Result<dm_syntax::AstFile, String> {
    let mut declarations = dm_syntax::AstFile::default();
    let report = dm_syntax::for_each_parsed_chunk(source, limit, |chunk, offset| {
        declarations.items.extend(
            chunk
                .items
                .iter()
                .map(|item| compact_declaration_item(item, offset)),
        );
        declarations
            .diagnostics
            .extend(chunk.diagnostics.iter().cloned().map(|mut diagnostic| {
                diagnostic.span.start += offset;
                diagnostic.span.end += offset;
                diagnostic
            }));
    });
    if report.skipped_declarations > 0 {
        return Err(format!("{} declarations exceed the parse chunk limit of {limit} bytes (first {:?}); set DM_BUILD_MAX_PARSE_CHUNK_BYTES to raise it", report.skipped_declarations, report.first_skipped_span));
    }
    if !declarations.diagnostics.is_empty() {
        return Err(format!(
            "syntax diagnostics: {:?}",
            declarations.diagnostics
        ));
    }
    Ok(declarations)
}

/// Declaration-only inspection. Error examples are capped at 64 entries.
#[derive(Debug, Default)]
pub struct DeclarationAudit {
    pub source_bytes: usize,
    pub parsed_chunks: usize,
    pub skipped_declarations: usize,
    pub compact_items: usize,
    pub compact_header_bytes: usize,
    pub procedure_items: usize,
    pub syntax_error_count: usize,
    pub syntax_errors: Vec<dm_syntax::Diagnostic>,
    pub index_error_count: usize,
    pub index_errors: Vec<String>,
    pub indexed_types: usize,
    pub indexed_variables: usize,
    pub indexed_procedures: usize,
}

pub fn audit_declarations(source: &str, max_chunk_bytes: usize) -> DeclarationAudit {
    const ERROR_EXAMPLES: usize = 64;
    let mut audit = DeclarationAudit {
        source_bytes: source.len(),
        ..DeclarationAudit::default()
    };
    let mut compact = dm_syntax::AstFile::default();
    fn count(items: &[Item], audit: &mut DeclarationAudit) {
        for item in items {
            audit.compact_items += 1;
            audit.compact_header_bytes += item.header.len();
            audit.procedure_items +=
                usize::from(matches!(item.kind, ItemKind::Proc | ItemKind::Verb));
            count(&item.children, audit);
        }
    }
    let report = dm_syntax::for_each_parsed_chunk(source, max_chunk_bytes, |chunk, offset| {
        audit.syntax_error_count += chunk.diagnostics.len();
        for diagnostic in &chunk.diagnostics {
            if audit.syntax_errors.len() == ERROR_EXAMPLES {
                break;
            }
            let mut diagnostic = diagnostic.clone();
            diagnostic.span.start += offset;
            diagnostic.span.end += offset;
            audit.syntax_errors.push(diagnostic);
        }
        compact.items.extend(
            chunk
                .items
                .iter()
                .map(|item| compact_declaration_item(item, offset)),
        );
    });
    audit.parsed_chunks = report.parsed_chunks;
    audit.skipped_declarations = report.skipped_declarations;
    count(&compact.items, &mut audit);
    match crate::declarations::lower_declarations(&compact) {
        Ok(declarations) => {
            drop(compact);
            match dm_semantics::DeclarationIndex::build(declarations) {
                Ok(index) => {
                    audit.indexed_types = index.types.len();
                    audit.indexed_variables = index.vars.len();
                    audit.indexed_procedures = index.procs.len();
                }
                Err(errors) => {
                    audit.index_error_count = errors.len();
                    audit.index_errors = errors
                        .into_iter()
                        .take(ERROR_EXAMPLES)
                        .map(|error| format!("{error:?}"))
                        .collect();
                }
            }
        }
        Err(errors) => {
            audit.index_error_count = errors.len();
            audit.index_errors = errors.into_iter().take(ERROR_EXAMPLES).collect();
        }
    }
    audit
}

#[derive(Debug, Default)]
pub struct LoweringAuditGroup {
    pub count: usize,
    pub samples: Vec<LoweringAuditSample>,
}

#[derive(Debug)]
pub struct LoweringAuditSample {
    pub procedure: String,
    pub span: dm_syntax::Span,
    pub statement: String,
}

#[derive(Debug, Default)]
pub struct LoweringAudit {
    pub procedures: usize,
    pub passed: usize,
    pub failed: usize,
    pub error_count: usize,
    pub groups: BTreeMap<String, LoweringAuditGroup>,
}

/// Canonical authored-body lowering with normal successful-body linking.
/// Lowering errors continue; setup/signature/link errors fail fast. Resource
/// existence, generated dynamic initializers and publication are not covered.
#[derive(Debug, Default)]
pub struct CanonicalLoweringAudit {
    pub expected_procedures: usize,
    pub lowering: LoweringAudit,
    pub cache_hits: usize,
    pub cache_misses: usize,
    pub truncated_texts: usize,
}

impl CanonicalLoweringAudit {
    fn bounded(&mut self, text: &str) -> String {
        let mut chars = text.chars();
        let mut result: String = chars.by_ref().take(512).collect();
        if chars.next().is_some() { self.truncated_texts += 1; result.push_str("..."); }
        result
    }

    fn record(&mut self, path: &str, span: dm_syntax::Span, body_base: usize,
        source_debug: Option<&crate::source_debug::SourceDebugIndex<'_>>,
        result: &Result<dm_codegen_byond::SimpleProc, Vec<dm_codegen_byond::LowerError>>) {
        self.lowering.procedures += 1;
        let Err(errors) = result else { self.lowering.passed += 1; return; };
        self.lowering.failed += 1;
        for error in errors {
            self.lowering.error_count += 1;
            let mut reason = self.bounded(&error.reason);
            if self.lowering.groups.len() >= 255 && !self.lowering.groups.contains_key(&reason) {
                reason = "other errors (group limit)".into();
            }
            let sample = if self.lowering.groups.get(&reason).map_or(0, |group| group.samples.len()) < 3 {
                let offset = error.statement_origin.as_ref().and_then(|relative| body_base.checked_add(relative.start))
                    .unwrap_or(span.start);
                Some(LoweringAuditSample {
                    procedure: self.bounded(path), span,
                    statement: self.bounded(&source_error(source_debug, offset, path,
                        &format!("{} ({})", error.reason, error.statement))),
                })
            } else { None };
            let group = self.lowering.groups.entry(reason).or_default();
            group.count += 1;
            if let Some(sample) = sample { group.samples.push(sample); }
        }
    }
}

/// Uses canonical metadata, frames and successful-body linking reservations.
/// A failed body has no valid allocation footprint, so subsequent numeric IDs
/// follow successful predecessors only. No partial image is exposed or encoded.
/// Resource paths receive symbol-only placeholder IDs; assets are not read.
pub fn audit_canonical_lowering(dme_path: &Path, preprocessed: &PreprocessedProject,
    builtin_image: &[u8], frontend: &mut crate::frontend::OutlineSession,
    workers: usize) -> Result<CanonicalLoweringAudit, String> {
    if !preprocessed.diagnostics.is_empty() {
        return Err("preprocessing diagnostics prevent canonical audit".into());
    }
    let mut report = CanonicalLoweringAudit::default();
    let mut cache = crate::lower_cache::ProcLoweringCache::open(crate::lower_cache::default_cache_root(dme_path));
    let source_debug = (preprocessed.origin_count() != 0).then(||
        crate::source_debug::SourceDebugIndex::new(preprocessed, dme_path.parent().unwrap_or_else(|| Path::new("."))));
    let discarded = emit_global_procs_mode_with_frontend_catalog(&preprocessed.text, builtin_image,
        "audit", None, &mut cache, None, None, workers.clamp(1, 2), Some(frontend), None,
        source_debug.as_ref(), Some(&mut report))?;
    drop(discarded);
    let stats = cache.stats();
    report.cache_hits = stats.hits;
    report.cache_misses = stats.misses;
    if report.lowering.procedures != report.expected_procedures {
        return Err("canonical audit did not visit every authored procedure".into());
    }
    Ok(report)
}

/// Lower every procedure independently without linking or loading resources.
/// The result inventories unsupported semantics; it does not imply runtime parity.
pub fn audit_lowering(
    source: &str,
    max_chunk_bytes: usize,
    builtin_image: &[u8],
) -> Result<LoweringAudit, String> {
    let mut compact = declaration_snapshot_with_limit(source, max_chunk_bytes)?;
    let modified = collect_modified_types(source)?;
    rewrite_modified_items(&mut compact.items, &modified);

    let declarations = crate::declarations::lower_declarations(&compact)
        .map_err(|errors| format!("declaration errors: {errors:?}"))?;
    let index = dm_semantics::DeclarationIndex::build(declarations)
        .map_err(|errors| format!("index errors: {errors:?}"))?;
    let builtin = Dmb::from_bytes(builtin_image).map_err(|error| error.to_string())?;
    let mut items = HashMap::new();
    fn flatten<'a>(items: &'a [Item], output: &mut HashMap<usize, &'a Item>) {
        for item in items {
            output.insert(item.span.start, item);
            flatten(&item.children, output);
        }
    }
    flatten(&compact.items, &mut items);
    let mut parent_paths: HashMap<String, String> = index
        .types
        .iter()
        .filter_map(|ty| {
            ty.parent.map(|parent| {
                (
                    ty.path.as_str().to_owned(),
                    index.types[parent.index()].path.as_str().to_owned(),
                )
            })
        })
        .collect();
    let mut fields: HashMap<String, LowerBindings> = HashMap::new();
    for (id, class) in builtin.classes.iter().enumerate() {
        let Some(path) = builtin.string(class.path_string_id()) else {
            continue;
        };
        let path = String::from_utf8_lossy(path).into_owned();
        if class.parent_class_id() != 0xffff {
            if let Some(parent) =
                builtin.string(builtin.classes[class.parent_class_id() as usize].path_string_id())
            {
                let explicit = index
                    .types
                    .iter()
                    .find(|ty| ty.path.as_str() == path)
                    .is_some_and(|ty| ty.explicit_parent.is_some());
                if !explicit {
                    parent_paths.insert(path.clone(), String::from_utf8_lossy(parent).into_owned());
                }
            }
        }
        let scope = fields.entry(path).or_default();
        seed_builtin_fields(
            &String::from_utf8_lossy(builtin.string(class.path_string_id()).unwrap()),
            scope,
        );
        if let Some(vars) = builtin.class_variable_declarations(id) {
            for (id, _) in vars {
                if let Some(name) = builtin.string(builtin.variables[id as usize].name) {
                    scope
                        .fields
                        .insert(String::from_utf8_lossy(name).into_owned());
                }
            }
        }
    }
    let mut shared = SharedLowerBindings::default();
    shared.modified_instances = modified.parents.clone();
    seed_builtin_constants(&mut shared);
    seed_native_member_procs(&mut shared, &builtin);
    seed_member_globals(&mut shared, &builtin);
    for ty in &index.types {
        seed_builtin_fields(
            ty.path.as_str(),
            fields.entry(ty.path.as_str().to_owned()).or_default(),
        );
    }
    for var in &index.vars {
        let owner = index.types[var.owner.index()].path.as_str();
        let declared_type = items
            .get(&(var.span.start as usize))
            .and_then(|item| declared_variable_type(&item.header));
        if owner == "/" {
            shared.globals.insert(var.name.clone());
            if let Some((name, path)) = declared_type {
                shared.global_types.insert(name, path);
            }
        } else {
            shared
                .known_member_fields
                .entry(owner.to_owned())
                .or_default()
                .insert(var.name.clone());
            let scope = fields.entry(owner.to_owned()).or_default();
            scope.fields.insert(var.name.clone());
            let global_member = items.get(&(var.span.start as usize)).is_some_and(|item| {
                item.header
                    .split('=')
                    .next()
                    .unwrap_or("")
                    .split('/')
                    .any(|part| matches!(part.trim(), "global" | "static"))
            });
            if global_member {
                let alias = format!(
                    "__dm_audit_global_{}",
                    crate::incremental::digest(format!("{owner}/{}", var.name).as_bytes())
                );
                shared
                    .member_globals
                    .entry(owner.to_owned())
                    .or_default()
                    .insert(var.name.clone(), alias.clone());
                shared.globals.insert(alias.clone());
                if let Some((_, path)) = &declared_type {
                    shared.global_types.insert(alias, path.clone());
                }
            }
            if let Some((name, path)) = declared_type {
                scope.field_types.insert(name, path);
            }
        }
    }
    shared.global_procs.extend(
        index
            .procs
            .iter()
            .filter(|proc| index.types[proc.owner.index()].path.as_str() == "/")
            .map(|proc| proc.name.clone()),
    );
    let mut return_annotations = Vec::new();
    for proc in &index.procs {
        let owner = index.types[proc.owner.index()].path.as_str();
        let annotation = items.get(&(proc.span.start as usize)).map(|item|
            declared_proc_return_type(&item.header)).transpose()?.flatten();
        if annotation.is_some() && owner != "/" {
            return_annotations.push((owner.to_owned(), proc.name.clone()));
        }
        if let Some(Some(return_type)) = annotation {
            if owner == "/" {
                shared.global_proc_return_types.insert(proc.name.clone(), return_type);
            } else {
                shared.member_proc_return_types.entry(owner.to_owned()).or_default()
                    .insert(proc.name.clone(), return_type);
            }
        }
        if owner != "/" {
            shared
                .known_member_procs
                .entry(owner.to_owned())
                .or_default()
                .insert(proc.name.clone());
        }
        if owner != "/"
            && items.get(&(proc.span.start as usize)).is_some_and(|item| {
                has_proc_name_setting(&item.children)
            })
        {
            let path = items
                .get(&(proc.span.start as usize))
                .and_then(|item| {
                    member_signature(item, owner, proc.kind == dm_semantics::ProcKind::Verb).ok()
                })
                .map_or_else(|| format!("{owner}/{}", proc.name), |(path, _)| path);
            shared
                .member_procs
                .entry(owner.to_owned())
                .or_default()
                .insert(proc.name.clone(), path);
        }
    }
    shared.member_types = fields
        .iter()
        .map(|(path, scope)| (path.clone(), scope.field_types.clone()))
        .collect();
    shared.parent_types = parent_paths.clone();
    for (owner, name) in return_annotations {
        if inherited_return_annotation_error(&shared, &owner, &name) {
            return Err(format!("{owner}/{name}: proc return type cannot be redefined from parent"));
        }
    }
    let shared = Arc::new(shared);
    let prepared_member_globals = PreparedMemberGlobals::new(Arc::clone(&shared));
    let mut audit = LoweringAudit::default();
    for proc in &index.procs {
        audit.procedures += 1;
        let owner = index.types[proc.owner.index()].path.as_str();
        let name = if owner == "/" {
            format!("/proc/{}", proc.name)
        } else {
            format!("{owner}/{}", proc.name)
        };
        let span = dm_syntax::Span::new(proc.span.start as usize, proc.span.end as usize);
        if std::env::var_os("DM_AUDIT_TRACE").is_some() {
            eprintln!("lowering {name} at {}..{}", span.start, span.end);
        }
        let attempt = (|| -> Result<(), Vec<dm_codegen_byond::LowerError>> {
            let fail = |reason: String| {
                vec![dm_codegen_byond::LowerError {
                    statement: name.clone(),
                    reason,
                    statement_origin: None,
                }]
            };
            let mut item = dm_syntax::parse_proc_at_span(source, span)
                .map_err(|error| fail(format!("procedure syntax: {}", error.message)))?;
            rewrite_modified_items(std::slice::from_mut(&mut item), &modified);
            let (procedure_path, params) = member_signature(
                &item,
                if owner == "/" { "" } else { owner },
                proc.kind == dm_semantics::ProcKind::Verb,
            )
            .map_err(fail)?;
            let mut bindings = LowerBindings {
                current_proc_path: Some(procedure_path),
                current_type_path: (owner != "/").then(|| owner.to_owned()),
                parameters: params.iter().map(|param| param.name.clone()).collect(),
                parameter_type_flags: params.iter().map(|param| param.type_flags).collect(),
                parameter_value_sources: params.iter().map(|param| param.value_source).collect(),
                parameter_defaults: params.iter().map(|param| param.default.clone()).collect(),
                parameter_types: params
                    .iter()
                    .filter_map(|param| {
                        param
                            .type_path
                            .as_ref()
                            .map(|path| (param.name.clone(), path.clone()))
                    })
                    .collect(),
                shared: Some(Arc::clone(&shared)),
                prepared_member_globals: prepared_member_globals.clone(),
                ..LowerBindings::default()
            };
            let mut current = owner;
            let mut visited = HashSet::new();
            while visited.insert(current) {
                if let Some(scope) = fields.get(current) {
                    bindings.fields.extend(scope.fields.iter().cloned());
                    for (name, path) in &scope.field_types {
                        bindings
                            .field_types
                            .entry(name.clone())
                            .or_insert_with(|| path.clone());
                    }
                }
                let Some(parent) = parent_paths.get(current) else {
                    break;
                };
                current = parent;
            }
            let (_, mut body) = proc_metadata(&item.children, None).map_err(fail)?;
            let mut static_declarations = Vec::new();
            extract_static_declarations(&mut body, &mut static_declarations);
            for declaration in static_declarations {
                if let Some(name) = static_local_name(&declaration) {
                    bindings.fields.remove(&name);
                    bindings.globals.insert(name);
                }
                if let Some((name, path)) = declared_variable_type(&declaration) {
                    bindings.global_types.insert(name, path);
                }
            }
            compile_simple_proc_with_bindings(&body, &bindings).map(|_| ())
        })();
        match attempt {
            Ok(()) => audit.passed += 1,
            Err(errors) => {
                audit.failed += 1;
                for error in errors {
                    audit.error_count += 1;
                    let reason =
                        if audit.groups.len() >= 256 && !audit.groups.contains_key(&error.reason) {
                            "other errors (group limit)".to_owned()
                        } else {
                            error.reason
                        };
                    let group = audit.groups.entry(reason).or_default();
                    group.count += 1;
                    if group.samples.len() < 3 {
                        group.samples.push(LoweringAuditSample {
                            procedure: name.clone(),
                            span,
                            statement: error.statement,
                        });
                    }
                }
            }
        }
    }
    Ok(audit)
}

fn static_local_name(header: &str) -> Option<String> {
    let declaration = header.split('=').next()?.trim();
    let name = declaration.rsplit('/').next()?.split('[').next()?.trim();
    (!name.is_empty()).then(|| name.to_owned())
}

fn extract_static_declarations(body: &mut Vec<Item>, declarations: &mut Vec<String>) {
    body.retain_mut(|statement| {
        let header = statement.header.trim();
        if ["var/static/", "var/global/", "var/const/"]
            .iter()
            .any(|prefix| header.starts_with(prefix))
        {
            declarations.push(header.to_owned());
            false
        } else {
            extract_static_declarations(&mut statement.children, declarations);
            true
        }
    });
}

fn emit_global_procs_inner(
    source: &str,
    builtin_image: &[u8],
    world_name: &str,
    resources: Option<&ResourceSet>,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    emit_global_procs_mode(
        source,
        builtin_image,
        world_name,
        resources,
        lowering_cache,
        None,
        None,
    )
}

/// Declaration/default diagnostics collected without lowering procedures or serializing output.
#[derive(Clone, Debug, Default)]
pub struct InitializerAudit {
    pub errors: Vec<String>,
    pub dependency_errors: Vec<String>,
    pub classes: usize,
    pub variables: usize,
}

impl InitializerAudit {
    fn record(&mut self, error: String) {
        if error.contains("unresolved") || error.contains("cyclic") {
            self.dependency_errors.push(error);
        } else {
            self.errors.push(error);
        }
    }
}

pub fn audit_initializers(source: &str, builtin_image: &[u8]) -> Result<InitializerAudit, String> {
    let mut audit = InitializerAudit::default();
    let mut cache = crate::lower_cache::ProcLoweringCache::disabled();
    let (dmb, _, _) = emit_global_procs_mode(
        source,
        builtin_image,
        "audit",
        None,
        &mut cache,
        Some(&mut audit),
        None,
    )?;
    audit.classes = dmb.classes.len();
    audit.variables = dmb.variables.len();
    Ok(audit)
}

fn emit_global_procs_mode(
    source: &str,
    builtin_image: &[u8],
    world_name: &str,
    resources: Option<&ResourceSet>,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache,
    audit: Option<&mut InitializerAudit>,
    capture: Option<&mut Option<crate::incremental::EmissionCheckpoint>>,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    emit_global_procs_mode_with_workers(
        source,
        builtin_image,
        world_name,
        resources,
        lowering_cache,
        audit,
        capture,
        procedure_pipeline::worker_count(),
    )
}

fn emit_global_procs_mode_with_workers(
    source: &str,
    builtin_image: &[u8],
    world_name: &str,
    resources: Option<&ResourceSet>,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache,
    audit: Option<&mut InitializerAudit>,
    capture: Option<&mut Option<crate::incremental::EmissionCheckpoint>>,
    workers: usize,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    emit_global_procs_mode_with_frontend(
        source,
        builtin_image,
        world_name,
        resources,
        lowering_cache,
        audit,
        capture,
        workers,
        None,
    )
}

fn emit_global_procs_mode_with_frontend(
    source: &str,
    builtin_image: &[u8],
    world_name: &str,
    resources: Option<&ResourceSet>,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache,
    audit: Option<&mut InitializerAudit>,
    capture: Option<&mut Option<crate::incremental::EmissionCheckpoint>>,
    workers: usize,
    frontend: Option<&mut crate::frontend::OutlineSession>,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    emit_global_procs_mode_with_frontend_catalog(source, builtin_image, world_name, resources,
        lowering_cache, audit, capture, workers, frontend, None, None, None)
}

fn source_error(index: Option<&crate::source_debug::SourceDebugIndex<'_>>, offset: usize,
    procedure: &str, message: &str) -> String {
    if let Some((file, line)) = index.and_then(|index| index.resolve(offset)) {
        format!("{file}:{line}:error: {message}")
    } else { format!("{procedure}: {message}") }
}

fn emit_global_procs_mode_with_frontend_catalog(
    source: &str, builtin_image: &[u8], world_name: &str, resources: Option<&ResourceSet>,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache, audit: Option<&mut InitializerAudit>,
    capture: Option<&mut Option<crate::incremental::EmissionCheckpoint>>, workers: usize,
    mut frontend: Option<&mut crate::frontend::OutlineSession>, catalog: Option<&dm_resources::ResourceCatalog>,
    source_debug: Option<&crate::source_debug::SourceDebugIndex<'_>>,
    lowering_audit: Option<&mut CanonicalLoweringAudit>,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    let mut session = frontend.as_deref_mut().map(|frontend| std::mem::take(&mut frontend.canonical)).unwrap_or_default();
    session.emission_stats = ArtifactReuseStats::default();
    let result = emit_global_procs_mode_with_frontend_catalog_inner(source, builtin_image, world_name,
        resources, lowering_cache, audit, capture, workers, frontend.as_deref_mut(), catalog,
        source_debug, lowering_audit, &mut session);
    if result.is_ok() {
        let flush_started = std::time::Instant::now();
        session.flush_derived();
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE final derived cache flush: {:.3}s",flush_started.elapsed().as_secs_f64());
        }
    }
    if let Some(frontend) = frontend { frontend.canonical = session; }
    result
}

fn emit_global_procs_mode_with_frontend_catalog_inner(
    source: &str, builtin_image: &[u8], world_name: &str, resources: Option<&ResourceSet>,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache, mut audit: Option<&mut InitializerAudit>,
    capture: Option<&mut Option<crate::incremental::EmissionCheckpoint>>, workers: usize,
    mut frontend: Option<&mut crate::frontend::OutlineSession>, catalog: Option<&dm_resources::ResourceCatalog>,
    source_debug: Option<&crate::source_debug::SourceDebugIndex<'_>>,
    mut lowering_audit: Option<&mut CanonicalLoweringAudit>,
    session: &mut canonical::CanonicalSession,
) -> Result<(Dmb, Vec<EmittedProc>, Vec<u8>), String> {
    let build_started = std::time::Instant::now();
    let trace = |stage: &str| {
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!(
                "DM_BUILD_TRACE {:.3}s {stage}",
                build_started.elapsed().as_secs_f64()
            );
        }
    };
    let _wire_declarations = wire_declarations::begin();
    trace("declaration snapshot start");
    let segmented_source = frontend.as_ref().and_then(|frontend| frontend.segmented_source()).cloned();
    let source_range = |span: dm_syntax::Span| -> Result<std::borrow::Cow<'_, str>, String> {
        if let Some(segmented) = &segmented_source {
            segmented.try_slice(span)
        } else {
            source.get(span.range()).map(std::borrow::Cow::Borrowed)
                .ok_or_else(|| "source span outside expansion".to_owned())
        }
    };
    let mut shared_declarations = None;
    let (mut ast, cached_outline, procedure_digests) = if let Some(frontend) = frontend.as_deref_mut() {
        if let Some(segmented) = &segmented_source {
            if capture.is_none() {
                shared_declarations = Some(frontend.declaration_fragments_segmented(segmented)?);
                (dm_syntax::AstFile::default(), None, None)
            } else {
                let (ast, outline) = frontend.compact_snapshot_segmented(segmented)?;
                (ast, Some(outline), None)
            }
        } else {
            let (ast, outline) = frontend.compact_snapshot(source)?;
            let digests = frontend.procedure_digests(source);
            (ast, Some(outline), digests)
        }
    } else {
        (declaration_snapshot(source)?, None, None)
    };
    let outline = if capture.is_some() {
        Some(if let Some(outline) = cached_outline {
            outline
        } else {
            source_outline_from_snapshot(source, &ast)?
        })
    } else {
        None
    };
    let mut captured_procedures = BTreeMap::new();
    trace("declaration snapshot complete");
    let modified = if let Some(segmented) = &segmented_source {
        collect_modified_types_segmented(segmented)?
    } else { collect_modified_types(source)? };
    rewrite_modified_items(&mut ast.items, &modified);

    let mut dmb = Dmb::from_bytes(builtin_image).map_err(|error| error.to_string())?;
    if source_debug.is_some() { dmb.header.flags |= 0x0002_0000; }
    let mut resource_ids = HashMap::new();
    let mut archive = Vec::new();
    if let Some(catalog) = catalog {
        let ids = catalog.attach(&mut dmb).map_err(|error| error.to_string())?;
        for (input, id) in catalog.entries.iter().zip(ids) {
            resource_ids.insert(input.archive_name.clone(), id.index() as u32);
        }
    }
    if let Some(resources) = resources {
        let (ids, borrowed_archive) = byond_dmb::dmb::attach_resource_refs(
            &mut dmb,
            resources.inputs.iter().map(|input| &input.named),
        )
        .map_err(|error| error.to_string())?;
        archive = borrowed_archive;
        for (input, id) in resources.inputs.iter().zip(ids) {
            resource_ids.insert(input.archive_name.clone(), id.index() as u32);
        }
    }
    if (audit.is_some() || lowering_audit.is_some()) && resources.is_none() && catalog.is_none() {
        // Symbol-only audit: archive bytes and filesystem existence are checked
        // by the separate resource audit. Never publish this placeholder image.
        resource_scan::visit_resources(source, &mut |raw| {
            resource_ids
                .entry(raw[1..raw.len() - 1].replace('\\', "/"))
                .or_insert(0);
        });
    }
    let skeleton_key = if let Some(fragments) = &shared_declarations {
        canonical::skeleton_key_fragments(fragments, &modified, builtin_image, world_name, &resource_ids, source_debug.is_some())
    } else {
        canonical::skeleton_key(&ast, &modified, builtin_image, world_name, &resource_ids, source_debug.is_some())
    };
    trace("skeleton identity complete");
    let current_resource_refs = dmb.resources.clone();
    let reusable = capture.is_none() && audit.is_none() && lowering_audit.is_none();
    let frozen = if reusable { session.skeleton(&skeleton_key, lowering_cache.cache_root()) } else { None };
    let frozen = if let Some(frozen) = frozen {
        trace("frozen declaration skeleton reused");
        frozen
    } else {
    // Structural changes materialize only the declaration projection required
    // by allocation. Body edits reuse immutable local AST fragments directly.
    if let Some(fragments) = &shared_declarations {
        for (offset, fragment) in fragments {
            let mut items = fragment.items.clone();
            for item in &mut items { rebase_declaration_item(item, *offset); }
            ast.items.extend(items);
        }
        rewrite_modified_items(&mut ast.items, &modified);
    }
    let declaration_preparation_started=std::time::Instant::now();
    let semantic_stats_before=semantic_declarations::stats();
    let base_key=canonical::declaration_base_key(&ast.items,&modified,builtin_image,world_name,&resource_ids,source_debug.is_some());
    let base=if reusable {session.declaration_base(&base_key,lowering_cache.cache_root())} else {None};
    let semantic_declarations=if base.is_some()&&session.semantic_declarations.is_some()&&session.semantic_base_revision.as_deref()==Some(base_key.as_str()) {
        trace("symbolic declaration model reused with allocation base");
        Arc::clone(session.semantic_declarations.as_ref().unwrap())
    } else {
        trace("default plan prefetch start");
        default_plans::prefetch(&ast.items, workers);
        trace("default plan prefetch complete");
        semantic_declarations::SemanticDeclarations::build(&ast.items,&modified.declarations,&dmb,builtin_image,session.semantic_declarations.as_ref(),workers)
    };
    session.semantic_declarations = Some(Arc::clone(&semantic_declarations));
    session.semantic_base_revision = Some(base_key.clone());
    let _semantic_model = semantic_declarations::activate(semantic_declarations);
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE symbolic declaration model prepared in {:.3}s",declaration_preparation_started.elapsed().as_secs_f64());}
    let is_global_const = |item: &Item| {
        item.kind == ItemKind::Var
            && item
                .header
                .split('=')
                .next()
                .is_some_and(|h| h.split('/').any(|part| part.trim() == "const"))
    };
    let (mut strings,mut proc_paths,mut class_paths,mut type_metadata,mut pending,mut pending_dynamic,mut globals,global_types,class_field_types)=if let Some(base)=base {
        trace("declaration allocation base reused");
        dmb=base.image;
        dmb.resources=current_resource_refs.clone();
        let mut source_types=Vec::new();collect_type_items(&ast.items,&mut source_types);
        let mut pending=Vec::new();
        for index in &base.type_order {
            let item=source_types.get(*index).ok_or("invalid declaration base owner handle")?;
            let path=item.header.trim();let class=*base.class_paths.get(path).ok_or("invalid declaration base class handle")?;
            for child in &item.children {if matches!(child.kind,ItemKind::Proc|ItemKind::Verb) {pending.push(PendingProc {source_offset:0,item:child,owner:Some(class),owner_path:path.to_owned(),verb:child.kind==ItemKind::Verb});}}
        }
        (base.strings.decode()?,base.proc_paths,base.class_paths,base.metadata,pending,base.dynamic,base.globals,base.global_types,base.field_types)
    } else {
    let mut strings = StringIndex::new(&dmb);
    dmb.world.ids[6] = strings.intern(&mut dmb, world_name);
    let proc_paths: HashSet<Vec<u8>> = dmb
        .procs
        .iter()
        .filter_map(|proc| dmb.string(proc.strings[0]).map(|bytes| bytes.to_vec()))
        .collect();
    let mut class_paths: HashMap<String, u32> = dmb
        .classes
        .iter()
        .enumerate()
        .filter_map(|(id, class)| {
            dmb.string(class.path_string_id())
                .map(|bytes| (String::from_utf8_lossy(bytes).into_owned(), id as u32))
        })
        .collect();
    let mut type_items = Vec::new();
    collect_type_items(&ast.items, &mut type_items);
    let source_types=type_items.clone();
    let mut type_metadata = TypeMetadataState {
        first_generated_class: dmb.classes.len(),
        emitted: HashSet::new(),
        authored_names: HashSet::new(),
        authored_texts: HashSet::new(),
        static_ids: HashMap::new(),
        dynamic_static_scopes: HashMap::new(),
    };
    for item in &type_items {
        ensure_class(item.header.trim(), &mut dmb, &mut strings, &mut class_paths)?;
    }
    for item in ast
        .items
        .iter()
        .filter(|item| matches!(item.kind, ItemKind::Proc | ItemKind::Verb))
    {
        let raw = item
            .header
            .split('(')
            .next()
            .unwrap()
            .trim()
            .trim_end_matches('/');
        let owner = raw
            .rsplit_once("/proc/")
            .or_else(|| raw.rsplit_once("/verb/"))
            .or_else(|| raw.rsplit_once('/'))
            .map(|(owner, _)| owner)
            .unwrap_or("");
        if !owner.is_empty() && !matches!(owner, "/proc" | "/verb" | "/world") {
            ensure_class(owner, &mut dmb, &mut strings, &mut class_paths)?;
        }
    }
    for item in &type_items {
        let class = class_paths[item.header.trim()];
        for child in &item.children {
            if let Some((key, value)) = child.header.split_once('=') {
                if key.trim() == "parent_type" {
                    let parent = *class_paths
                        .get(value.trim())
                        .ok_or_else(|| format!("unresolved parent type {}", value.trim()))?;
                    dmb.classes[class as usize].initial_ids[1] = parent;
                }
                if key.trim() == "text" {
                    type_metadata.authored_texts.insert(class);
                }
                if key.trim() == "name" && value.trim() != "null" {
                    type_metadata.authored_names.insert(class);
                }
            }
        }
    }
    // Derive each ancestry edge once. The old per-owner full parent walk made
    // declaration allocation proportional to owner count times ancestry depth.
    let mut depths = HashMap::new();
    let mut depth_by_class = HashMap::<u32, usize>::new();
    for item in &type_items {
        let mut class = class_paths[item.header.trim()];
        let mut chain = Vec::new();
        let mut visited = HashSet::new();
        let mut depth = 0;
        while class != 0xffff {
            if let Some(cached) = depth_by_class.get(&class) { depth = *cached; break; }
            if !visited.insert(class) {
                return Err(format!("cyclic type ancestry: {}", item.header));
            }
            chain.push(class);
            class = dmb.classes[class as usize].parent_class_id();
        }
        for class in chain.into_iter().rev() { depth += 1; depth_by_class.insert(class, depth); }
        depths.insert(item.header.trim().to_owned(), depth_by_class[&class_paths[item.header.trim()]]);
    }
    type_items.sort_by_key(|item| depths[item.header.trim()]);
    type_items = order_type_initializers(type_items, &dmb, &class_paths)?;
    for declaration in &modified.declarations {
        let alias = declaration.header.trim();
        let parent = &modified.parents[alias];
        let (kind, class) = type_path_value(&mut dmb, parent, &strings)?;
        if dmb.instances.len() >= 0xffff {
            return Err("modified instance table exceeds native ID limit".into());
        }
        let id = dmb.instances.len() as u32;
        dmb.instances.push(Instance {
            kind,
            class,
            initializer: 0xffff,
        });
        strings.4.insert(alias.to_owned(), id);
    }

    let mut pending = Vec::new();
    let mut pending_dynamic = Vec::new();
    let mut globals = HashMap::new();
    let global_types: HashMap<String, String> = ast
        .items
        .iter()
        .filter(|item| item.kind == ItemKind::Var)
        .filter_map(|item| declared_variable_type(&item.header))
        .collect();
    let mut class_field_types: HashMap<String, HashMap<String, String>> = HashMap::new();
    for item in &type_items {
        let fields = class_field_types
            .entry(item.header.trim().to_owned())
            .or_default();
        fields.extend(default_plans::owner(item).field_types.iter().map(|(name, ty)| (name.clone(), ty.clone())));
    }
    // Constants can refer to globals declared later. Resolve their dependency
    // graph before emitting runtime initializers or type settings.
    let mut unresolved_consts: Vec<_> = ast
        .items
        .iter()
        .filter(|item| is_global_const(item))
        .collect();
    while !unresolved_consts.is_empty() {
        let before = unresolved_consts.len();
        let mut last_error = String::new();
        unresolved_consts.retain(|item| {
            match emit_global_var(
                item,
                &mut dmb,
                &mut strings,
                &resource_ids,
                &mut globals,
                &mut pending_dynamic,
            ) {
                Ok(()) => false,
                Err(error) => {
                    last_error = error;
                    true
                }
            }
        });
        if before == unresolved_consts.len() {
            if let Some(audit) = audit.as_deref_mut() {
                for item in &unresolved_consts {
                    audit.dependency_errors.push(format!(
                        "unresolved or cyclic global constant: {}",
                        item.header
                    ));
                }
                break;
            }
            return Err(format!(
                "unresolved or cyclic global constant: {last_error}"
            ));
        }
    }
    trace("type defaults start");
    let operation_stats_before=declaration_operations::stats();
    let mut owner_plan_time=std::time::Duration::ZERO;
    let mut default_plan_time=std::time::Duration::ZERO;
    let mut default_wire_time=std::time::Duration::ZERO;
    for window in type_items.chunks(1024) {
    let started=std::time::Instant::now();
    let owner_plans=default_plans::owner_batch(window,workers);
    owner_plan_time+=started.elapsed();
    let started=std::time::Instant::now();
    semantic_declarations::prefetch_owner_defaults(window,&owner_plans,workers);
    default_plan_time+=started.elapsed();
    declaration_operations::prefetch(window);
    let wire_started=std::time::Instant::now();
    for (item,owner_plan) in window.iter().zip(&owner_plans) {
        let result = emit_type(
            item,
            &mut dmb,
            &mut strings,
            &mut class_paths,
            &resource_ids,
            &mut pending,
            &mut pending_dynamic,
            &mut type_metadata,
            owner_plan,
            audit.as_deref_mut(),
        );
        if let Err(error) = result {
            if let Some(audit) = audit.as_deref_mut() {
                audit.record(format!("{}: {error}", item.header));
            } else {
                return Err(error);
            }
        }
    }
    default_wire_time+=wire_started.elapsed();
    }
    trace(&format!("type default stages: ownerplans={:.3}s semanticplans={:.3}s wire={:.3}s",owner_plan_time.as_secs_f64(),default_plan_time.as_secs_f64(),default_wire_time.as_secs_f64()));
    if std::env::var_os("DM_BUILD_TRACE").is_some(){let(hits,misses)=declaration_operations::stats();eprintln!("DM_BUILD_TRACE typed declaration operations: reused={} derived={}",hits.saturating_sub(operation_stats_before.0),misses.saturating_sub(operation_stats_before.1));}
    trace("type defaults complete");
    let source_handles:HashMap<usize,usize>=source_types.iter().enumerate().map(|(index,item)|(*item as *const Item as usize,index)).collect();
    let type_order=type_items.iter().map(|item|source_handles[&(*item as *const Item as usize)]).collect::<Vec<_>>();
    if reusable {
        let base=canonical::DeclarationBase {image:dmb.clone(), strings:strings.clone().into(),proc_paths:proc_paths.clone(),class_paths:class_paths.clone(),metadata:type_metadata.clone(),dynamic:pending_dynamic.clone(),globals:globals.clone(),global_types:global_types.clone(),field_types:class_field_types.clone(),type_order};
        session.store_declaration_base(base_key.clone(),&base,lowering_cache.cache_root());
    }
    (strings,proc_paths,class_paths,type_metadata,pending,pending_dynamic,globals,global_types,class_field_types)
    };
    let mut generated_proc_paths=HashSet::new();
    trace("procedure declaration collection start");
    let mut verb_owners: HashMap<String, Vec<String>> = HashMap::new();
    let mut indexed_pending = 0;
    for item in &ast.items {
        for earlier in &pending[indexed_pending..] {
            if earlier.verb {
                if let Some((path, _)) = earlier.item.header.split_once('(') {
                    if let Some(name) = path.trim_end_matches('/').rsplit('/').next() {
                        verb_owners
                            .entry(name.to_owned())
                            .or_default()
                            .push(earlier.owner_path.clone());
                    }
                }
            }
        }
        indexed_pending = pending.len();
        if is_global_const(item) {
            continue;
        }
        if item.kind == ItemKind::Type {
            if item.header.trim() == "/world" {
                let result = emit_world(item, &mut dmb, &mut strings, &mut pending);
                if let Err(error) = result {
                    if let Some(audit) = audit.as_deref_mut() {
                        audit.record(error);
                    } else {
                        return Err(error);
                    }
                }
            }
            continue;
        }
        if item.kind == ItemKind::Var {
            let result = emit_global_var(
                item,
                &mut dmb,
                &mut strings,
                &resource_ids,
                &mut globals,
                &mut pending_dynamic,
            );
            if let Err(error) = result {
                if let Some(audit) = audit.as_deref_mut() {
                    audit.record(error);
                } else {
                    return Err(error);
                }
            }
            continue;
        }
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            let header_path = item
                .header
                .split_once('(')
                .map_or("", |(path, _)| path.trim().trim_end_matches('/'));
            if let Some((owner_path, marker)) = header_path
                .rsplit_once("/verb/")
                .map(|(owner, _)| (owner, "verb/"))
                .or_else(|| {
                    header_path
                        .rsplit_once("/proc/")
                        .map(|(owner, _)| (owner, "proc/"))
                })
            {
                if !owner_path.is_empty() {
                    if owner_path == "/world" {
                        pending.push(PendingProc {
                            source_offset: 0,
                            item,
                            owner: None,
                            owner_path: owner_path.to_owned(),
                            verb: false,
                        });
                        continue;
                    }
                    let owner = ensure_class(owner_path, &mut dmb, &mut strings, &mut class_paths)?;
                    pending.push(PendingProc {
                        source_offset: 0,
                        item,
                        owner: Some(owner),
                        owner_path: owner_path.to_owned(),
                        verb: marker == "verb/",
                    });
                    continue;
                }
            }
            if let Some((owner_path, name)) = header_path.rsplit_once('/') {
                if !owner_path.is_empty() && owner_path != "/proc" && owner_path != "/verb" {
                    if owner_path == "/world" {
                        pending.push(PendingProc {
                            source_offset: 0,
                            item,
                            owner: None,
                            owner_path: owner_path.to_owned(),
                            verb: false,
                        });
                        continue;
                    }
                    let owner = ensure_class(owner_path, &mut dmb, &mut strings, &mut class_paths)?;
                    let verb = verb_owners.get(name).is_some_and(|owners| {
                        owners.iter().any(|earlier| owner_path.starts_with(earlier))
                    });
                    pending.push(PendingProc {
                        source_offset: 0,
                        item,
                        owner: Some(owner),
                        owner_path: owner_path.to_owned(),
                        verb,
                    });
                    continue;
                }
            }
            pending.push(PendingProc {
                source_offset: 0,
                item,
                owner: None,
                owner_path: String::new(),
                verb: false,
            });
            continue;
        }
        return Err(format!(
            "unsupported top-level declaration: {}",
            item.header
        ));
    }
    refresh_remaining_implicit_class_headers(&mut dmb, &mut type_metadata)?;
    if audit.is_some() {
        trace("initializer audit complete; no procedure lowering or output");
        return Ok((dmb, Vec::new(), Vec::new()));
    }
    for class_id in 0..dmb.classes.len() as u32 {
        if class_inherits(&dmb, class_id, b"/mob") {
            ensure_mob_record(&mut dmb, class_id)?;
        }
    }
    for world in ast
        .items
        .iter()
        .filter(|item| item.header.trim() == "/world")
    {
        for setting in &world.children {
            let Some((name, value)) = setting.header.split_once('=') else {
                continue;
            };
            let slot = match name.trim() {
                "mob" => 0,
                "turf" => 1,
                "area" => 2,
                _ => continue,
            };
            let value = value.trim();
            if value == "null" {
                dmb.world.ids[slot] = 0xffff;
                continue;
            }
            let class = *class_paths
                .get(value)
                .ok_or_else(|| format!("unresolved world.{} type: {value}", name.trim()))?;
            let base: &[u8] = match slot {
                0 => b"/mob",
                1 => b"/turf",
                _ => b"/area",
            };
            if !class_inherits(&dmb, class, base) {
                return Err(format!("invalid world.{} type: {value}", name.trim()));
            }
            dmb.world.ids[slot] = if slot == 0 {
                ensure_mob_record(&mut dmb, class)? as u32
            } else {
                class
            };
        }
    }
    if dmb.grid.is_empty() {
        let mut remaining = dmb
            .dimensions
            .iter()
            .try_fold(1u64, |total, value| total.checked_mul(u64::from(*value)))
            .ok_or_else(|| "world dimensions overflow".to_owned())?;
        if remaining > 0 {
            let turf = crate::maps::default_map_instance(&mut dmb, 10)?;
            let area = crate::maps::default_map_instance(&mut dmb, 11)?;
            while remaining > 0 {
                let count = remaining.min(255);
                dmb.grid.push(byond_dmb::dmb::GridRun {
                    turf,
                    area,
                    contents: 0xffff,
                    copies: count as u8,
                });
                remaining -= count;
            }
        }
    }
    // Class declarations are emitted in ancestry order, but their procedures
    // must retain source order: procedure statics run in this same order.
    pending.sort_by_key(|proc| proc.item.span.start);
    let mut global_proc_ids: HashMap<String, u32> = dmb
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, proc)| {
            dmb.string(proc.strings[0])
                .and_then(|path| std::str::from_utf8(path).ok())
                .map(|path| (path.to_owned(), id as u32))
        })
        .collect();
    for (ordinal, proc) in pending.iter().enumerate() {
        let (path, _) = member_signature(proc.item, &proc.owner_path, proc.verb)?;
        let raw_id = dmb.procs.len() as u32 + ordinal as u32;
        global_proc_ids.insert(
            path,
            raw_id + u32::from(raw_id >= 0xffff && dmb.procs.len() <= 0xffff),
        );
    }
    let mut initializer_globals = globals.clone();
    initializer_globals.extend(type_metadata.static_ids.clone());
    let mut shared_bindings = SharedLowerBindings {
        globals: globals.keys().cloned().collect(),
        global_types,
        global_procs: global_proc_ids
            .keys()
            .filter_map(|path| path.strip_prefix("/proc/"))
            .map(str::to_owned)
            .collect(),
        ..SharedLowerBindings::default()
    };
    shared_bindings.modified_instances = modified.parents.clone();
    shared_bindings.member_types = class_field_types;
    initializer_globals.extend(seed_member_globals(&mut shared_bindings, &dmb));
    // Static fields are addressed as private global aliases during startup.
    // Preserve their declared types for inferred istype/new member operations.
    for (class_id, class) in dmb.classes.iter().enumerate() {
        let Some(path) = dmb
            .string(class.path_string_id())
            .and_then(|path| std::str::from_utf8(path).ok())
        else {
            continue;
        };
        let Some(types) = shared_bindings.member_types.get(path) else {
            continue;
        };
        for (variable_id, flags) in dmb
            .class_variable_declarations(class_id)
            .unwrap_or_default()
        {
            if flags & 1 == 0 {
                continue;
            }
            let Some(name) = dmb
                .string(dmb.variables[variable_id as usize].name)
                .and_then(|name| std::str::from_utf8(name).ok())
            else {
                continue;
            };
            if let Some(ty) = types.get(name) {
                shared_bindings
                    .global_types
                    .insert(static_symbol("__dm_class_static_", path, name), ty.clone());
            }
        }
    }
    seed_native_member_procs(&mut shared_bindings, &dmb);
    let mut return_annotations = Vec::new();
    for proc in &pending {
        let name = proc.item.header.split('(').next().unwrap_or("")
            .trim_end_matches('/').rsplit('/').next().unwrap_or("").to_owned();
        let annotation = declared_proc_return_type(&proc.item.header).map_err(|reason|
            source_error(source_debug, proc.item.span.start, &proc.item.header, &reason))?;
        if annotation.is_some() && !proc.owner_path.is_empty() {
            return_annotations.push((proc.owner_path.clone(), name.clone(), proc.item.span.start));
        }
        if let Some(Some(return_type)) = annotation {
            if proc.owner_path.is_empty() {
                shared_bindings.global_proc_return_types.insert(name, return_type);
            } else {
                shared_bindings.member_proc_return_types.entry(proc.owner_path.clone()).or_default()
                    .insert(name, return_type);
            }
        }
        if !proc.owner_path.is_empty() {
            let (path, _) = member_signature(proc.item, &proc.owner_path, proc.verb)?;
            shared_bindings
                .known_member_procs
                .entry(proc.owner_path.clone())
                .or_default()
                .insert(path.rsplit('/').next().unwrap().to_owned());
        }
        if !proc.owner_path.is_empty()
            && has_proc_name_setting(&proc.item.children)
        {
            let (path, _) = member_signature(proc.item, &proc.owner_path, proc.verb)?;
            let name = path.rsplit('/').next().unwrap().to_owned();
            shared_bindings
                .member_procs
                .entry(proc.owner_path.clone())
                .or_default()
                .insert(name, path);
        }
    }
    for class in &dmb.classes {
        let Some(path) = dmb.string(class.path_string_id()) else {
            continue;
        };
        let path = String::from_utf8_lossy(path).into_owned();
        let mut builtin_fields = LowerBindings::default();
        seed_builtin_fields(&path, &mut builtin_fields);
        let fields = shared_bindings
            .member_types
            .entry(path.clone())
            .or_default();
        for (name, ty) in builtin_fields.field_types {
            fields.entry(name).or_insert(ty);
        }
        if let Some(parent) = dmb
            .classes
            .get(class.parent_class_id() as usize)
            .and_then(|parent| dmb.string(parent.path_string_id()))
        {
            let parent = String::from_utf8_lossy(parent).into_owned();
            if parent != path {
                shared_bindings.parent_types.insert(path, parent);
            }
        }
    }
    for (owner, name, offset) in return_annotations {
        if inherited_return_annotation_error(&shared_bindings, &owner, &name) {
            return Err(source_error(source_debug, offset, &format!("{owner}/{name}"),
                "proc return type cannot be redefined from parent"));
        }
    }
    seed_builtin_constants(&mut shared_bindings);
    let shared_bindings = Arc::new(shared_bindings);
    let prepared_member_globals = PreparedMemberGlobals::new(Arc::clone(&shared_bindings));
    for assignment in &mut pending_dynamic {
        if let Some(&scope) = type_metadata.dynamic_static_scopes.get(&assignment.name) {
            assignment.expression = qualify_static_expression(&assignment.expression, scope, &dmb);
        }
    }
    trace("procedure binding index complete; invocation plans start");
    let mut invocation_plans = Vec::with_capacity(pending.len());
    let metadata_sources: HashMap<_, _> = pending.iter().filter_map(|procedure| procedure.owner.map(|owner| (
        (owner, procedure.item.header.split('(').next().unwrap_or("").trim_end_matches('/').rsplit('/').next().unwrap_or("").to_owned(), procedure.verb), procedure.item))).collect();
    let mut resolved_metadata = HashMap::new();
    let mut dynamic_by_name: HashMap<String, Vec<usize>> = HashMap::new();
    for (index, assignment) in pending_dynamic.iter().enumerate() {
        dynamic_by_name.entry(assignment.name.clone()).or_default().push(index);
    }
    session.invocation_fragments.counters=Default::default();
    let invocation_preparation_started=std::time::Instant::now();
    let invocation_total = pending.len();
    let authored_pending=&pending;
    for (invocation_ordinal,pending) in authored_pending.iter().enumerate() {
                    if invocation_ordinal%1024==0 {
                        let window_end=invocation_ordinal.saturating_add(1024).min(invocation_total);
                        session.invocation_fragments.prefetch_syntax(&authored_pending[invocation_ordinal..window_end].iter()
                            .map(|procedure|(procedure.item,procedure.owner_path.as_str(),procedure.verb)).collect::<Vec<_>>());
                    }
                    if invocation_ordinal%1024==0 && std::env::var_os("DM_BUILD_TRACE").is_some() {
                        eprintln!("DM_BUILD_TRACE invocation preparation: {} of {}, {:.3}s", invocation_ordinal,invocation_total,invocation_preparation_started.elapsed().as_secs_f64());
                    }
                    let item = pending.item;
                    let (path, params) = session.invocation_fragments.signature(item, &pending.owner_path, pending.verb)?;
                    let repeated = !proc_paths.insert(path.as_bytes().to_vec());
                    let explicit_definition =
                        item.header.split_once('(').is_some_and(|(header, _)| {
                            header.contains("/proc/") || header.contains("/verb/")
                        });
                    if repeated && (explicit_definition || !generated_proc_paths.contains(&path)) {
                        return Err(format!("duplicate procedure definition: {path}"));
                    }
                    generated_proc_paths.insert(path.clone());
                    let mut bindings = LowerBindings {
                        current_proc_path: Some(path.clone()),
                        current_type_path: (!pending.owner_path.is_empty()).then(||pending.owner_path.clone()),
                        shared: Some(Arc::clone(&shared_bindings)),
                        prepared_member_globals: prepared_member_globals.clone(),
                        ..LowerBindings::default()
                    };
                    if pending.owner_path == "/world" {
                        seed_builtin_fields("/world", &mut bindings);
                    }
                    let inherited = pending.owner.and_then(|owner| {
                        find_inherited_proc(
                            &dmb,
                            owner,
                            path.rsplit('/').next().unwrap(),
                            pending.verb,
                        )
                    });
                    let inherited_metadata = if let Some(owner) = pending.owner {
                        resolve_pending_parent_metadata(
                            &dmb,
                            owner,
                            path.rsplit('/').next().unwrap(),
                            pending.verb,
                            &metadata_sources,
                            &mut resolved_metadata,
                            &mut session.invocation_fragments,
                        )?
                    } else {
                        None
                    };
                    let base_metadata = if let Some(base) = inherited_metadata { base }
                        else { proc_metadata(&[], inherited.map(|proc| (&dmb, proc)))?.0 };
                    let syntax = session.invocation_fragments.syntax(item, &path, &params, base_metadata)?;
                    let metadata = syntax.metadata.clone();
                    if let Some(owner) = pending.owner {
                        resolved_metadata.insert(
                            (
                                owner,
                                path.rsplit('/').next().unwrap().to_owned(),
                                pending.verb,
                            ),
                            metadata.clone(),
                        );
                    }
                    let static_declarations = syntax.statics.clone();
                    let mut static_ids = HashMap::new();
                    let mut local_const_ids = HashMap::new();
                    let local_names: HashSet<String> = static_declarations
                        .iter()
                        .filter_map(|declaration| {
                            declaration
                                .split('=')
                                .next()?
                                .trim()
                                .rsplit('/')
                                .next()
                                .map(|name| name.split('[').next().unwrap().to_owned())
                        })
                        .collect();
                    for declaration in static_declarations {
                        let sized_array = is_sized_array_declaration(&declaration);
                        let normalized = normalize_array_declaration(
                            &declaration,
                            &dmb,
                            pending.owner,
                            &strings,
                        )?;
                        let declaration = normalized.unwrap_or(declaration);
                        let declaration =
                            if let Some((header, expression)) = declaration.split_once('=') {
                                let context = HashMap::from([
                                    ("__PROC__".to_owned(), path.clone()),
                                    (
                                        "__TYPE__".to_owned(),
                                        if pending.owner_path.is_empty() {
                                            "null".to_owned()
                                        } else {
                                            pending.owner_path.clone()
                                        },
                                    ),
                                ]);
                                format!(
                                    "{header}= {}",
                                    qualify_expression_with_aliases(expression.trim(), &context)
                                )
                            } else {
                                declaration
                            };
                        let default_plan=default_plans::declaration(&declaration)?;
                        let name=default_plan.name.as_str();
                        let initial=default_plan.initial.as_deref();
                        if static_ids.contains_key(name) {
                            return Err(format!("{path}: duplicate or unsupported static local: {declaration}"));
                        }
                        let is_const=default_plan.is_const;
                        let folded = initial.and_then(|expression| {
                            const_eval::evaluate(expression, |name| {
                                if let Some(id) = local_const_ids.get(name) {
                                    constant_from_variable(&dmb, *id, &strings)
                                } else if local_names.contains(name) {
                                    None
                                } else {
                                    fold_constant(name, &dmb, pending.owner, &strings)
                                }
                            })
                        });
                        let initial_value = if let Some(value) = folded {
                            encode_constant(value, &mut dmb, &mut strings)
                        } else {
                            constant_variable_value_scoped(
                                initial,
                                &declaration,
                                &mut dmb,
                                &mut strings,
                                &resource_ids,
                                pending.owner,
                                &local_names,
                            )
                        };
                        let (kind, value, dynamic) = match initial_value {
                            Ok((kind, value)) => (kind, value, None),
                            Err(error) if is_const => {
                                return Err(format!(
                                    "{path}: invalid static const initializer: {error}"
                                ))
                            }
                            Err(_) if initial.is_some() => {
                                let expression = default_plan.dynamic.clone()?;
                                let (global_constructor_count, constructor_count) =
                                    wire_declarations::constructor_counts(&pending_dynamic);
                                let (kind, value) = if expression.starts_with("new ") {
                                    // Native DM records the initializer sequence once a
                                    // global constructor has established it. Standalone
                                    // static constructors leave this slot zero.
                                    (
                                        62,
                                        if global_constructor_count == 0 {
                                            0
                                        } else {
                                            constructor_count + 1
                                        },
                                    )
                                } else {
                                    (0, 0)
                                };
                                (kind, value, Some(expression))
                            }
                            Err(error) => return Err(format!("{path}: {error}")),
                        };
                        let variable_id = dmb.variables.len() as u32;
                        let initializer_name = static_symbol("__dm_static_", &path, name);
                        let name_id = strings.intern(&mut dmb, name);
                        dmb.variables.push(Variable {
                            kind,
                            value,
                            name: name_id,
                        });
                        let footer = dmb.variable_footer;
                        if footer == 0xffff {
                            dmb.variable_footer = append_list(
                                &mut dmb,
                                vec![variable_id, if is_const { 3 } else { 1 }],
                            );
                        } else {
                            dmb.lists[footer as usize]
                                .extend([variable_id, if is_const { 3 } else { 1 }]);
                        }
                        initializer_globals.insert(initializer_name.clone(), variable_id);
                        static_ids.insert(name.to_owned(), variable_id);
                        bindings.globals.insert(name.into());
                        bindings.hide_owner_field(name);
                        if let Some((_, path)) = declared_variable_type(&declaration) {
                            bindings.global_types.insert(name.into(), path);
                        }
                        if is_const {
                            local_const_ids.insert(name.to_owned(), variable_id);
                        }
                        if let Some(expression) = dynamic {
                            dynamic_by_name
                                .entry(initializer_name.clone())
                                .or_default()
                                .push(pending_dynamic.len());
                            pending_dynamic.push(PendingDynamic {
                                owner: None,
                                name: initializer_name,
                                expression,
                                sized_array,
                            });
                        }
                    }
                    let local_aliases: HashMap<_, _> = static_ids
                        .iter()
                        .map(|(name, _)| (name.clone(), static_symbol("__dm_static_", &path, name)))
                        .collect();
                    for name in static_ids.keys() {
                        if let Some(indices) = dynamic_by_name.get(&static_symbol("__dm_static_", &path, name)) {
                            for &index in indices {
                                let assignment = &mut pending_dynamic[index];
                                assignment.expression = qualify_expression_with_aliases(
                                    &assignment.expression,
                                    &local_aliases,
                                );
                                if let Some(owner) = pending.owner {
                                    assignment.expression = qualify_static_expression(
                                        &assignment.expression, owner, &dmb,
                                    );
                                }
                            }
                        }
                    }
        bindings.shared = None;
        bindings.owner = None;
        let (bindings, frame_digest) = session.invocation_fragments.frame(&syntax, bindings.into());
        invocation_plans.push(canonical::InvocationPlan { path, params, metadata, static_ids, bindings, frame_digest });
    }
        if std::env::var_os("DM_BUILD_TRACE").is_some(){let c=session.invocation_fragments.counters;eprintln!("DM_BUILD_TRACE invocation queries: signature_hits={} signature_misses={} syntax_hits={} syntax_misses={} frame_hits={} frame_misses={} point_reads={} batch_records={}",c.signature_hits,c.signature_misses,c.syntax_hits,c.syntax_misses,c.frame_hits,c.frame_misses,c.point_reads,c.batch_records);}
        trace("invocation plans complete; wire metadata start");
        apply_mouse_proc_flags(&mut dmb, &pending, &invocation_plans);
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            let now=semantic_declarations::stats();
            eprintln!("DM_BUILD_TRACE declaration allocation {:.3}s, symbolic expressions {}, scoped default hits {}, misses {}",declaration_preparation_started.elapsed().as_secs_f64(),now.0-semantic_stats_before.0,now.1-semantic_stats_before.1,now.2-semantic_stats_before.2);
        }
        trace("initializer recipe planning start");
        let initializer_recipes=initializer_pipeline::recipes(&initializer_pipeline::group_assignments(pending_dynamic.clone()),&dmb,&strings,true);
        let modified_groups:Vec<_>=modified.declarations.iter().filter(|declaration|!declaration.children.is_empty()).map(|declaration| {
            let owner=class_paths[&modified.parents[declaration.header.trim()]];
            let assignments=declaration.children.iter().map(|child| {
                let (name,expression)=child.header.split_once('=').expect("modified assignment");
                PendingDynamic {owner:Some(owner),name:name.trim().into(),expression:expression.trim().into(),sized_array:false}
            }).collect();(Some(owner),assignments)
        }).collect();
        let modified_initializer_recipes=initializer_pipeline::recipes(&modified_groups,&dmb,&strings,false);
        trace("initializer recipe planning complete; frozen composition start");
        let frozen = canonical::FrozenSkeleton::new(dmb, canonical::SkeletonMetadata {
            strings:strings.into(), proc_paths, class_paths,
            pending: pending.iter().map(|proc| canonical::OwnedPendingProc {
                owner: proc.owner, owner_path: proc.owner_path.clone(), verb: proc.verb,
            }).collect(), dynamic: pending_dynamic, initializers:initializer_recipes,modified_initializers:modified_initializer_recipes,initializer_globals, global_proc_ids,
            shared: Arc::clone(&shared_bindings), invocations: invocation_plans,
        });
        trace("frozen composition complete; snapshot publication start");
        if reusable { session.store(skeleton_key.clone(), frozen, lowering_cache.cache_root()) }
        else { Arc::new(frozen) }
    };
    trace("declaration snapshot selected; output allocation start");
    session.owner_frames.lock().unwrap_or_else(|e|e.into_inner()).bind_revision(&skeleton_key);
    let mut dmb = frozen.image.clone();
    dmb.resources = current_resource_refs;
    let state = &frozen.metadata;
    let mut strings = state.strings.decode()?;
    let class_paths = &state.class_paths;
    let initializer_globals = &state.initializer_globals;
    let global_proc_ids = &state.global_proc_ids;
    let invocations = &state.invocations;
    // Locations follow current syntax; semantic plans remain shared and immutable.
    fn current_procedures<'a>(items: &'a [Item], offset: usize, output: &mut Vec<(&'a Item, usize)>) {
        for item in items {
            if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) { output.push((item,offset)); }
            else { current_procedures(&item.children,offset,output); }
        }
    }
    let mut current = Vec::with_capacity(state.pending.len());
    if let Some(fragments) = &shared_declarations {
        for (offset, fragment) in fragments { current_procedures(&fragment.items,*offset,&mut current); }
    } else { current_procedures(&ast.items,0,&mut current); }
    // Fragment order and recursive declaration order already follow source spans.
    if current.len() != state.pending.len() { return Err("cached skeleton procedure count mismatch".into()); }
    let pending: Vec<_> = state.pending.iter().zip(current).map(|(proc, (item, source_offset))| PendingProc {
        item, source_offset, owner: proc.owner, owner_path: proc.owner_path.clone(), verb: proc.verb,
    }).collect();
    let pending_dynamic = state.dynamic.clone();
    let shared_bindings = Arc::clone(&state.shared);
    let prepared_member_globals = PreparedMemberGlobals::new(Arc::clone(&shared_bindings));
    let mut emitted = Vec::new();
    let mut pending_argument_sources = Vec::new();
    let mut argument_source_indices: HashMap<String, usize> = HashMap::new();
    let worker_modified=Arc::new(ModifiedTypes { aliases:modified.aliases.clone(),declarations:Vec::new(),parents:HashMap::new() });
    let procedure_count = pending.len();
    // Preserve the original first-procedure allocation order for builtin vars.
    // The immutable binding plan can then reuse that exact concrete slot.
    if procedure_count != 0 {
        bind_builtin_global_vars(&mut dmb, &mut strings, &mut Ledger::default())?;
    }
    let resource_assignment_identity = crate::lower_cache::shared_binding_fingerprint(
        &resource_ids.iter().collect::<BTreeMap<_, _>>());
    if let Some(report) = lowering_audit.as_deref_mut() { report.expected_procedures = procedure_count; }
    session.active_keys.clear();
    session.procedure_fragments.stats = Default::default();
    session.procedure_fragments.set_workers(workers);
    let mut occurrences = HashMap::<String, u32>::new();
    let procedure_keys: Vec<_> = invocations.iter().map(|plan| {
        let occurrence = occurrences.entry(plan.path.clone()).or_default();
        let key = crate::ProcKey { path: plan.path.clone(), occurrence: *occurrence };
        *occurrence += 1;
        key
    }).collect();
    let declarations_current = session.declaration_inputs.as_ref()
        .is_some_and(|inputs| inputs.has_revision(&skeleton_key));
    // A body edit preserves every declaration witness and authored key. Avoid
    // building a resolver index and helper inventory that no query will read.
    let invocation_indices: HashMap<_, _> = if declarations_current && !session.graph.has_pending_validation() { HashMap::new() } else {
        procedure_keys.iter().cloned().enumerate().map(|(index, key)| (key, index)).collect()
    };
    if reusable && !declarations_current {
        trace("procedure header preparation start");
        let mut graph_keys = procedure_keys.clone();
        for (index, plan) in invocations.iter().enumerate() {
            for (parameter, param) in plan.params.iter().enumerate() {
                if param.source_expression.is_some() {
                    graph_keys.push(crate::ProcKey { path: format!("@argument|{}|{parameter}", procedure_keys[index].path),
                        occurrence: procedure_keys[index].occurrence });
                }
            }
        }
        graph_keys.extend(state.initializers.iter().chain(&state.modified_initializers).map(|recipe|recipe.key.clone()));
        let _ = session.graph.prepare_keys(&graph_keys);
        trace("procedure header preparation complete");
    }
    let mut fact_frames = OwnerBindingCache::with_queries(4 * 1024 * 1024, 64, Arc::clone(&session.owner_frames));
    let mut resolved_frame: Option<(crate::ProcKey, LowerBindings)> = None;
    let shared_fact_frame = LowerBindings {
        shared: Some(Arc::clone(&shared_bindings)),
        prepared_member_globals: prepared_member_globals.clone(),
        ..LowerBindings::default()
    };
    let mut shared_fact_values = BTreeMap::new();
    let changed_facts = session.declaration_inputs.as_ref().map(|previous|
        previous.changes(&skeleton_key, &shared_bindings, &procedure_keys, invocations,
            initializer_globals, session.graph.observed_facts()));
    let mut resolve_fact = |key: &crate::ProcKey, fact: &dm_codegen_byond::BindingFact| {
        if fact.is_shared() {
            return shared_fact_values.entry(fact.clone())
                .or_insert_with(|| shared_fact_frame.binding_fact(fact)).clone();
        }
        if key.path.starts_with("@initializer|") {
            if let dm_codegen_byond::BindingFact::Global(name) = fact {
                return dm_codegen_byond::FactValue::Boolean(initializer_globals.contains_key(name)
                    || shared_bindings.globals.contains(name));
            }
        }
        if resolved_frame.as_ref().map(|(cached, _)| cached) != Some(key) {
            let mut bindings;
            let owner;
            if let Some(&index) = invocation_indices.get(key) {
                bindings = invocations[index].lower_bindings();
                owner = pending[index].owner;
            } else if let Some(raw) = key.path.strip_prefix("@argument|") {
                let Some(parent) = raw.rsplit_once('|').map(|(parent, _)| parent) else { return dm_codegen_byond::FactValue::Absent; };
                let parent = crate::ProcKey { path: parent.to_owned(), occurrence: key.occurrence };
                let Some(&index) = invocation_indices.get(&parent) else { return dm_codegen_byond::FactValue::Absent; };
                bindings = invocations[index].lower_bindings();
                bindings.parameter_defaults.clear(); bindings.parameter_value_sources.clear();
                owner = pending[index].owner;
            } else if let Some(raw) = key.path.strip_prefix("@initializer|") {
                let owner_path = raw.split('|').next().unwrap_or("");
                owner = class_paths.get(owner_path).copied();
                bindings = LowerBindings::default();
            } else { return dm_codegen_byond::FactValue::Absent; }
            bindings.shared = Some(Arc::clone(&shared_bindings));
            bindings.prepared_member_globals = prepared_member_globals.clone();
            if let Some(owner) = owner { fact_frames.populate(owner, &dmb, &shared_bindings, &mut bindings); }
            resolved_frame = Some((key.clone(), bindings));
        }
        resolved_frame.as_ref().unwrap().1.binding_fact(fact)
    };
    trace("procedure fact refresh start");
    if let Some(changed) = &changed_facts {
        session.graph.refresh_changed_facts(&skeleton_key, changed, &mut resolve_fact);
    } else {
        session.graph.refresh_facts(&skeleton_key, &mut resolve_fact);
    }
    trace("procedure fact refresh complete");
    if !session.declaration_inputs.as_ref().is_some_and(|inputs|inputs.has_revision(&skeleton_key)) {
        session.declaration_inputs = Some(canonical::DeclarationInputs::snapshot(
            &skeleton_key, Arc::clone(&shared_bindings), &procedure_keys, invocations, initializer_globals));
    }
    // Compact coordinates permit source-order parser prefetch without retaining
    // procedure text or duplicating declaration nodes.
    let parser_spans: Vec<_> = pending.iter().map(PendingProc::span).collect();
    let mut pending = pending.into_iter().enumerate().peekable();
    let mut owner_bindings = OwnerBindingCache::with_queries(4 * 1024 * 1024, 64, Arc::clone(&session.owner_frames));
    let pool_cache = lowering_cache.fork();
    let (lowering_result, worker_stats) = procedure_pipeline::with_lowering_cache(
        &pool_cache,
        workers,
        |pool| -> Result<(), String> {
            let mut prefetched_until = 0;
            let mut parser_prefetched_until = 0;
            let mut replay_scratch = ReplayScratch::default();
            let output_started = std::time::Instant::now();
            let mut parent_prepare_seconds = 0.0f64;
            let mut parent_wait_seconds = 0.0f64;
            let mut parent_section_seconds = 0.0f64;
            let mut parent_link_seconds = 0.0f64;
            let mut parent_record_seconds = 0.0f64;
            let mut parent_fragment_seconds = 0.0f64;
            let mut next_progress = 0usize;
            while pending.peek().is_some() {
                let progress_ordinal = pending.peek().unwrap().0;
                if progress_ordinal >= next_progress {
                    let stats = &session.procedure_fragments.stats;
                    let graph_stats = session.graph.stats();
                    let (constant_entries,constant_evictions)=const_eval::cache_stats();
                    trace(&format!("procedure output {progress_ordinal}/{procedure_count}: elapsed={:.3}s reused={} built={} encode={:.3}s flush={:.3}s read={:.3}s decode={:.3}s graph_persist={:.3}s graph_install={:.3}s constant_entries={} constant_evictions={}",
                        output_started.elapsed().as_secs_f64(), stats.reused, stats.built,
                        stats.encode_seconds, stats.flush_seconds, stats.read_seconds, stats.decode_seconds,
                        graph_stats.prepared_persist_seconds,graph_stats.candidate_install_seconds,constant_entries,constant_evictions));
                    trace(&format!("procedure parent phases: prepare={parent_prepare_seconds:.3}s wait={parent_wait_seconds:.3}s section={parent_section_seconds:.3}s link={parent_link_seconds:.3}s records_helpers={parent_record_seconds:.3}s fragments={parent_fragment_seconds:.3}s"));
                    next_progress = progress_ordinal.saturating_add(1024);
                }
                if reusable {
                    let ordinal = pending.peek().unwrap().0;
                    if ordinal >= prefetched_until {
                        prefetched_until = ordinal.saturating_add(1024).min(procedure_keys.len());
                        // Session pressure may discard all encoded/decoded
                        // payloads while retaining valid semantic candidates.
                        // Restore nearby code in bounded reads instead of
                        // opening the shared store once for every procedure.
                        let mut keys = procedure_keys[ordinal..prefetched_until].to_vec();
                        for index in ordinal..prefetched_until {
                            for (parameter, param) in invocations[index].params.iter().enumerate() {
                                if param.source_expression.is_some() {
                                    keys.push(crate::ProcKey {
                                        path: format!("@argument|{}|{parameter}", procedure_keys[index].path),
                                        occurrence: procedure_keys[index].occurrence,
                                    });
                                }
                            }
                        }
                        session.procedure_fragments.prefetch(&procedure_keys[ordinal..prefetched_until]);
                        keys.retain(|key| !session.procedure_fragments.has_handle(key));
                        let _ = session.graph.prefetch(&keys);
                    }
                }
                let ordinal = pending.peek().unwrap().0;
                if ordinal >= parser_prefetched_until {
                    parser_prefetched_until = ordinal.saturating_add(1024).min(procedure_keys.len());
                    let mut parse_keys = Vec::new();
                    for index in ordinal..parser_prefetched_until {
                        // Existing output handles take the validated replay
                        // path below. Do not probe their witnesses twice merely
                        // to prefetch a parser they normally never need.
                        if reusable && lowering_audit.is_none() && outline.is_none()
                            && session.procedure_fragments.has_handle(&procedure_keys[index]) { continue; }
                        let span = parser_spans[index];
                        let digest = frontend.as_ref().and_then(|frontend| frontend.procedure_digest_at(span)).map(str::to_owned)
                            .or_else(|| procedure_digests.as_ref().and_then(|digests| digests.get(&(span.start,span.end))).cloned())
                            .map(Ok).unwrap_or_else(|| source_range(span).map(|raw|crate::incremental::digest(raw.as_bytes())))?;
                        let descriptor = crate::ProcDescriptor { body_digest:digest.clone(), frame_digest:invocations[index].frame_digest.clone() };
                        if !reusable || session.graph.probe_validity(&procedure_keys[index],&descriptor).is_none() {
                            parse_keys.push(digest);
                        }
                    }
                    pool.prefetch_source_keys(&parse_keys);
                }
                // Reusable output nodes compose directly before entering the
                // lower/prepared pipeline. A miss uses the same ordered path,
                // and only its small neighboring worker window is decoded.
                if reusable && lowering_audit.is_none() && outline.is_none() {
                    let (ordinal, next) = pending.peek().unwrap();
                    let ordinal = *ordinal;
                    let plan = &invocations[ordinal];
                    let key = &procedure_keys[ordinal];
                    let descriptor = crate::ProcDescriptor {
                        body_digest: frontend.as_ref().and_then(|frontend| frontend.procedure_digest_at(next.span())).map(str::to_owned)
                            .or_else(|| procedure_digests.as_ref().and_then(|digests| digests.get(&(next.span().start, next.span().end))).cloned())
                            .map(Ok).unwrap_or_else(|| source_range(next.span()).map(|raw| crate::incremental::digest(raw.as_bytes())))?,
                        frame_digest: plan.frame_digest.clone(),
                    };
                    if let Some(candidate) = session.graph.probe_validity(key, &descriptor) {
                        if let Some(fragment) = session.procedure_fragments.get(key, &descriptor, &candidate) {
                            let started = std::time::Instant::now();
                            if let Some((proc_index, words, relocated, linked_rows)) = replay_procedure_fragment(&fragment, &candidate, &mut replay_scratch, next, plan,
                                &mut dmb, &mut strings, class_paths, &resource_ids, initializer_globals, global_proc_ids,
                                source_debug, &mut session.graph, &mut session.active_keys,
                                &mut argument_source_indices, &mut pending_argument_sources)? {
                                session.active_keys.insert(key.clone());
                                session.emission_stats.authored_prepared_reused += 1;
                                session.procedure_fragments.stats.reused += 1;
                                session.procedure_fragments.stats.relocated += usize::from(relocated);
                                session.procedure_fragments.stats.linked_rows_reused += usize::from(linked_rows);
                                session.procedure_fragments.stats.replay_seconds += started.elapsed().as_secs_f64();
                                emitted.push(EmittedProc { path: plan.path.clone(), proc_index, words: words.into() });
                                pending.next();
                                continue;
                            }
                        }
                    }
                }
                // The fixed batch width is independent of worker count, so
                // static-slot allocation and ordered linking produce identical
                // table IDs regardless of worker count. AST jobs are bounded.
                let mut prepared = Vec::with_capacity(procedure_pipeline::LOWERING_WINDOW);
                let mut cached_results = Vec::new();
                let mut submitted = 0;
                let prepare_started = std::time::Instant::now();
                for _ in 0..procedure_pipeline::LOWERING_WINDOW {
                    let Some((ordinal, pending)) = pending.next() else {
                        break;
                    };
                    if ordinal % 5000 == 0 {
                        trace(&format!(
                            "procedure lowering {ordinal}/{procedure_count}: {}",
                            pending.item.header
                        ));
                    }
                    let plan = &invocations[ordinal];
                    let path = plan.path.clone();
                    let params = plan.params.clone();
                    let metadata = plan.metadata.clone();
                    let static_ids = plan.static_ids.clone();
                    let key = procedure_keys[ordinal].clone();
                    session.active_keys.insert(key.clone());
                    let descriptor = crate::ProcDescriptor {
                        body_digest: frontend.as_ref().and_then(|frontend| frontend.procedure_digest_at(pending.span())).map(str::to_owned)
                            .or_else(|| procedure_digests.as_ref().and_then(|digests| digests.get(&(pending.span().start, pending.span().end))).cloned())
                            .map(Ok).unwrap_or_else(|| source_range(pending.span()).map(|raw| crate::incremental::digest(raw.as_bytes())))?,
                        frame_digest: plan.frame_digest.clone(),
                    };
                    let cached = if reusable { session.graph.probe(&key, &descriptor) } else { crate::ProcedureProbe::Miss };
                    let envelope = match cached {
                        crate::ProcedureProbe::Resident(crate::ProcedureArtifact::Prepared(envelope)) => Some(envelope),
                        _ => None,
                    };
                    // Pure authored hits need only the prepared section. Retain
                    // invocation bindings for misses and argument-source helpers.
                    let needs_bindings = envelope.is_none()
                        || params.iter().any(|param| param.source_expression.is_some());
                    let bindings = if needs_bindings {
                        let mut bindings = plan.lower_bindings();
                        bindings.shared = Some(Arc::clone(&shared_bindings));
                        bindings.prepared_member_globals = prepared_member_globals.clone();
                        if let Some(owner) = pending.owner {
                            owner_bindings.populate(owner, &dmb, &shared_bindings, &mut bindings);
                        }
                        bindings
                    } else {
                        LowerBindings::default()
                    };
                    let body_base;
                    if let Some(envelope) = &envelope {
                        body_base = pending.span().start + envelope.body_base_relative;
                        cached_results.push(procedure_pipeline::LoweringResult {
                            ordinal, bindings, compiled: Ok(envelope.metadata.clone()), memo: None, lowering_cache_hit: false, body_base:None,source_error:None,internal_panic: None,
                        });
                    } else {
                        body_base = pending.span().start;
                        pool.submit_source(ordinal,Arc::from(source_range(pending.span())?.as_ref()),
                            pending.span().start,metadata.clone(),Arc::clone(&worker_modified),bindings);
                        submitted += 1;
                    }
                    prepared.push((ordinal, pending, path, params, metadata, static_ids, body_base, key, descriptor, envelope));
                }
                parent_prepare_seconds += prepare_started.elapsed().as_secs_f64();
                let wait_started = std::time::Instant::now();
                cached_results.extend(pool.receive_batch(submitted));
                parent_wait_seconds += wait_started.elapsed().as_secs_f64();
                cached_results.sort_by_key(|result| result.ordinal);
                let results = cached_results;
                for ((ordinal, pending, path, params, metadata, static_ids, body_base, key, descriptor, cached_envelope), result) in
                    prepared.into_iter().zip(results)
                {
                    assert_eq!(ordinal, result.ordinal, "lowered procedure order");
                    if let Some(error)=&result.source_error { return Err(error.clone()); }
                    let body_base=result.body_base.unwrap_or(body_base);
                    if let Some(report) = lowering_audit.as_deref_mut() {
                        report.record(&path, pending.span(), body_base, source_debug, &result.compiled);
                        if result.compiled.is_err() { continue; }
                    }
                    let bindings = result.bindings;
                    let simple = result
                        .compiled
                        .map_err(|errors| errors.iter().map(|error| {
                            let offset = error.statement_origin.as_ref().and_then(|span| body_base.checked_add(span.start))
                                .unwrap_or(pending.header_span().start);
                            source_error(source_debug, offset, &path,
                                &format!("{} ({})", error.reason, error.statement))
                        }).collect::<Vec<_>>().join("\n"))?;
                    let prepared_reused = cached_envelope.is_some();
                    let section_started = std::time::Instant::now();
                    let envelope = if let Some(envelope) = cached_envelope { envelope } else {
                        if result.lowering_cache_hit { session.emission_stats.authored_cache_reused += 1; }
                        else { session.emission_stats.authored_lowered += 1; }
                        let mut envelope = dm_codegen_byond::prepared_cache::PreparedProcedureEnvelope::prepare(&simple)
                            .map_err(|error| format!("{path}: prepare code section: {error}"))?;
                        envelope.body_base_relative = body_base.saturating_sub(pending.span().start);
                        let envelope = Arc::new(envelope);
                        if reusable {
                            if let Some(memo) = &result.memo {
                                session.graph.install_prepared(key.clone(), descriptor.clone(), Arc::clone(&envelope),
                                    memo.dependencies.clone().into(), None);
                            }
                        }
                        envelope
                    };
                    if prepared_reused { session.emission_stats.authored_prepared_reused += 1; }
                    parent_section_seconds += section_started.elapsed().as_secs_f64();
                    let link_started = std::time::Instant::now();
                    let output_variable_base = dmb.variables.len();
                    let output_allocation_start=procedure_fragments::AllocationCounts::from_dmb(&dmb)
                        .ok_or("output allocation count exceeds u32")?;
                    let mut output_helpers = Vec::new();
                    let mut output_helper_proofs = HashMap::new();
                    if reusable { strings.begin_trace(); }
                    let literal_ids: Vec<_> = simple.strings.iter()
                        .map(|value| strings.intern_bytes(&mut dmb, simple.string_bytes(value))).collect();
                    let cached_ledger = if reusable {
                        session.emission_plans.get(&key, &descriptor, &skeleton_key,
                            &resource_assignment_identity, &literal_ids)
                    } else { None };
                    let fully_cached_ledger = cached_ledger.is_some();
                    // Structural changes reconsider only this section's actual
                    // assignment dependencies. Unrelated declarations retain
                    // their concrete immutable ledger without rebinding.
                    let cached_ledger = cached_ledger.or_else(|| {
                        if !reusable { return None; }
                        let prior = session.emission_plans.candidate(&key, &descriptor, &literal_ids)?;
                        let mut matches = true;
                        envelope.section.for_each_reference(|table, name| {
                            if !matches { return; }
                            let current = match table {
                                Table::String => simple.strings.iter().zip(&literal_ids)
                                    .find(|(value, _)| value.as_str() == name).map(|(_, id)| *id),
                                Table::Class => class_link_id(&dmb, class_paths, name),
                                Table::Variable if name == dm_codegen_byond::BUILTIN_GLOBAL_VARS_SYMBOL => strings.5,
                                Table::Variable => static_ids.get(name).or_else(|| initializer_globals.get(name)).copied(),
                                Table::Proc => global_proc_ids.get(name).copied(),
                                Table::Instance => strings.4.get(name).copied(),
                                Table::Resource => resource_ids.get(name).copied(),
                                _ => None,
                            };
                            matches = current.is_some() && current == prior.id(&Symbol::new(table, name));
                        });
                        matches.then_some(prior)
                    });
                    let ledger = if let Some(ledger) = cached_ledger { ledger } else {
                        let mut ledger = Ledger::default();
                        for class_path in &simple.class_paths {
                            let id = class_link_id(&dmb, &class_paths, class_path).ok_or_else(|| {
                                let offset = envelope.reference_origin(Table::Class, class_path)
                                    .and_then(|span| body_base.checked_add(span.start))
                                    .unwrap_or(pending.header_span().start);
                                source_error(source_debug, offset, &path, &format!("unresolved constructor type: {class_path}"))
                            })?;
                            bind_class_link(&mut ledger, class_path, id)?;
                        }
                        bind_builtin_global_vars(&mut dmb, &mut strings, &mut ledger)
                            .map_err(|error| format!("{path}: {error}"))?;
                        for (value, &id) in simple.strings.iter().zip(&literal_ids) {
                            let symbol = Symbol::new(Table::String, value);
                            if ledger.id(&symbol).is_none() {
                                ledger.bind(symbol, id).map_err(|error| error.to_string())?;
                            }
                        }
                        for path in &simple.resources {
                            let id = resource_ids
                                .get(path)
                                .ok_or_else(|| format!("{path}: resource literal was not loaded"))?;
                            ledger
                                .bind_alias(Symbol::new(Table::Resource, path), *id)
                                .map_err(|error| format!("procedure resource {path}: {error}"))?;
                        }
                        bind_prepared_references(&envelope.section, &strings, &mut ledger,
                            &initializer_globals, Some(&static_ids), &global_proc_ids)
                            .map_err(|error| format!("{path}: {error}"))?;
                        let ledger = if let Some(prior) = session.emission_plans.candidate(&key, &descriptor, &literal_ids) {
                            let delta = ledger.changes_since(&prior);
                            if !envelope.section.references_changed(&delta) { prior } else { Arc::new(ledger) }
                        } else { Arc::new(ledger) };
                        ledger
                    };
                    if reusable && !fully_cached_ledger {
                        session.emission_plans.retain(key.clone(), descriptor.clone(), &skeleton_key,
                            &resource_assignment_identity, literal_ids, Arc::clone(&ledger));
                    }
                    envelope.section.attach_projection_cache(Arc::clone(&session.output_projections));
                    let linked_words = envelope.section.materialize_with_debug_shared(&ledger, &simple.statement_origins, |relative| {
                        let (file, line) = source_debug?.resolve(body_base.checked_add(relative)?)?;
                        Some((strings.intern_debug(&mut dmb, &file, relative), line))
                    }).map_err(|error| format!("{path}: {error}"))?;
                    if linked_words.len() > u16::MAX as usize {
                        return Err(format!("{path}: code exceeds DMB list limit"));
                    }
                    parent_link_seconds += link_started.elapsed().as_secs_f64();
                    let records_started = std::time::Instant::now();
                    let path_id = strings.intern(&mut dmb, &path);
                    let name = path.rsplit('/').next().unwrap_or(&path).replace('_', " ");
                    let display_id = strings.intern_bytes(
                        &mut dmb,
                        metadata.name.as_deref().unwrap_or(name.as_bytes()),
                    );
                    let description_id =
                        metadata.description.as_ref().map_or(0xffff, |description| {
                            strings.intern_bytes(&mut dmb, description)
                        });
                    let category_id = metadata
                        .category
                        .as_ref()
                        .map_or(0xffff, |category| strings.intern_bytes(&mut dmb, category));
                    let code_id = dmb.append_shared_list(Arc::clone(&linked_words)).map_err(|error|error.to_string())?;
                    let local_ids = simple
                        .local_names
                        .iter()
                        .map(|name| append_null_variable(&mut dmb, &mut strings, name))
                        .collect();
                    let locals_id = append_list(&mut dmb, local_ids);
                    let mut arg_words = Vec::new();
                    let mut arguments = simple
                        .argument_metadata()
                        .into_iter()
                        .enumerate()
                        .peekable();
                    while arguments.peek().is_some() {
                        let batch: Vec<_> = arguments.by_ref().take(procedure_pipeline::LOWERING_WINDOW).collect();
                        let mut submitted = 0;
                        let mut helpers = HashMap::new();
                        let mut helper_descriptors = HashMap::new();
                        for (index, _) in &batch {
                            if let Some(expression) = &params[*index].source_expression {
                                let mut source_bindings = bindings.clone();
                                source_bindings.parameter_defaults.clear();
                                source_bindings.parameter_value_sources.clear();
                                let source = format!("/proc/__argument_source()\n    return {expression}\n");
                                let helper_key = crate::ProcKey { path: format!("@argument|{}|{index}", key.path), occurrence: key.occurrence };
                                session.active_keys.insert(helper_key.clone());
                                let mut frame_identity = source_bindings.clone();
                                frame_identity.shared = None; frame_identity.owner = None;
                                let helper_descriptor = crate::ProcDescriptor {
                                    body_digest: crate::incremental::digest(source.as_bytes()),
                                    frame_digest: crate::lower_cache::shared_binding_fingerprint(&frame_identity),
                                };
                                output_helper_proofs.insert(*index, (helper_key.clone(), helper_descriptor.clone()));
                                let cached = if reusable { session.graph.probe(&helper_key, &helper_descriptor) } else { crate::ProcedureProbe::Miss };
                                if let crate::ProcedureProbe::Resident(crate::ProcedureArtifact::Prepared(envelope)) = cached {
                                    session.emission_stats.generated_prepared_reused += 1;
                                    helpers.insert(*index, envelope);
                                } else {
                                    let mut ast = parse(&source);
                                    if !ast.diagnostics.is_empty() { return Err(format!("argument source syntax: {:?}", ast.diagnostics)); }
                                    let body = std::mem::take(&mut ast.items[0].children);
                                    pool.submit_for_phase(procedure_pipeline::LoweringPhase::ArgumentSource, *index, body, source_bindings);
                                    helper_descriptors.insert(*index, (helper_key, helper_descriptor));
                                    submitted += 1;
                                }
                            }
                        }
                        for result in pool.receive_batch(submitted) {
                            let expression = params[result.ordinal].source_expression.as_deref().unwrap();
                            let helper = result.compiled.map_err(|errors| format!("argument source {expression}: {errors:?}"))?;
                            if result.lowering_cache_hit { session.emission_stats.generated_cache_reused += 1; }
                            else { session.emission_stats.generated_lowered += 1; }
                            let envelope = Arc::new(dm_codegen_byond::prepared_cache::PreparedProcedureEnvelope::prepare(&helper)
                                .map_err(|error| format!("argument source section: {error}"))?);
                            if reusable {
                                if let Some(memo) = result.memo {
                                    let (helper_key, helper_descriptor) = helper_descriptors.remove(&result.ordinal).unwrap();
                                    session.graph.install_prepared(helper_key, helper_descriptor, Arc::clone(&envelope), memo.dependencies.clone().into(), None);
                                }
                            }
                            helpers.insert(result.ordinal, envelope);
                        }
                        for (index, mut arg) in batch {
                            if params[index].source_expression.is_some() {
                                let helper = helpers
                                    .remove(&index)
                                    .expect("prepared argument source helper");
                                let mut referenced_statics = BTreeMap::new();
                                helper.section.for_each_reference(|table, name| {
                                    if table == Table::Variable {
                                        if let Some(id) = static_ids.get(name) {
                                            referenced_statics.insert(name.to_owned(), *id);
                                        }
                                    }
                                });
                                // The VM evaluates sources in their owning object context. Deduplicate
                                // equivalent symbolic code, retaining proc-static slot identity.
                                let key = crate::lower_cache::shared_binding_fingerprint(&(
                                    helper.section.encode().map_err(|error| error.to_string())?,
                                    referenced_statics.clone(),
                                ));
                                if let Some((helper_key, helper_descriptor)) = output_helper_proofs.remove(&index) {
                                    if let Some(identity) = session.graph.probe_validity(&helper_key, &helper_descriptor) {
                                        output_helpers.push(procedure_fragments::HelperRecipe { parameter: index,
                                            key: helper_key, descriptor: helper_descriptor, identity, dedup: key.clone(),
                                            statics: referenced_statics.clone() });
                                    }
                                }
                                let reference_index = if let Some(id) =
                                    argument_source_indices.get(&key)
                                {
                                    *id
                                } else {
                                    let reference_index = dmb.proc_references.len();
                                    if reference_index > u8::MAX as usize {
                                        return Err(
                                            "too many distinct argument source procedures".into()
                                        );
                                    }
                                    dmb.proc_references.push(0xffff);
                                    pending_argument_sources.push((
                                        reference_index,
                                        helper,
                                        static_ids.clone(),
                                    ));
                                    argument_source_indices.insert(key, reference_index);
                                    reference_index
                                };
                                arg.value_source = ((reference_index as u32) << 8) | 0x40;
                            }
                            let variable_id =
                                append_null_variable(&mut dmb, &mut strings, &arg.name);
                            arg_words.extend([
                                arg.type_flags,
                                arg.value_source,
                                variable_id,
                                arg.reserved,
                            ]);
                        }
                    }
                    let args_id = append_list(&mut dmb, arg_words);
                    crate::reserve_proc_sentinel(&mut dmb);
                    let proc_index = dmb.procs.len();
                    dmb.procs.push(Proc {
                        strings: [path_id, display_id, description_id, category_id],
                        source_parameter: metadata.source_parameter,
                        source_kind: metadata.source_kind,
                        flags: if metadata.flags & !0xff != 0 || metadata.invisibility.is_some() {
                            0x80 | metadata.flags as u8 & 0x7f
                        } else {
                            metadata.flags as u8 & 0x7f
                        },
                        extended_flags: (metadata.flags & !0xff != 0
                            || metadata.invisibility.is_some())
                        .then_some((metadata.flags | 0x80, metadata.invisibility.unwrap_or(255))),
                        code_locals_args: [code_id, locals_id, args_id],
                    });
                    parent_record_seconds += records_started.elapsed().as_secs_f64();
                    let fragment_started = std::time::Instant::now();
                    if reusable {
                        let recipes = strings.end_trace();
                        if output_helpers.len() == params.iter().filter(|param| param.source_expression.is_some()).count() {
                            if let Some(candidate) = session.graph.probe_validity(&key, &descriptor) {
                                let (relocations, debug) = envelope.section.output_relocations(&simple.statement_origins,
                                    |relative| source_debug.and_then(|source| source.resolve(body_base + relative)).is_some())
                                    .map_err(|error| format!("{path}: output dependency slots: {error}"))?;
                                let linked=output_helpers.is_empty().then(||procedure_fragments::ObjectWitness {
                                    semantic_identity:candidate.clone(),recipe_identity:String::new(),start:output_allocation_start,
                                    allocation_mask:procedure_fragments::AllocationMask::NONE,
                                    read_identities:Vec::new(),scalar_reads:Vec::new(),
                                    unresolved_debug:if source_debug.is_some() {simple.statement_origins.iter()
                                        .filter(|mark|source_debug.and_then(|source|source.resolve(body_base+mark.start)).is_none())
                                        .map(|mark|mark.start).collect()} else {Vec::new()},
                                    string_ids:{let mut ids:Vec<_>=recipes.iter().filter_map(|recipe|match recipe {
                                        procedure_fragments::StringRecipe::Bytes{old_id,..}=>Some(*old_id),procedure_fragments::StringRecipe::Debug{..}=>None,
                                    }).collect();ids.sort_unstable();ids},
                                    symbol_ids:relocations.iter().map(|relocation| {
                                        let at=relocation.offset as usize;
                                        match relocation.packed_tag { None=>linked_words[at],Some(_)=>((linked_words[at]>>8)<<16)|linked_words[at+1] }
                                    }).collect(),
                                    debug_ids:debug.iter().map(|mark|(linked_words[mark.file_offset as usize],linked_words[mark.line_offset as usize])).collect(),
                                });
                                let variable_count=dmb.variables.len().saturating_sub(output_variable_base);
                                let allocated_rows=procedure_fragments::ProcedureRowLayout::new(u32::try_from(variable_count)
                                    .map_err(|_|"procedure variable allocation count exceeds u32")?);
                                let local_offsets=dmb.lists[locals_id as usize].iter().map(|id|id.checked_sub(output_variable_base as u32)
                                    .ok_or("procedure local allocation reference precedes object")).collect::<Result<Vec<_>,_>>()?;
                                let mut argument_offsets=dmb.lists[args_id as usize].to_vec();
                                for argument in argument_offsets.chunks_exact_mut(4) {argument[2]=argument[2].checked_sub(output_variable_base as u32)
                                    .ok_or("procedure argument allocation reference precedes object")?;}
                                let mut relative_record=dmb.procs[proc_index].clone();relative_record.code_locals_args=[0,1,2];
                                let fragment = procedure_fragments::OutputFragment {
                                    body_base_relative: body_base.saturating_sub(pending.span().start),
                                    debug_enabled: source_debug.is_some(),
                                    unresolved_debug: if source_debug.is_some() { simple.statement_origins.iter()
                                        .filter(|mark| source_debug.and_then(|source| source.resolve(body_base + mark.start)).is_none())
                                        .map(|mark| mark.start).collect() } else { Vec::new() },
                                    strings: recipes,
                                    variables: dmb.variables[output_variable_base..].to_vec(),
                                    old_variable_base: output_variable_base as u32,
                                    locals: local_offsets.into(), arguments: argument_offsets.into(),
                                    record: relative_record, relocations, debug,
                                    helpers: output_helpers, linked, code_digest:None, code_word_count:None, allocated_rows:Some(allocated_rows), words: Arc::clone(&linked_words),
                                };
                                session.procedure_fragments.retain(key.clone(), descriptor.clone(), candidate, fragment);
                            }
                        }
                    }
                    attach_emitted_proc(&mut dmb, pending.owner, &pending.owner_path, pending.verb, proc_index);
                    parent_fragment_seconds += fragment_started.elapsed().as_secs_f64();
                    if let Some(outline) = &outline {
                        if let Some(entry) = outline.procedures.get(&path) {
                            let frame = LowerBindings {
                                current_proc_path: bindings.current_proc_path.clone(),
                                current_type_path: bindings.current_type_path.clone(),
                                parameters: bindings.parameters.clone(),
                                parameter_type_flags: bindings.parameter_type_flags.clone(),
                                parameter_value_sources: bindings.parameter_value_sources.clone(),
                                parameter_defaults: bindings.parameter_defaults.clone(),
                                parameter_types: bindings.parameter_types.clone(),
                                globals: bindings.globals.clone(),
                                global_types: bindings.global_types.clone(),
                                global_procs: bindings.global_procs.clone(),
                                ..LowerBindings::default()
                            };
                            captured_procedures.insert(
                                path.clone(),
                                crate::incremental::ProcedureCheckpoint {
                                    proc_id: proc_index as u32,
                                    owner_path: pending.owner_path.clone(),
                                    source_digest: entry.digest.clone(),
                                    bindings: frame,
                                    patchable: entry.patchable,
                                },
                            );
                        }
                    }
                    emitted.push(EmittedProc {
                        path,
                        proc_index,
                        words: linked_words.into(),
                    });
                }
            }
            if lowering_audit.is_some() {
                trace("canonical procedure audit complete; no dynamic initializers or output");
                return Ok(());
            }
            session.emission_plans.finish(&session.active_keys);
            trace(&format!("procedure parent phases complete: prepare={parent_prepare_seconds:.3}s wait={parent_wait_seconds:.3}s section={parent_section_seconds:.3}s link={parent_link_seconds:.3}s records_helpers={parent_record_seconds:.3}s fragments={parent_fragment_seconds:.3}s"));
            session.procedure_fragments.finish(&session.active_keys);
            trace(&format!("linked output objects: typed_rows_reused={} code_read_bytes={} code_hydration_seconds={:.3}",
                session.procedure_fragments.stats.linked_rows_reused,session.procedure_fragments.stats.code_read_bytes,
                session.procedure_fragments.stats.code_hydration_seconds));
            trace(&format!("output DAG: reused={} relocated={} built={} refill_batches={} refill_bytes={} replay_seconds={:.3} read_seconds={:.3} decode_seconds={:.3} encode_seconds={:.3} flush_seconds={:.3} write_batches={}",
                session.procedure_fragments.stats.reused, session.procedure_fragments.stats.relocated,
                session.procedure_fragments.stats.built, session.procedure_fragments.stats.batches,
                session.procedure_fragments.stats.disk_bytes, session.procedure_fragments.stats.replay_seconds,
                session.procedure_fragments.stats.read_seconds, session.procedure_fragments.stats.decode_seconds,
                session.procedure_fragments.stats.encode_seconds, session.procedure_fragments.stats.flush_seconds,
                session.procedure_fragments.stats.write_batches));
            trace("procedure lowering complete; dynamic initializers start");
            initializer_pipeline::emit_initializer_groups_with_pool(
                &mut dmb,
                initializer_pipeline::group_assignments(pending_dynamic),
                &mut strings,
                &class_paths,
                &resource_ids,
                &initializer_globals,
                &global_proc_ids,
                &shared_bindings,
                &prepared_member_globals,
                lowering_cache,
                true,
                Some(pool),
                reusable.then_some(&mut *session),
                Some(&state.initializers),
            )?;
            trace("primary dynamic initializers complete; modified initializers start");
            // Keep modified-instance groups distinct even when their base owner
            // matches. Restore their requested payloads in one bounded stage,
            // rather than reopening the database for each individual instance.
            let groups:Vec<_>=modified.declarations.iter().filter(|declaration|!declaration.children.is_empty()).map(|declaration| {
                let owner=class_paths[&modified.parents[declaration.header.trim()]];
                let pending=declaration.children.iter().map(|child| {
                    let (name,expression)=child.header.split_once('=').expect("modified assignment");
                    PendingDynamic {owner:Some(owner),name:name.trim().into(),expression:expression.trim().into(),sized_array:false}
                }).collect();
                (Some(owner),pending)
            }).collect();
            let ids=initializer_pipeline::emit_initializer_groups_with_pool(
                &mut dmb,groups,&mut strings,&class_paths,&resource_ids,&initializer_globals,
                &global_proc_ids,&shared_bindings,&prepared_member_globals,lowering_cache,false,
                Some(pool),reusable.then_some(&mut *session),Some(&state.modified_initializers))?;
            for (declaration,id) in modified.declarations.iter().filter(|declaration|!declaration.children.is_empty()).zip(ids) {
                let instance=strings.4[declaration.header.trim()] as usize;
                dmb.instances[instance].initializer=id;
            }
            trace("dynamic initializers complete; worker finalization start");
            Ok(())
        },
    );
    lowering_cache.merge_stats(worker_stats);
    trace("worker finalization complete; semantic cache publication start");
    if reusable {
        session.graph.retain_keys(&session.active_keys);
        let _ = session.graph.flush();
        let _ = session.output_projections.flush();
    }
    trace("semantic cache publication complete; output record finalization start");
    lowering_result?;
    if lowering_audit.is_some() { return Ok((dmb, Vec::new(), Vec::new())); }
    if emitted
        .iter()
        .any(|p| p.path == "/client/Import" || p.path == "/client/proc/Import")
    {
        dmb.world.set_client_import_handler(true);
    }
    reorder_member_override_lists(&mut dmb);
    trace("member override order finalized; argument helper linking start");
    for (reference_index, envelope, static_ids) in pending_argument_sources {
        let simple = &envelope.metadata;
        let mut ledger = Ledger::default();
        bind_builtin_global_vars(&mut dmb, &mut strings, &mut ledger)?;
        for value in &simple.strings {
            let id = strings.intern_bytes(&mut dmb, simple.string_bytes(value));
            ledger
                .bind(Symbol::new(Table::String, value), id)
                .map_err(|error| error.to_string())?;
        }
        for path in &simple.class_paths {
            let id = class_link_id(&dmb, &class_paths, path)
                .ok_or_else(|| format!("unresolved argument source type: {path}"))?;
            bind_class_link(&mut ledger, path, id)?;
        }
        for path in &simple.resources {
            let id = resource_ids
                .get(path)
                .ok_or_else(|| format!("argument source resource was not loaded: {path}"))?;
            ledger
                .bind_alias(Symbol::new(Table::Resource, path), *id)
                .map_err(|error| format!("argument source resource {path}: {error}"))?;
        }
        bind_prepared_references(&envelope.section, &strings, &mut ledger,
            &initializer_globals, Some(&static_ids), &global_proc_ids)?;
        envelope.section.attach_projection_cache(Arc::clone(&session.output_projections));
        let words = envelope.section.materialize(&ledger).map_err(|error| error.to_string())?;
        let code_id = append_list(&mut dmb, words);
        let empty_id = append_list(&mut dmb, vec![]);
        crate::reserve_proc_sentinel(&mut dmb);
        let proc_id = dmb.procs.len() as u32;
        dmb.procs.push(Proc {
            strings: [0xffff; 4],
            source_parameter: 255,
            source_kind: 0,
            flags: 4,
            extended_flags: None,
            code_locals_args: [code_id, empty_id, empty_id],
        });
        dmb.proc_references[reference_index] = proc_id;
    }
    trace("argument helper linking complete; procedure constants start");
    let procedure_ids: HashMap<&[u8], u32> = dmb
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, proc)| dmb.string(proc.strings[0]).map(|path| (path, id as u32)))
        .collect();
    let mut resolved_procedure_values = HashMap::with_capacity(strings.2.len());
    for (path, placeholder) in &strings.2 {
        let proc_id = *procedure_ids
            .get(path.as_bytes())
            .ok_or_else(|| format!("unresolved procedure constant: {path}"))?;
        resolved_procedure_values.insert(*placeholder, proc_id);
    }
    drop(procedure_ids);
    for variable in &mut dmb.variables {
        if variable.kind == 38 {
            if let Some(id) = resolved_procedure_values.get(&variable.value) {
                variable.value = *id;
            }
        }
    }
    let value_lists: HashSet<u32> = dmb
        .classes
        .iter()
        .flat_map(|class| [class.lists_and_procs[3], class.overrides])
        .filter(|id| *id != 0xffff)
        .collect();
    for id in value_lists {
        let Some(values) = dmb.lists.get_mut(id as usize) else {
            continue;
        };
        let mut cursor = 0;
        while cursor + 2 < values.len() {
            let kind = values[cursor + 1] & 0xff;
            if kind == 38 {
                if let Some(id) = resolved_procedure_values.get(&values[cursor + 2]) {
                    values[cursor + 1] = 38 | ((*id >> 16) << 8);
                    values[cursor + 2] = *id & 0xffff;
                }
            }
            cursor += if kind == 42 { 4 } else { 3 };
        }
    }
    trace("procedure constants complete; object ID promotion start");
    crate::promote_object_ids(&mut dmb);
    trace("object ID promotion complete; reference validation start");
    dmb.validate_references_incremental(&mut session.output_validation)
        .map_err(|error| error.to_string())?;
    let _ = session.output_projections.flush();
    trace("reference validation complete; resource archive serialization start");
    let rsc_bytes = if catalog.is_some() { Vec::new() } else {
        byond_dmb::rsc::named_archive_bytes(&archive).map_err(|error| error.to_string())?
    };
    trace("assembly complete");
    if let (Some(target), Some(outline)) = (capture, outline) {
        let mut symbols = BTreeMap::new();
        for (name, id) in initializer_globals {
            symbols.insert(Symbol::new(Table::Variable, name), *id);
        }
        for (name, id) in &resource_ids {
            symbols.insert(Symbol::new(Table::Resource, name), *id);
        }
        for (name, id) in global_proc_ids {
            symbols.insert(Symbol::new(Table::Proc, name), *id);
        }
        for (name, id) in &strings.4 {
            symbols.insert(Symbol::new(Table::Instance, name), *id);
        }
        if let Some(id) = strings.5 {
            symbols.insert(
                Symbol::new(
                    Table::Variable,
                    dm_codegen_byond::BUILTIN_GLOBAL_VARS_SYMBOL,
                ),
                id,
            );
        }
        *target = Some(crate::incremental::EmissionCheckpoint {
            abi_digest: outline.abi_digest,
            procedures: captured_procedures,
            shared: shared_bindings.as_ref().clone(),
            symbols: symbols.into_iter().collect(),
        });
    }
    Ok((dmb, emitted, rsc_bytes))
}

fn resolve_pending_parent_metadata(
    dmb: &Dmb,
    owner: u32,
    name: &str,
    verb: bool,
    declarations: &HashMap<(u32, String, bool), &Item>,
    resolved: &mut HashMap<(u32, String, bool), ProcMetadata>,
    fragments: &mut canonical::InvocationFragments,
) -> Result<Option<ProcMetadata>, String> {
    let mut parent = dmb.classes[owner as usize].parent_class_id();
    let mut chain = Vec::new();
    let mut visited = HashSet::new();
    let mut base = None;
    while parent != 0xffff {
        if !visited.insert(parent) {
            return Err("cyclic procedure metadata ancestry".into());
        }
        let key = (parent, name.to_owned(), verb);
        if let Some(metadata) = resolved.get(&key) {
            base = Some(metadata.clone());
            break;
        }
        if let Some(item) = declarations.get(&key) {
            chain.push((key, *item));
        } else if let Some(procedure) = dmb
            .lists
            .get(dmb.classes[parent as usize].lists_and_procs[usize::from(!verb)] as usize)
            .and_then(|ids| {
                ids.iter()
                    .rev()
                    .filter_map(|id| dmb.procs.get(*id as usize))
                    .find(|procedure| {
                        dmb.string(procedure.strings[0]).is_some_and(|path| {
                            path.rsplit(|byte| *byte == b'/').next() == Some(name.as_bytes())
                        })
                    })
            })
        {
            base = Some(proc_metadata(&[], Some((dmb, procedure)))?.0);
            break;
        }
        parent = dmb.classes[parent as usize].parent_class_id();
    }
    for (key, item) in chain.into_iter().rev() {
        let owner_path = dmb.string(dmb.classes[key.0 as usize].path_string_id())
            .and_then(|bytes| std::str::from_utf8(bytes).ok()).unwrap_or("");
        let (path, params) = fragments.signature(item, owner_path, verb)?;
        let inherited = match base {
            Some(previous) => previous,
            None => proc_metadata(&[], None)?.0,
        };
        let metadata = fragments.syntax(item, &path, &params, inherited)?.metadata.clone();
        resolved.insert(key, metadata.clone());
        base = Some(metadata);
    }
    Ok(base)
}

fn find_inherited_proc<'a>(
    dmb: &'a Dmb,
    mut owner: u32,
    name: &str,
    verb: bool,
) -> Option<&'a Proc> {
    let slot = if verb { 0 } else { 1 };
    loop {
        let class = dmb.classes.get(owner as usize)?;
        let list_id = class.lists_and_procs[slot];
        if list_id != 0xffff {
            for id in dmb.lists.get(list_id as usize)?.iter().rev() {
                let proc = dmb.procs.get(*id as usize)?;
                if dmb.string(proc.strings[0]).is_some_and(|path| {
                    path.rsplit(|byte| *byte == b'/').next() == Some(name.as_bytes())
                }) {
                    return Some(proc);
                }
            }
        }
        let parent = class.parent_class_id();
        if parent == 0xffff {
            return None;
        }
        owner = parent;
    }
}

fn reorder_member_override_lists(dmb: &mut Dmb) {
    for class_id in 0..dmb.classes.len() {
        let Some(owner) = dmb
            .string(dmb.classes[class_id].path_string_id())
            .map(|path| String::from_utf8_lossy(path).into_owned())
        else {
            continue;
        };
        for slot in [0, 1] {
            let list_id = dmb.classes[class_id].lists_and_procs[slot];
            if list_id == 0xffff {
                continue;
            }
            let members = dmb.lists[list_id as usize].to_vec();
            let paths: Vec<_> = members
                .iter()
                .map(|id| {
                    dmb.string(dmb.procs[*id as usize].strings[0])
                        .map(|path| String::from_utf8_lossy(path).into_owned())
                        .unwrap_or_default()
                })
                .collect();
            // DreamDaemon selects the first matching member; reopened definitions
            // therefore precede their earlier same-path implementations.
            let mut grouped = HashMap::<String, Vec<u32>>::new();
            for (&id, path) in members.iter().zip(&paths) {
                grouped.entry(path.clone()).or_default().push(id);
            }
            let members: Vec<_> = paths
                .iter()
                .map(|path| grouped.get_mut(path).unwrap().pop().unwrap())
                .collect();
            let implicit: HashSet<_> = paths
                .iter()
                .filter_map(|path| {
                    path.strip_prefix(&format!("{owner}/"))
                        .filter(|name| !name.contains('/'))
                        .map(str::to_owned)
                })
                .collect();
            if implicit.is_empty() {
                dmb.lists[list_id as usize] = (members).into();
                continue;
            }
            let mut active = Vec::new();
            let mut other = Vec::new();
            let mut shadowed = Vec::new();
            for (id, path) in members.into_iter().zip(paths) {
                if path
                    .strip_prefix(&format!("{owner}/"))
                    .is_some_and(|name| implicit.contains(name))
                {
                    active.push(id);
                } else if path
                    .strip_prefix(&format!("{owner}/proc/"))
                    .is_some_and(|name| implicit.contains(name))
                    || path
                        .strip_prefix(&format!("{owner}/verb/"))
                        .is_some_and(|name| implicit.contains(name))
                {
                    shadowed.push(id);
                } else {
                    other.push(id);
                }
            }
            active.extend(other);
            active.extend(shadowed);
            dmb.lists[list_id as usize] = (active).into();
        }
    }
}

fn referenced_initializer_globals(
    source: &str,
    globals: &HashMap<String, u32>,
) -> BTreeSet<String> {
    // Include interpolated-string words conservatively. A token-only visitor
    // would omit names evaluated within strings; harmless extra matches are
    // preferable to removing a valid binding.
    let mut used = BTreeSet::new();
    let mut start = None;
    for (offset, character) in source
        .char_indices()
        .chain(std::iter::once((source.len(), ' ')))
    {
        if character == '_'
            || character.is_alphabetic()
            || (start.is_some() && character.is_alphanumeric())
        {
            start.get_or_insert(offset);
        } else if let Some(begin) = start.take() {
            let name = &source[begin..offset];
            if globals.contains_key(name) {
                used.insert(name.to_owned());
            }
        }
    }
    used
}

fn is_sized_array_declaration(header: &str) -> bool {
    header
        .split('=')
        .next()
        .and_then(|declaration| {
            declaration
                .find('[')
                .map(|at| declaration[at..].trim() != "[]")
        })
        .unwrap_or(false)
}

/// Native materializes literal lists before running dynamic initializer calls.
/// Allocating a datum, alist, matrix or regex can execute runtime work and belongs
/// to the later phase, even when its arguments are constants.
fn literal_initializer(expression: &str, dmb: &Dmb, strings: &StringIndex) -> bool {
    fn literal(expr: &dm_syntax::Expr, dmb: &Dmb, strings: &StringIndex) -> bool {
        use dm_syntax::ExprKind;
        match &expr.kind {
            ExprKind::Literal(raw) => {
                const_eval::evaluate(raw, |_| None).is_some()
                    || (raw.starts_with('\'') && raw.ends_with('\''))
            }
            ExprKind::TypePath(_) => true,
            ExprKind::Ident(name) => fold_constant(name, dmb, None, strings).is_some(),
            ExprKind::Group(inner) => literal(inner, dmb, strings),
            ExprKind::Unary { op, value } if matches!(op.as_str(), "!" | "+" | "-" | "~") => {
                literal(value, dmb, strings)
            }
            ExprKind::Binary { op, lhs, rhs } if op != "=" => {
                literal(lhs, dmb, strings) && literal(rhs, dmb, strings)
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                literal(condition, dmb, strings)
                    && literal(then_value, dmb, strings)
                    && literal(else_value, dmb, strings)
            }
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "list") => {
                args.iter().all(|arg| {
                    if let ExprKind::Binary { op, lhs, rhs } = &arg.kind {
                        if op == "=" {
                            return (matches!(lhs.kind, ExprKind::Ident(_))
                                || literal(lhs, dmb, strings))
                                && literal(rhs, dmb, strings);
                        }
                    }
                    literal(arg, dmb, strings)
                })
            }
            ExprKind::Call { callee, args }
                if matches!(&callee.kind, ExprKind::Ident(name) if name == "newlist")
                    && args.is_empty() =>
            {
                true
            }
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") => {
                args.len() == 1 && dm_codegen_byond::nameof_reference(&args[0]).is_some()
            }
            _ => false,
        }
    }
    const_eval::parsed_expression(expression).as_ref().is_some_and(|expr|literal(expr,dmb,strings))
}


fn emit_world<'a>(
    item: &'a Item,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    pending: &mut Vec<PendingProc<'a>>,
) -> Result<(), String> {
    for member in &item.children {
        if matches!(member.kind, ItemKind::Proc | ItemKind::Verb) {
            if member.kind == ItemKind::Verb {
                return Err("world verbs are unsupported".into());
            }
            pending.push(PendingProc {
                source_offset: 0,
                item: member,
                owner: None,
                owner_path: "/world".into(),
                verb: false,
            });
            continue;
        }
        let (name, value) = member
            .header
            .trim()
            .split_once('=')
            .ok_or_else(|| format!("unsupported world setting: {}", member.header))?;
        let name = name.trim();
        let raw_value = value.trim();
        let folded = match fold_constant(raw_value, dmb, None, strings) {
            Some(const_eval::Constant::Number(n)) => Some(n.to_string()),
            Some(const_eval::Constant::Text(text)) => Some(format!("\"{text}\"")),
            _ => None,
        };
        let value = folded.as_deref().unwrap_or(raw_value);

        match name {
            "name" if value.starts_with('"') && value.ends_with('"') && value.len() >= 2 => {
                dmb.world.ids[6] = strings.intern(dmb, &value[1..value.len() - 1]);
            }
            "mob" | "turf" | "area" if value.starts_with('/') || value == "null" => {}
            "maxx" | "maxy" | "maxz" => {
                let dimension = value
                    .parse::<u16>()
                    .map_err(|_| format!("invalid world.{name}: {value}"))?;
                let slot = match name {
                    "maxx" => 0,
                    "maxy" => 1,
                    _ => 2,
                };
                dmb.dimensions[slot] = dimension;
            }
            "view" => {
                dmb.world.view_dimensions = encode_world_view(value)?;
                dmb.header.flags &= !0x200;
            }
            "hub_password" => {
                dmb.world.hub_password = if value == "null" {
                    0xffff
                } else {
                    let text = value
                        .strip_prefix('"')
                        .and_then(|v| v.strip_suffix('"'))
                        .ok_or_else(|| format!("invalid world.hub_password: {value}"))?;
                    strings.intern(dmb, &byond_dmb::hash::hub_password_hash(text.as_bytes()))
                };
            }
            "status" | "hub" => {
                let text = value.strip_prefix('"').and_then(|v| v.strip_suffix('"'));
                let id = if value == "null" {
                    0xffff
                } else {
                    strings.intern(
                        dmb,
                        text.ok_or_else(|| format!("invalid world.{name}: {value}"))?,
                    )
                };
                if name == "status" {
                    dmb.world.server_name = id;
                } else {
                    dmb.world.hub_channel_skin[0] = id;
                }
            }
            "fps" => {
                let fps = value
                    .parse::<u32>()
                    .ok()
                    .filter(|v| (1..=100).contains(v))
                    .ok_or_else(|| format!("invalid world.fps: {value}"))?;
                dmb.world.tick_lag = 1000 / fps;
            }
            "version" => {
                dmb.world.version = value
                    .parse::<i32>()
                    .map_err(|_| format!("invalid world.version: {value}"))?
                    as u32;
            }
            "cache_lifespan" => {
                dmb.world.cache_lifespan = value
                    .parse::<u16>()
                    .map_err(|_| format!("invalid world.cache_lifespan: {value}"))?;
            }
            "icon_size" | "map_format" => {
                let number = value
                    .parse::<u16>()
                    .map_err(|_| format!("invalid world.{name}: {value}"))?;
                if name == "icon_size" {
                    dmb.world.icon_dimensions_format[0] = number;
                    dmb.world.icon_dimensions_format[1] = number;
                } else {
                    dmb.world.icon_dimensions_format[2] = number;
                }
                if dmb.world.savefile_byond_version == 0 {
                    dmb.header.compatibility_line = b"min compatibility v514 507\n".to_vec();
                }
            }
            "sleep_offline" | "loop_checks" | "visibility" => {
                let number = value
                    .parse::<i32>()
                    .map_err(|_| format!("invalid world.{name}: {value}"))?;
                let (mask, enabled) = match name {
                    "sleep_offline" => (0x20, number != 0),
                    "loop_checks" => (0x2, number == 0),
                    _ => (0x2000, number == 0),
                };
                if enabled {
                    dmb.header.flags |= mask;
                } else {
                    dmb.header.flags &= !mask;
                }
            }
            "tick_lag" => {
                let deciseconds = value
                    .parse::<f32>()
                    .map_err(|_| format!("unsupported world.tick_lag: {value}"))?;
                if !deciseconds.is_finite()
                    || deciseconds < 0.0
                    || f64::from(deciseconds) * 100.0 > f64::from(u32::MAX)
                {
                    return Err(format!("invalid world.tick_lag: {value}"));
                }
                dmb.world.tick_lag = (deciseconds * 100.0).round() as u32;
            }
            _ => return Err(format!("unsupported world setting: {}", member.header)),
        }
    }
    Ok(())
}

/// Native view metadata stores numeric radii as square dimensions. A textual
/// width of zero instead selects the compact radius encoding.
fn encode_world_view(value: &str) -> Result<u16, String> {
    let invalid = || format!("invalid world.view: {value}");
    if let Ok(radius) = value.parse::<f32>() {
        if !radius.is_finite() || !(-1.0..=35.0).contains(&radius) {
            return Err(invalid());
        }
        let side = (radius as i32 * 2 + 1) as u16;
        return Ok((side << 8) | side);
    }
    let text = value
        .strip_prefix('"')
        .and_then(|v| v.strip_suffix('"'))
        .ok_or_else(invalid)?;
    let (width, height) = text.split_once('x').ok_or_else(invalid)?;
    let width = width.parse::<u16>().map_err(|_| invalid())?;
    let height = height.parse::<u16>().map_err(|_| invalid())?;
    if width > 255 || height > 255 || u32::from(width) * u32::from(height) > 5041 {
        return Err(invalid());
    }
    Ok(if width == 0 {
        height / 2
    } else {
        (width << 8) | height
    })
}

fn class_inherits(dmb: &Dmb, mut class: u32, path: &[u8]) -> bool {
    for _ in 0..dmb.classes.len() {
        let Some(record) = dmb.classes.get(class as usize) else {
            return false;
        };
        if dmb.string(record.path_string_id()) == Some(path) {
            return true;
        }
        class = record.parent_class_id();
    }
    false
}

fn ensure_mob_record(dmb: &mut Dmb, class: u32) -> Result<usize, String> {
    if let Some(index) = dmb.mobs.iter().position(|m| m.class == class) {
        return Ok(index);
    }
    let parent = dmb.classes[class as usize].parent_class_id();
    let mut record = if class_inherits(dmb, parent, b"/mob") {
        let index = ensure_mob_record(dmb, parent)?;
        dmb.mobs[index].clone()
    } else {
        MobType {
            class,
            key: 0xffff,
            sight: 0,
            extended_sight: None,
        }
    };
    record.class = class;
    let index = dmb.mobs.len();
    dmb.mobs.push(record);
    Ok(index)
}

fn ensure_class(
    path: &str,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    classes: &mut HashMap<String, u32>,
) -> Result<u32, String> {
    if let Some(&id) = classes.get(path) {
        return Ok(id);
    }
    let parent_path = path
        .rsplit_once('/')
        .map(|(parent, _)| parent)
        .unwrap_or("");
    let parent_path = if parent_path.is_empty() {
        "/datum"
    } else {
        parent_path
    };
    let parent = ensure_class(parent_path, dmb, strings, classes)?;
    let mut class = dmb.classes[parent as usize].clone();
    class.initial_ids[0] = strings.intern(dmb, path);
    class.initial_ids[1] = parent;
    let leaf = path.rsplit('/').next().unwrap();
    let display = leaf.replace('_', " ");
    class.initial_ids[2] = strings.intern(dmb, &display);
    class.text = strings.intern(dmb, &display.chars().take(1).collect::<String>());
    class.lists_and_procs = [0xffff; 6];
    class.overrides = 0xffff;
    crate::reserve_class_sentinel(dmb);
    let id = dmb.classes.len() as u32;
    dmb.classes.push(class);
    classes.insert(path.into(), id);
    strings.3.insert(path.into(), id);
    if path == "/particles" {
        let mut defaults = Vec::new();
        for (name, number) in [
            ("width", Some(100.0f32)),
            ("height", Some(100.0)),
            ("spawning", Some(1.0)),
            ("count", Some(100.0)),
            ("bound1", Some(-1000.0)),
            ("bound2", Some(1000.0)),
            ("gravity", None),
            ("gradient", None),
            ("transform", None),
            ("lifespan", None),
            ("fade", None),
            ("fadein", None),
            ("position", None),
            ("velocity", None),
            ("color", None),
            ("color_change", None),
            ("friction", None),
            ("icon", None),
            ("icon_state", None),
            ("scale", None),
            ("grow", None),
            ("rotation", None),
            ("spin", None),
            ("drift", None),
        ] {
            let variable = dmb.variables.len() as u32;
            let name = strings.intern(dmb, name);
            dmb.variables.push(Variable {
                kind: if number.is_some() { 42 } else { 0 },
                value: number.map_or(0, f32::to_bits),
                name,
            });
            defaults.extend([variable, 0]);
        }
        let declarations = append_list(dmb, defaults);
        dmb.classes[id as usize].lists_and_procs[4] = declarations;
    }
    Ok(id)
}

/// Initial-value references read the final target class, even when its subtype
/// declarations appear later. Group reopenings in source order and resolve the
/// parent/reference graph before evaluating any defaults.
fn order_type_initializers<'a>(
    items: Vec<&'a Item>,
    dmb: &Dmb,
    classes: &HashMap<String, u32>,
) -> Result<Vec<&'a Item>, String> {
    let mut groups: HashMap<&str, Vec<&Item>> = HashMap::new();
    let mut order = Vec::new();
    for item in items {
        if !groups.contains_key(item.header.trim()) {
            order.push(item.header.trim());
        }
        groups.entry(item.header.trim()).or_default().push(item);
    }
    let mut dependencies: HashMap<&str, Vec<String>> = HashMap::new();
    for &path in &order {
        let mut deps = Vec::new();
        let parent = dmb.classes[classes[path] as usize].parent_class_id();
        if parent != 0xffff {
            if let Some(parent) = dmb.string(dmb.classes[parent as usize].path_string_id()) {
                let parent = String::from_utf8_lossy(parent).into_owned();
                if parent != path && groups.contains_key(parent.as_str()) {
                    deps.push(parent);
                }
            }
        }
        for item in &groups[path] {
            for child in &item.children {
                if !child.header.contains("::") {
                    continue;
                }
                let tokens = dm_syntax::lex_spans(&child.header).tokens;
                for (index, token) in tokens.iter().enumerate() {
                    if token.text(&child.header) == "::"
                        || (token.text(&child.header) == ":"
                            && tokens.get(index + 1).is_some_and(|next| {
                                next.text(&child.header) == ":" && next.span.start == token.span.end
                            }))
                    {
                        let prefix = child.header[..token.span.start].trim_end();
                        let target = prefix
                            .rsplit(|c: char| !(c.is_alphanumeric() || c == '_' || c == '/'))
                            .next()
                            .unwrap_or("")
                            .trim_end_matches('/');
                        if target != path
                            && groups.contains_key(target)
                            && !deps.iter().any(|dependency| dependency == target)
                        {
                            deps.push(target.to_owned());
                        }
                    }
                }
            }
        }
        dependencies.insert(path, deps);
    }
    let mut finished = HashSet::new();
    let mut active = HashSet::new();
    let mut output = Vec::new();
    for path in order {
        let mut stack = vec![(path.to_owned(), false)];
        while let Some((path, exiting)) = stack.pop() {
            if exiting {
                active.remove(&path);
                if finished.insert(path.clone()) {
                    output.extend(groups[path.as_str()].iter().copied());
                }
                continue;
            }
            if finished.contains(&path) {
                continue;
            }
            if !active.insert(path.clone()) {
                return Err(format!("cyclic type initializer dependency: {path}"));
            }
            stack.push((path.clone(), true));
            for dependency in dependencies[path.as_str()].iter().rev() {
                if !finished.contains(dependency) {
                    stack.push((dependency.clone(), false));
                }
            }
        }
    }
    Ok(output)
}

/// Proc-only types have no emit_type visit, but still inherit finalized data.
fn refresh_remaining_implicit_class_headers(
    dmb: &mut Dmb,
    metadata: &mut TypeMetadataState,
) -> Result<(), String> {
    for class in metadata.first_generated_class as u32..dmb.classes.len() as u32 {
        let mut chain = Vec::new();
        let mut current = class;
        while current != 0xffff
            && current as usize >= metadata.first_generated_class
            && !metadata.emitted.contains(&current)
        {
            if chain.contains(&current) {
                return Err("cyclic implicit class ancestry".to_owned());
            }
            chain.push(current);
            current = dmb.classes[current as usize].parent_class_id();
        }
        for class in chain.into_iter().rev() {
            let parent = dmb.classes[class as usize].parent_class_id();
            let path = String::from_utf8_lossy(
                dmb.string(dmb.classes[class as usize].path_string_id())
                    .ok_or("implicit class has no path")?,
            )
            .into_owned();
            refresh_inherited_class_header(class, parent, &path, dmb, metadata)?;
        }
    }
    Ok(())
}

fn refresh_inherited_class_header(
    class_id: u32,
    parent: u32,
    path: &str,
    dmb: &mut Dmb,
    metadata: &mut TypeMetadataState,
) -> Result<(), String> {
    if (class_id as usize) < metadata.first_generated_class || !metadata.emitted.insert(class_id) {
        return Ok(());
    }
    let original = dmb.classes[class_id as usize].clone();
    let mut inherited = dmb.classes[parent as usize].clone();
    inherited.initial_ids[0] = original.initial_ids[0];
    inherited.initial_ids[1] = parent;
    inherited.lists_and_procs = [0xffff; 6];
    inherited.overrides = if inherited.overrides == 0xffff {
        0xffff
    } else {
        let values = dmb.lists[inherited.overrides as usize].to_vec();
        append_list(dmb, values)
    };
    let mut ancestor = parent;
    let mut named = path
        .rsplit('/')
        .next()
        .is_some_and(|leaf| leaf.starts_with("__dm_modified_"));
    while ancestor != 0xffff {
        if metadata.authored_names.contains(&ancestor) {
            named = true;
            break;
        }
        ancestor = dmb.classes[ancestor as usize].parent_class_id();
    }
    if !named {
        inherited.initial_ids[2] = original.initial_ids[2];
        inherited.text = original.text;
    }
    dmb.classes[class_id as usize] = inherited;
    if class_inherits(dmb, class_id, b"/mob") {
        let parent_index = ensure_mob_record(dmb, parent)?;
        let mut record = dmb.mobs[parent_index].clone();
        record.class = class_id;
        let index = ensure_mob_record(dmb, class_id)?;
        dmb.mobs[index] = record;
    }
    Ok(())
}

/// Existing native builtin descendants also inherit authored changes to their parents.
/// Apply only parent-relative changes; preserve each builtin's intrinsic differences.
fn propagate_builtin_parent_defaults(
    dmb: &mut Dmb,
    parent: u32,
    before: byond_dmb::dmb::Class,
    limit: usize,
    authored: &HashSet<&str>,
) {
    let mut queue = vec![(parent, before)];
    let mut visited = HashSet::new();
    while let Some((parent, old_parent)) = queue.pop() {
        if !visited.insert(parent) {
            continue;
        }
        let new_parent = dmb.classes[parent as usize].clone();
        let children: Vec<_> = (0..limit)
            .filter(|&id| id as u32 != parent && dmb.classes[id].parent_class_id() == parent)
            .collect();
        for id in children {
            let original = dmb.classes[id].clone();
            let child = &mut dmb.classes[id];
            macro_rules! inherit { ($($field:ident),*) => { $(if original.$field == old_parent.$field { child.$field = new_parent.$field.clone(); })* }; }
            inherit!(
                direction,
                text,
                maptext,
                maptext_geometry,
                suffix,
                layer_bits,
                transform_flag,
                transform,
                color_matrix_flag,
                color_matrix
            );
            for index in 2..6 {
                if original.initial_ids[index] == old_parent.initial_ids[index] {
                    child.initial_ids[index] = new_parent.initial_ids[index];
                }
            }
            if authored.contains("layer") {
                child.layer_bits = new_parent.layer_bits;
            }
            if authored.contains("dir") {
                child.direction = new_parent.direction;
            }
            for (name, index) in [("name", 2), ("desc", 3), ("icon", 4), ("icon_state", 5)] {
                if authored.contains(name) {
                    child.initial_ids[index] = new_parent.initial_ids[index];
                }
            }
            let mut authored_flags = 0u64;
            for (name, mask) in [
                ("density", 2),
                ("opacity", 1),
                ("appearance_flags", !((1 << 21) - 1)),
                ("animate_movement", 0xc400),
                ("luminosity", 0x38),
                ("mouse_opacity", 0x3000),
                ("gender", 0xc0),
            ] {
                if authored.contains(name) {
                    authored_flags |= mask;
                }
            }
            let intrinsic = (original.flags ^ old_parent.flags) & !authored_flags;
            child.flags = (new_parent.flags & !intrinsic) | (original.flags & intrinsic);
            let old_overrides = dmb
                .class_builtin_overrides(parent as usize)
                .unwrap_or_default();
            // Decode the previous parent list independently of its replaced class header.

            dmb.classes[parent as usize] = old_parent.clone();
            let previous_overrides = dmb
                .class_builtin_overrides(parent as usize)
                .unwrap_or_default();
            dmb.classes[parent as usize] = new_parent.clone();
            let own = dmb.class_builtin_overrides(id).unwrap_or_default();
            let mut merged = old_overrides;
            for entry in own {
                if previous_overrides.iter().any(|parent| {
                    parent.name_string_id == entry.name_string_id && parent.value == entry.value
                }) {
                    continue;
                }
                merged.retain(|parent| parent.name_string_id != entry.name_string_id);
                merged.push(entry);
            }
            if !merged.is_empty() {
                let mut words = Vec::new();
                for entry in merged {
                    words.push(entry.name_string_id);
                    words.extend(entry.value.encode());
                }
                dmb.classes[id].overrides = append_list(dmb, words);
            }
            queue.push((id as u32, original));
        }
    }
}
fn emit_type<'a>(
    item: &'a Item,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    classes: &mut HashMap<String, u32>,
    resources: &HashMap<String, u32>,
    pending: &mut Vec<PendingProc<'a>>,
    pending_dynamic: &mut Vec<PendingDynamic>,
    metadata: &mut TypeMetadataState,
    owner_plan: &default_plans::OwnerDeclarationPlan,
    mut audit: Option<&mut InitializerAudit>,
) -> Result<(), String> {
    let path = item.header.trim();
    if !path.starts_with('/') || path == "/" {
        return Err(format!("type path must be absolute: {path}"));
    }
    let parent_path = path
        .rsplit_once('/')
        .map(|(parent, _)| parent)
        .unwrap_or("");
    let lexical_parent = if parent_path.is_empty() {
        "/datum"
    } else {
        parent_path
    };
    let explicit_parent = owner_plan.explicit_parent.as_deref();
    let parent_path = explicit_parent.unwrap_or(lexical_parent);
    let parent = *classes
        .get(parent_path)
        .ok_or_else(|| format!("unresolved parent type {parent_path} for {path}"))?;
    let class_id = if let Some(&id) = classes.get(path) {
        id
    } else {
        let mut class = dmb.classes[parent as usize].clone();
        class.initial_ids[0] = strings.intern(dmb, path);
        class.initial_ids[1] = parent;
        let leaf = path.rsplit('/').next().unwrap();
        let display = leaf.replace('_', " ");
        class.initial_ids[2] = strings.intern(dmb, &display);
        class.text = strings.intern(dmb, &display.chars().take(1).collect::<String>());
        class.lists_and_procs = [0xffff; 6];
        class.overrides = 0xffff;
        crate::reserve_class_sentinel(dmb);
        let id = dmb.classes.len() as u32;
        dmb.classes.push(class);
        classes.insert(path.into(), id);
        strings.3.insert(path.into(), id);
        id
    };
    let previous_builtin_header = ((class_id as usize) < metadata.first_generated_class)
        .then(|| dmb.classes[class_id as usize].clone());
    let mut implicit_ancestors = Vec::new();
    let mut ancestor = parent;
    let mut visited = HashSet::new();
    while ancestor != 0xffff
        && ancestor as usize >= metadata.first_generated_class
        && !metadata.emitted.contains(&ancestor)
    {
        if !visited.insert(ancestor) {
            return Err(format!("cyclic implicit class ancestry: {path}"));
        }
        implicit_ancestors.push(ancestor);
        ancestor = dmb.classes[ancestor as usize].parent_class_id();
    }
    for ancestor in implicit_ancestors.into_iter().rev() {
        let parent = dmb.classes[ancestor as usize].parent_class_id();
        let path = String::from_utf8_lossy(
            dmb.string(dmb.classes[ancestor as usize].path_string_id())
                .unwrap(),
        )
        .into_owned();
        refresh_inherited_class_header(ancestor, parent, &path, dmb, metadata)?;
    }
    refresh_inherited_class_header(class_id, parent, path, dmb, metadata)?;
    if explicit_parent.is_some() {
        dmb.classes[class_id as usize].initial_ids[1] = parent;
    }
    let is_const = |child: &Item| {
        child.kind == ItemKind::Var && child.header.split('=').next()
            .is_some_and(|header| header.split('/').any(|part| part.trim() == "const"))
    };
    let mutable_names = &owner_plan.mutable_names;
    let mut unresolved: Vec<_> = owner_plan.const_indexes.iter()
        .map(|index| &item.children[*index]).collect();
    while !unresolved.is_empty() {
        let before = unresolved.len();
        let mut last_error = String::new();
        unresolved.retain(|child| {
            match emit_class_var(
                child,
                class_id,
                dmb,
                strings,
                resources,
                pending_dynamic,
                &mutable_names,
                metadata,
            ) {
                Ok(()) => false,
                Err(error) => {
                    last_error = error;
                    true
                }
            }
        });
        if before == unresolved.len() {
            if let Some(audit) = audit.as_deref_mut() {
                for child in &unresolved {
                    audit.dependency_errors.push(format!(
                        "unresolved or cyclic class constant in {path}: {}",
                        child.header
                    ));
                }
                break;
            }
            return Err(format!(
                "unresolved or cyclic class constant in {path}: {last_error}"
            ));
        }
    }
    for child in &item.children {
        if is_const(child) {
            continue;
        }
        if child.header.trim().starts_with("parent_type") {
            continue;
        }
        let result = (|| -> Result<(), String> {
            match child.kind {
                ItemKind::Type => {}
                ItemKind::Var => emit_class_var(
                    child,
                    class_id,
                    dmb,
                    strings,
                    resources,
                    pending_dynamic,
                    &mutable_names,
                    metadata,
                )?,
                ItemKind::Unknown | ItemKind::Statement if child.header.contains('=') => {
                    if let Err(error) = emit_class_default(child, class_id, dmb, strings, resources)
                    {
                        if error.contains("re-initialization of global var") {
                            return Err(format!("{path}: {error}"));
                        }
                        let (name, expression) = child.header.split_once('=').unwrap();
                        let name = name.trim();
                        let expression = expression.trim();
                        let declared = wire_declarations::builtin_field(dmb, class_id, name)
                            || wire_declarations::inherited(dmb, class_id, name).is_some();
                        let parsed = const_eval::parsed_expression(expression);
                        let allocated_list = parsed.as_ref().is_some_and(|expr| {
                        match &expr.kind {
                            dm_syntax::ExprKind::Ident(name) => name == "new",
                            dm_syntax::ExprKind::Unary { op, .. } => op == "new",
                            dm_syntax::ExprKind::Call { callee, .. } => matches!(&callee.kind, dm_syntax::ExprKind::Ident(name) if matches!(name.as_str(), "new" | "newlist" | "list" | "alist" | "icon" | "sound" | "matrix" | "regex" | "image" | "mutable_appearance" | "generator" | "rgb")),
                            _ => false,
                        }
                    });
                        if declared && allocated_list {
                            pending_dynamic.push(PendingDynamic {
                                owner: Some(class_id),
                                name: name.to_owned(),
                                expression: expression.to_owned(),
                                sized_array: false,
                            });
                        } else {
                            return Err(format!("{path}: {error}"));
                        }
                    }
                }
                ItemKind::Proc | ItemKind::Verb => pending.push(PendingProc {
                    source_offset: 0,
                    item: child,
                    owner: Some(class_id),
                    owner_path: path.to_owned(),
                    verb: child.kind == ItemKind::Verb,
                }),
                _ => return Err(format!("unsupported member of {path}: {}", child.header)),
            }
            Ok(())
        })();
        if let Err(error) = result {
            if let Some(audit) = audit.as_deref_mut() {
                audit.record(format!("{path}: {error}"));
            } else {
                return Err(error);
            }
        }
    }
    if class_inherits(dmb, class_id, b"/atom") {
        let mut ancestor = class_id;
        let mut explicit_text = false;
        let mut visited = HashSet::new();
        while ancestor != 0xffff && visited.insert(ancestor) {
            explicit_text |= metadata.authored_texts.contains(&ancestor);
            ancestor = dmb.classes[ancestor as usize].parent_class_id();
        }
        if !explicit_text {
            let name = dmb
                .string(dmb.classes[class_id as usize].initial_ids[2])
                .unwrap_or_default();
            let mut start = 0;
            while name.get(start) == Some(&0xff) && start + 1 < name.len() {
                start += 2;
            }
            let first = String::from_utf8_lossy(&name[start..])
                .chars()
                .next()
                .map(|c| c.to_string())
                .unwrap_or_default();
            dmb.classes[class_id as usize].text = strings.intern(dmb, &first);
        }
    }
    if let Some(previous) = previous_builtin_header {
        let authored = item
            .children
            .iter()
            .filter_map(|child| child.header.split_once('=').map(|(name, _)| name.trim()))
            .collect::<HashSet<_>>();
        propagate_builtin_parent_defaults(
            dmb,
            class_id,
            previous,
            metadata.first_generated_class,
            &authored,
        );
    }
    Ok(())
}

fn emit_class_default(item:&Item,class_id:u32,dmb:&mut Dmb,strings:&mut StringIndex,resources:&HashMap<String,u32>)->Result<(),String> {
    if !declaration_operations::eligible(&item.header)||strings.6.is_some() {
        return emit_class_default_uncached(item,class_id,dmb,strings,resources);
    }
    if declaration_operations::replay(&item.header,class_id,dmb,strings,resources,None) {return Ok(());}
    let snapshot=declaration_operations::begin(&item.header,class_id,dmb,resources);
    strings.begin_trace();
    let result=emit_class_default_uncached(item,class_id,dmb,strings,resources);
    let operations=strings.end_trace();
    if result.is_ok() {declaration_operations::record(&item.header,class_id,snapshot,dmb,operations,None);}
    result
}

fn emit_class_default_uncached(
    item: &Item,
    class_id: u32,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    resources: &HashMap<String, u32>,
) -> Result<(), String> {
    let (key, value) = item
        .header
        .split_once('=')
        .ok_or_else(|| format!("unsupported class default: {}", item.header))?;
    let key = key.trim();
    let raw_value = value.trim();
    let folded = match fold_constant(raw_value, dmb, Some(class_id), strings) {
        Some(const_eval::Constant::Number(n)) => Some(n.to_string()),
        Some(const_eval::Constant::Text(text)) => Some(format!("\"{text}\"")),
        _ => None,
    };
    let value = folded.as_deref().unwrap_or(raw_value);
    if key == "byond_version"
        && dmb.string(dmb.classes[class_id as usize].path_string_id())
            == Some(b"/savefile".as_slice())
    {
        let number = value
            .parse::<f32>()
            .map_err(|_| format!("invalid /savefile/byond_version: {raw_value}"))?;
        if !number.is_finite() || number < 0.0 || number.fract() != 0.0 || number >= u32::MAX as f32
        {
            return Err(format!("invalid /savefile/byond_version: {raw_value}"));
        }
        dmb.world.savefile_byond_version = number as u32;
        let compatibility = String::from_utf8_lossy(&dmb.header.compatibility_line)
            .strip_prefix("min compatibility v")
            .and_then(|tail| tail.split_whitespace().next())
            .and_then(|version| version.parse::<u16>().ok())
            .ok_or("invalid compatibility header")?;
        if number != 0.0 && compatibility <= 514 {
            dmb.header.compatibility_line = b"min compatibility v515 468\n".to_vec();
        }
        return Ok(());
    }
    if key == "luminosity" && class_inherits(dmb, class_id, b"/area") {
        let number = value
            .parse::<f32>()
            .map_err(|_| format!("invalid area luminosity: {raw_value}"))?;
        dmb.classes[class_id as usize]
            .set_luminosity(number as u8)
            .map_err(|error| error.to_string())?;
        append_builtin_override(dmb, strings, class_id, key, 42, number.to_bits());
        return Ok(());
    }
    let mut ancestor = Some(class_id);
    while let Some(id) = ancestor {
        let variable = wire_declarations::local(dmb, id, key);
        if let Some((variable, flags)) = variable {
            if flags & 3 == 1 {
                return Err(format!("re-initialization of global var: {key}"));
            }
            let (kind, data) = constant_variable_value_scoped(
                Some(raw_value),
                &item.header,
                dmb,
                strings,
                resources,
                Some(class_id),
                &HashSet::new(),
            )?;
            let encoded = if kind == 42 {
                vec![42, data >> 16, data & 0xffff]
            } else {
                encode_tagged_constant(kind, data)
            };
            let list_id = dmb.classes[class_id as usize].lists_and_procs[3];
            let list_id = if list_id == 0xffff {
                let id = append_list(dmb, Vec::new());
                dmb.classes[class_id as usize].lists_and_procs[3] = id;
                id
            } else {
                list_id
            };
            dmb.lists[list_id as usize].push(variable);
            dmb.lists[list_id as usize].extend(encoded);
            return Ok(());
        }
        let parent = dmb.classes[id as usize].parent_class_id();
        ancestor = (parent != 0xffff).then_some(parent);
    }
    if class_inherits(dmb, class_id, b"/client")
        && matches!(
            key,
            "authenticate"
                | "show_map"
                | "show_popup_menus"
                | "macro_mode"
                | "show_verb_panel"
                | "lazy_eye"
                | "control_freak"
                | "preload_rsc"
                | "perspective"
                | "script"
        )
    {
        match key {
            "authenticate" | "show_map" | "show_popup_menus" | "macro_mode" | "show_verb_panel" => {
                let enabled = match value {
                    "0" => false,
                    "1" => true,
                    _ => return Err(format!("invalid client.{key}: {value}")),
                };
                let mask = match key {
                    "authenticate" => 0x8000,
                    "show_map" => 0x0010_0000,
                    "show_popup_menus" => 0x1000_0000,
                    "macro_mode" => 0x80,
                    _ => 0x400,
                };
                let set = if key == "macro_mode" {
                    enabled
                } else {
                    !enabled
                };
                if set {
                    dmb.header.flags |= mask;
                } else {
                    dmb.header.flags &= !mask;
                }
            }
            "lazy_eye" => {
                let number = value
                    .parse::<f32>()
                    .ok()
                    .filter(|v| (-1.0..=35.0).contains(v))
                    .ok_or_else(|| format!("invalid client.lazy_eye: {value}"))?;
                dmb.world.eye = number as i32 as u8;
                dmb.header.flags &= !0x100;
            }
            "control_freak" => {
                dmb.world.control = value
                    .parse::<u16>()
                    .ok()
                    .filter(|v| *v <= 7)
                    .ok_or_else(|| format!("invalid client.control_freak: {value}"))?;
            }
            "preload_rsc" => {
                let mode = match value {
                    "0" => 0x800,
                    "1" => 0,
                    "2" => 0x1000,
                    _ if value.starts_with('"') => 0x800,
                    _ => return Err(format!("invalid client.preload_rsc: {value}")),
                };
                dmb.header.flags = (dmb.header.flags & !0x1800) | mode;
                if value.starts_with('"') {
                    let (kind, data) = constant_variable_value(
                        Some(value),
                        &item.header,
                        dmb,
                        strings,
                        resources,
                    )?;
                    append_builtin_override(dmb, strings, class_id, key, kind, data);
                }
            }
            "perspective" => {
                let number = value
                    .parse::<u32>()
                    .ok()
                    .filter(|v| *v <= 3)
                    .ok_or_else(|| format!("invalid client.perspective: {value}"))?;
                dmb.header.flags = (dmb.header.flags & !0x0800_0000)
                    | if number & 1 != 0 { 0x0800_0000 } else { 0 };
                append_builtin_override(dmb, strings, class_id, key, 42, (number as f32).to_bits());
            }
            "script" => {
                let (kind, data) =
                    constant_variable_value(Some(value), &item.header, dmb, strings, resources)?;
                match kind {
                    6 => dmb.world.client_script = data,
                    12 => {
                        dmb.world.client_script_files.push(data);
                        dmb.world.client_script = 0xffff;
                    }
                    _ => return Err(format!("invalid client.script: {value}")),
                };
            }
            _ => unreachable!(),
        }
        return Ok(());
    }
    if matches!(key, "sight" | "see_in_dark" | "see_invisible")
        && class_inherits(dmb, class_id, b"/mob")
    {
        let number = value
            .parse::<u32>()
            .map_err(|_| format!("invalid mob.{key}: {value}"))?;
        let index = ensure_mob_record(dmb, class_id)?;
        let record = &mut dmb.mobs[index];
        let mut sight = record.sight_bits();
        let mut dark = record.see_in_dark_setting().unwrap_or(2);
        let mut invisible = record.see_invisible_setting().unwrap_or(0);
        match key {
            "sight" => sight = number & 0xffff,
            "see_in_dark" => dark = number as u8,
            _ => invisible = number as u8,
        };
        if record.extended_sight.is_some() || key != "sight" || sight > 0x7f {
            record.sight = (sight as u8) | 0x80;
            record.extended_sight = Some((sight | 0x80, dark, invisible));
        } else {
            record.sight = sight as u8;
        }
        return Ok(());
    }
    let class = &mut dmb.classes[class_id as usize];
    let string_value = || value.strip_prefix('"').and_then(|v| v.strip_suffix('"'));
    match key {
        "name" | "desc" | "icon_state" | "maptext" | "text" | "suffix" => {
            let id = if value == "null" {
                0xffff
            } else {
                match fold_constant(raw_value, dmb, Some(class_id), strings) {
                    Some(const_eval::Constant::Text(text)) => strings.intern(dmb, &text),
                    Some(const_eval::Constant::EncodedText(text)) => {
                        strings.intern_bytes(dmb, &text)
                    }
                    _ => return Err(format!("unsupported class default: {}", item.header)),
                }
            };
            let class = &mut dmb.classes[class_id as usize];
            match key {
                "name" => class.initial_ids[2] = id,
                "desc" => class.initial_ids[3] = id,
                "icon_state" => class.initial_ids[5] = id,
                "maptext" => class.maptext = id,
                "text" => class.text = id,
                "suffix" => class.suffix = id,
                _ => unreachable!(),
            }
        }
        "icon" => {
            let id = if value == "null" {
                0xffff
            } else {
                let path = value
                    .strip_prefix('\'')
                    .and_then(|v| v.strip_suffix('\''))
                    .ok_or_else(|| format!("unsupported class default: {}", item.header))?
                    .replace('\\', "/");
                *resources
                    .get(&path)
                    .ok_or_else(|| format!("resource was not loaded: {path}"))?
            };
            class.initial_ids[4] = id;
        }
        "density" | "opacity" => {
            let enabled = match value {
                "1" | "TRUE" => true,
                "0" | "FALSE" => false,
                _ => return Err(format!("unsupported class default: {}", item.header)),
            };
            if key == "density" {
                class.set_dense(enabled);
            } else {
                class.set_opaque(enabled);
            }
        }
        "layer" => {
            let layer: f32 = value
                .parse()
                .map_err(|_| format!("unsupported class default: {}", item.header))?;
            class.layer_bits = layer.to_bits();
        }
        "dir" => {
            class.direction = match value {
                "NORTH" => 1,
                "SOUTH" => 2,
                "EAST" => 4,
                "WEST" => 8,
                _ => value
                    .parse()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?,
            };
        }
        "maptext_width" | "maptext_height" | "maptext_x" | "maptext_y" => {
            let slot = match key {
                "maptext_width" => 0,
                "maptext_height" => 1,
                "maptext_x" => 2,
                _ => 3,
            };
            let encoded = if slot < 2 {
                value
                    .parse::<u16>()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?
            } else {
                value
                    .parse::<i16>()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?
                    as u16
            };
            class.maptext_geometry[slot] = encoded;
        }
        "mouse_opacity" => class
            .set_mouse_opacity(
                value
                    .parse()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?,
            )
            .map_err(|error| error.to_string())?,
        "animate_movement" => class
            .set_animate_movement(
                value
                    .parse()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?,
            )
            .map_err(|error| error.to_string())?,
        "luminosity" => class
            .set_luminosity(
                value
                    .parse()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?,
            )
            .map_err(|error| error.to_string())?,
        "appearance_flags" => class.set_appearance_flags(
            value
                .parse()
                .map_err(|_| format!("unsupported class default: {}", item.header))?,
        ),
        "alpha" | "plane" | "pixel_x" | "pixel_y" | "glide_size" | "blend_mode" | "color"
        | "vis_flags" => {
            let encoded = if key == "color" && string_value().is_some() {
                encode_tagged_constant(6, strings.intern(dmb, string_value().unwrap()))
            } else if key == "color" && value == "null" {
                vec![0, 0]
            } else if key == "color" {
                return Err(format!("unsupported class default: {}", item.header));
            } else {
                let number: f32 = value
                    .parse()
                    .map_err(|_| format!("unsupported class default: {}", item.header))?;
                let bits = number.to_bits();
                vec![42, bits >> 16, bits & 0xffff]
            };
            let name_id = strings.intern(dmb, key);
            let list_id = dmb.classes[class_id as usize].overrides;
            let list_id = if list_id == 0xffff {
                let id = append_list(dmb, Vec::new());
                dmb.classes[class_id as usize].overrides = id;
                id
            } else {
                list_id
            };
            dmb.lists[list_id as usize].push(name_id);
            dmb.lists[list_id as usize].extend(encoded);
        }
        _ => {
            if wire_declarations::builtin_field(dmb, class_id, key) {
                let (kind, data) =
                    constant_variable_value(Some(value), &item.header, dmb, strings, resources)?;
                append_builtin_override(dmb, strings, class_id, key, kind, data);
                return Ok(());
            }
            let variable = wire_declarations::inherited(dmb, class_id, key)
                .map(|(variable, _)| variable)
                .ok_or_else(|| format!("unsupported class default: {}", item.header))?;
            let (kind, data) =
                constant_variable_value(Some(value), &item.header, dmb, strings, resources)?;
            let encoded = if kind == 42 {
                vec![42, data >> 16, data & 0xffff]
            } else {
                encode_tagged_constant(kind, data)
            };
            let list_id = dmb.classes[class_id as usize].lists_and_procs[3];
            let list_id = if list_id == 0xffff {
                let id = append_list(dmb, Vec::new());
                dmb.classes[class_id as usize].lists_and_procs[3] = id;
                id
            } else {
                list_id
            };
            dmb.lists[list_id as usize].push(variable);
            dmb.lists[list_id as usize].extend(encoded);
        }
    }
    Ok(())
}

fn encode_tagged_constant(kind: u8, data: u32) -> Vec<u32> {
    if kind == 42 {
        vec![42, data >> 16, data & 0xffff]
    } else if kind == 38 && data & 0x8000_0000 != 0 {
        // Deferred procedure constants are relocated before encoding their payload.
        vec![u32::from(kind), data]
    } else {
        vec![u32::from(kind) | ((data >> 16) << 8), data & 0xffff]
    }
}
fn append_builtin_override(
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    class: u32,
    key: &str,
    kind: u8,
    data: u32,
) {
    let name = strings.intern(dmb, key);
    let mut encoded = vec![name];
    encoded.extend(encode_tagged_constant(kind, data));
    let list = dmb.classes[class as usize].overrides;
    if list == 0xffff {
        dmb.classes[class as usize].overrides = append_list(dmb, encoded);
    } else {
        dmb.lists[list as usize].extend(encoded);
    }
}

fn emit_class_var(item:&Item,class_id:u32,dmb:&mut Dmb,strings:&mut StringIndex,resources:&HashMap<String,u32>,pending_dynamic:&mut Vec<PendingDynamic>,blocked_constants:&HashSet<String>,metadata:&mut TypeMetadataState)->Result<(),String> {
    if !declaration_operations::eligible_variable(&item.header)||strings.6.is_some(){return emit_class_var_uncached(item,class_id,dmb,strings,resources,pending_dynamic,blocked_constants,metadata);}
    if declaration_operations::replay(&item.header,class_id,dmb,strings,resources,Some(&mut *metadata)){return Ok(());}
    let snapshot=declaration_operations::begin(&item.header,class_id,dmb,resources);strings.begin_trace();
    let result=emit_class_var_uncached(item,class_id,dmb,strings,resources,pending_dynamic,blocked_constants,metadata);
    let operations=strings.end_trace();if result.is_ok(){declaration_operations::record(&item.header,class_id,snapshot,dmb,operations,Some(&*metadata));}result
}

fn emit_class_var_uncached(
    item: &Item,
    class_id: u32,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    resources: &HashMap<String, u32>,
    pending_dynamic: &mut Vec<PendingDynamic>,
    blocked_constants: &HashSet<String>,
    metadata: &mut TypeMetadataState,
) -> Result<(), String> {
    let normalized = normalize_array_declaration(&item.header, dmb, Some(class_id), strings)?;
    let declaration = normalized.as_deref().unwrap_or(item.header.trim());
    if !declaration.starts_with("var/") { return Err(format!("unsupported class variable: {declaration}")); }
    let plan=default_plans::declaration(declaration)?;
    let name=plan.name.as_str();
    let initial=plan.initial.as_deref();
    let is_tmp=plan.is_tmp;
    let is_const=plan.is_const;
    let is_static=plan.is_static;
    let (kind, value) = match constant_variable_value_scoped(
        initial,
        declaration,
        dmb,
        strings,
        resources,
        Some(class_id),
        blocked_constants,
    ) {
        Ok(value) => value,
        Err(_) if initial.is_some() && !is_const => {
            let synthetic = class_static_symbol(dmb, class_id, name);
            pending_dynamic.push(PendingDynamic {
                owner: if is_static { None } else { Some(class_id) },
                name: if is_static {
                    synthetic.clone()
                } else {
                    name.into()
                },
                expression: plan.dynamic.clone()?,
                sized_array: is_sized_array_declaration(&item.header),
            });
            if is_static {
                metadata.dynamic_static_scopes.insert(synthetic, class_id);
            }
            (0, 0)
        }
        Err(error) => return Err(error),
    };
    let name_id = strings.intern(dmb, name);
    let variable_id = dmb.variables.len() as u32;
    dmb.variables.push(Variable {
        kind,
        value,
        name: name_id,
    });
    let flags = (if is_const {
        3
    } else if is_static {
        1
    } else {
        0
    }) | (if is_tmp { 4 } else { 0 });
    if is_static || is_const {
        metadata
            .static_ids
            .insert(class_static_symbol(dmb, class_id, name), variable_id);
        let footer = dmb.variable_footer;
        if footer == 0xffff {
            dmb.variable_footer = append_list(dmb, vec![variable_id, flags]);
        } else {
            dmb.lists[footer as usize].extend([variable_id, flags]);
        }
    }
    let existing = dmb.classes[class_id as usize].lists_and_procs[4];
    if existing == 0xffff {
        let list = append_list(dmb, vec![variable_id, flags]);
        dmb.classes[class_id as usize].lists_and_procs[4] = list;
    } else {
        dmb.lists[existing as usize].extend([variable_id, flags]);
    }
    Ok(())
}

fn emit_global_var(
    item: &Item,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    resources: &HashMap<String, u32>,
    globals: &mut HashMap<String, u32>,
    pending_dynamic: &mut Vec<PendingDynamic>,
) -> Result<(), String> {
    let normalized = normalize_array_declaration(&item.header, dmb, None, strings)?;
    let declaration = normalized.as_deref().unwrap_or(item.header.trim());
    let plan=default_plans::declaration(declaration)?;
    let name=plan.name.as_str();
    let initial=plan.initial.as_deref();
    let is_const=plan.is_const;
    if globals.contains_key(name) {return Err(format!("unsupported or duplicate global variable: {declaration}"));}
    let (kind, value) = match constant_variable_value(initial, declaration, dmb, strings, resources)
    {
        Ok(value) => value,
        Err(_) if initial.is_some() => {
            if is_const {
                return Err(format!(
                    "dynamic const initializer is unsupported: {declaration}"
                ));
            }
            let expression = plan.dynamic.clone()?;
            let ordinal = wire_declarations::constructor_counts(pending_dynamic).1 + 1;
            pending_dynamic.push(PendingDynamic {
                owner: None,
                name: name.into(),
                expression: expression.clone(),
                sized_array: is_sized_array_declaration(&item.header),
            });
            if expression.starts_with("new ") {
                (62, ordinal)
            } else {
                (0, 0)
            }
        }
        Err(error) => return Err(error),
    };
    let name_id = strings.intern(dmb, name);
    let variable_id = dmb.variables.len() as u32;
    dmb.variables.push(Variable {
        kind,
        value,
        name: name_id,
    });
    let footer = dmb.variable_footer;
    if footer == 0xffff {
        dmb.variable_footer = append_list(dmb, vec![variable_id, 1 | if is_const { 2 } else { 0 }]);
    } else {
        dmb.lists[footer as usize].extend([variable_id, 1 | if is_const { 2 } else { 0 }]);
    }
    globals.insert(name.into(), variable_id);
    if is_const {
        strings.1.insert(name.into(), variable_id);
    }
    Ok(())
}

fn constant_variable_value(
    initial: Option<&str>,
    declaration: &str,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    resources: &HashMap<String, u32>,
) -> Result<(u8, u32), String> {
    constant_variable_value_scoped(
        initial,
        declaration,
        dmb,
        strings,
        resources,
        None,
        &HashSet::new(),
    )
}

fn constant_variable_value_scoped(
    initial: Option<&str>,
    declaration: &str,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    resources: &HashMap<String, u32>,
    owner: Option<u32>,
    blocked_constants: &HashSet<String>,
) -> Result<(u8, u32), String> {
    let plan = default_plans::resolve_value(initial, declaration, dmb, strings, owner, blocked_constants)?;
    match plan {
        default_plans::SymbolicDefaultValue::Constant(value) => encode_constant(value, dmb, strings),
        default_plans::SymbolicDefaultValue::Resource(name) => resources.get(&name).copied()
            .map(|id| (12, id)).ok_or_else(|| format!("resource was not loaded: {name}")),
    }
}

fn encode_constant(
    value: const_eval::Constant,
    dmb: &mut Dmb,
    strings: &mut StringIndex,
) -> Result<(u8, u32), String> {
    Ok(match value {
        const_eval::Constant::Null => (0, 0),
        const_eval::Constant::Number(n) => (42, n.to_bits()),
        const_eval::Constant::Text(text) => (6, strings.intern(dmb, &text)),
        const_eval::Constant::EncodedText(text) => (6, strings.intern_bytes(dmb, &text)),
        const_eval::Constant::TypePath(path) => {
            let path = if path == "/" {
                path
            } else {
                path.trim_end_matches('/').to_owned()
            };
            if path.ends_with("/proc") || path.ends_with("/verb") {
                (6, strings.intern(dmb, &path))
            } else if path.contains("/proc/") || path.contains("/verb/") {
                let next = 0x8000_0000 | strings.2.len() as u32;
                (38, *strings.2.entry(path).or_insert(next))
            } else {
                type_path_value(dmb, &path, strings)?
            }
        }
    })
}

fn fold_constant(
    source: &str,
    dmb: &Dmb,
    owner: Option<u32>,
    strings: &StringIndex,
) -> Option<const_eval::Constant> {
    fold_constant_scoped(source, dmb, owner, &HashSet::new(), strings)
}
fn fold_constant_scoped(
    source: &str,
    dmb: &Dmb,
    owner: Option<u32>,
    blocked: &HashSet<String>,
    strings: &StringIndex,
) -> Option<const_eval::Constant> {
    let owner_path = owner.and_then(|id|dmb.classes.get(id as usize))
        .and_then(|class|dmb.string(class.path_string_id()))
        .and_then(|path|std::str::from_utf8(path).ok());
    if let Some(value) = semantic_declarations::evaluate(source, owner_path, blocked) { return value; }
    // Legacy isolated helpers import their own DMB. Production declaration
    // resolution always uses the active symbolic owner model above.
    const_eval::evaluate(source, |name| {
        if let Some((path, field)) = name.split_once("::") {
            let mut class = *strings.3.get(path)?;
            let mut visited = HashSet::new();
            while class != 0xffff && visited.insert(class) {
                if let Some(value) = dmb
                    .class_initial_values(class as usize)
                    .unwrap_or_default()
                    .iter()
                    .find(|value| {
                        dmb.string(dmb.variables[value.variable_id as usize].name)
                            == Some(field.as_bytes())
                    })
                {
                    let variable = Variable {
                        name: 0,
                        kind: value.value.tag(),
                        value: value
                            .value
                            .number_bits()
                            .unwrap_or_else(|| value.value.id()),
                    };
                    return constant_from_value(dmb, &variable, strings);
                }
                if let Some((variable, _)) = dmb
                    .class_variable_declarations(class as usize)
                    .unwrap_or_default()
                    .iter()
                    .find(|(id, _)| {
                        dmb.string(dmb.variables[*id as usize].name) == Some(field.as_bytes())
                    })
                {
                    return constant_from_variable(dmb, *variable, strings);
                }
                class = dmb.classes[class as usize].parent_class_id();
            }
            return None;
        }
        if blocked.contains(name) {
            return None;
        }

        let mut class = owner;
        while let Some(id) = class {
            if let Some(declarations) = dmb.class_variable_declarations(id as usize) {
                if let Some((variable, flags)) = declarations.iter().find(|(v, _)| {
                    dmb.string(dmb.variables[*v as usize].name) == Some(name.as_bytes())
                }) {
                    return if flags & 2 != 0 {
                        constant_from_variable(dmb, *variable, strings)
                    } else {
                        None
                    };
                }
            }
            let parent = dmb.classes[id as usize].parent_class_id();
            class = (parent != 0xffff).then_some(parent);
        }
        strings
            .1
            .get(name)
            .and_then(|id| constant_from_variable(dmb, *id, strings))
            .or_else(|| builtin_constant(name))
    })
}
fn constant_from_variable(
    dmb: &Dmb,
    id: u32,
    strings: &StringIndex,
) -> Option<const_eval::Constant> {
    let variable = &dmb.variables[id as usize];
    constant_from_value(dmb, variable, strings)
}

fn constant_from_value(
    dmb: &Dmb,
    variable: &Variable,
    strings: &StringIndex,
) -> Option<const_eval::Constant> {
    match variable.kind {
        0 => Some(const_eval::Constant::Null),
        42 => Some(const_eval::Constant::Number(f32::from_bits(variable.value))),
        38 => {
            let path = if variable.value & 0x8000_0000 != 0 {
                strings
                    .2
                    .iter()
                    .find(|(_, value)| **value == variable.value)?
                    .0
                    .clone()
            } else {
                String::from_utf8(
                    dmb.string(dmb.procs.get(variable.value as usize)?.strings[0])?
                        .to_vec(),
                )
                .ok()?
            };
            Some(const_eval::Constant::TypePath(path))
        }
        6 => Some(
            match String::from_utf8(dmb.string(variable.value)?.to_vec()) {
                Ok(text) => const_eval::Constant::Text(text),
                Err(error) => const_eval::Constant::EncodedText(error.into_bytes()),
            },
        ),
        8 | 9 | 10 | 11 | 32 | 63 | 89 => {
            let class = if variable.kind == 8 {
                dmb.mobs.get(variable.value as usize)?.class
            } else {
                variable.value
            };
            Some(const_eval::Constant::TypePath(
                String::from_utf8(
                    dmb.string(dmb.classes.get(class as usize)?.path_string_id())?
                        .to_vec(),
                )
                .ok()?,
            ))
        }
        36 | 39 | 40 | 59 => Some(const_eval::Constant::TypePath(
            match variable.kind {
                36 => "/savefile",
                39 => "/file",
                40 => "/list",
                _ => "/client",
            }
            .into(),
        )),
        _ => None,
    }
}

fn qualify_static_expression(source: &str, mut scope: u32, dmb: &Dmb) -> String {
    let mut aliases = HashMap::new();
    loop {
        if let Some(declarations) = dmb.class_variable_declarations(scope as usize) {
            for (id, flags) in declarations {
                if flags & 1 != 0 {
                    if let Some(name) = dmb.string(dmb.variables[id as usize].name) {
                        aliases
                            .entry(String::from_utf8_lossy(name).into_owned())
                            .or_insert_with(|| class_static_symbol(dmb, scope, &String::from_utf8_lossy(name)));
                    }
                }
            }
        }
        scope = dmb.classes[scope as usize].parent_class_id();
        if scope == 0xffff {
            break;
        }
    }
    qualify_expression_with_aliases(source, &aliases)
}
fn qualify_expression_with_aliases(source: &str, aliases: &HashMap<String, String>) -> String {
    fn references(
        expr: &dm_syntax::Expr,
        aliases: &HashMap<String, String>,
        output: &mut Vec<(usize, usize, String)>,
    ) {
        use dm_syntax::ExprKind;
        match &expr.kind {
            ExprKind::Ident(name) => {
                if let Some(alias) = aliases.get(name) {
                    output.push((expr.span.start, expr.span.end, alias.clone()));
                }
            }
            ExprKind::Group(value) | ExprKind::Unary { value, .. } => {
                references(value, aliases, output)
            }
            ExprKind::Binary { lhs, rhs, .. } => {
                references(lhs, aliases, output);
                references(rhs, aliases, output);
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                references(condition, aliases, output);
                references(then_value, aliases, output);
                references(else_value, aliases, output);
            }
            ExprKind::Call { callee, args } => {
                // Bare calls resolve in the procedure namespace. A static
                // variable named `regex` must not rename the regex() builtin.
                if !matches!(callee.kind, ExprKind::Ident(_)) {
                    references(callee, aliases, output);
                }
                for arg in args {
                    references(arg, aliases, output);
                }
            }
            ExprKind::Member { object, .. } => references(object, aliases, output),
            ExprKind::Index { object, index } => {
                references(object, aliases, output);
                references(index, aliases, output);
            }
            _ => {}
        }
    }
    let mut edits = Vec::new();
    if let Some(expr) = dm_syntax::parse_expression(source).expr {
        references(&expr, &aliases, &mut edits);
    }
    edits.sort_by_key(|edit| edit.0);
    let mut output = String::new();
    let mut cursor = 0;
    for (start, end, alias) in edits {
        output.push_str(&source[cursor..start]);
        output.push_str(&alias);
        cursor = end;
    }
    output.push_str(&source[cursor..]);
    output
}

fn bind_class_link(ledger: &mut Ledger, path: &str, id: u32) -> Result<(), String> {
    let tagged_builtin = ["/list", "/savefile", "/file", "/client"]
        .iter()
        .any(|base| path == *base || path.starts_with(&format!("{base}/")));
    let symbol = Symbol::new(Table::Class, path);
    if (tagged_builtin && id == 0) || path == "/mob" || path.starts_with("/mob/") {
        ledger.bind_alias(symbol, id)
    } else {
        ledger.bind(symbol, id)
    }
    .map_err(|error| error.to_string())
}

fn class_link_id(dmb: &Dmb, classes: &HashMap<String, u32>, path: &str) -> Option<u32> {
    if ["/list", "/savefile", "/file", "/client"]
        .iter()
        .any(|base| path == *base || path.starts_with(&format!("{base}/")))
    {
        Some(0)
    } else {
        let class = *classes.get(path)?;
        if class_inherits(dmb, class, b"/mob") {
            dmb.mobs
                .iter()
                .position(|mob| mob.class == class)
                .map(|id| id as u32)
        } else {
            Some(class)
        }
    }
}

fn type_path_value(dmb: &mut Dmb, path: &str, strings: &StringIndex) -> Result<(u8, u32), String> {
    if let Some(id) = strings.4.get(path) {
        return Ok((41, *id));
    }
    for (base, tag) in [
        ("/list", 40),
        ("/savefile", 36),
        ("/file", 39),
        ("/client", 59),
    ] {
        if path == base || path.starts_with(&format!("{base}/")) {
            return Ok((tag, 0));
        }
    }
    let class = *strings
        .3
        .get(path)
        .ok_or_else(|| format!("unresolved type constant: {path}"))?;
    let tag = [
        (b"/alist".as_slice(), 89),
        (b"/mob".as_slice(), 8),
        (b"/obj", 9),
        (b"/atom/movable", 9),
        (b"/turf", 10),
        (b"/area", 11),
        (b"/image", 63),
        (b"/mutable_appearance", 63),
        (b"/atom", 10),
    ]
    .into_iter()
    .find_map(|(base, tag)| class_inherits(dmb, class, base).then_some(tag))
    .unwrap_or(32);
    let id = if tag == 8 {
        ensure_mob_record(dmb, class)? as u32
    } else {
        class
    };
    Ok((tag, id))
}

fn normalize_array_declaration(
    header: &str,
    dmb: &Dmb,
    owner: Option<u32>,
    strings: &StringIndex,
) -> Result<Option<String>, String> {
    let declaration = header.split('=').next().unwrap_or(header).trim();
    let Some(start) = declaration.find('[') else {
        return Ok(None);
    };
    if declaration[start..].trim() == "[]" {
        let variable = declaration[..start].trim();
        let normalized = if variable.split('/').any(|p| p == "list") {
            variable.to_owned()
        } else {
            variable.replacen("var/", "var/list/", 1)
        };
        return Ok(Some(match header.split_once('=') {
            Some((_, value)) => format!("{normalized} = {}", value.trim()),
            None => normalized,
        }));
    }
    let mut remaining = declaration[start..].trim();
    let mut dimensions = Vec::new();
    while !remaining.is_empty() {
        let body = remaining
            .strip_prefix('[')
            .ok_or_else(|| format!("invalid array declaration: {header}"))?;
        let (size, tail) = body
            .split_once(']')
            .ok_or_else(|| format!("invalid array declaration: {header}"))?;
        let Some(const_eval::Constant::Number(size)) =
            fold_constant(size.trim(), dmb, owner, strings)
        else {
            return Err(format!(
                "array dimension must be a constant integer: {header}"
            ));
        };
        if !(0.0..=65535.0).contains(&size) || size.fract() != 0.0 {
            return Err(format!("invalid array dimension: {header}"));
        }
        dimensions.push((size as u32).to_string());
        remaining = tail.trim();
    }
    if header.contains('=') {
        return Err(format!(
            "explicit sized array initializer is unsupported: {header}"
        ));
    }
    let variable = declaration[..start].trim();
    let normalized = if variable.split('/').any(|p| p == "list") {
        variable.to_owned()
    } else {
        variable.replacen("var/", "var/list/", 1)
    };
    Ok(Some(format!(
        "{normalized} = new /list({})",
        dimensions.join(", ")
    )))
}

fn normalize_dynamic_expression(
    value: &str,
    type_parts: &[&str],
    declaration: &str,
) -> Result<String, String> {
    let Some(arguments) = value.trim().strip_prefix("new") else {
        return Ok(value.into());
    };
    let arguments = arguments.trim();
    // An explicit constructor type remains unchanged. Only a missing type
    // inherits the declaration's type, including constructors with arguments.
    if !arguments.is_empty() && !arguments.starts_with('(') {
        return Ok(value.into());
    }
    if type_parts.contains(&"list") && matches!(arguments, "" | "()") {
        return Ok("list()".into());
    }
    let path: Vec<_> = type_parts
        .iter()
        .copied()
        .filter(|part| !matches!(*part, "global" | "static" | "const" | "tmp"))
        .collect();
    if path.is_empty() {
        return Err(format!(
            "untyped new initializer is unsupported: {declaration}"
        ));
    }
    // List element annotations describe elements, not the list constructor.
    let path = if path.contains(&"list") {
        "list".into()
    } else {
        path.join("/")
    };
    Ok(format!(
        "new /{path}{}",
        if arguments.is_empty() {
            "()"
        } else {
            arguments
        }
    ))
}

fn append_list(dmb: &mut Dmb, values: Vec<u32>) -> u32 {
    if dmb.lists.len() == 0xffff {
        dmb.lists.push(Vec::new());
    }
    let id = dmb.lists.len() as u32;
    dmb.lists.push(values);
    id
}

fn append_null_variable(dmb: &mut Dmb, strings: &mut StringIndex, name: &str) -> u32 {
    let name_id = strings.intern(dmb, name);
    let id = dmb.variables.len() as u32;
    dmb.variables.push(Variable {
        kind: 0,
        value: 0,
        name: name_id,
    });
    id
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
struct StringIndex(
    #[serde(with = "byte_string_index")]
    HashMap<Vec<u8>, u32>,
    HashMap<String, u32>,
    HashMap<String, u32>,
    HashMap<String, u32>,
    HashMap<String, u32>,
    Option<u32>,
    #[serde(skip)] Option<StringTrace>,
);
#[derive(Clone, Default)]
struct StringTrace {
    recipes: Vec<procedure_fragments::StringRecipe>,
    bytes: HashSet<u32>,
    debug: usize,
}

mod byte_string_index {
    use super::*;
    use serde::{Deserialize, Deserializer, Serializer};
    pub(super) fn serialize<S: Serializer>(values: &HashMap<Vec<u8>, u32>, serializer: S) -> Result<S::Ok, S::Error> {
        let mut ordered: Vec<_> = values.iter().collect();
        ordered.sort_by(|a, b| a.0.cmp(b.0));
        serde::Serialize::serialize(&ordered, serializer)
    }
    pub(super) fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<HashMap<Vec<u8>, u32>, D::Error> {
        let values = Vec::<(Vec<u8>, u32)>::deserialize(deserializer)?;
        let mut index = HashMap::with_capacity(values.len());
        for (name, id) in values {
            if index.insert(name, id).is_some() {
                return Err(serde::de::Error::custom("duplicate cached string identity"));
            }
        }
        Ok(index)
    }
}

impl StringIndex {
    fn new(dmb: &Dmb) -> Self {
        let mut index = HashMap::with_capacity(dmb.strings.len());
        for (id, value) in dmb.strings.iter().enumerate() {
            if crate::native_reserved_string_id(id as u32) {
                continue;
            }
            index.entry(value.data.clone()).or_insert(id as u32);
        }
        let mut classes = HashMap::with_capacity(dmb.classes.len());
        for (id, class) in dmb.classes.iter().enumerate() {
            if let Some(path) = dmb.string(class.path_string_id()) {
                classes
                    .entry(String::from_utf8_lossy(path).into_owned())
                    .or_insert(id as u32);
            }
        }
        let builtin_vars = dmb
            .variables
            .iter()
            .position(|variable| variable.kind == 82 && dmb.string(variable.name) == Some(b"vars"))
            .map(|id| id as u32);
        Self(
            index,
            HashMap::new(),
            HashMap::new(),
            classes,
            HashMap::new(),
            builtin_vars,
            None,
        )
    }

    fn intern(&mut self, dmb: &mut Dmb, value: &str) -> u32 {
        self.intern_bytes(dmb, value.as_bytes())
    }

    fn begin_trace(&mut self) { self.6 = Some(StringTrace::default()); }
    fn end_trace(&mut self) -> Vec<procedure_fragments::StringRecipe> {
        self.6.take().map_or_else(Vec::new, |trace| trace.recipes)
    }
    fn intern_debug(&mut self, dmb: &mut Dmb, file: &str, _relative: usize) -> u32 {
        let trace = self.6.take();
        let id = self.intern_bytes(dmb, file.as_bytes());
        self.6 = trace;
        if let Some(trace) = &mut self.6 {
            trace.recipes.push(procedure_fragments::StringRecipe::Debug { index: trace.debug });
            trace.debug += 1;
        }
        id
    }
    fn intern_bytes(&mut self, dmb: &mut Dmb, value: &[u8]) -> u32 {
        let id = if let Some(&id) = self.0.get(value) { id } else {
            while crate::native_reserved_string_id(dmb.strings.len() as u32) {
                dmb.strings.push(DmString { data: Vec::new(), long_chunks: 0 });
            }
            let id = dmb.strings.len() as u32;
            let bytes = value.to_vec();
            dmb.strings.push(DmString {
                long_chunks: u16::try_from(bytes.len() / u16::MAX as usize).unwrap_or(u16::MAX),
                data: bytes.clone(),
            });
            self.0.insert(bytes, id);
            id
        };
        if let Some(trace) = &mut self.6 {
            if trace.bytes.insert(id) {
                trace.recipes.push(procedure_fragments::StringRecipe::Bytes { old_id: id, bytes: Arc::from(value) });
            }
        }
        id
    }

}

fn proc_signature(item: &Item) -> Result<(String, Vec<ParsedParameter>), String> {
    let header = item.header.trim();
    let (path, params) = header
        .split_once('(')
        .ok_or_else(|| format!("unsupported procedure header {header}"))?;
    let path = path.trim_end_matches('/');
    let params = params
        .rsplit_once(") as ")
        .map(|(params, _)| params)
        .or_else(|| params.strip_suffix(')'))
        .ok_or_else(|| format!("unsupported procedure header {header}"))?;
    if !path.starts_with("/proc/") || path[6..].contains('/') {
        return Err(format!("bootstrap only supports global procs: {header}"));
    }
    Ok((path.into(), parse_parameters(params)?))
}

fn member_signature(
    item: &Item,
    owner: &str,
    verb: bool,
) -> Result<(String, Vec<ParsedParameter>), String> {
    if owner.is_empty() {
        return proc_signature(item);
    }
    let header = item.header.trim();
    let (raw_path, raw_params) = header
        .split_once('(')
        .ok_or_else(|| format!("unsupported procedure header {header}"))?;
    let raw_path = raw_path.trim_end_matches('/');
    let raw_params = raw_params
        .rsplit_once(") as ")
        .map(|(params, _)| params)
        .or_else(|| raw_params.strip_suffix(')'))
        .ok_or_else(|| format!("unsupported procedure header {header}"))?;
    let marker = if verb { "verb/" } else { "proc/" };
    let name = raw_path
        .strip_prefix(marker)
        .or_else(|| raw_path.strip_prefix(&format!("{owner}/{marker}")))
        .or_else(|| raw_path.strip_prefix(&format!("{owner}/")))
        .or_else(|| (!raw_path.contains('/')).then_some(raw_path))
        .ok_or_else(|| format!("unsupported member procedure header {header}"))?;
    if name.is_empty() || name.contains('/') {
        return Err(format!("unsupported procedure name: {header}"));
    }
    let path = if raw_path == format!("{owner}/{name}") {
        raw_path.to_owned()
    } else if raw_path == name {
        format!("{owner}/{name}")
    } else {
        format!("{owner}/{marker}{name}")
    };
    Ok((path, parse_parameters(raw_params)?))
}

fn parse_parameters(source: &str) -> Result<Vec<ParsedParameter>, String> {
    if source.trim().is_empty() {
        return Ok(Vec::new());
    }
    let mut parts = Vec::new();
    let mut depth = 0i32;
    let mut quote = false;
    let mut escape = false;
    let mut start = 0;
    for (at, ch) in source.char_indices() {
        if escape {
            escape = false;
            continue;
        }
        if ch == '\\' && quote {
            escape = true;
            continue;
        }
        if ch == '"' {
            quote = !quote;
            continue;
        }
        if quote {
            continue;
        }
        match ch {
            '(' | '[' => depth += 1,
            ')' | ']' => depth -= 1,
            ',' if depth == 0 => {
                parts.push(source[start..at].trim());
                start = at + 1;
            }
            _ => {}
        }
        if depth < 0 {
            return Err("unbalanced parameter declaration".into());
        }
    }
    if quote || depth != 0 {
        return Err("unbalanced parameter declaration".into());
    }
    parts.push(source[start..].trim());
    if parts.last() == Some(&"") {
        parts.pop();
    }
    if parts.last() == Some(&"...") {
        parts.pop();
    }
    parts
        .into_iter()
        .map(|part| {
            let (declaration, default) =
                part.split_once('=').map_or((part, None), |(name, value)| {
                    (name.trim(), Some(value.trim().to_owned()))
                });
            let (declaration, source) = declaration
                .split_once(" in ")
                .map_or((declaration, None), |(name, source)| {
                    (name.trim(), Some(source.trim()))
                });
            let mut source_expression = None;
            let value_source = match source {
                None | Some("view()") => 0x7d01,
                Some("oview()") => 0x7d02,
                Some("usr.contents") => 0x7f08,
                Some("world") => 0x7f10,
                Some(range) if range.starts_with("range(") && range.ends_with(')') => {
                    let radius = range[6..range.len() - 1]
                        .trim()
                        .parse::<u8>()
                        .map_err(|_| format!("unsupported range argument source: {part}"))?;
                    (u32::from(radius) << 8) | 0x05
                }
                Some(expression)
                    if expression.starts_with("list(") && expression.ends_with(')') =>
                {
                    source_expression = Some(expression.into());
                    0x40
                }
                Some(expression) => {
                    source_expression = Some(expression.into());
                    0x40
                }
            };
            let (declaration, as_type) = declaration
                .split_once(" as ")
                .map_or((declaration, None), |(path, ty)| {
                    (path.trim(), Some(ty.trim()))
                });
            let declaration = declaration.trim_end_matches('/');
            let (path, name) = declaration
                .rsplit_once('/')
                .map_or(("", declaration), |(path, name)| (path, name));
            let array = name.ends_with("[]");
            let name = name.strip_suffix("[]").unwrap_or(name);
            let path = if array { "list" } else { path };
            let path = if path == "const" || path == "var" {
                ""
            } else {
                path
            };
            let path = path.strip_prefix("var/").unwrap_or(path);
            let path = path.strip_prefix("const/").unwrap_or(path);
            let path = if path == "const" { "" } else { path };
            if name.is_empty()
                || !name.chars().next().unwrap().is_alphabetic() && !name.starts_with('_')
                || !name.chars().all(|ch| ch.is_alphanumeric() || ch == '_')
            {
                return Err(format!("invalid parameter name: {part}"));
            }
            let root = path.trim_start_matches('/').split('/').next().unwrap_or("");
            let mut flags = match root {
                "" | "datum" | "client" | "list" | "image" | "matrix" | "regex" | "savefile" | "callee"
                | "mutable_appearance" | "appearance" | "generator" | "alist" | "database"
                | "exception" => 0,
                "icon" | "sound" => 0,
                "atom" => {
                    if path.trim_start_matches('/').starts_with("atom/movable") {
                        3
                    } else {
                        0x123
                    }
                }
                "mob" => 1,
                "obj" => 2,
                "turf" => 0x20,
                "area" => 0x100,
                _ => return Err(format!("unsupported parameter type: {part}")),
            };
            if let Some(as_type) = as_type {
                let mut union = 0;
                for restriction in as_type.split('|').map(str::trim) {
                    union |= match restriction {
                        "anything" => 0x1000,
                        "mob" => 1,
                        "obj" => 2,
                        "text" => 4,
                        "num" => 8,
                        "file" => 0x10,
                        "turf" => 0x20,
                        "null" => 0x80,
                        "message" => 0x800,
                        "area" => 0x100,
                        "icon" => 0x200,
                        "sound" => 0x400,
                        _ => return Err(format!("unsupported parameter as type: {part}")),
                    };
                }
                flags = union;
            }
            if source == Some("world") && flags == 0 {
                flags = 0x123;
            }
            if default.as_ref().is_some_and(|value| value.is_empty()) {
                return Err(format!("empty parameter default: {part}"));
            }
            Ok(ParsedParameter {
                name: name.into(),
                type_flags: flags,
                type_path: (!path.is_empty()).then(|| format!("/{}", path.trim_start_matches('/'))),
                value_source,
                source_expression,
                default,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_audit_bounds_unique_errors_and_unicode_samples() {
        let mut report = CanonicalLoweringAudit::default();
        for index in 0..300 {
            let errors = Err(vec![dm_codegen_byond::LowerError {
                statement: "é".repeat(900), reason: format!("distinct unsupported form {index}"),
                statement_origin: None,
            }]);
            report.record("/proc/probe", dm_syntax::Span::new(0, 1), 0, None, &errors);
        }
        assert_eq!(report.lowering.error_count, 300);
        assert_eq!(report.lowering.groups.len(), 256);
        assert_eq!(report.lowering.groups.values().map(|group| group.count).sum::<usize>(), 300);
        assert!(report.lowering.groups.values().all(|group| group.samples.len() <= 3));
        assert!(report.truncated_texts > 0);
        assert!(report.lowering.groups.values().flat_map(|group| &group.samples)
            .all(|sample| sample.statement.chars().count() <= 515));
    }

    #[test]
    fn canonical_audit_visits_valid_bodies_after_multiple_failures_without_output() {
        let root = std::env::temp_dir().join(format!("dm-canonical-audit-{}-{}", std::process::id(),
            std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        std::fs::create_dir_all(&root).unwrap();
        let source = "/obj/probe\n    icon = 'not-loaded.dmi'\n/proc/first()\n    return 1\n/proc/bad_one()\n    unknown_a()\n/proc/bad_two()\n    unknown_b()\n/proc/last()\n    return 2\n";
        let file = Arc::new(root.join("authored.dm"));
        let project = PreprocessedProject {
            text: source.into(),
            origins: source.lines().enumerate().map(|(line, _)| dm_preprocess::Origin {
                output_line: line + 1, source_line: line + 101, path: Arc::clone(&file),
            }).collect(), ..PreprocessedProject::default()
        };
        let report = audit_canonical_lowering(&root.join("world.dme"), &project, BUILTINS,
            &mut crate::frontend::OutlineSession::new(None), 2).unwrap();
        assert_eq!((report.expected_procedures, report.lowering.procedures), (4, 4));
        assert_eq!((report.lowering.passed, report.lowering.failed), (2, 2));
        assert_eq!(report.cache_hits + report.cache_misses, 4);
        assert!(report.lowering.groups.values().flat_map(|group| &group.samples)
            .all(|sample| sample.statement.contains("authored.dm:") && sample.statement.contains(":error:")));
        assert!(!root.join("world.dmb").exists());
        assert!(!root.join("world.rsc").exists());
        assert!(root.starts_with(std::env::temp_dir()));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn owner_binding_cache_preserves_frames_and_respects_budgets() {
        let (dmb, _) = emit_global_procs(
            "/datum/base\n    var/value = 7\n/datum/child\n    parent_type = /datum/base\n    var/other = 8\n",
            BUILTINS,
            "owner-cache",
        ).unwrap();
        let owner = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/datum/child".as_slice())
            })
            .unwrap() as u32;
        let shared = SharedLowerBindings::default();
        let mut expected = LowerBindings::default();
        collect_owner_fields(owner, &dmb, &shared, &mut expected);
        let mut cache = OwnerBindingCache::new(4 * 1024 * 1024, 1);
        let mut first = LowerBindings::default();
        cache.populate(owner, &dmb, &shared, &mut first);
        assert_eq!(first.fields, expected.fields);
        assert_eq!(first.field_types, expected.field_types);
        // A proc-local static shadows a field only in its job's cloned frame.
        assert!(first.fields.remove("value"));
        let mut second = LowerBindings::default();
        cache.populate(owner, &dmb, &shared, &mut second);
        assert_eq!(second.fields, expected.fields);
        assert!(second.fields.contains("value"));
        assert!(cache.bytes <= cache.byte_limit);
        assert!(cache.frames.len() <= cache.entry_limit);
        let mut tiny = OwnerBindingCache::new(1, 1);
        tiny.populate(owner, &dmb, &shared, &mut second);
        assert!(tiny.frames.is_empty());
        assert_eq!(tiny.bytes, 0);
        assert_eq!(second.fields, expected.fields);
    }

    #[test]
    fn parallel_lowering_preserves_static_slots_inherited_metadata_and_output_bytes() {
        let source = "/var/list/global_table = list(first())\n/datum/base\n    var/value = 7\n    var/list/base_table = list(first())\n/datum/base/proc/get()\n    set name = \"Base Name\"\n    var/static/count = 1\n    return count + value\n/datum/child\n    parent_type = /datum/base\n    var/list/child_table = list(second())\n/datum/child/get()\n    return ..() + 2\n/proc/first()\n    var/static/seed = 3\n    return seed++\n/proc/second()\n    var/const/bias = 2\n    return bias\n/proc/with_sources(value in list(1, 2), sibling in list(3, 4))\n    return value + sibling\n";
        let build = |workers| {
            emit_global_procs_mode_with_workers(
                source,
                BUILTINS,
                "parallel-proof",
                None,
                &mut crate::lower_cache::ProcLoweringCache::disabled(),
                None,
                None,
                workers,
            )
            .unwrap()
        };
        let (serial, serial_procs, serial_resources) = build(1);
        let (parallel, parallel_procs, parallel_resources) = build(2);
        assert_eq!(serial.to_bytes().unwrap(), parallel.to_bytes().unwrap());
        assert_eq!(serial_procs, parallel_procs);
        assert_eq!(serial_resources, parallel_resources);
        assert!(parallel.world.global_initializer_proc_id() != 0xffff);
        assert_eq!(parallel.proc_references.len(), 2);
        let find = |dmb: &Dmb, path: &[u8]| {
            dmb.procs
                .iter()
                .find(|proc| dmb.string(proc.strings[0]) == Some(path))
                .unwrap()
                .strings[1]
        };
        let base = find(&parallel, b"/datum/base/proc/get");
        let child = find(&parallel, b"/datum/child/get");
        assert_eq!(parallel.string(base), parallel.string(child));
        assert_eq!(parallel.string(child), Some(b"Base Name".as_slice()));
    }

    #[test]
    fn streaming_body_guard_matches_allocating_lexer() {
        let fixtures = [
            include_str!("../../../fixtures/v516_builtins.dm"),
            include_str!("../../../fixtures/mob_sight.dm"),
            "/proc/run(α)\n    return α + 1 // static const set global { 'ignored'\n",
            "/proc/run()\n    return \"static [global.foo] [f('hidden.dmi')] {\"\n",
            "/proc/run()\n    var/static/value = 1\n",
            "/proc/run()\n    var/const/value = 1\n",
            "/proc/run()\n    set name = \"name\"\n",
            "/proc/run()\n    return global.value\n",
            "/proc/run() { return 1 }\n",
            "/proc/run()\n    return 'icons/α.dmi'\n",
            "/proc/run()\n    return @'not-a-resource'\n",
        ];
        for source in fixtures {
            let expected = lex(source).tokens.iter().any(|token| {
                matches!(
                    token.text.as_str(),
                    "static" | "const" | "set" | "global" | "{"
                ) || token.kind == TokenKind::Resource
            });
            assert_eq!(procedure_body_requires_full_emission(source), expected);
        }
    }
    #[test]
    fn implicit_ancestors_inherit_finalized_headers_and_overrides() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/implicit_header/probe.native.bin"
        ))
        .unwrap();
        let (proof, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/implicit_header/probe.dm"),
            BUILTINS,
            "proof",
        )
        .unwrap();
        for path in ["/obj/base/implicit", "/obj/base/implicit/leaf"] {
            let find = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .position(|c| image.string(c.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
            };
            assert_eq!(
                proof.classes[find(&proof)].flags,
                native.classes[find(&native)].flags
            );
            assert_eq!(
                proof.classes[find(&proof)].layer_bits,
                native.classes[find(&native)].layer_bits
            );
        }
        let source = "/obj/base\n    layer = 7\n    appearance_flags = 3\n    plane = 12\n    vis_flags = 3\n/obj/base/implicit/leaf\n    name = \"leaf\"\n";
        let (image, _) = emit_global_procs(source, BUILTINS, "inherit").unwrap();
        for path in ["/obj/base/implicit", "/obj/base/implicit/leaf"] {
            let id = image
                .classes
                .iter()
                .position(|c| image.string(c.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(image.classes[id].layer_bits, 7f32.to_bits());
            assert_eq!(image.classes[id].flags >> 21 & 0x7ff, 3);
            let overrides = image.class_builtin_overrides(id).unwrap();
            for (name, value) in [("plane", 12f32), ("vis_flags", 3f32)] {
                let entry = overrides
                    .iter()
                    .find(|entry| image.string(entry.name_string_id) == Some(name.as_bytes()))
                    .unwrap();
                assert_eq!(entry.value.number_bits(), Some(value.to_bits()));
            }
        }
    }

    #[test]
    fn proc_only_subtypes_inherit_finalized_headers_and_builtin_overrides() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/implicit_proc_header/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/implicit_proc_header/probe.dm"),
            BUILTINS,
            "proc_only",
        )
        .unwrap();
        for path in ["/obj/base/proc_only", "/obj/base/proc_only/leaf"] {
            let find = |dmb: &Dmb| {
                dmb.classes
                    .iter()
                    .position(|class| dmb.string(class.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
            };
            let actual = find(&image);
            let expected = find(&native);
            assert_eq!(
                image.classes[actual].flags, native.classes[expected].flags,
                "{path}"
            );
            assert_eq!(
                image.classes[actual].layer_bits, native.classes[expected].layer_bits,
                "{path}"
            );
            for name in ["plane", "vis_flags"] {
                let get = |dmb: &Dmb, class| {
                    dmb.class_builtin_overrides(class)
                        .unwrap()
                        .into_iter()
                        .find(|value| dmb.string(value.name_string_id) == Some(name.as_bytes()))
                        .unwrap()
                        .value
                        .number_bits()
                };
                assert_eq!(get(&image, actual), get(&native, expected), "{path}.{name}");
            }
        }
    }

    #[test]
    fn reopened_same_owner_members_use_latest_first_parent_chain() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/reopened_proc_chain/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/reopened_proc_chain/probe.dm"),
            BUILTINS,
            "chain",
        )
        .unwrap();
        let chain = |image: &Dmb, path: &[u8]| {
            let mut class = image
                .classes
                .iter()
                .find(|c| image.string(c.path_string_id()) == Some(path))
                .unwrap();
            while class.lists_and_procs[1] == 0xffff {
                class = &image.classes[class.parent_class_id() as usize];
            }
            image.lists[class.lists_and_procs[1] as usize]
                .iter()
                .map(|id| {
                    let words =
                        &image.lists[image.procs[*id as usize].code_locals_args[0] as usize];
                    words
                        .windows(3)
                        .find_map(|words| {
                            (words[0] == opcode::PUSH_VAL && words[1] == 6)
                                .then(|| image.string(words[2]))
                                .flatten()
                                .filter(|text| text.starts_with(b"CHAIN_"))
                                .map(|text| text.to_vec())
                        })
                        .unwrap()
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(
            chain(&image, b"/datum/chain"),
            chain(&native, b"/datum/chain")
        );
        assert_eq!(
            chain(&image, b"/datum/chain"),
            vec![
                b"CHAIN_THIRD".to_vec(),
                b"CHAIN_SECOND".to_vec(),
                b"CHAIN_BASE".to_vec()
            ]
        );
        assert_eq!(
            chain(&image, b"/datum/chain/child"),
            chain(&native, b"/datum/chain/child")
        );
    }

    #[test]
    fn area_layer_and_luminosity_follow_native_special_metadata() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/area_inherited_defaults/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/area_inherited_defaults/probe.dm"),
            BUILTINS,
            "area",
        )
        .unwrap();
        for path in ["/area", "/area/probe"] {
            let find = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .position(|c| image.string(c.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
            };
            let actual = find(&image);
            let expected = find(&native);
            assert_eq!(
                image.classes[actual].layer_bits, native.classes[expected].layer_bits,
                "{path}"
            );
            assert_eq!(
                image.classes[actual].flags, native.classes[expected].flags,
                "{path}"
            );
            let lum = |image: &Dmb, id| {
                image
                    .class_builtin_overrides(id)
                    .unwrap()
                    .into_iter()
                    .rev()
                    .find(|entry| {
                        image.string(entry.name_string_id) == Some(b"luminosity".as_slice())
                    })
                    .unwrap()
                    .value
            };
            assert_eq!(
                lum(&image, actual).number_bits(),
                lum(&native, expected).number_bits(),
                "{path}"
            );
        }
    }

    #[test]
    fn mouse_handlers_and_animation_match_native_class_flags() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/mouse_headers/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/mouse_headers/probe.dm"),
            BUILTINS,
            "mouse",
        )
        .unwrap();
        for path in ["/obj/base", "/obj/base/child"] {
            let find = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .find(|c| image.string(c.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
                    .clone()
            };
            assert_eq!(find(&image).flags, find(&native).flags, "{path}");
            assert_eq!(find(&image).animate_movement(), 2);
        }
    }

    #[test]
    fn automatic_atom_text_tracks_name_but_preserves_explicit_text() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/default_text/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/default_text/probe.dm"),
            BUILTINS,
            "text",
        )
        .unwrap();
        for path in [
            "/obj/base",
            "/obj/base/child",
            "/obj/explicit",
            "/obj/explicit/child",
        ] {
            let find = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .find(|c| image.string(c.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
                    .text
            };
            assert_eq!(
                image.string(find(&image)),
                native.string(find(&native)),
                "{path}"
            );
        }
    }

    #[test]
    fn authored_builtin_parent_defaults_reach_native_intermediaries() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/builtin_inherited_headers/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/builtin_inherited_headers/probe.dm"),
            BUILTINS,
            "builtins",
        )
        .unwrap();
        for path in ["/obj", "/obj/probe", "/mob", "/mob/probe"] {
            let find = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .position(|c| image.string(c.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
            };
            let actual = find(&image);
            let expected = find(&native);
            assert_eq!(
                image.classes[actual].flags, native.classes[expected].flags,
                "{path}"
            );
            assert_eq!(
                image.classes[actual].interface, native.classes[expected].interface,
                "{path}"
            );
            let glide = |image: &Dmb, id| {
                image
                    .class_builtin_overrides(id)
                    .unwrap()
                    .into_iter()
                    .rev()
                    .find(|entry| {
                        image.string(entry.name_string_id) == Some(b"glide_size".as_slice())
                    })
                    .unwrap()
                    .value
            };
            assert_eq!(
                glide(&image, actual).number_bits(),
                glide(&native, expected).number_bits(),
                "{path}"
            );
        }
    }

    #[test]
    fn tagged_class_defaults_preserve_large_payload_ids() {
        for (kind, id) in [(6, 0x12345), (11, 0x20304), (32, 0x34567), (38, 0x14567)] {
            let words = encode_tagged_constant(kind, id);
            let (decoded, _) = byond_dmb::operands::Value::decode(&words).unwrap();
            assert_eq!(decoded.tag(), kind);
            assert_eq!(decoded.id(), id);
        }
        let mut image = Dmb::from_bytes(BUILTINS).unwrap();
        while image.strings.len() <= 0x10000 {
            image.strings.push(byond_dmb::dmb::DmString {
                data: b"padding".to_vec(),
                long_chunks: 0,
            });
        }
        let mut strings = StringIndex::new(&image);
        let text = strings.intern(&mut image, "high payload string");
        let field = strings.intern(&mut image, "high_field");
        let variable = image.variables.len() as u32;
        image.variables.push(Variable {
            name: field,
            kind: 0,
            value: 0,
        });
        let mut words = vec![variable];
        words.extend(encode_tagged_constant(6, text));
        image.classes[0].lists_and_procs[3] = append_list(&mut image, words);
        append_builtin_override(&mut image, &mut strings, 0, "render_target", 6, text);
        crate::promote_object_ids(&mut image);
        let decoded = Dmb::from_bytes(&image.to_bytes().unwrap()).unwrap();
        let initial = decoded.class_initial_values(0).unwrap();
        assert_eq!(
            decoded.string(initial[0].value.id()),
            Some(b"high payload string".as_slice())
        );
        let overrides = decoded.class_builtin_overrides(0).unwrap();
        let value = overrides
            .iter()
            .find(|entry| decoded.string(entry.name_string_id) == Some(b"render_target".as_slice()))
            .unwrap()
            .value;
        assert_eq!(
            decoded.string(value.id()),
            Some(b"high payload string".as_slice())
        );
    }

    #[test]
    fn macro_style_braced_class_fields_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/admin_braced_type/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/admin_braced_type/probe.dm"),
            BUILTINS,
            "admin",
        )
        .unwrap();
        let values = |image: &Dmb| {
            let id = image
                .classes
                .iter()
                .position(|c| {
                    image.string(c.path_string_id())
                        == Some(b"/datum/admin_verb/player_panel_new".as_slice())
                })
                .unwrap();
            image
                .class_initial_values(id)
                .unwrap()
                .into_iter()
                .map(|entry| {
                    let variable = &image.variables[entry.variable_id as usize];
                    let value = if entry.value.tag() == 6 {
                        image.string(entry.value.id()).unwrap().to_vec()
                    } else {
                        entry
                            .value
                            .number_bits()
                            .unwrap_or(entry.value.id())
                            .to_le_bytes()
                            .to_vec()
                    };
                    (image.string(variable.name).unwrap().to_vec(), value)
                })
                .collect::<BTreeMap<_, _>>()
        };
        let actual = values(&image);
        let expected = values(&native);
        for name in ["name", "description", "category", "permissions", "enabled"] {
            assert_eq!(
                actual.get(name.as_bytes()),
                expected.get(name.as_bytes()),
                "{name}"
            );
        }
    }

    #[test]
    fn absolute_savefile_version_matches_native_world_field() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/savefile_version/probe.native.bin"
        ))
        .unwrap();
        let (image, _) = emit_global_procs(
            include_str!("../../../fixtures/native_compiler/savefile_version/probe.dm"),
            BUILTINS,
            "savefile",
        )
        .unwrap();
        assert_eq!(
            image.world.savefile_byond_version,
            native.world.savefile_byond_version
        );
        let (image, _) =
            emit_global_procs("/savefile/byond_version = 516\n", BUILTINS, "savefile").unwrap();
        assert_eq!(image.world.savefile_byond_version, 516);
        let decoded = Dmb::from_bytes(&image.to_bytes().unwrap()).unwrap();
        assert_eq!(decoded.world.savefile_byond_version, 516);
        let (image, _) = emit_global_procs(
            "/savefile/byond_version = 516\n/world\n    icon_size=32\n    map_format=1\n",
            BUILTINS,
            "savefile",
        )
        .unwrap();
        assert_eq!(
            Dmb::from_bytes(&image.to_bytes().unwrap())
                .unwrap()
                .world
                .savefile_byond_version,
            516
        );
    }

    #[test]
    fn absolute_multiline_field_override_does_not_create_a_type() {
        let source = "/datum/language\n    var/list/syllables\n/datum/language/human\n/datum/language/human/syllables = list(\n    \"one\",\n    \"two\"\n)\n";
        let (image, _) = emit_global_procs(source, BUILTINS, "language").unwrap();
        assert!(!image.classes.iter().any(|c| image
            .string(c.path_string_id())
            .is_some_and(|p| p.starts_with(b"/datum/language/human/syllables"))));
        let id = image
            .classes
            .iter()
            .position(|c| {
                image.string(c.path_string_id()) == Some(b"/datum/language/human".as_slice())
            })
            .unwrap();
        assert_ne!(image.classes[id].initializer_proc_id(), 0xffff);
    }

    #[test]
    fn argument_source_helpers_preserve_owner_context_without_argument_tables() {
        let source = include_str!("../../../fixtures/native_compiler/argument_candidate.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/argument_candidate.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "source_context").unwrap();
        for method in ["proc_choice", "type_choice", "src_choice", "static_choice"] {
            let path = format!("/datum/source_context/proc/{method}");
            let helper = |image: &Dmb| {
                let id = image
                    .procs
                    .iter()
                    .position(|proc| image.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap();
                image
                    .argument_source_proc_id(&image.proc_arguments(id).unwrap()[0])
                    .unwrap() as usize
            };
            let actual_helper = helper(&output);
            let native_helper = helper(&native);
            assert!(output.proc_arguments(actual_helper).unwrap().is_empty());
            assert!(native.proc_arguments(native_helper).unwrap().is_empty());
            assert_eq!(
                output.procs[actual_helper].effective_flags(),
                native.procs[native_helper].effective_flags()
            );
            let actual =
                byond_dmb::bytecode::decode(output.proc_code_words(actual_helper).unwrap())
                    .unwrap();
            let expected =
                byond_dmb::bytecode::decode(native.proc_code_words(native_helper).unwrap())
                    .unwrap();
            assert_eq!(actual[0].opcode, expected[0].opcode, "{method}");
            match method {
                "proc_choice" => {
                    assert_eq!(actual[0].operands[0], 38);
                    assert_eq!(
                        output.string(output.procs[actual[0].operands[1] as usize].strings[0]),
                        Some(path.as_bytes())
                    );
                }
                "type_choice" => {
                    assert_eq!(actual[0].operands[0], 32);
                    assert_eq!(
                        output.string(
                            output.classes[actual[0].operands[1] as usize].path_string_id()
                        ),
                        Some(b"/datum/source_context".as_slice())
                    );
                }
                "src_choice" => assert_eq!(actual[0].operands, expected[0].operands),
                _ => {
                    // The instance field selector resolves the class's shared
                    // static slot; native chooses its direct global slot.
                    assert_eq!(
                        output.string(*actual[0].operands.last().unwrap()),
                        Some(b"choices".as_slice())
                    );
                    assert_eq!(expected[0].operands[0], 0xffdb);
                }
            }
        }
    }

    #[test]
    fn proc_static_vars_and_explicit_global_vars_use_distinct_symbols() {
        let source = "var/smoke_qualified = 3\n/proc/check()\n    var/static/list/vars = list(4,5)\n    return vars[1] + global.vars[\"smoke_qualified\"]\n";
        let (output, _) = emit_global_procs(source, BUILTINS, "vars_shadow").unwrap();
        let builtin = output
            .variables
            .iter()
            .position(|value| value.kind == 82)
            .unwrap();
        assert_eq!(
            output.string(output.variables[builtin].name),
            Some(b"vars".as_slice())
        );
        assert!(
            output
                .variables
                .iter()
                .any(|value| value.kind != 82
                    && output.string(value.name) == Some(b"vars".as_slice()))
        );
    }

    #[test]
    fn argument_sources_keep_candidate_and_sibling_argument_slots() {
        let source = include_str!("../../../fixtures/native_compiler/argument_candidate.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/argument_candidate.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "candidate").unwrap();
        for (path, selected) in [
            ("/proc/self_source", 0),
            ("/proc/sibling_source", 1),
            ("/proc/second_candidate", 1),
        ] {
            let helper_code = |image: &Dmb| {
                let id = image
                    .procs
                    .iter()
                    .position(|proc| image.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap();
                let argument = image.proc_arguments(id).unwrap()[selected];
                let source_id = image.argument_source_proc_id(&argument).unwrap();
                byond_dmb::bytecode::decode(image.proc_code_words(source_id as usize).unwrap())
                    .unwrap()
            };
            let actual = helper_code(&output);
            let expected = helper_code(&native);
            assert_eq!(actual[0].opcode, opcode::GET_VAR);
            assert_eq!(actual[0].operands, expected[0].operands, "{path}");
        }
    }

    #[test]
    fn renamed_verb_without_assignment_whitespace_has_static_bindings() {
        for setting in [
            "set name=\"Custom Halt\"",
            " set\tname = \"Custom Halt\"",
            "set name/*comment*/=\"Custom Halt\"",
        ] {
            assert!(is_proc_name_setting(setting), "{setting}");
        }
        for setting in ["set names=1", "set name in list()", "var/name=1"] {
            assert!(!is_proc_name_setting(setting), "{setting}");
        }
        let source = include_str!("../../../fixtures/native_compiler/verb_call_selectors/probe.dm");
        let (image, _) = emit_global_procs(source, BUILTINS, "renamed_verb").unwrap();
        let verb = image
            .procs
            .iter()
            .position(|proc| {
                image.string(proc.strings[0])
                    == Some(b"/mob/selector_probe/verb/halt_probe".as_slice())
            })
            .unwrap() as u32;
        for path in [
            "/mob/selector_probe/proc/bare_probe",
            "/mob/selector_probe/proc/member_probe",
        ] {
            let id = image
                .procs
                .iter()
                .position(|proc| image.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert!(
                image
                    .proc_code_words(id)
                    .unwrap()
                    .windows(2)
                    .any(|words| words == [0xffe0, verb]),
                "{path}"
            );
        }
        let audit = audit_lowering(source, 1024 * 1024, BUILTINS).unwrap();
        assert_eq!(audit.failed, 0, "{audit:?}");
    }

    #[test]
    fn interpolated_proc_metadata_is_rejected_like_native() {
        // Native 516.1687 rejects the embedded interpolation as "bad text".
        let source =
            include_str!("../../../fixtures/native_compiler/proc_text_metadata_invalid.dm");
        let error = emit_global_procs(source, BUILTINS, "invalid_metadata").unwrap_err();
        assert!(error.contains("unsupported procedure setting"), "{error}");
    }

    #[test]
    fn escaped_and_inherited_proc_text_metadata_matches_native() {
        let source = include_str!("../../../fixtures/native_compiler/proc_text_metadata.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/proc_text_metadata.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "proc_text").unwrap();
        for path in [
            b"/datum/text_metadata_base/proc/action".as_slice(),
            b"/datum/text_metadata_base/child/action",
        ] {
            let actual = output
                .procs
                .iter()
                .find(|proc| output.string(proc.strings[0]) == Some(path))
                .unwrap();
            let expected = native
                .procs
                .iter()
                .find(|proc| native.string(proc.strings[0]) == Some(path))
                .unwrap();
            for slot in 1..4 {
                assert_eq!(
                    output.string(actual.strings[slot]),
                    native.string(expected.strings[slot]),
                    "{} slot{slot}",
                    String::from_utf8_lossy(path)
                );
            }
        }
    }

    #[test]
    fn inherited_static_default_cannot_be_reinitialized() {
        // BYOND 516 rejects this as "re-initialization of global var".
        let source = "/datum/base\n    var/static/value = 1\n/datum/base/child\n    value = 2\n";
        assert!(emit_global_procs(source, BUILTINS, "invalid_static").is_err());
    }

    #[test]
    fn inherited_field_initializers_and_statics_match_native_order() {
        let source = include_str!("../../../fixtures/native_compiler/initializer_order/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/initializer_order/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "initializer_order").unwrap();
        let string_values = |image: &Dmb, proc_id: u32| {
            byond_dmb::bytecode::decode(image.proc_code_words(proc_id as usize).unwrap())
                .unwrap()
                .into_iter()
                .filter(|instruction| {
                    instruction.opcode == opcode::PUSH_VAL
                        && instruction.operands.first() == Some(&6)
                })
                .map(|instruction| image.string(instruction.operands[1]).unwrap().to_vec())
                .collect::<Vec<_>>()
        };
        assert_eq!(
            string_values(&output, output.world.global_initializer_proc_id()),
            string_values(&native, native.world.global_initializer_proc_id())
        );
        for path in [b"/datum/order_base".as_slice(), b"/datum/order_base/child"] {
            let class = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .find(|class| image.string(class.path_string_id()) == Some(path))
                    .unwrap()
                    .initializer_proc_id()
            };
            assert_eq!(
                string_values(&output, class(&output)),
                string_values(&native, class(&native)),
                "{}",
                String::from_utf8_lossy(path)
            );
        }
    }

    #[test]
    fn global_vars_binding_installs_native_builtin_when_missing() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        let mut strings = StringIndex::new(&dmb);
        let name = strings.intern(&mut dmb, "vars");
        for variable in &mut dmb.variables {
            if variable.name == name && variable.kind == 82 {
                variable.kind = 0;
            }
        }
        let before = dmb.variables.len();
        let mut ledger = Ledger::default();
        strings.5 = None;
        bind_builtin_global_vars(&mut dmb, &mut strings, &mut ledger).unwrap();
        assert_eq!(dmb.variables.len(), before + 1);
        assert_eq!(
            ledger.id(&Symbol::new(
                Table::Variable,
                dm_codegen_byond::BUILTIN_GLOBAL_VARS_SYMBOL
            )),
            Some(before as u32)
        );
        assert_eq!(
            (dmb.variables[before].kind, dmb.variables[before].value),
            (82, 0)
        );
        let mut ledger = Ledger::default();
        bind_builtin_global_vars(&mut dmb, &mut strings, &mut ledger).unwrap();
        assert_eq!(dmb.variables.len(), before + 1);
    }

    #[test]
    fn tagged_builtin_class_payloads_are_explicit_aliases() {
        let mut ledger = Ledger::default();
        for path in ["/list", "/savefile", "/file", "/client"] {
            bind_class_link(&mut ledger, path, 0).unwrap();
            assert_eq!(ledger.id(&Symbol::new(Table::Class, path)), Some(0));
        }
        bind_class_link(&mut ledger, "/datum", 0).unwrap();
        assert!(bind_class_link(&mut ledger, "/different_real_class", 0).is_err());
    }

    #[test]
    fn interned_long_strings_encode_length_chunks_and_round_trip() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        let mut strings = StringIndex::new(&dmb);
        let text = "x".repeat(u16::MAX as usize * 2 + 17);
        let id = strings.intern(&mut dmb, &text);
        assert_eq!(dmb.strings[id as usize].long_chunks, 2);
        let bytes = dmb.to_bytes().unwrap();
        let decoded = Dmb::from_bytes(&bytes).unwrap();
        assert_eq!(decoded.string(id), Some(text.as_bytes()));
        assert_eq!(decoded.to_bytes().unwrap(), bytes);
    }

    #[test]
    fn native_table_growth_reserves_selectors_and_promotes_width() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let mut dmb = Dmb::from_bytes(bytes).unwrap();
        dmb.strings.resize(
            0xffcd,
            DmString {
                data: Vec::new(),
                long_chunks: 0,
            },
        );
        let mut strings = StringIndex::new(&dmb);
        assert_eq!(strings.intern(&mut dmb, "reserved crossing"), 0xfff2);
        dmb.strings.resize(
            0xffff,
            DmString {
                data: Vec::new(),
                long_chunks: 0,
            },
        );
        assert_eq!(strings.intern(&mut dmb, "nullable crossing"), 0x10000);
        dmb.lists.resize(0xffff, Vec::new());
        assert_eq!(append_list(&mut dmb, vec![0]), 0x10000);
        dmb.classes.resize(0xffff, dmb.classes[0].clone());
        crate::reserve_class_sentinel(&mut dmb);
        assert_eq!(dmb.classes.len(), 0x10000);
        assert_eq!(dmb.classes[0xffff].path_string_id(), 0xffff);
        dmb.procs.resize(0xffff, dmb.procs[0].clone());
        crate::reserve_proc_sentinel(&mut dmb);
        assert_eq!(dmb.procs.len(), 0x10000);
        assert_eq!(dmb.procs[0xffff].strings, [0xffff; 4]);
        crate::promote_object_ids(&mut dmb);
        assert_ne!(dmb.header.flags & 0x4000_0000, 0);
    }

    #[test]
    fn resource_pointer_and_string_appearance_overrides_match_native() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/translation/resource_pointer");
        let source = include_str!("../../../fixtures/translation/resource_pointer/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/resource_pointer/probe.native.bin"
        ))
        .unwrap();
        let resources = ResourceSet::load([ResourceRequest {
            archive_name: "screen_drag.dmi".into(),
            disk_path: fixture.join("screen_drag.dmi"),
        }])
        .unwrap();
        let (output, _, _) =
            emit_global_procs_with_resources(source, BUILTINS, "pointer", &resources).unwrap();
        let class_id = |image: &Dmb| {
            image
                .classes
                .iter()
                .position(|class| {
                    image.string(class.path_string_id()) == Some(b"/obj/resource_pointer")
                })
                .unwrap()
        };
        assert_eq!(
            output.string(output.classes[class_id(&output)].initial_ids[2]),
            native.string(native.classes[class_id(&native)].initial_ids[2])
        );
        let actual = output.class_builtin_overrides(class_id(&output)).unwrap();
        let expected = native.class_builtin_overrides(class_id(&native)).unwrap();
        for field in [
            "mouse_drag_pointer",
            "render_source",
            "render_target",
            "screen_loc",
        ] {
            let actual = actual
                .iter()
                .find(|value| output.string(value.name_string_id) == Some(field.as_bytes()))
                .unwrap()
                .value;
            let expected = expected
                .iter()
                .find(|value| native.string(value.name_string_id) == Some(field.as_bytes()))
                .unwrap()
                .value;
            assert_eq!(actual.kind(), expected.kind(), "{field}");
            if field == "mouse_drag_pointer" {
                assert_eq!(actual.tag(), 12);
                assert_eq!(actual.id(), 0);
            } else {
                assert_eq!(actual.tag(), 6);
                assert_eq!(
                    output.string(actual.id()),
                    native.string(expected.id()),
                    "{field}"
                );
            }
        }
    }

    #[test]
    fn initializer_audit_collects_independent_defaults_without_lowering() {
        let source = "/datum/base\n\tvar/value = 1\n/datum/first\n\tparent_type = /datum/base\n\tvalue = unsupported_first()\n/datum/second\n\tparent_type = /datum/base\n\tvalue = unsupported_second()\n/proc/not_lowerable()\n\tunknown_name\n";
        let audit = audit_initializers(source, BUILTINS).unwrap();
        assert_eq!(audit.errors.len(), 2, "{audit:?}");
        assert!(audit
            .errors
            .iter()
            .any(|error| error.contains("unsupported_first")));
        assert!(audit
            .errors
            .iter()
            .any(|error| error.contains("unsupported_second")));
        assert!(audit.dependency_errors.is_empty(), "{audit:?}");
    }

    #[test]
    fn initializer_audit_preserves_constant_dependencies_and_resource_symbols() {
        let source = "var/const/derived = later + 2\nvar/const/later = 3\n/datum/defaults\n\tvar/const/value = derived\n\tvar/icon_asset = 'not-loaded.dmi'\n/datum/defaults/child\n\tvalue = 7\n";
        let audit = audit_initializers(source, BUILTINS).unwrap();
        assert!(audit.errors.is_empty(), "{audit:?}");
        assert!(audit.dependency_errors.is_empty(), "{audit:?}");
    }

    #[test]
    fn forward_procedure_constants_and_gender_values_match_native() {
        let source = include_str!("../../../fixtures/translation/proc_constants/probe.dm");
        let audit = audit_lowering(source, 1024, BUILTINS).unwrap();
        assert_eq!(audit.failed, 0, "{audit:?}");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/proc_constants/probe.native.bin"
        ))
        .unwrap();
        let (output, _, _) = emit_global_procs_with_resources(
            source,
            BUILTINS,
            "constants",
            &ResourceSet::default(),
        )
        .unwrap();
        for name in [
            "procedure_reference",
            "procedure_alias",
            "gender_male",
            "gender_female",
            "gender_plural",
            "gender_neuter",
            "description",
            "escaped_description",
            "proper_description",
            "static_reference",
            "inherited_global_reference",
            "inherited_proc_name",
            "global_proc_namespace",
            "local_proc_namespace",
            "global_verb_reference",
            "verb_reference",
        ] {
            let actual = output
                .variables
                .iter()
                .find(|v| output.string(v.name) == Some(name.as_bytes()))
                .unwrap();
            let expected = native
                .variables
                .iter()
                .find(|v| native.string(v.name) == Some(name.as_bytes()))
                .unwrap();
            assert_eq!(actual.kind, expected.kind, "{name}");
            if actual.kind == 42 {
                assert_eq!(actual.value, expected.value, "{name}");
            } else if actual.kind == 38 {
                assert_eq!(
                    output.string(output.procs[actual.value as usize].strings[0]),
                    native.string(native.procs[expected.value as usize].strings[0])
                );
            } else {
                assert_eq!(
                    output.string(actual.value),
                    native.string(expected.value),
                    "{name}"
                );
            }
        }
        let actual_pointer = output
            .classes
            .iter()
            .find(|class| {
                output.string(class.path_string_id()) == Some(b"/obj/native_pointer_defaults")
            })
            .unwrap();
        let native_pointer = native
            .classes
            .iter()
            .find(|class| {
                native.string(class.path_string_id()) == Some(b"/obj/native_pointer_defaults")
            })
            .unwrap();
        assert_eq!(
            output.string(actual_pointer.initial_ids[3]),
            native.string(native_pointer.initial_ids[3])
        );
        let trailing_path = b"/datum/trailing_member_header/child/receive_signal";
        assert!(output
            .procs
            .iter()
            .any(|proc| output.string(proc.strings[0]) == Some(trailing_path)));
        assert!(!output
            .classes
            .iter()
            .any(|class| output.string(class.path_string_id()) == Some(trailing_path)));
        let parameters = parse_parameters("href_list[], value,").unwrap();
        assert_eq!(parameters.len(), 2);
        assert_eq!(parameters[0].type_path.as_deref(), Some("/list"));
        let method = output
            .procs
            .iter()
            .find(|proc| {
                output.string(proc.strings[0]) == Some(b"/datum/ctor_base/proc/under_score_method")
            })
            .unwrap();
        assert_eq!(
            output.string(method.strings[1]),
            Some(b"under score method".as_slice())
        );
        let class = output
            .classes
            .iter()
            .position(|class| {
                output.string(class.path_string_id()) == Some(b"/particles/native_color_zero")
            })
            .unwrap();
        let native_class = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id()) == Some(b"/particles/native_color_zero")
            })
            .unwrap();
        let actual = output.class_initial_values(class).unwrap();
        let expected = native.class_initial_values(native_class).unwrap();
        assert_eq!(
            actual[0].value.number_bits(),
            expected[0].value.number_bits()
        );
        let background = output
            .procs
            .iter()
            .find(|proc| output.string(proc.strings[0]) == Some(b"/proc/nested_background"))
            .unwrap();
        let native_background = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(b"/proc/nested_background"))
            .unwrap();
        assert_eq!(
            background.effective_flags(),
            native_background.effective_flags()
        );
        let appearance = output
            .classes
            .iter()
            .find(|class| output.string(class.path_string_id()) == Some(b"/image/native_maptext"))
            .unwrap();
        let native_appearance = native
            .classes
            .iter()
            .find(|class| native.string(class.path_string_id()) == Some(b"/image/native_maptext"))
            .unwrap();
        assert_eq!(
            appearance.maptext_geometry,
            native_appearance.maptext_geometry
        );
        let class = output
            .classes
            .iter()
            .position(|class| {
                output.string(class.path_string_id()) == Some(b"/obj/native_generic_defaults")
            })
            .unwrap();
        let native_class = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id()) == Some(b"/obj/native_generic_defaults")
            })
            .unwrap();
        let actual = output.class_builtin_overrides(class).unwrap();
        let expected = native.class_builtin_overrides(native_class).unwrap();
        for name in [
            "pixel_z",
            "pixel_w",
            "render_source",
            "render_target",
            "screen_loc",
            "bound_width",
        ] {
            let actual = actual
                .iter()
                .find(|value| output.string(value.name_string_id) == Some(name.as_bytes()))
                .unwrap();
            let expected = expected
                .iter()
                .find(|value| native.string(value.name_string_id) == Some(name.as_bytes()))
                .unwrap();
            if actual.value.number_bits().is_some() {
                assert_eq!(
                    actual.value.number_bits(),
                    expected.value.number_bits(),
                    "{name}"
                );
            } else {
                assert_eq!(
                    output.string(actual.value.id()),
                    native.string(expected.value.id()),
                    "{name}"
                );
            }
        }
    }

    #[test]
    fn global_argument_sources_and_inherited_alists_compile() {
        let source = "var/datum/source_scope/GLOB = new\n/datum/source_scope\n    var/list/choices = list(1, 2)\n/datum/base_scope\n    var/factors\n/datum/base_scope/child\n    factors = alist (45 = 50)\n/proc/select(choice in GLOB.choices)\n    return choice\n";
        let (output, _, _) =
            emit_global_procs_with_resources(source, BUILTINS, "sources", &ResourceSet::default())
                .unwrap();
        assert!(output.procs.iter().any(|proc| proc.source_kind == 0));
        assert_eq!(audit_lowering(source, 1024, BUILTINS).unwrap().failed, 0);
    }

    #[test]
    fn repeated_argument_sources_share_native_companion_limit() {
        let source = include_str!("../../../fixtures/translation/argument_sources_many/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_sources_many/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "many arguments").unwrap();
        assert_eq!(output.proc_references.len(), native.proc_references.len());
        assert_eq!(output.proc_references.len(), 1);
    }

    #[test]
    fn predefined_constant_inventory_matches_native_values() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/native_constants/probe.native.bin"
        ))
        .unwrap();
        for variable in &native.variables {
            let Some(name) = native
                .string(variable.name)
                .and_then(|name| std::str::from_utf8(name).ok())
                .and_then(|name| name.strip_prefix("probe_"))
            else {
                continue;
            };
            if variable.kind == 42 {
                assert_eq!(
                    builtin_constant(name),
                    Some(const_eval::Constant::Number(f32::from_bits(variable.value)))
                );
            } else if variable.kind == 6 {
                assert_eq!(
                    builtin_constant(name),
                    Some(const_eval::Constant::Text(
                        std::str::from_utf8(native.string(variable.value).unwrap())
                            .unwrap()
                            .to_owned()
                    ))
                );
            } else {
                panic!("unsupported predefined constant {name}: {variable:?}");
            }
        }
    }

    #[test]
    fn typed_parameters_supply_inferred_istype_path() {
        let params = parse_parameters("datum/value/x, mob/y, untyped").unwrap();
        assert_eq!(params[0].type_path.as_deref(), Some("/datum/value"));
        assert_eq!(params[1].type_path.as_deref(), Some("/mob"));
        assert_eq!(params[2].type_path, None);
        emit_global_procs(
            "/datum/value\n/proc/probe(datum/value/x)\n    return istype(x)\n",
            BUILTINS,
            "typed",
        )
        .unwrap();
    }

    #[test]
    fn declaration_snapshot_drops_bodies_and_rebases_source_spans() {
        let source = "/datum/example\n    var/base = 1\n    proc/run()\n        return base\n";
        let ast = parse(source);
        let compact = compact_declaration_item(&ast.items[0], 100);
        assert_eq!(compact.header, "/datum/example");
        assert_eq!(compact.span.start, ast.items[0].span.start + 100);
        assert_eq!(compact.children[0].header, "var/base = 1");
        assert!(!ast.items[0].children[1].children.is_empty());
        assert!(compact.children[1].children.is_empty());
        assert_eq!(
            compact.children[1].span.end,
            ast.items[0].children[1].span.end + 100
        );
    }

    #[test]
    fn chunked_snapshot_reparses_later_bodies_and_rejects_oversized_declarations() {
        let source = "/proc/first()\n    return 1\n/proc/second()\n    return 2\n";
        let compact = declaration_snapshot_with_limit(source, 32).unwrap();
        assert!(compact.tokens.is_empty());
        assert_eq!(compact.items.len(), 2);
        assert!(compact.items.iter().all(|item| item.children.is_empty()));
        let second = dm_syntax::parse_proc_at_span(source, compact.items[1].span).unwrap();
        assert_eq!(second.children[0].header, "return 2");
        assert!(second.children[0].span.start > compact.items[1].header_span.end);
        assert!(declaration_snapshot_with_limit(source, 8)
            .unwrap_err()
            .contains("exceed the parse chunk limit"));
    }

    #[test]
    fn declaration_audit_counts_index_without_retaining_proc_statements() {
        let source = "/datum/example\n    var/number = 1\n    proc/run()\n        return number\n";
        let audit = audit_declarations(source, 1024);
        assert_eq!(audit.syntax_error_count, 0);
        assert_eq!(audit.index_error_count, 0);
        assert_eq!(audit.compact_items, 3);
        assert_eq!(audit.procedure_items, 1);
        assert_eq!(audit.indexed_variables, 1);
        assert_eq!(audit.indexed_procedures, 1);
        assert_eq!(audit_declarations(source, 8).skipped_declarations, 1);
    }

    #[test]
    fn lowering_audit_continues_after_unsupported_procedure() {
        let source = "/datum/probe/\n    var/base = 1\n    proc/good/()\n        return base\n    proc/bad()\n        goto missing_label\n/proc/last()\n    return 3\n";
        let audit = audit_lowering(source, 1024, BUILTINS).unwrap();
        assert_eq!(audit.procedures, 3);
        assert_eq!(audit.passed, 2);
        assert_eq!(audit.failed, 1);
        assert!(!audit.groups.is_empty());
        assert!(audit.groups.values().all(|group| group.samples.len() <= 3));
    }

    #[test]
    fn argument_type_unions_match_native_flags() {
        let source = include_str!("../../../fixtures/translation/argument_unions/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_unions/probe.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "unions").unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe"))
            .unwrap();
        let expected = native.proc_arguments(native_id).unwrap();
        let actual = output.proc_arguments(emitted[0].proc_index).unwrap();
        assert_eq!(
            actual.iter().map(|arg| arg.type_flags).collect::<Vec<_>>(),
            expected
                .iter()
                .map(|arg| arg.type_flags)
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn builtin_parameter_paths_match_native_restrictions() {
        let source = include_str!("../../../fixtures/translation/argument_builtin_types/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_builtin_types/probe.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "types").unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe"))
            .unwrap();
        assert_eq!(
            output
                .proc_arguments(emitted[0].proc_index)
                .unwrap()
                .iter()
                .map(|arg| arg.type_flags)
                .collect::<Vec<_>>(),
            native
                .proc_arguments(native_id)
                .unwrap()
                .iter()
                .map(|arg| arg.type_flags)
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn implicit_builtins_and_absolute_class_global_types_are_bound() {
        let source = include_str!("../../../fixtures/translation/implicit_builtins/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/implicit_builtins/probe.native.bin"
        ))
        .unwrap();
        let mut shared = SharedLowerBindings::default();
        seed_builtin_constants(&mut shared);
        for (name, constant) in [("unix_value", "UNIX"), ("windows_value", "MS_WINDOWS")] {
            let value = native
                .variables
                .iter()
                .find(|var| native.string(var.name) == Some(name.as_bytes()))
                .unwrap();
            assert_eq!(
                Some(shared.string_constants[constant].as_bytes()),
                native.string(value.value)
            );
        }
        assert_eq!(audit_lowering(source, 1024, BUILTINS).unwrap().failed, 0);
        let (output, emitted) = emit_global_procs(source, BUILTINS, "builtins").unwrap();
        let actual = emitted
            .iter()
            .find(|proc| proc.path.ends_with("/verb/messages"))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(actual.path.as_bytes()))
            .unwrap();
        assert_eq!(
            output.procs[actual.proc_index].source_kind,
            expected.source_kind
        );
        assert_eq!(
            output.procs[actual.proc_index].source_parameter,
            expected.source_parameter
        );
        let native_id = native
            .procs
            .iter()
            .position(|proc| std::ptr::eq(proc, expected))
            .unwrap();
        assert_eq!(
            output.proc_arguments(actual.proc_index).unwrap()[0].type_flags,
            native.proc_arguments(native_id).unwrap()[0].type_flags
        );
        let source = "/datum/value\n/datum/global_vars/var/global/datum/value/value\n/datum/global_vars/proc/init(...)\n    value = new\n    return UNIX\n";
        let audit = audit_lowering(source, 1024, BUILTINS).unwrap();
        assert_eq!(audit.failed, 0, "{:?}", audit.groups);
        emit_global_procs(source, BUILTINS, "types").unwrap();
    }

    #[test]
    fn modified_code_types_preserve_original_class_identity() {
        let source = include_str!("../../../fixtures/translation/modified_code_types/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/modified_code_types/probe.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "modified").unwrap();
        assert!(!output.classes.iter().any(|class| output
            .string(class.path_string_id())
            .unwrap()
            .windows(14)
            .any(|bytes| bytes == b"__dm_modified_")));
        let base = output
            .classes
            .iter()
            .position(|class| output.string(class.path_string_id()) == Some(b"/datum/object_probe"))
            .unwrap();
        let instances: Vec<_> = output
            .instances
            .iter()
            .enumerate()
            .filter(|(_, instance)| {
                instance.kind == 32
                    && instance.class == base as u32
                    && instance.initializer != 0xffff
            })
            .collect();
        assert_eq!(
            instances.len(),
            1,
            "whitespace-equivalent modifiers share one descriptor"
        );
        let (id, instance) = instances[0];
        let words = output
            .proc_code_words(instance.initializer as usize)
            .unwrap();
        let native_instance = native
            .instances
            .iter()
            .find(|instance| {
                instance.initializer != 0xffff
                    && native
                        .classes
                        .get(instance.class as usize)
                        .is_some_and(|class| {
                            native.string(class.path_string_id()) == Some(b"/datum/object_probe")
                        })
            })
            .unwrap();
        let expected = native
            .proc_code_words(native_instance.initializer as usize)
            .unwrap();
        // Symbol relocation changes only the final field-name StringID.
        assert_eq!(&words[..words.len() - 2], &expected[..expected.len() - 2]);
        assert_eq!(
            output.string(words[words.len() - 2]),
            native.string(expected[expected.len() - 2])
        );
        assert_eq!(words.last(), expected.last());
        assert_eq!(output.procs[instance.initializer as usize].flags, 4);
        assert_eq!(audit_lowering(source, 1024, BUILTINS).unwrap().failed, 0);
        assert!(emitted
            .iter()
            .filter(|proc| proc.path.starts_with("/proc/"))
            .all(|proc| proc
                .words
                .windows(3)
                .any(|words| words == [opcode::PUSH_VAL, 41, id as u32])));
    }

    #[test]
    fn nested_static_and_proc_global_declarations_use_persistent_slots() {
        let source = "/proc/probe(condition)\n    if(condition)\n        var/static/count = 2\n        count += 1\n        return count\n    var/global/offset = 3\n    return offset\n";
        let (dmb, _) = emit_global_procs(source, BUILTINS, "nested").unwrap();
        for name in ["count", "offset"] {
            assert!(dmb
                .global_variable_flags()
                .unwrap()
                .iter()
                .any(
                    |(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(name.as_bytes())
                ));
        }
        assert_eq!(audit_lowering(source, 1024, BUILTINS).unwrap().failed, 0);
    }

    #[test]
    fn argument_sources_retain_owning_fields_and_native_helper_shape() {
        let source = include_str!("../../../fixtures/native_compiler/argument_context/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/argument_context/probe.native.bin"
        ))
        .unwrap();
        let (actual, emitted) = emit_global_procs(source, BUILTINS, "context").unwrap();
        for name in ["choices", "bare_choices"] {
            let path = format!("/datum/context_base/proc/{name}");
            let entry = emitted.iter().find(|proc| proc.path == path).unwrap();
            let native_id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let actual_source = actual.proc_arguments(entry.proc_index).unwrap()[0].value_source;
            let native_source = native.proc_arguments(native_id).unwrap()[0].value_source;
            assert_eq!(actual_source & 0xff, native_source & 0xff);
            let actual_helper = actual.proc_references[(actual_source >> 8) as usize] as usize;
            let native_helper = native.proc_references[(native_source >> 8) as usize] as usize;
            let ours = actual.proc_code_words(actual_helper).unwrap();
            let expected = native.proc_code_words(native_helper).unwrap();
            assert_eq!(&ours[..3], &expected[..3]);
            assert_eq!(actual.string(ours[3]), native.string(expected[3]));
            assert_eq!(&ours[4..], &expected[4..]);
            assert_eq!(
                actual.procs[actual_helper].flags,
                native.procs[native_helper].flags
            );
        }
    }

    #[test]
    fn modified_base_and_child_instances_match_native_descriptors() {
        let source = include_str!("../../../fixtures/native_compiler/modified_identity/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/modified_identity/probe.native.bin"
        ))
        .unwrap();
        let (generated, _) = emit_global_procs(source, BUILTINS, "identity").unwrap();
        for path in [
            b"/datum/identity_base".as_slice(),
            b"/datum/identity_base/child",
        ] {
            let actual_class = generated
                .classes
                .iter()
                .position(|class| generated.string(class.path_string_id()) == Some(path))
                .unwrap();
            let native_class = native
                .classes
                .iter()
                .position(|class| native.string(class.path_string_id()) == Some(path))
                .unwrap();
            let actual = generated
                .instances
                .iter()
                .find(|instance| {
                    instance.class == actual_class as u32 && instance.initializer != 0xffff
                })
                .unwrap();
            let expected = native
                .instances
                .iter()
                .find(|instance| {
                    instance.class == native_class as u32 && instance.initializer != 0xffff
                })
                .unwrap();
            assert_eq!(actual.kind, expected.kind);
            assert_eq!(
                generated.string(generated.classes[actual.class as usize].path_string_id()),
                Some(path)
            );
            let actual_parent = generated.classes[actual.class as usize].parent_class_id() as usize;
            let native_parent = native.classes[expected.class as usize].parent_class_id() as usize;
            assert_eq!(
                generated.string(generated.classes[actual_parent].path_string_id()),
                native.string(native.classes[native_parent].path_string_id())
            );
            let code = generated
                .proc_code_words(actual.initializer as usize)
                .unwrap();
            let expected_code = native
                .proc_code_words(expected.initializer as usize)
                .unwrap();
            assert_eq!(
                &code[..code.len() - 2],
                &expected_code[..expected_code.len() - 2]
            );
            assert_eq!(
                generated.string(code[code.len() - 2]),
                native.string(expected_code[expected_code.len() - 2])
            );
        }
        assert_eq!(generated.classes.len(), native.classes.len());
    }

    #[test]
    fn modified_type_list_overrides_are_initialized_before_new() {
        let source = "/datum/list_probe\n    var/list/values\n/proc/probe()\n    return new /datum/list_probe/ {values = list(1, 2)}\n";
        let (dmb, _) = emit_global_procs(source, BUILTINS, "lists").unwrap();
        let instance = dmb
            .instances
            .iter()
            .find(|instance| {
                instance.initializer != 0xffff
                    && dmb
                        .classes
                        .get(instance.class as usize)
                        .is_some_and(|class| {
                            dmb.string(class.path_string_id()) == Some(b"/datum/list_probe")
                        })
            })
            .unwrap();
        assert_ne!(instance.initializer, 0xffff);
        let code = dmb.proc_code_words(instance.initializer as usize).unwrap();
        assert!(code.contains(&opcode::NEW_LIST));
        assert_eq!(
            dmb.classes[instance.class as usize].initializer_proc_id(),
            0xffff
        );
        assert_eq!(audit_lowering(source, 1024, BUILTINS).unwrap().failed, 0);
    }

    const SOURCE: &str = include_str!("../../../fixtures/native_compiler/simple.dm");
    const NATIVE: &[u8] = include_bytes!("../../../fixtures/native_compiler/simple.native.bin");
    const BUILTINS: &[u8] = include_bytes!("../../../fixtures/native_template.bin");

    #[test]
    fn verified_resource_catalog_preserves_canonical_dmb() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/translation/resource_pointer");
        let resources = ResourceSet::load([ResourceRequest {
            archive_name: "screen_drag.dmi".into(), disk_path: fixture.join("screen_drag.dmi"),
        }]).unwrap();
        let source = "/obj/test\n    icon = 'screen_drag.dmi'\n/proc/probe()\n    return 'screen_drag.dmi'\n";
        let (full, _, archive) = emit_global_procs_with_resources(source, BUILTINS, "catalog", &resources).unwrap();
        let catalog = resources.catalog().unwrap();
        let (cached, _, omitted_archive) = emit_global_procs_mode_with_frontend_catalog(
            source, BUILTINS, "catalog", None, &mut crate::lower_cache::ProcLoweringCache::disabled(),
            None, None, 1, None, Some(&catalog), None, None).unwrap();
        assert_eq!(full.to_bytes().unwrap(), cached.to_bytes().unwrap());
        assert!(!archive.is_empty());
        assert!(omitted_archive.is_empty());
        let mut corrupt = catalog;
        let mut alias = corrupt.entries[0].clone();
        alias.archive_name = "alias.dmi".into();
        alias.content_digest[0] ^= 1;
        corrupt.entries.push(alias);
        assert!(corrupt.validate().is_err());
    }

    #[test]
    fn procedure_flags_match_native_fixture() {
        let source = include_str!("../../../fixtures/translation/proc_attributes.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/proc_attributes.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "proc_attributes").unwrap();
        for entry in emitted {
            let native_proc = native
                .procs
                .iter()
                .find(|proc| native.string(proc.strings[0]) == Some(entry.path.as_bytes()))
                .unwrap();
            let generated = &output.procs[entry.proc_index];
            assert_eq!(
                generated.effective_flags(),
                native_proc.effective_flags(),
                "{}",
                entry.path
            );
            assert_eq!(
                generated.invisibility_setting(),
                native_proc.invisibility_setting(),
                "{}",
                entry.path
            );
        }
    }

    #[test]
    fn implicit_verb_override_matches_native_metadata() {
        let source = include_str!("../../../fixtures/translation/verb_metadata.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/verb_metadata.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "verb_metadata").unwrap();
        for entry in emitted {
            let native_proc = native
                .procs
                .iter()
                .find(|proc| native.string(proc.strings[0]) == Some(entry.path.as_bytes()))
                .unwrap();
            let generated = &output.procs[entry.proc_index];
            assert_eq!(
                generated.source_location(),
                native_proc.source_location(),
                "{}",
                entry.path
            );
            assert_eq!(
                output.string(generated.strings[3]),
                native.string(native_proc.strings[3]),
                "{}",
                entry.path
            );
        }
    }

    #[test]
    fn class_appearance_defaults_are_encoded() {
        let source = "/obj/painted\n    name = \"Painted\"\n    desc = \"A fixture\"\n    icon_state = \"ready\"\n    density = 1\n    opacity = 0\n    layer = 6\n    dir = EAST\n    mouse_opacity = 0\n    luminosity = 2\n";
        let (output, _) = emit_global_procs(source, BUILTINS, "appearance").unwrap();
        let class = output
            .classes
            .iter()
            .find(|class| output.string(class.path_string_id()) == Some(b"/obj/painted".as_slice()))
            .unwrap();
        assert_eq!(
            output.string(class.name_string_id()),
            Some(b"Painted".as_slice())
        );
        assert_eq!(
            output.string(class.description_string_id()),
            Some(b"A fixture".as_slice())
        );
        assert_eq!(
            output.string(class.icon_state_string_id()),
            Some(b"ready".as_slice())
        );
        assert!(class.is_dense());
        assert!(!class.is_opaque());
        assert_eq!(f32::from_bits(class.layer_bits), 6.0);
        assert_eq!(class.direction, 4);
        assert_eq!(class.mouse_opacity(), 0);
        assert_eq!(class.luminosity(), 2);
    }

    #[test]
    fn class_parent_alias_and_inherited_variable_override() {
        let source = "/obj/base\n    var/unrelated = 1\n/custom_alias\n    parent_type = /obj/base\n    alpha = 163\n    color = \"#123456\"\n    unrelated = 7\n";
        let (output, _) = emit_global_procs(source, BUILTINS, "alias").unwrap();
        let alias_id = output
            .classes
            .iter()
            .position(|class| {
                output.string(class.path_string_id()) == Some(b"/custom_alias".as_slice())
            })
            .unwrap();
        let parent_id = output.classes[alias_id].parent_class_id() as usize;
        assert_eq!(
            output.string(output.classes[parent_id].path_string_id()),
            Some(b"/obj/base".as_slice())
        );
        let overrides = output.class_builtin_overrides(alias_id).unwrap();
        assert_eq!(overrides.len(), 2);
        assert_eq!(
            output.string(overrides[0].name_string_id),
            Some(b"alpha".as_slice())
        );
        assert_eq!(overrides[0].value.number_bits(), Some(163f32.to_bits()));
        assert_eq!(
            output.string(overrides[1].value.id()),
            Some(b"#123456".as_slice())
        );
        let initial = output.class_initial_values(alias_id).unwrap();
        assert_eq!(initial.len(), 1);
        assert_eq!(initial[0].value.number_bits(), Some(7f32.to_bits()));
    }

    #[test]
    fn class_header_fields_match_native_appearance_fixture() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inherited_builtin_appearance/probe.native.bin"
        ))
        .unwrap();
        let source = "/obj/appearance_base\n    name = \"base name\"\n    desc = \"base description\"\n    icon_state = \"base state\"\n    density = 1\n    opacity = 1\n    layer = 6\n    dir = EAST\n    mouse_opacity = 0\n    luminosity = 2\n    alpha = 191\n    color = \"#123456\"\n";
        let (output, _) = emit_global_procs(source, BUILTINS, "appearance").unwrap();
        let path = b"/obj/appearance_base".as_slice();
        let generated_id = output
            .classes
            .iter()
            .position(|class| output.string(class.path_string_id()) == Some(path))
            .unwrap();
        let native_id = native
            .classes
            .iter()
            .position(|class| native.string(class.path_string_id()) == Some(path))
            .unwrap();
        let generated = &output.classes[generated_id];
        let expected = &native.classes[native_id];
        for index in [2, 3, 5] {
            assert_eq!(
                output.string(generated.initial_ids[index]),
                native.string(expected.initial_ids[index])
            );
        }
        assert_eq!(generated.is_dense(), expected.is_dense());
        assert_eq!(generated.is_opaque(), expected.is_opaque());
        assert_eq!(generated.layer_bits, expected.layer_bits);
        assert_eq!(generated.direction, expected.direction);
        assert_eq!(generated.mouse_opacity(), expected.mouse_opacity());
        assert_eq!(generated.luminosity(), expected.luminosity());
        let overrides = output.class_builtin_overrides(generated_id).unwrap();
        let native_overrides = native.class_builtin_overrides(native_id).unwrap();
        for key in [b"alpha".as_slice(), b"color".as_slice()] {
            let actual = overrides
                .iter()
                .find(|entry| output.string(entry.name_string_id) == Some(key))
                .unwrap();
            let expected = native_overrides
                .iter()
                .find(|entry| native.string(entry.name_string_id) == Some(key))
                .unwrap();
            assert_eq!(actual.value.kind(), expected.value.kind());
            if key == b"alpha" {
                assert_eq!(actual.value.number_bits(), expected.value.number_bits());
            } else {
                assert_eq!(
                    output.string(actual.value.id()),
                    native.string(expected.value.id())
                );
            }
        }
    }

    #[test]
    fn project_compiles_dme_map_include() {
        let root = std::env::temp_dir().join(format!("dm-project-map-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(
            root.join("test.dme"),
            "#define MAP_ENABLED 1\n#include \"types.dm\"\n#if MAP_ENABLED\n#include \"map.dmm\"\n#else\n#include \"missing.dmm\"\n#endif\n",
        )
        .unwrap();
        std::fs::write(root.join("types.dm"), "/turf/stone\n/area/room\n").unwrap();
        std::fs::write(
            root.join("map.dmm"),
            "\"a\" = (/turf/stone,/area/room)\n(1,1,1) = {\"a\"}\n",
        )
        .unwrap();
        let built =
            compile_project_with_resources(&root.join("test.dme"), BUILTINS, "test").unwrap();
        assert_eq!(built.dmb.dimensions, [1, 1, 1]);
        assert_eq!(built.dmb.grid.len(), 1);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn map_asset_literals_enter_resource_fingerprint() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/translation/resource_archive_order");
        let set = load_resource_set(&root.join("dms_map.dme"), "").unwrap();
        let names: Vec<_> = set
            .inputs
            .iter()
            .map(|input| input.archive_name.as_str())
            .collect();
        assert!(names.contains(&"A.txt"));
        assert!(names.contains(&"tiny.png"));
    }

    #[test]
    fn native_map_initializer_is_a_procedure() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/map_order.native.bin"
        ))
        .unwrap();
        let template = Dmb::from_bytes(BUILTINS).unwrap();
        let initializer = native.instances[9].initializer as usize;
        assert!(native.proc_code_words(initializer).is_some());
        assert_eq!(native.dimensions, [1, 1, 1]);
        assert_eq!(native.grid.len(), 1);
        assert_eq!(template.grid.len(), 0);
    }

    #[test]
    fn typed_class_variable_flags_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/class_const.native.bin"
        ))
        .unwrap();
        let id = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id())
                    == Some(b"/obj/class_const_fixture".as_slice())
            })
            .unwrap();
        let (generated, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/class_const.dm"),
            BUILTINS,
            "class_const",
        )
        .unwrap();
        let generated_id = generated
            .classes
            .iter()
            .position(|class| {
                generated.string(class.path_string_id())
                    == Some(b"/obj/class_const_fixture".as_slice())
            })
            .unwrap();
        let extract = |dmb: &Dmb, class_id| {
            dmb.class_variable_declarations(class_id)
                .unwrap()
                .into_iter()
                .map(|(var, flags)| {
                    (
                        dmb.string(dmb.variables[var as usize].name)
                            .unwrap()
                            .to_vec(),
                        flags,
                    )
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(extract(&generated, generated_id), extract(&native, id));
    }

    #[test]
    fn typed_static_global_variable_flag_matches_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/global_declarations.native.bin"
        ))
        .unwrap();
        let (generated, _) =
            emit_global_procs("/var/static/uid = 0\n", BUILTINS, "global").unwrap();
        let flags_for = |dmb: &Dmb, name: &[u8]| {
            dmb.global_variable_flags()
                .unwrap()
                .into_iter()
                .find_map(|(var, flags)| {
                    (dmb.string(dmb.variables[var as usize].name) == Some(name)).then_some(flags)
                })
                .unwrap()
        };
        assert_eq!(flags_for(&generated, b"uid"), flags_for(&native, b"uid"));
    }

    #[test]
    fn dynamic_initializers_match_native_shape() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/class_init_order.native.bin"
        ))
        .unwrap();
        let id = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id()) == Some(b"/datum/holder".as_slice())
            })
            .unwrap();
        let (generated, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/class_init_order.dm"),
            BUILTINS,
            "class_init",
        )
        .unwrap();
        let generated_id = generated
            .classes
            .iter()
            .position(|class| {
                generated.string(class.path_string_id()) == Some(b"/datum/holder".as_slice())
            })
            .unwrap();
        let native_code = byond_dmb::bytecode::decode(
            native
                .proc_code_words(native.classes[id].initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        let generated_code = byond_dmb::bytecode::decode(
            generated
                .proc_code_words(generated.classes[generated_id].initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(generated_code.len(), native_code.len());
        for (ours, theirs) in generated_code.iter().zip(&native_code) {
            assert_eq!(ours.opcode, theirs.opcode);
            match ours.opcode {
                opcode::PUSH_VAL if ours.operands[0] == 32 => {
                    assert_eq!(theirs.operands[0], 32);
                    let ours_path = generated
                        .string(generated.classes[ours.operands[1] as usize].path_string_id());
                    let their_path =
                        native.string(native.classes[theirs.operands[1] as usize].path_string_id());
                    assert_eq!(ours_path, their_path);
                }
                opcode::PUSH_VAL if ours.operands[0] == 6 => {
                    assert_eq!(theirs.operands[0], 6);
                    assert_eq!(
                        generated.string(ours.operands[1]),
                        native.string(theirs.operands[1])
                    );
                }
                opcode::SET_VAR => {
                    fn source_field(words: &[u32]) -> u32 {
                        use byond_dmb::operands::Variable;
                        let (mut variable, used) = Variable::decode(words).unwrap();
                        assert_eq!(used, words.len());
                        loop {
                            match variable {
                                Variable::SetCache(owner, field) => {
                                    assert_eq!(*owner, Variable::Src);
                                    variable = *field;
                                }
                                Variable::Field(id) => return id,
                                other => panic!("initializer must write a src field: {other:?}"),
                            }
                        }
                    }
                    assert_eq!(
                        generated.string(source_field(&ours.operands)),
                        native.string(source_field(&theirs.operands))
                    );
                }
                _ => assert_eq!(ours.operands, theirs.operands),
            }
        }
        assert_ne!(generated.world.global_initializer_proc_id(), 0xffff);
    }

    #[test]
    fn global_and_static_initializers_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/global_init_order.native.bin"
        ))
        .unwrap();
        let source = include_str!("../../../fixtures/translation/global_init_order.dm");
        let (generated, _) = emit_global_procs(source, BUILTINS, "global_init").unwrap();
        let generated_code = byond_dmb::bytecode::decode(
            generated
                .proc_code_words(generated.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        let native_code = byond_dmb::bytecode::decode(
            native
                .proc_code_words(native.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(generated_code.len(), native_code.len());
        for (ours, theirs) in generated_code.iter().zip(&native_code) {
            assert_eq!(ours.opcode, theirs.opcode);
            match ours.opcode {
                opcode::PUSH_VAL if ours.operands[0] == 32 => {
                    assert_eq!(
                        generated
                            .string(generated.classes[ours.operands[1] as usize].path_string_id()),
                        native.string(native.classes[theirs.operands[1] as usize].path_string_id())
                    );
                }
                opcode::PUSH_VAL if ours.operands[0] == 6 => {
                    assert_eq!(
                        generated.string(ours.operands[1]),
                        native.string(theirs.operands[1])
                    );
                }
                opcode::SET_VAR => {
                    assert_eq!(ours.operands[0], 0xffdb);
                    assert_eq!(ours.operands[0], theirs.operands[0]);
                    assert_eq!(
                        generated.string(generated.variables[ours.operands[1] as usize].name),
                        native.string(native.variables[theirs.operands[1] as usize].name)
                    );
                }
                _ => assert_eq!(ours.operands, theirs.operands),
            }
        }
        for name in [b"A".as_slice(), b"B", b"SA", b"SB"] {
            let ours = generated
                .variables
                .iter()
                .find(|variable| generated.string(variable.name) == Some(name))
                .unwrap();
            let theirs = native
                .variables
                .iter()
                .find(|variable| native.string(variable.name) == Some(name))
                .unwrap();
            assert_eq!((ours.kind, ours.value), (theirs.kind, theirs.value));
        }
        let proc_by_path = |dmb: &Dmb| {
            dmb.procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(b"/proc/static_order"))
                .unwrap()
        };
        let ours = byond_dmb::bytecode::decode(
            generated.proc_code_words(proc_by_path(&generated)).unwrap(),
        )
        .unwrap();
        let theirs =
            byond_dmb::bytecode::decode(native.proc_code_words(proc_by_path(&native)).unwrap())
                .unwrap();
        assert_eq!(ours.len(), theirs.len());
        for (ours, theirs) in ours.iter().zip(&theirs) {
            assert_eq!(ours.opcode, theirs.opcode);
            if ours.opcode == opcode::GET_VAR {
                assert_eq!(ours.operands[0], 0xffdb);
                assert_eq!(theirs.operands[0], 0xffdb);
                assert_eq!(
                    generated.string(generated.variables[ours.operands[1] as usize].name),
                    native.string(native.variables[theirs.operands[1] as usize].name)
                );
            } else {
                assert_eq!(ours.operands, theirs.operands);
            }
        }
    }

    #[test]
    fn static_local_does_not_leak_into_other_proc() {
        let source = "/proc/owner()\n    var/static/owned = 7\n    return owned\n/proc/other()\n    return owned\n";
        assert!(emit_global_procs(source, BUILTINS, "scoped").is_err());
    }

    #[test]
    fn static_names_are_scoped_to_each_proc() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/static_name_collision/probe.dmb"
        ))
        .unwrap();
        let (generated, emitted) = emit_global_procs(
            include_str!("../../../fixtures/translation/static_name_collision/probe.dm"),
            BUILTINS,
            "static",
        )
        .unwrap();
        assert_eq!(emitted.len(), 2);
        for path in [b"/proc/first".as_slice(), b"/proc/second"] {
            let code = |dmb: &Dmb| {
                let id = dmb
                    .procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path))
                    .unwrap();
                byond_dmb::bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap()
            };
            let ours = code(&generated);
            let theirs = code(&native);
            assert_eq!(ours.len(), theirs.len());
            for (ours, theirs) in ours.iter().zip(&theirs) {
                assert_eq!(ours.opcode, theirs.opcode);
                if ours.operands.first() == Some(&0xffdb) {
                    let ours = &generated.variables[ours.operands[1] as usize];
                    let theirs = &native.variables[theirs.operands[1] as usize];
                    assert_eq!((ours.kind, ours.value), (theirs.kind, theirs.value));
                } else {
                    assert_eq!(ours.operands, theirs.operands);
                }
            }
        }
    }

    #[test]
    fn duplicate_dynamic_static_names_get_separate_initializer_slots() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/static_name_collision_dynamic/probe.dmb"
        ))
        .unwrap();
        let (generated, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/static_name_collision_dynamic/probe.dm"),
            BUILTINS,
            "static",
        )
        .unwrap();
        let cache_ids = |dmb: &Dmb| {
            dmb.variables
                .iter()
                .enumerate()
                .filter_map(|(id, var)| {
                    (dmb.string(var.name) == Some(b"cache"))
                        .then_some((id as u32, var.kind, var.value))
                })
                .collect::<Vec<_>>()
        };
        let ours = cache_ids(&generated);
        let theirs = cache_ids(&native);
        assert_eq!(ours.len(), 2);
        assert_eq!(
            ours.iter()
                .map(|entry| (entry.1, entry.2))
                .collect::<Vec<_>>(),
            theirs
                .iter()
                .map(|entry| (entry.1, entry.2))
                .collect::<Vec<_>>()
        );
        let code = |dmb: &Dmb| {
            byond_dmb::bytecode::decode(
                dmb.proc_code_words(dmb.world.global_initializer_proc_id() as usize)
                    .unwrap(),
            )
            .unwrap()
        };
        let ours_code = code(&generated);
        let native_code = code(&native);
        assert_eq!(
            ours_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>(),
            native_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>()
        );
        let ours_targets = ours_code
            .iter()
            .filter(|ins| ins.opcode == opcode::SET_VAR)
            .map(|ins| ins.operands[1])
            .collect::<Vec<_>>();
        let native_targets = native_code
            .iter()
            .filter(|ins| ins.opcode == opcode::SET_VAR)
            .map(|ins| ins.operands[1])
            .collect::<Vec<_>>();
        assert_eq!(
            ours_targets,
            ours.iter().map(|entry| entry.0).collect::<Vec<_>>()
        );
        assert_eq!(
            native_targets,
            theirs.iter().map(|entry| entry.0).collect::<Vec<_>>()
        );
    }

    #[test]
    fn inferred_new_uses_declared_field_and_global_types() {
        let source = "/datum/value\n/datum/holder\n    var/datum/value/cache\n    proc/set()\n        cache = new()\n        return cache\n/var/datum/value/shared\n/proc/set_shared()\n    shared = new()\n    return shared\n";
        let (dmb, _) = emit_global_procs(source, BUILTINS, "inferred").unwrap();
        for path in [b"/datum/holder/proc/set".as_slice(), b"/proc/set_shared"] {
            let id = dmb
                .procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(path))
                .unwrap();
            let code = byond_dmb::bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
            assert!(code
                .iter()
                .any(|instruction| instruction.opcode == opcode::NEW));
        }
    }

    #[test]
    fn inferred_new_list_initializes_typed_class_var() {
        let source = "/datum/alarm_handler\n    var/list/datum/alarm/alarms = new\n";
        let (generated, _) = emit_global_procs(source, BUILTINS, "alarm").unwrap();
        let id = generated
            .classes
            .iter()
            .position(|class| {
                generated.string(class.path_string_id()) == Some(b"/datum/alarm_handler".as_slice())
            })
            .unwrap();
        let code = byond_dmb::bytecode::decode(
            generated
                .proc_code_words(generated.classes[id].initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(code[0].opcode, opcode::NEW_LIST);
        assert_eq!(code[1].opcode, opcode::SET_VAR);
    }

    #[test]
    fn typed_static_constructors_preserve_arguments_and_array_dimensions() {
        assert_eq!(
            normalize_dynamic_expression("new(\"pattern\", \"g\")", &["static", "regex"], "regex")
                .unwrap(),
            "new /regex(\"pattern\", \"g\")"
        );
        assert_eq!(
            normalize_dynamic_expression("new(2, 3)", &["static", "list", "datum"], "list")
                .unwrap(),
            "new /list(2, 3)"
        );
        let source = "/datum/constructor_holder\n    var/static/regex/pattern = new(\"a+\", \"g\")\n    var/static/list/grid = new(2, 3)\n    var/list/instance_grid = new(3, 2)\n    var/list/sized[2][3]\n";
        let (generated, _) = emit_global_procs(source, BUILTINS, "typedstatic").unwrap();
        let instructions: Vec<_> = (0..generated.procs.len())
            .flat_map(|id| {
                byond_dmb::bytecode::decode(generated.proc_code_words(id).unwrap()).unwrap()
            })
            .collect();
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == opcode::NEW));
    }

    #[test]
    fn constant_left_shift_clamps_negative_input_like_native() {
        let (generated, _) =
            emit_global_procs("/var/shift = -1 << 1\n", BUILTINS, "shift").unwrap();
        let value = generated
            .variables
            .iter()
            .find(|value| generated.string(value.name) == Some(b"shift"))
            .unwrap();
        assert_eq!(value.kind, 42);
        assert_eq!(value.value, 0.0f32.to_bits());
    }

    #[test]
    fn world_dimensions_match_native_blank_grid() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/world_dimensions/probe.native.bin"
        ))
        .unwrap();
        let source = include_str!("../../../fixtures/native_compiler/world_dimensions/probe.dm");
        let (output, _) = emit_global_procs(source, BUILTINS, "dimensions").unwrap();
        assert_eq!(output.dimensions, native.dimensions);
        assert_eq!(
            output
                .grid
                .iter()
                .map(|run| usize::from(run.copies))
                .sum::<usize>(),
            12
        );
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn static_initializer_aliases_retain_declared_types() {
        let source = "/datum/alias_value\n/datum/alias_holder\n    var/static/datum/alias_value/value = new\n    var/static/is_value = istype(value)\n";
        emit_global_procs(source, BUILTINS, "staticalias").unwrap();
    }

    #[test]
    fn mob_constructor_links_mob_descriptor_not_class_id() {
        let mut ledger = Ledger::default();
        bind_class_link(&mut ledger, "/datum/collision", 1).unwrap();
        bind_class_link(&mut ledger, "/mob/collision", 1).unwrap();
        assert_eq!(
            ledger.id(&Symbol::new(Table::Class, "/mob/collision")),
            Some(1)
        );
        let source = "/datum/preceding_class\n/mob/constructor_probe\n/proc/create_mob()\n    return new /mob/constructor_probe()\n";
        let (generated, _) = emit_global_procs(source, BUILTINS, "mobctor").unwrap();
        let class = generated
            .classes
            .iter()
            .position(|class| {
                generated.string(class.path_string_id()) == Some(b"/mob/constructor_probe")
            })
            .unwrap() as u32;
        let mob = generated
            .mobs
            .iter()
            .position(|mob| mob.class == class)
            .unwrap() as u32;
        let proc = generated
            .procs
            .iter()
            .position(|proc| generated.string(proc.strings[0]) == Some(b"/proc/create_mob"))
            .unwrap();
        let code = generated.proc_code_words(proc).unwrap();
        assert!(code
            .windows(3)
            .any(|words| words == [opcode::PUSH_VAL, 8, mob]));
    }

    #[test]
    fn inherited_proc_chain_matches_native_calls() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inheritance.native.bin"
        ))
        .unwrap();
        let source = "/datum/fixture_parent\n    var/value = 5\n    proc/result()\n        return value\n/datum/fixture_parent/fixture_child\n    value = 9\n    result()\n        return ..() + 1\n";
        let (generated, emitted) = emit_global_procs(source, BUILTINS, "inheritance").unwrap();
        for entry in emitted
            .into_iter()
            .filter(|entry| entry.path.ends_with("result"))
        {
            let native_id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(entry.path.as_bytes()))
                .unwrap_or_else(|| panic!("native missing {}", entry.path));
            let ours =
                byond_dmb::bytecode::decode(generated.proc_code_words(entry.proc_index).unwrap())
                    .unwrap();
            let theirs =
                byond_dmb::bytecode::decode(native.proc_code_words(native_id).unwrap()).unwrap();
            assert_eq!(
                ours.iter().map(|ins| ins.opcode).collect::<Vec<_>>(),
                theirs.iter().map(|ins| ins.opcode).collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn same_owner_proc_membership_matches_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/same_owner_procs.native.bin"
        ))
        .unwrap();
        let (generated, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/same_owner_procs.dm"),
            BUILTINS,
            "reopen",
        )
        .unwrap();
        let extract = |dmb: &Dmb| {
            let id = dmb
                .classes
                .iter()
                .position(|class| {
                    dmb.string(class.path_string_id()) == Some(b"/datum/reopen".as_slice())
                })
                .unwrap();
            let list = dmb.classes[id].proc_list_id();
            dmb.lists[list as usize]
                .iter()
                .map(|id| {
                    dmb.string(dmb.procs[*id as usize].strings[0])
                        .unwrap()
                        .to_vec()
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(extract(&generated), extract(&native));
    }

    #[test]
    fn inherited_proc_flags_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inherited_proc_flags.native.bin"
        ))
        .unwrap();
        let (generated, emitted) = emit_global_procs(
            include_str!("../../../fixtures/translation/inherited_proc_flags.dm"),
            BUILTINS,
            "flags",
        )
        .unwrap();
        for entry in emitted {
            let native_proc = native
                .procs
                .iter()
                .find(|proc| native.string(proc.strings[0]) == Some(entry.path.as_bytes()))
                .unwrap();
            assert_eq!(
                generated.procs[entry.proc_index].effective_flags(),
                native_proc.effective_flags(),
                "{}",
                entry.path
            );
        }
    }

    #[test]
    fn inherited_verb_metadata_matches_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inherited_verb_flags.native.bin"
        ))
        .unwrap();
        let (generated, emitted) = emit_global_procs(
            include_str!("../../../fixtures/translation/inherited_verb_flags.dm"),
            BUILTINS,
            "verbs",
        )
        .unwrap();
        for entry in emitted {
            let Some(native_proc) = native
                .procs
                .iter()
                .find(|proc| native.string(proc.strings[0]) == Some(entry.path.as_bytes()))
            else {
                continue;
            };
            let ours = &generated.procs[entry.proc_index];
            assert_eq!(
                ours.effective_flags(),
                native_proc.effective_flags(),
                "{}",
                entry.path
            );
            for index in 1..=3 {
                assert_eq!(
                    generated.string(ours.strings[index]),
                    native.string(native_proc.strings[index]),
                    "{} field {}",
                    entry.path,
                    index
                );
            }
        }
    }

    #[test]
    fn repeated_implicit_proc_chain_matches_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/duplicate_proc_chain/probe.native.bin"
        ))
        .unwrap();
        let (generated, emitted) = emit_global_procs(
            include_str!("../../../fixtures/translation/duplicate_proc_chain/probe.dm"),
            BUILTINS,
            "chain",
        )
        .unwrap();
        let chain = emitted
            .iter()
            .filter(|proc| proc.path == "/datum/chain/value")
            .collect::<Vec<_>>();
        assert_eq!(chain.len(), 2);
        for (index, entry) in chain.into_iter().enumerate() {
            let native_words = native.proc_code_words(index + 1).unwrap();
            assert_eq!(entry.words, native_words, "definition {index}");
            assert_eq!(
                generated.proc_code_words(entry.proc_index),
                Some(native_words)
            );
        }
        let class_members = |dmb: &Dmb| {
            let class = dmb
                .classes
                .iter()
                .find(|class| dmb.string(class.path_string_id()) == Some(b"/datum/chain"))
                .unwrap();
            let id = class.proc_list_id();
            dmb.lists[id as usize]
                .iter()
                .map(|id| {
                    dmb.string(dmb.procs[*id as usize].strings[0])
                        .unwrap()
                        .to_vec()
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(class_members(&generated), class_members(&native));
    }

    #[test]
    fn repeated_explicit_proc_is_rejected() {
        let source =
            "/datum/chain/proc/value()\n    return 1\n/datum/chain/proc/value()\n    return 2\n";
        assert!(emit_global_procs(source, BUILTINS, "chain")
            .unwrap_err()
            .contains("duplicate procedure"));
    }

    #[test]
    fn world_new_and_proc_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/world_new/probe.native.bin"
        ))
        .unwrap();
        let (generated, emitted) = emit_global_procs(
            include_str!("../../../fixtures/translation/world_new/probe.dm"),
            BUILTINS,
            "world",
        )
        .unwrap();
        let native_members = &native.lists[native.world.proc_list_id() as usize];
        let generated_members = &generated.lists[generated.world.proc_list_id() as usize];
        assert_eq!(generated_members.len(), native_members.len());
        for (ours, theirs) in generated_members.iter().zip(native_members) {
            let ours = *ours as usize;
            let theirs = *theirs as usize;
            assert_eq!(
                generated.string(generated.procs[ours].strings[0]),
                native.string(native.procs[theirs].strings[0])
            );
            assert_eq!(
                generated.proc_code_words(ours),
                native.proc_code_words(theirs)
            );
        }
        assert_eq!(emitted.len(), 2);
    }

    #[test]
    fn world_block_members_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/world_new_block/probe.native.bin"
        ))
        .unwrap();
        let (generated, emitted) = emit_global_procs(
            include_str!("../../../fixtures/translation/world_new_block/probe.dm"),
            BUILTINS,
            "world",
        )
        .unwrap();
        let native_members = &native.lists[native.world.proc_list_id() as usize];
        let generated_members = &generated.lists[generated.world.proc_list_id() as usize];
        assert_eq!(generated_members.len(), native_members.len());
        for (ours, theirs) in generated_members.iter().zip(native_members) {
            let ours = *ours as usize;
            let theirs = *theirs as usize;
            assert_eq!(
                generated.string(generated.procs[ours].strings[0]),
                native.string(native.procs[theirs].strings[0])
            );
            assert_eq!(
                generated.proc_code_words(ours),
                native.proc_code_words(theirs)
            );
        }
        assert_eq!(emitted.len(), 2);
    }

    #[test]
    fn rust_lowered_procs_match_native_fixture_words() {
        let native = Dmb::from_bytes(NATIVE).unwrap();
        let (output, emitted) = replace_existing_procs(SOURCE, NATIVE).unwrap();
        assert_eq!(emitted.len(), 3);
        for proc in emitted {
            assert_eq!(
                Some(proc.words.as_slice()),
                native.proc_code_words(proc.proc_index),
                "{}",
                proc.path
            );
            assert_eq!(
                Some(proc.words.as_slice()),
                output.proc_code_words(proc.proc_index)
            );
        }
        let encoded = output.to_bytes().unwrap();
        Dmb::from_bytes(&encoded)
            .unwrap()
            .validate_references()
            .unwrap();
    }

    #[test]
    fn unsupported_body_fails_instead_of_copying_template_code() {
        let source = "/proc/return_seven()\n    switch (1)\n        if (1) return 7\n";
        assert!(replace_existing_procs(source, NATIVE).is_err());
    }

    #[test]
    fn direct_global_procs_from_builtin_schema_have_native_code() {
        let native = Dmb::from_bytes(NATIVE).unwrap();
        let (output, emitted) = emit_global_procs(SOURCE, BUILTINS, "simple").unwrap();
        assert_eq!(emitted.len(), 3);
        for proc in emitted {
            let native_id = native
                .procs
                .iter()
                .position(|record| native.string(record.strings[0]) == Some(proc.path.as_bytes()))
                .unwrap();
            let native_words = native.proc_code_words(native_id).unwrap();
            if proc.path == "/proc/return_text" {
                assert_eq!(&proc.words[..2], &native_words[..2]);
                assert_eq!(&proc.words[3..], &native_words[3..]);
                assert_eq!(output.string(proc.words[2]), native.string(native_words[2]));
            } else {
                assert_eq!(proc.words, native_words, "{}", proc.path);
            }
            assert_eq!(
                Some(proc.words.as_slice()),
                output.proc_code_words(proc.proc_index)
            );
        }
        Dmb::from_bytes(&output.to_bytes().unwrap())
            .unwrap()
            .validate_references()
            .unwrap();
    }

    #[test]
    fn direct_global_procs_emit_argument_and_local_metadata() {
        let source = include_str!("../../../fixtures/native_compiler/flow.dm");
        let (output, emitted) = emit_global_procs(source, BUILTINS, "flow").unwrap();
        assert_eq!(emitted.len(), 4);
        let local_sum = emitted
            .iter()
            .find(|proc| proc.path == "/proc/local_sum")
            .unwrap();
        let record = &output.procs[local_sum.proc_index];
        let locals = &output.lists[record.code_locals_args[1] as usize];
        assert_eq!(locals.len(), 1);
        assert_eq!(
            output.string(output.variables[locals[0] as usize].name),
            Some(b"y".as_slice())
        );
        let args = output.proc_arguments(local_sum.proc_index).unwrap();
        assert_eq!(args.len(), 1);
        assert_eq!(
            output.string(output.variables[args[0].variable_id as usize].name),
            Some(b"x".as_slice())
        );
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn dme_project_compiles_in_include_order() {
        let manifest =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/simple.dme");
        let (output, emitted) = compile_project(&manifest, BUILTINS, "simple").unwrap();
        assert_eq!(emitted.len(), 3);
        assert_eq!(
            output.string(output.world.ids[6]),
            Some(b"simple".as_slice())
        );
    }

    #[test]
    fn direct_types_and_constant_members_round_trip() {
        let source = "/datum/compiler_probe\n    var/count = 7\n    var/title = \"probe\"\n/datum/compiler_probe/child\n";
        let (output, emitted) = emit_global_procs(source, BUILTINS, "types").unwrap();
        assert!(emitted.is_empty());
        let parent = output
            .classes
            .iter()
            .position(|class| {
                output.string(class.path_string_id()) == Some(b"/datum/compiler_probe".as_slice())
            })
            .unwrap();
        let child = output
            .classes
            .iter()
            .position(|class| {
                output.string(class.path_string_id())
                    == Some(b"/datum/compiler_probe/child".as_slice())
            })
            .unwrap();
        assert_eq!(output.classes[child].parent_class_id(), parent as u32);
        let declared = output.classes[parent].defining_variable_list_id();
        assert_eq!(output.lists[declared as usize].len(), 4);
        let decoded = Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
        decoded.validate_references().unwrap();
    }

    #[test]
    fn direct_type_paths_match_native_type_fixture() {
        let source = include_str!("../../../fixtures/native_compiler/types.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/types.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "types").unwrap();
        for path in ["/datum/compiler_probe", "/datum/compiler_probe/child"] {
            let actual = output
                .classes
                .iter()
                .find(|class| output.string(class.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            let expected = native
                .classes
                .iter()
                .find(|class| native.string(class.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(
                output.string(actual.name_string_id()),
                native.string(expected.name_string_id())
            );
            let actual_parent = &output.classes[actual.parent_class_id() as usize];
            let native_parent = &native.classes[expected.parent_class_id() as usize];
            assert_eq!(
                output.string(actual_parent.path_string_id()),
                native.string(native_parent.path_string_id())
            );
        }
    }

    #[test]
    fn manifest_skin_and_its_icon_enter_output_resources() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/translation/selected_skin");
        let project =
            compile_project_with_resources(&root.join("probe.dme"), BUILTINS, "skin").unwrap();
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/selected_skin/probe.native.bin"
        ))
        .unwrap();
        let skin = &project.dmb.resources[project.dmb.world.skin_resource_id() as usize];
        let expected = &native.resources[native.world.skin_resource_id() as usize];
        assert_eq!(skin.id, expected.id);
        assert_eq!(skin.kind, expected.kind);
        let archive = byond_dmb::rsc::read_all(&mut project.rsc_bytes.as_slice()).unwrap();
        assert!(archive.iter().any(|entry| matches!(entry, byond_dmb::rsc::Entry::Named(named) if named.name == b"skin.dmf")));
        assert!(archive.iter().any(|entry| matches!(entry, byond_dmb::rsc::Entry::Named(named) if named.name == b"tiny.png")));
    }

    #[test]
    fn local_constants_statics_and_infinity_keep_lexical_scopes() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/local_constants/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/local_constants/probe.dm"),
            BUILTINS,
            "test",
        )
        .unwrap();
        let values = |dmb: &Dmb| {
            let mut values: Vec<_> = dmb
                .global_variable_flags()
                .unwrap()
                .into_iter()
                .filter_map(|(id, flags)| {
                    let v = &dmb.variables[id as usize];
                    let name = dmb.string(v.name)?;
                    (flags == 3
                        && [
                            b"limit".as_slice(),
                            b"copy",
                            b"positive_infinity",
                            b"negative_infinity",
                        ]
                        .contains(&name))
                    .then_some((name.to_vec(), v.kind, v.value))
                })
                .collect();
            values.sort();
            values
        };
        assert_eq!(values(&output), values(&native));
        let code = byond_dmb::bytecode::decode(
            output
                .proc_code_words(output.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            code.iter().filter(|i| i.opcode == opcode::SET_VAR).count(),
            3
        );
        for entry in output.procs.iter().filter(|p| {
            output.string(p.strings[0]).is_some_and(|name| {
                name == b"/proc/other" || name == b"/datum/local_scope/proc/read"
            })
        }) {
            assert!(output.lists[entry.code_locals_args[1] as usize].is_empty());
        }
        assert!(emit_global_procs(
            "/datum/a\n    var/const/leaked = 2\n/var/const/b = leaked\n",
            BUILTINS,
            "test"
        )
        .is_err());
        assert!(emit_global_procs(
            "/proc/bad()\n    var/const/a = list()\n    return a\n",
            BUILTINS,
            "test"
        )
        .is_err());
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn class_statics_are_shared_globals_with_scoped_initializers() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/class_static/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/class_static/probe.dm"),
            BUILTINS,
            "test",
        )
        .unwrap();
        let footer = output.global_variable_flags().unwrap();
        for path in [b"/datum/static_one".as_slice(), b"/datum/static_two"] {
            let class = output
                .classes
                .iter()
                .position(|c| output.string(c.path_string_id()) == Some(path))
                .unwrap();
            let expected_class = native
                .classes
                .iter()
                .position(|c| native.string(c.path_string_id()) == Some(path))
                .unwrap();
            let actual: std::collections::BTreeMap<_, _> = output
                .class_variable_declarations(class)
                .unwrap()
                .into_iter()
                .map(|(id, flags)| {
                    assert!(footer.contains(&(id, flags)));
                    (
                        output
                            .string(output.variables[id as usize].name)
                            .unwrap()
                            .to_vec(),
                        flags,
                    )
                })
                .collect();
            let expected: std::collections::BTreeMap<_, _> = native
                .class_variable_declarations(expected_class)
                .unwrap()
                .into_iter()
                .map(|(id, flags)| {
                    (
                        native
                            .string(native.variables[id as usize].name)
                            .unwrap()
                            .to_vec(),
                        flags,
                    )
                })
                .collect();
            assert_eq!(actual, expected);
            assert_eq!(output.classes[class].initializer_proc_id(), 0xffff);
        }
        let code = byond_dmb::bytecode::decode(
            output
                .proc_code_words(output.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            code.iter().filter(|i| i.opcode == opcode::SET_VAR).count(),
            3
        );
        for instruction in code.iter().filter(|i| i.opcode == opcode::SET_VAR) {
            let (variable, _) =
                byond_dmb::operands::Variable::decode(&instruction.operands).unwrap();
            assert!(matches!(variable, byond_dmb::operands::Variable::Global(_)));
        }
        assert!(emit_global_procs(
            "/proc/bad()\n    var/static/const/a = list()\n    return a\n",
            BUILTINS,
            "test"
        )
        .is_err());
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn sized_array_declarations_allocate_lists() {
        let source = include_str!("../../../fixtures/translation/array_declarations/probe.dm");
        let (output, _) = emit_global_procs(source, BUILTINS, "test").unwrap();
        for name in [b"grid".as_slice(), b"items", b"empty", b"lazy", b"values"] {
            assert!(output
                .variables
                .iter()
                .any(|v| output.string(v.name) == Some(name)));
        }
        assert_ne!(output.world.global_initializer_proc_id(), 0xffff);
        let class = output
            .classes
            .iter()
            .find(|c| output.string(c.path_string_id()) == Some(b"/datum/array_probe"))
            .unwrap();
        assert_ne!(class.initializer_proc_id(), 0xffff);
        assert!(emit_global_procs("/var/global/bad[-1]\n", BUILTINS, "test").is_err());
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn forward_type_constants_and_inherited_headers_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/typed_path_constants/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/typed_path_constants/probe.dm"),
            BUILTINS,
            "test",
        )
        .unwrap();
        let type_path = |dmb: &Dmb, value: &Variable| match value.kind {
            36 => b"/savefile".to_vec(),
            39 => b"/file".to_vec(),
            40 => b"/list".to_vec(),
            59 => b"/client".to_vec(),
            _ => {
                let class = if value.kind == 8 {
                    dmb.mobs[value.value as usize].class
                } else {
                    value.value
                };
                dmb.string(dmb.classes[class as usize].path_string_id())
                    .unwrap()
                    .to_vec()
            }
        };
        for expected in native.variables.iter().filter(|v| {
            native
                .string(v.name)
                .is_some_and(|n| n.starts_with(b"type_"))
        }) {
            let name = native.string(expected.name).unwrap();
            let actual = output
                .variables
                .iter()
                .find(|v| output.string(v.name) == Some(name))
                .unwrap();
            assert_eq!(
                actual.kind,
                expected.kind,
                "{}",
                String::from_utf8_lossy(name)
            );
            assert_eq!(type_path(&output, actual), type_path(&native, expected));
        }
        let actual = output
            .classes
            .iter()
            .find(|c| output.string(c.path_string_id()) == Some(b"/obj/path_probe"))
            .unwrap();
        let expected = native
            .classes
            .iter()
            .find(|c| native.string(c.path_string_id()) == Some(b"/obj/path_probe"))
            .unwrap();
        assert_eq!(
            output.string(actual.initial_ids[2]),
            native.string(expected.initial_ids[2])
        );
        assert_eq!(actual.flags, expected.flags);
        let constant = output
            .variables
            .iter()
            .position(|v| output.string(v.name) == Some(b"local_constant"))
            .unwrap() as u32;
        assert_eq!(
            output
                .global_variable_flags()
                .unwrap()
                .into_iter()
                .find(|(v, _)| *v == constant)
                .unwrap()
                .1,
            3
        );
        assert_eq!(
            f32::from_bits(output.variables[constant as usize].value),
            3.0
        );
        assert!(emit_global_procs(
            "/datum/a\n    parent_type = /datum/b\n/datum/b\n    parent_type = /datum/a\n",
            BUILTINS,
            "test"
        )
        .is_err());
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn constant_edge_semantics_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/constant_edges/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(
            include_str!("../../../fixtures/translation/constant_edges/probe.dm"),
            BUILTINS,
            "test",
        )
        .unwrap();
        for expected in native.variables.iter().filter(|v| {
            native
                .string(v.name)
                .is_some_and(|n| n.starts_with(b"edge_"))
        }) {
            let name = native.string(expected.name).unwrap();
            let actual = output
                .variables
                .iter()
                .find(|v| output.string(v.name) == Some(name))
                .unwrap();
            assert_eq!(
                actual.kind,
                expected.kind,
                "{}",
                String::from_utf8_lossy(name)
            );
            if expected.kind == 6 {
                assert_eq!(output.string(actual.value), native.string(expected.value));
            } else {
                assert_eq!(
                    actual.value,
                    expected.value,
                    "{}",
                    String::from_utf8_lossy(name)
                );
            }
        }
        for source in ["/var/const/a = null + 1\n", "/var/const/a = null == 0\n",
            "/var/const/shared = 5\n/datum/shadow\n    var/const/result = shared + 1\n    var/shared = 7\n"] {
            assert!(emit_global_procs(source, BUILTINS, "test").is_err(), "{source}");
        }
    }

    #[test]
    fn forward_constants_resolve_and_runtime_names_are_not_folded() {
        let source = "/var/const/first = second * 2\n/var/const/second = 7\n/var/global/runtime = 3\n/var/global/copy = runtime + first\n/datum/forward\n    var/const/earlier = later + first\n    var/const/later = 2\n";
        let (dmb, _) = emit_global_procs(source, BUILTINS, "test").unwrap();
        let first = dmb
            .variables
            .iter()
            .find(|v| dmb.string(v.name) == Some(b"first"))
            .unwrap();
        assert_eq!(f32::from_bits(first.value), 14.0);
        let earlier = dmb
            .variables
            .iter()
            .find(|v| dmb.string(v.name) == Some(b"earlier"))
            .unwrap();
        assert_eq!(f32::from_bits(earlier.value), 16.0);
        assert_ne!(dmb.world.global_initializer_proc_id(), 0xffff);
        assert!(
            emit_global_procs("/var/const/a = b\n/var/const/b = a\n", BUILTINS, "test").is_err()
        );
        assert!(emit_global_procs("/var/const/a = 1 / 0\n", BUILTINS, "test").is_err());
    }

    #[test]
    fn constant_initializers_and_settings_match_native() {
        let source = include_str!("../../../fixtures/translation/constant_folding/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/constant_folding/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "probe").unwrap();
        let values = |dmb: &Dmb| {
            dmb.variables
                .iter()
                .filter_map(|v| {
                    let name = dmb.string(v.name)?;
                    (name.starts_with(b"global_")
                        || [
                            b"local_scale".as_slice(),
                            b"local_mask",
                            b"choice",
                            b"modulo",
                            b"negative",
                            b"power",
                            b"logical_and",
                            b"logical_or",
                            b"null_equal",
                            b"hex",
                            b"value",
                            b"inherited",
                        ]
                        .contains(&name))
                    .then(|| {
                        (
                            name.to_vec(),
                            (
                                v.kind,
                                if v.kind == 6 {
                                    dmb.string(v.value).unwrap().to_vec()
                                } else {
                                    v.value.to_le_bytes().to_vec()
                                },
                            ),
                        )
                    })
                })
                .collect::<std::collections::BTreeMap<_, _>>()
        };
        assert_eq!(values(&output), values(&native));
        assert_eq!(
            output.string(output.world.name_string_id()),
            native.string(native.world.name_string_id())
        );
        let display_name = |dmb: &Dmb| {
            let class = dmb
                .classes
                .iter()
                .find(|c| dmb.string(c.path_string_id()) == Some(b"/obj/fold_probe"))
                .unwrap();
            dmb.string(class.initial_ids[2]).unwrap().to_vec()
        };
        assert_eq!(display_name(&output), display_name(&native));
        assert_eq!(output.world.view_dimensions, native.world.view_dimensions);
        assert_eq!(output.world.tick_lag, native.world.tick_lag);
        assert_eq!(output.world.global_initializer_proc_id(), 0xffff);
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn world_type_defaults_validate_ancestry_and_null() {
        assert!(emit_global_procs("/world\n    mob = /turf\n", BUILTINS, "test").is_err());
        assert!(emit_global_procs("/world\n    turf = /missing\n", BUILTINS, "test").is_err());
        let (dmb, _) = emit_global_procs(
            "/world\n    mob = null\n    turf = null\n    area = null\n",
            BUILTINS,
            "test",
        )
        .unwrap();
        assert_eq!(&dmb.world.ids[..3], &[0xffff; 3]);
        let (dmb, _) =
            emit_global_procs("/client/Import()\n    return null\n", BUILTINS, "test").unwrap();
        assert!(dmb.world.has_client_import_handler());
    }

    #[test]
    fn world_type_defaults_and_client_setup_match_native() {
        let source = include_str!("../../../fixtures/translation/world_type_defaults/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/world_type_defaults/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "probe").unwrap();
        let mob = &output.mobs[output.world.ids[0] as usize];
        let native_mob = &native.mobs[native.world.ids[0] as usize];
        assert_eq!(
            output.string(output.classes[mob.class as usize].path_string_id()),
            native.string(native.classes[native_mob.class as usize].path_string_id())
        );
        assert_eq!(mob.sight_bits(), native_mob.sight_bits());
        assert_eq!(mob.extended_sight, native_mob.extended_sight);
        for slot in [1, 2] {
            assert_eq!(
                output.string(output.classes[output.world.ids[slot] as usize].path_string_id()),
                native.string(native.classes[native.world.ids[slot] as usize].path_string_id())
            );
        }
        for record in &output.mobs {
            if output.string(output.classes[record.class as usize].path_string_id())
                == Some(b"/mob/compiler_probe/child")
            {
                assert_eq!(record.extended_sight, mob.extended_sight);
            }
        }
        assert_eq!(output.world.eye, native.world.eye);
        assert_eq!(output.world.control, native.world.control);
        assert_eq!(
            output.header.flags & 0x18109d80,
            native.header.flags & 0x18109d80
        );
        let client = output
            .classes
            .iter()
            .find(|c| output.string(c.path_string_id()) == Some(b"/client"))
            .unwrap();
        assert_eq!(
            output.string(output.classes[client.parent_class_id() as usize].path_string_id()),
            Some(b"/datum".as_slice())
        );
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn world_metadata_and_tmp_variables_match_native() {
        let source = include_str!("../../../fixtures/translation/declaration_metadata/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/declaration_metadata/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "default").unwrap();
        assert_eq!(output.world.view_dimensions, native.world.view_dimensions);
        assert_eq!(output.world.tick_lag, native.world.tick_lag);
        assert_eq!(output.world.version, native.world.version);
        assert_eq!(output.world.cache_lifespan, native.world.cache_lifespan);
        assert_eq!(
            output.world.icon_dimensions_format,
            native.world.icon_dimensions_format
        );
        assert_eq!(output.header.flags & 0x2222, native.header.flags & 0x2222);
        assert_eq!(
            output.string(output.world.server_name),
            native.string(native.world.server_name)
        );
        assert_eq!(
            output.string(output.world.hub_channel_skin[0]),
            native.string(native.world.hub_channel_skin[0])
        );
        let declarations = |dmb: &Dmb| {
            let class = dmb
                .classes
                .iter()
                .find(|c| dmb.string(c.path_string_id()) == Some(b"/datum/metadata_probe"))
                .unwrap();
            dmb.lists[class.lists_and_procs[4] as usize]
                .chunks_exact(2)
                .map(|pair| {
                    (
                        dmb.string(dmb.variables[pair[0] as usize].name)
                            .unwrap()
                            .to_vec(),
                        pair[1],
                    )
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(declarations(&output), declarations(&native));
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn world_view_and_timing_reject_invalid_values() {
        for value in ["36", "-2", "\"256x1\"", "\"80x80\"", "\"bad\""] {
            assert!(
                emit_global_procs(&format!("/world\n    view = {value}\n"), BUILTINS, "test")
                    .is_err()
            );
        }
        assert_eq!(encode_world_view("7").unwrap(), 0x0f0f);
        assert_eq!(encode_world_view("\"0x15\"").unwrap(), 7);
        assert!(
            emit_global_procs("/world\n    tick_lag = 99999999999\n", BUILTINS, "test").is_err()
        );
        assert!(emit_global_procs("/world\n    fps = 0\n", BUILTINS, "test").is_err());
    }

    #[test]
    fn explicit_world_settings_override_build_defaults() {
        let source = "/world\n    name = \"A test world\"\n    view = 7\n    tick_lag = 0.5\n";
        let (output, _) = emit_global_procs(source, BUILTINS, "default").unwrap();
        assert_eq!(
            output.string(output.world.name_string_id()),
            Some(b"A test world".as_slice())
        );
        assert_eq!(output.world.view_dimensions, 0x0f0f);
        assert_eq!(output.world.tick_lag, 50);
        Dmb::from_bytes(&output.to_bytes().unwrap()).unwrap();
    }

    #[test]
    fn global_constants_and_type_methods_link() {
        let source = "/var/global/count = 7\n/datum/compiler_probe\n    var/value = 2\n    proc/read(x)\n        return value + x + count\n    verb/peek()\n        return value\n";
        let (output, emitted) = emit_global_procs(source, BUILTINS, "members").unwrap();
        assert_eq!(emitted.len(), 2);
        let global = output
            .global_variable_flags()
            .unwrap()
            .last()
            .copied()
            .unwrap();
        assert_eq!(global.1, 1);
        assert_eq!(
            output.string(output.variables[global.0 as usize].name),
            Some(b"count".as_slice())
        );
        let class = output
            .classes
            .iter()
            .find(|class| {
                output.string(class.path_string_id()) == Some(b"/datum/compiler_probe".as_slice())
            })
            .unwrap();
        assert_eq!(output.lists[class.proc_list_id() as usize].len(), 1);
        assert_eq!(output.lists[class.verb_list_id() as usize].len(), 1);
        Dmb::from_bytes(&output.to_bytes().unwrap())
            .unwrap()
            .validate_references()
            .unwrap();
    }

    #[test]
    fn unsupported_global_initializer_fails_closed() {
        let source = "/var/global/const/answer = list(1, 2)\n";
        assert!(emit_global_procs(source, BUILTINS, "globals").is_err());
    }

    #[test]
    fn forward_global_call_uses_direct_proc_id() {
        let source = "/proc/answer()\n    return helper(3)\n/proc/helper(x)\n    return x + 4\n";
        let (output, emitted) = emit_global_procs(source, BUILTINS, "calls").unwrap();
        let answer = emitted
            .iter()
            .find(|proc| proc.path == "/proc/answer")
            .unwrap();
        let helper = emitted
            .iter()
            .find(|proc| proc.path == "/proc/helper")
            .unwrap();
        assert!(answer
            .words
            .windows(3)
            .any(|words| words == [0x30, 1, helper.proc_index as u32]));
        output.validate_references().unwrap();
    }

    #[test]
    fn typed_default_arguments_emit_metadata_and_code() {
        let source = "/proc/typed_default(obj/O, amount = 5, label = \"hi\")\n    return O\n";
        let (dmb, emitted) = emit_global_procs(source, BUILTINS, "typed_defaults").unwrap();
        let proc_id = emitted[0].proc_index;
        let args = dmb.proc_arguments(proc_id).unwrap();
        assert_eq!(
            args.iter().map(|arg| arg.type_flags).collect::<Vec<_>>(),
            [2, 0, 0]
        );
        assert_eq!(
            args.iter()
                .map(|arg| dmb
                    .string(dmb.variables[arg.variable_id as usize].name)
                    .unwrap())
                .collect::<Vec<_>>(),
            [b"O".as_slice(), b"amount", b"label"]
        );
        assert!(dmb.proc_code_words(proc_id).unwrap().len() > 10);
        dmb.validate_references().unwrap();
    }

    #[test]
    fn native_argument_defaults_compile_end_to_end() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_defaults.native.bin"
        ))
        .unwrap();
        let source =
            "/proc/default_arg_probe(a = 5, b = \"hi\", c = list(1, 2), d = /obj)\n    return a\n";
        let (output, emitted) = replace_existing_procs(
            source,
            include_bytes!("../../../fixtures/translation/argument_defaults.native.bin"),
        )
        .unwrap();
        let proc_id = emitted[0].proc_index;
        assert_eq!(
            output.proc_code_words(proc_id),
            native.proc_code_words(proc_id)
        );
        output.validate_references().unwrap();
    }

    #[test]
    fn resource_literal_links_to_paired_rsc() {
        let root =
            std::env::temp_dir().join(format!("dm-compiler-resource-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let disk_path = root.join("asset.txt");
        std::fs::write(&disk_path, b"resource payload").unwrap();
        let resources = ResourceSet::load([ResourceRequest {
            archive_name: "asset.txt".into(),
            disk_path: disk_path.clone(),
        }])
        .unwrap();
        let source = "/proc/load_asset()\n    return 'asset.txt'\n";
        let (dmb, emitted, rsc_bytes) =
            emit_global_procs_with_resources(source, BUILTINS, "assets", &resources).unwrap();
        let words = &emitted[0].words;
        assert!(words.windows(2).any(|pair| pair == [12, 0]));
        let archive = byond_dmb::rsc::read_all(&mut rsc_bytes.as_slice()).unwrap();
        assert!(dmb.missing_resources(&archive).is_empty());
        std::fs::remove_file(disk_path).unwrap();
        std::fs::remove_dir(root).unwrap();
    }

    #[test]
    fn identical_resource_payloads_allow_distinct_literal_path_aliases() {
        let root =
            std::env::temp_dir().join(format!("dm-compiler-resource-alias-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let disk_path = root.join("asset.txt");
        std::fs::write(&disk_path, b"shared resource payload").unwrap();
        let resources = ResourceSet::load(["asset.txt", "alias/asset.txt"].map(|archive_name| {
            ResourceRequest {
                archive_name: archive_name.into(),
                disk_path: disk_path.clone(),
            }
        }))
        .unwrap();
        let source = "/var/list/assets = list('asset.txt', 'alias/asset.txt')\n/datum/asset_holder\n    var/list/assets = list('asset.txt', 'alias/asset.txt')\n/proc/load_assets(value in list('asset.txt', 'alias/asset.txt'))\n    return list('asset.txt', 'alias/asset.txt')\n";
        let (dmb, _, bytes) =
            emit_global_procs_with_resources(source, BUILTINS, "aliases", &resources).unwrap();
        assert_eq!(dmb.resources.len(), 1);
        assert_eq!(
            byond_dmb::rsc::read_all(&mut bytes.as_slice())
                .unwrap()
                .len(),
            1
        );
        std::fs::remove_file(disk_path).unwrap();
        std::fs::remove_dir(root).unwrap();
    }

    #[test]
    fn alist_type_constant_uses_native_class_descriptor() {
        let (dmb, emitted) = emit_global_procs(
            "/var/assoc_type = /alist\n/proc/assoc_type()\n    return /alist\n",
            BUILTINS,
            "alisttype",
        )
        .unwrap();
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/alist"))
            .unwrap() as u32;
        let value = dmb
            .variables
            .iter()
            .find(|var| dmb.string(var.name) == Some(b"assoc_type"))
            .unwrap();
        assert_eq!((value.kind, value.value), (89, class));
        assert!(emitted[0]
            .words
            .windows(3)
            .any(|words| words == [opcode::PUSH_VAL, 89, class]));
    }

    #[test]
    fn ordinary_inherited_member_calls_are_known_without_static_dispatch() {
        let source = "/atom/proc/Safe_COORD_Location()\n    return 7\n/obj/member_guard_probe/proc/check()\n    return Safe_COORD_Location()\n";
        let (_, emitted) = emit_global_procs(source, BUILTINS, "memberguard").unwrap();
        let proc = emitted
            .iter()
            .find(|proc| proc.path == "/obj/member_guard_probe/proc/check")
            .unwrap();
        assert!(byond_dmb::bytecode::decode(&proc.words)
            .unwrap()
            .iter()
            .any(|instruction| instruction.opcode == opcode::CALL));
        assert_eq!(
            audit_lowering(source, 1024 * 1024, BUILTINS)
                .unwrap()
                .failed,
            0
        );
    }

    #[test]
    fn static_aliases_preserve_builtin_and_procedure_callees() {
        let source =
            include_str!("../../../fixtures/native_compiler/static_callee_collision/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/static_callee_collision/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "callee").unwrap();
        let code = byond_dmb::bytecode::decode(
            output
                .proc_code_words(output.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        let expected = byond_dmb::bytecode::decode(
            native
                .proc_code_words(native.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            code.iter()
                .filter(|instruction| instruction.opcode == opcode::REGEX_NEW)
                .count(),
            expected
                .iter()
                .filter(|instruction| instruction.opcode == opcode::REGEX_NEW)
                .count()
        );
        assert!(code
            .iter()
            .any(|instruction| instruction.opcode == opcode::CALL_GLOB));
        let aliases = HashMap::from([("colliding".to_owned(), "__alias".to_owned())]);
        assert_eq!(
            qualify_expression_with_aliases("colliding(colliding)", &aliases),
            "colliding(__alias)"
        );
        assert_eq!(
            qualify_expression_with_aliases("call(colliding)(1)", &aliases),
            "call(__alias)(1)"
        );
    }

    #[test]
    fn initializer_global_subset_includes_interpolations_without_unused_names() {
        let globals = HashMap::from([
            ("__used".into(), 1),
            ("__interpolated".into(), 2),
            ("unused".into(), 3),
        ]);
        let source = "__used = list(\"[__interpolated]\", 1)";
        assert_eq!(
            referenced_initializer_globals(source, &globals),
            BTreeSet::from(["__used".into(), "__interpolated".into()])
        );
    }

    #[test]
    fn constant_resource_variables_use_rsc_index() {
        let root =
            std::env::temp_dir().join(format!("dm-compiler-resource-var-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let disk_path = root.join("asset.txt");
        std::fs::write(&disk_path, b"constant payload").unwrap();
        let resources = ResourceSet::load([ResourceRequest {
            archive_name: "asset.txt".into(),
            disk_path: disk_path.clone(),
        }])
        .unwrap();
        let source = "/var/global_asset = 'asset.txt'\n/datum/resource_probe\n    var/file_ref = 'asset.txt'\n";
        let (dmb, _, rsc_bytes) =
            emit_global_procs_with_resources(source, BUILTINS, "assets", &resources).unwrap();
        for name in [b"global_asset".as_slice(), b"file_ref".as_slice()] {
            let variable = dmb
                .variables
                .iter()
                .find(|variable| dmb.string(variable.name) == Some(name))
                .unwrap();
            assert_eq!((variable.kind, variable.value), (12, 0));
        }
        let archive = byond_dmb::rsc::read_all(&mut rsc_bytes.as_slice()).unwrap();
        assert!(dmb.missing_resources(&archive).is_empty());
        std::fs::remove_file(disk_path).unwrap();
        std::fs::remove_dir(root).unwrap();
    }

    #[test]
    fn direct_argument_sources_match_native_metadata() {
        let source = include_str!("../../../fixtures/translation/argument_sources.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_sources.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "argument_sources").unwrap();
        for proc in emitted {
            let native_id = native
                .procs
                .iter()
                .position(|record| native.string(record.strings[0]) == Some(proc.path.as_bytes()))
                .unwrap();
            let native_args = native.proc_arguments(native_id).unwrap();
            let output_args = output.proc_arguments(proc.proc_index).unwrap();
            assert_eq!(
                output_args[0].type_flags, native_args[0].type_flags,
                "{}",
                proc.path
            );
            assert_eq!(
                output_args[0].value_source, native_args[0].value_source,
                "{}",
                proc.path
            );
        }
    }

    #[test]
    fn list_argument_source_emits_companion_proc() {
        let source = include_str!("../../../fixtures/translation/argument_defaults.dm");
        let (output, emitted) = emit_global_procs(source, BUILTINS, "argument_defaults").unwrap();
        let owner = emitted
            .iter()
            .find(|proc| proc.path == "/proc/argument_in_probe")
            .unwrap();
        let arg = output.proc_arguments(owner.proc_index).unwrap()[0];
        assert_eq!(arg.type_flags, 4);
        assert_eq!(arg.value_source, 0x40);
        let companion = output.argument_source_proc_id(&arg).unwrap() as usize;
        assert_eq!(output.procs[companion].strings, [0xffff; 4]);
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_defaults.native.bin"
        ))
        .unwrap();
        let native_owner = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/argument_in_probe".as_slice())
            })
            .unwrap();
        let native_arg = native.proc_arguments(native_owner).unwrap()[0];
        let native_companion = native.argument_source_proc_id(&native_arg).unwrap() as usize;
        let actual_code =
            byond_dmb::bytecode::decode(output.proc_code_words(companion).unwrap()).unwrap();
        let native_code =
            byond_dmb::bytecode::decode(native.proc_code_words(native_companion).unwrap()).unwrap();
        assert_eq!(
            actual_code
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            native_code
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>()
        );
        output.validate_references().unwrap();
    }

    #[test]
    fn interpolated_string_interns_native_template_bytes() {
        let source = "/proc/greet(name)\n    return \"Hello [name]\"\n";
        let (output, emitted) = emit_global_procs(source, BUILTINS, "greeting").unwrap();
        assert_eq!(emitted.len(), 1);
        assert!(output
            .strings
            .iter()
            .any(|string| string.data == b"Hello \xff\x01"));
        output.validate_references().unwrap();
    }

    #[test]
    fn file_dir_resolution_matches_native_rsc_assets() {
        use byond_dmb::rsc::{read_all, Entry};
        let root =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/file_dir");
        let project = root.join("probe.dme");
        let source = dm_preprocess::preprocess_project(
            &project,
            &dm_preprocess::FileSystem,
            &BTreeMap::new(),
        );
        assert!(source.diagnostics.is_empty(), "{:?}", source.diagnostics);
        assert_eq!(
            source.file_dirs,
            ["first", "second", "gen"].map(std::path::PathBuf::from)
        );
        let maps = crate::maps::MapSet {
            files: Vec::new(),
            fingerprint: [0; 32],
        };
        let generated = load_resource_set_with_maps_skins_and_dirs(
            &project,
            &source.text,
            &maps,
            &[],
            &source.file_dirs,
        )
        .unwrap();
        let native = include_bytes!("../../../fixtures/native_compiler/file_dir/probe.native.rsc");
        let native = read_all(&mut native.as_slice()).unwrap();
        for entry in native {
            let Entry::Named(native) = entry else {
                continue;
            };
            let name = String::from_utf8(native.name.clone()).unwrap();
            let actual = generated
                .inputs
                .iter()
                .find(|input| input.archive_name == name)
                .unwrap();
            assert_eq!(
                actual.named.asset_bytes().unwrap(),
                native.asset_bytes().unwrap(),
                "{name}"
            );
        }
    }

    #[test]
    fn undef_file_dir_resource_resolution_matches_native_rsc() {
        use byond_dmb::rsc::{read_all, Entry};
        let root =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/file_dir");
        let project = root.join("undef.dme");
        let source = dm_preprocess::preprocess_project(
            &project,
            &dm_preprocess::FileSystem,
            &BTreeMap::new(),
        );
        assert!(source.diagnostics.is_empty());
        assert_eq!(source.file_dirs, [std::path::PathBuf::from("first")]);
        let maps = crate::maps::MapSet {
            files: Vec::new(),
            fingerprint: [0; 32],
        };
        let generated = load_resource_set_with_maps_skins_and_dirs(
            &project,
            &source.text,
            &maps,
            &[],
            &source.file_dirs,
        )
        .unwrap();
        let native = include_bytes!("../../../fixtures/native_compiler/file_dir/undef.native.rsc");
        for entry in read_all(&mut native.as_slice()).unwrap() {
            let Entry::Named(native) = entry else {
                continue;
            };
            let name = String::from_utf8(native.name.clone()).unwrap();
            let actual = generated
                .inputs
                .iter()
                .find(|input| input.archive_name == name)
                .unwrap();
            assert_eq!(
                actual.named.asset_bytes().unwrap(),
                native.asset_bytes().unwrap(),
                "{name}"
            );
        }
    }
    #[test]
    fn incremental_outline_preserves_declaration_abi_for_safe_body_edits() {
        let before =
            "/datum/outline\n    var/value = 2\n    proc/run(x)\n        return x + value\n";
        let after = before.replace("x + value", "x * value + 1");
        let left = incremental_source_outline(before).unwrap();
        let right = incremental_source_outline(&after).unwrap();
        assert_eq!(left.abi_digest, right.abi_digest);
        assert!(left.procedures["/datum/outline/proc/run"].patchable);
        assert_ne!(
            left.procedures["/datum/outline/proc/run"].digest,
            right.procedures["/datum/outline/proc/run"].digest
        );
        assert_ne!(
            left.abi_digest,
            incremental_source_outline(&before.replace("value = 2", "value = 3"))
                .unwrap()
                .abi_digest
        );
        assert_ne!(
            left.abi_digest,
            incremental_source_outline(&before.replace("run(x)", "run(x, y)"))
                .unwrap()
                .abi_digest
        );
    }

    #[test]
    fn incremental_outline_guards_initializers_metadata_and_duplicate_definitions() {
        for source in [
            "/proc/run(x = 1)\n    return x\n",
            "/proc/run()\n    var/static/value = 1\n    return value\n",
            "/proc/run()\n    set waitfor = 0\n    return 1\n",
            "/datum/test/run()\n    return 1\n/datum/test/run()\n    return 2\n",
        ] {
            let original = incremental_source_outline(source).unwrap();
            assert!(original.procedures.values().all(|entry| !entry.patchable));
            let changed = incremental_source_outline(
                &source
                    .replace("return 1", "return 3")
                    .replace("return x", "return x + 1")
                    .replace("return value", "return value + 1")
                    .replace("return 2", "return 4"),
            )
            .unwrap();
            assert_ne!(original.abi_digest, changed.abi_digest);
        }
    }

    #[test]
    fn incremental_checkpoint_restores_inherited_owner_fields_without_per_proc_copies() {
        let source = "/datum/incremental_base\n    var/datum/typed\n    var/value = 3\n/datum/incremental_base/child/proc/run(x)\n    return value + x\n";
        let mut cache = crate::lower_cache::ProcLoweringCache::disabled();
        let mut capture = None;
        let (dmb, _, _) = emit_global_procs_mode(
            source,
            include_bytes!("../../../fixtures/native_template.bin"),
            "incremental",
            None,
            &mut cache,
            None,
            Some(&mut capture),
        )
        .unwrap();
        let checkpoint = capture.unwrap();
        let proc = &checkpoint.procedures["/datum/incremental_base/child/proc/run"];
        assert!(proc.patchable);
        assert!(proc.bindings.fields.is_empty());
        assert!(proc.bindings.field_types.is_empty());
        assert!(proc.bindings.shared.is_none());
        let mut restored = proc.bindings.clone();
        restored.shared = Some(Arc::new(checkpoint.shared));
        restore_owner_bindings(&dmb, &proc.owner_path, &mut restored).unwrap();
        assert!(restored.fields.contains("value"));
        assert_eq!(
            restored.field_types.get("typed").map(String::as_str),
            Some("/datum")
        );
        assert_eq!(restored.parameters, ["x"]);
    }
    #[test]
    fn raw_constant_strings_preserve_native_bytes_and_concatenation() {
        let source =
            include_str!("../../../fixtures/native_compiler/raw_constant_strings/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/raw_constant_strings/probe.native.bin"
        ))
        .unwrap();
        let (generated, _) = emit_global_procs(
            source,
            include_bytes!("../../../fixtures/native_template.bin"),
            "raw",
        )
        .unwrap();
        for name in ["double_quote", "single_quote", "concat"] {
            let value = |dmb: &Dmb| {
                let variable = dmb
                    .variables
                    .iter()
                    .find(|var| dmb.string(var.name) == Some(name.as_bytes()) && var.kind == 6)
                    .unwrap();
                dmb.string(variable.value).unwrap().to_vec()
            };
            assert_eq!(value(&generated), value(&native), "{name}");
        }
        assert_eq!(
            const_eval::evaluate("@\"[literal]\\n\"", |_| None),
            Some(const_eval::Constant::Text("[literal]\\n".into()))
        );
    }
    #[test]
    fn global_and_class_initializers_wait_for_callees_like_native() {
        let source = include_str!("../../../fixtures/native_compiler/initializer_order/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/initializer_order/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "initializer_flags").unwrap();
        assert_eq!(
            output.procs[output.world.global_initializer_proc_id() as usize].effective_flags(),
            native.procs[native.world.global_initializer_proc_id() as usize].effective_flags()
        );
        for path in ["/datum/order_base", "/datum/order_base/child"] {
            let initial = |image: &Dmb| {
                image
                    .classes
                    .iter()
                    .find(|class| image.string(class.path_string_id()) == Some(path.as_bytes()))
                    .unwrap()
                    .initializer_proc_id()
            };
            assert_eq!(
                output.procs[initial(&output) as usize].effective_flags(),
                native.procs[initial(&native) as usize].effective_flags(),
                "{path}"
            );
        }
    }
    #[test]
    fn typed_global_members_bypass_null_receivers_like_native() {
        let source = include_str!("../../../fixtures/native_compiler/null_global_member/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/null_global_member/probe.native.bin"
        ))
        .unwrap();
        let (output, emitted) = emit_global_procs(source, BUILTINS, "null_members").unwrap();
        for path in ["/proc/read", "/proc/write"] {
            let actual = emitted.iter().find(|proc| proc.path == path).unwrap();
            let expected = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let a = byond_dmb::bytecode::decode(&actual.words).unwrap();
            let b = byond_dmb::bytecode::decode(native.proc_code_words(expected).unwrap()).unwrap();
            assert_eq!(
                a.iter().map(|i| i.opcode).collect::<Vec<_>>(),
                b.iter().map(|i| i.opcode).collect::<Vec<_>>(),
                "{path}"
            );
            for (actual, expected) in a.iter().zip(&b) {
                if expected.operands.first() == Some(&0xffdb) {
                    assert_eq!(actual.operands.first(), Some(&0xffdb));
                    assert_eq!(
                        output.string(output.variables[actual.operands[1] as usize].name),
                        native.string(native.variables[expected.operands[1] as usize].name)
                    );
                }
            }
        }
        let audit = audit_lowering(source, 1024 * 1024, BUILTINS).unwrap();
        assert_eq!(audit.failed, 0, "{:?}", audit.groups);
    }

    #[test]
    fn literal_list_initializers_precede_dynamic_calls_in_native_order() {
        let source =
            include_str!("../../../fixtures/native_compiler/initializer_categories/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/initializer_categories/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "phased_initializers").unwrap();
        let targets = |image: &Dmb| {
            byond_dmb::bytecode::decode(
                image
                    .proc_code_words(image.world.global_initializer_proc_id() as usize)
                    .unwrap(),
            )
            .unwrap()
            .iter()
            .filter(|instruction| {
                instruction.opcode == opcode::SET_VAR
                    && instruction.operands.first() == Some(&0xffdb)
            })
            .map(|instruction| {
                image
                    .string(image.variables[instruction.operands[1] as usize].name)
                    .unwrap()
                    .to_vec()
            })
            .collect::<Vec<_>>()
        };
        assert_eq!(targets(&output), targets(&native));
    }

    #[test]
    fn procedure_statics_preserve_source_order_across_nested_owners() {
        let source = "/proc/cache_value()\n    return list(7)\n/proc/early()\n    var/static/list/declared_counts = cache_value()\n/world\n    proc/late()\n        var/static/genesis_result = cache_value()\n";
        let (output, _) = emit_global_procs(source, BUILTINS, "static_order").unwrap();
        let instructions = byond_dmb::bytecode::decode(
            output
                .proc_code_words(output.world.global_initializer_proc_id() as usize)
                .unwrap(),
        )
        .unwrap();
        let names = instructions
            .iter()
            .filter(|instruction| {
                instruction.opcode == opcode::SET_VAR
                    && instruction.operands.first() == Some(&0xffdb)
            })
            .map(|instruction| {
                output
                    .string(output.variables[instruction.operands[1] as usize].name)
                    .unwrap()
                    .to_vec()
            })
            .collect::<Vec<_>>();
        assert_eq!(
            names,
            vec![b"declared_counts".to_vec(), b"genesis_result".to_vec()]
        );
    }

    #[test]
    fn included_manifest_static_order_matches_native() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/native_compiler/manifest_static_order");
        let source = dm_preprocess::preprocess_project(
            &root.join("probe.dme"),
            &dm_preprocess::FileSystem,
            &BTreeMap::new(),
        );
        assert!(source.diagnostics.is_empty());
        let (output, _) = emit_global_procs(&source.text, BUILTINS, "manifest_order").unwrap();
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/manifest_static_order/probe.native.bin"
        ))
        .unwrap();
        let values = |image: &Dmb| {
            byond_dmb::bytecode::decode(
                image
                    .proc_code_words(image.world.global_initializer_proc_id() as usize)
                    .unwrap(),
            )
            .unwrap()
            .into_iter()
            .filter(|instruction| instruction.opcode == opcode::PUSH_INT)
            .map(|instruction| instruction.operands[0])
            .collect::<Vec<_>>()
        };
        assert_eq!(values(&native), vec![1, 2, 3]);
        assert_eq!(values(&output), values(&native));
    }

    #[test]
    fn procedure_static_context_constants_use_declaring_procedure() {
        let source = include_str!("../../../fixtures/native_compiler/static_proc_context/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/static_proc_context/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "static_context").unwrap();
        for name in [b"p".as_slice(), b"t".as_slice()] {
            let actual = output
                .variables
                .iter()
                .rev()
                .find(|var| output.string(var.name) == Some(name))
                .unwrap();
            let expected = native
                .variables
                .iter()
                .rev()
                .find(|var| native.string(var.name) == Some(name))
                .unwrap();
            assert_eq!(actual.kind, expected.kind);
            if actual.kind == 38 {
                assert_eq!(
                    output.string(output.procs[actual.value as usize].strings[0]),
                    native.string(native.procs[expected.value as usize].strings[0])
                );
            } else {
                assert_eq!(
                    output.string(output.classes[actual.value as usize].path_string_id()),
                    native.string(native.classes[expected.value as usize].path_string_id())
                );
            }
        }
        let source = "/proc/register_type(value)\n    return value\n/datum/static_context/proc/current()\n    var/static/registered = register_type(__TYPE__)\n";
        let (image, _) = emit_global_procs(source, BUILTINS, "dynamic_context").unwrap();
        let code = image
            .proc_code_words(image.world.global_initializer_proc_id() as usize)
            .unwrap();
        let class = image
            .classes
            .iter()
            .position(|class| {
                image.string(class.path_string_id()) == Some(b"/datum/static_context".as_slice())
            })
            .unwrap() as u32;
        assert!(code
            .windows(3)
            .any(|words| words == [opcode::PUSH_VAL, 32, class]));
    }

    #[test]
    fn forward_parent_procedure_metadata_matches_native() {
        for (setting, expected) in [
            ("set src = usr", (32, 255, 6)),
            ("set src in usr", (8, 127, 4)),
        ] {
            let parsed = parse(&format!("/proc/probe()\n    {setting}\n"));
            let metadata = proc_metadata(&parsed.items[0].children, None).unwrap().0;
            assert_eq!(
                (
                    metadata.source_kind,
                    metadata.source_parameter,
                    metadata.flags
                ),
                expected
            );
        }
        let source =
            include_str!("../../../fixtures/native_compiler/forward_proc_metadata/probe.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/forward_proc_metadata/probe.native.bin"
        ))
        .unwrap();
        let (output, _) = emit_global_procs(source, BUILTINS, "forward_metadata").unwrap();
        for path in [
            b"/datum/parent/child/action".as_slice(),
            b"/datum/parent/proc/action".as_slice(),
        ] {
            let actual = output
                .procs
                .iter()
                .find(|proc| output.string(proc.strings[0]) == Some(path))
                .unwrap();
            let expected = native
                .procs
                .iter()
                .find(|proc| native.string(proc.strings[0]) == Some(path))
                .unwrap();
            assert_eq!(actual.effective_flags(), expected.effective_flags());
            assert_eq!(
                (actual.source_kind, actual.source_parameter),
                (expected.source_kind, expected.source_parameter)
            );
            for slot in 1..=3 {
                assert_eq!(
                    output.string(actual.strings[slot]),
                    native.string(expected.strings[slot])
                );
            }
        }
    }
}
