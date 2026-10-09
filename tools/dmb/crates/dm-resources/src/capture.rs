//! Filesystem capture for qualified immutable resource queries.
//!
//! Only this boundary reads candidate files. Search order matches the preserved
//! compiler: project-direct first, then terminal FILE_DIR roots in reverse order.
//! Raw payload encoding requires explicit caller certification; storage support
//! in ResourceSet alone does not certify DreamMaker's resource transformations.
use crate::native_resolver::{
    CapturedResourceLookup, CapturedResourceOutcome, CapturedSearchContext, NativeResourceResolver,
};
use crate::SharedBytes;
use std::sync::Arc;
use crate::{ResourceInput, ResourceRequest, ResourceSet};
use dm_preprocess::regions::{DirectivePlan, ExpandedRegions};
use dm_syntax::{Span, SpanToken, TokenKind};
use sha2::{Digest, Sha256};
use std::collections::{BTreeSet, HashMap};
use std::io;
use std::path::{Component, Path, PathBuf};
mod parallel;
pub use parallel::capture_discovered_on_executor;

/// There are deliberately no default certified extensions. The driver supplies
/// its paired encoding evidence, or supplies an already encoded captured record.
#[derive(Clone, Debug, Default)]
pub struct CapturePolicy {
    pub certified_raw_extensions: BTreeSet<String>,
}
impl CapturePolicy {
    fn raw_supported(&self, name: &str) -> bool {
        let extension = Path::new(name)
            .extension()
            .and_then(|part| part.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        self.certified_raw_extensions.contains(&extension)
    }
}
/// An encoded payload is bound to the exact current source capture. The encoder
/// supplies its output record and the digest of bytes it actually consumed.
#[derive(Clone, Debug)]
pub struct EncodedResourceInput {
    pub input: ResourceInput,
    pub source_digest: [u8; 32],
}
/// Already encoded inputs are explicit authoritative records for this capture,
/// not an old archive hint. The resolver validates their exact payload/ID/digest.
#[derive(Clone, Copy)]
pub struct CaptureConfig<'a> {
    pub policy: &'a CapturePolicy,
    pub encoded: &'a [EncodedResourceInput],
    /// Extra ordered assets discovered by map/skin consumers, after source literals.
    pub additional: &'a [ResourceRequest],
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LiteralRequest {
    pub path: String,
    pub span: Span,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CandidateOutcome {
    Missing,
    Captured { digest: [u8; 32], length: usize },
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CandidateObservation {
    pub path: PathBuf,
    pub outcome: CandidateOutcome,
}
#[derive(Clone, Debug)]
pub struct UnsupportedResource {
    pub path: String,
    pub span: Option<Span>,
    pub reason: &'static str,
}
pub struct CapturedResources {
    pub resources: ResourceSet,
    pub context: CapturedSearchContext,
    pub lookups: Vec<CapturedResourceLookup>,
    pub observations: Vec<CandidateObservation>,
    pub literals: Vec<LiteralRequest>,
    /// Prefix captured from expanded source; following literals use map/skin
    /// source coordinates and cannot be queried as expanded-source spans.
    pub source_literal_count: usize,
    pub unsupported: Vec<UnsupportedResource>,
}
/// Current grammar demands and terminal search policy, without resource reads.
pub struct ResourceDemand {
    pub context: CapturedSearchContext,
    pub literals: Vec<LiteralRequest>,
    pub source_literal_count: usize,
    pub additional: Vec<ResourceRequest>,
    root: PathBuf,
    directories: Vec<PathBuf>,
}
pub fn discover_demand(
    plan: &DirectivePlan,
    expanded: &ExpandedRegions,
    extra: &[LiteralRequest],
    additional: &[ResourceRequest],
) -> Result<ResourceDemand, CaptureError> {
    if !plan.diagnostics.is_empty()
        || !expanded.diagnostics.is_empty()
        || !expanded.lexical_diagnostics.is_empty()
    {
        return Err(CaptureError::Invalid(
            "resource capture requires successful directive/expansion output".into(),
        ));
    }
    let mut literals = discover_literals(&expanded.text)?;
    let source_literal_count = literals.len();
    literals.extend_from_slice(extra);
    let root = normalize(&plan.project_dir);
    let directories = plan
        .file_dirs
        .iter()
        .map(|directory| normalize(&root.join(directory)))
        .collect::<Vec<_>>();
    let context = search_context(&root, &directories)?;
    Ok(ResourceDemand {
        context,
        literals,
        source_literal_count,
        additional: additional.to_vec(),
        root,
        directories,
    })
}
impl CapturedResources {
    /// Output assembly must require completeness even for extra map/skin assets
    /// that are not demanded through a source ResourceIn query.
    pub fn require_complete(&self) -> io::Result<()> {
        if self.unsupported.is_empty() {
            Ok(())
        } else {
            Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "resource capture contains unsupported payload transformations",
            ))
        }
    }
    /// Compose captured records without reopening or rewriting any RSC archive.
    pub fn into_resolver<R: dm_ir::Resolver>(
        self,
        tree: R,
        symbols: &dm_ir::SymbolTable,
    ) -> io::Result<NativeResourceResolver<R>> {
        NativeResourceResolver::from_captured(
            tree,
            symbols,
            self.resources,
            [self.context],
            self.lookups,
        )
    }
    pub fn into_resolver_shared<R: dm_ir::Resolver>(
        self,
        tree: R,
        symbols: Arc<dm_ir::SymbolTable>,
    ) -> io::Result<NativeResourceResolver<R>> {
        NativeResourceResolver::from_shared_symbols(
            tree,
            symbols,
            self.resources,
            [self.context],
            self.lookups,
        )
    }
}
#[derive(Debug)]
pub enum CaptureError {
    Source { span: Span, reason: String },
    UnsupportedExpression { span: Span, reason: &'static str },
    Io { path: PathBuf, source: io::Error },
    Invalid(String),
}
impl std::fmt::Display for CaptureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for CaptureError {}

/// A provider returns a snapshot payload or a genuine negative candidate.
/// Permission/decoding/storage errors must be Err, never negative or Unsupported.
pub trait CaptureProvider {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<SharedBytes>>;
}
pub struct FileSystemCapture;
impl CaptureProvider for FileSystemCapture {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<SharedBytes>> {
        match std::fs::metadata(path) {
            Ok(metadata) if !metadata.is_file() => return Ok(None),
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        }
        // Disappearance after observing a file is an IO failure, not a fabricated
        // negative snapshot of a candidate that was never captured.
        std::fs::read(path).map(|bytes| Some(SharedBytes::from(bytes)))
    }
}

pub fn capture_expanded<P: CaptureProvider>(
    plan: &DirectivePlan,
    expanded: &ExpandedRegions,
    config: CaptureConfig<'_>,
    provider: &P,
) -> Result<CapturedResources, CaptureError> {
    capture_expanded_with_literals(plan, expanded, config, &[], provider)
}
/// Append captured map/skin literal demands to the same source-qualified search
/// ledger. No second FILE_DIR resolution policy is introduced.
pub fn capture_expanded_with_literals<P: CaptureProvider>(
    plan: &DirectivePlan,
    expanded: &ExpandedRegions,
    config: CaptureConfig<'_>,
    extra_literals: &[LiteralRequest],
    provider: &P,
) -> Result<CapturedResources, CaptureError> {
    let demand = discover_demand(plan, expanded, extra_literals, config.additional)?;
    capture_discovered(demand, config, provider)
}
/// Consume one already-discovered demand without rediscovering expanded grammar.
/// The additional-input order and qualified search context must match capture.
pub fn capture_discovered<P: CaptureProvider>(
    demand: ResourceDemand,
    config: CaptureConfig<'_>,
    provider: &P,
) -> Result<CapturedResources, CaptureError> {
    capture_seeded(demand, config, provider, HashMap::new(), HashMap::new())
}

fn validate_demand(demand: &ResourceDemand, config: CaptureConfig<'_>) -> Result<(), CaptureError> {
    if demand.additional != config.additional {
        return Err(CaptureError::Invalid(
            "resource demand additional inputs differ from capture configuration".into(),
        ));
    }
    if demand.source_literal_count > demand.literals.len()
        || search_context(&demand.root, &demand.directories)?.bytes() != demand.context.bytes()
    {
        return Err(CaptureError::Invalid(
            "resource demand context or source prefix is inconsistent".into(),
        ));
    }
    Ok(())
}

fn capture_seeded<P: CaptureProvider>(
    demand: ResourceDemand,
    config: CaptureConfig<'_>,
    provider: &P,
    files: HashMap<PathBuf, CapturedCandidate>,
    failures: HashMap<PathBuf, CaptureError>,
) -> Result<CapturedResources, CaptureError> {
    validate_demand(&demand, config)?;
    let ResourceDemand {
        context,
        literals,
        source_literal_count,
        root,
        directories,
        ..
    } = demand;
    let mut capture = Capture {
        provider,
        config,
        files,
        failures,
        inputs: Vec::new(),
        aliases: HashMap::new(),
        observations: Vec::new(),
        unsupported: Vec::new(),
    };
    let mut lookups = Vec::new();
    let mut queried = HashMap::new();
    for literal in &literals {
        if queried.contains_key(&literal.path) {
            continue;
        }
        let alias = literal.path.replace('\\', "/");
        crate::validate_archive_name(&alias)
            .map_err(|error| CaptureError::Invalid(error.to_string()))?;
        let mut selected = None;
        for directory in std::iter::once(&root).chain(directories.iter().rev()) {
            let path = normalize(&directory.join(&alias));
            if let Some(bytes) = capture.read(&path)? {
                selected = Some((path, bytes));
                break;
            }
        }
        let outcome = match selected {
            None => CapturedResourceOutcome::Missing,
            Some((disk_path, bytes)) => capture.add(
                ResourceRequest {
                    archive_name: alias,
                    disk_path,
                },
                bytes,
                Some(literal.span),
            )?,
        };
        queried.insert(literal.path.clone(), outcome);
        lookups.push(CapturedResourceLookup {
            path: literal.path.clone(),
            search_context: context.identity(),
            outcome,
        });
    }
    for request in config.additional {
        crate::validate_archive_name(&request.archive_name)
            .map_err(|error| CaptureError::Invalid(error.to_string()))?;
        let path = normalize(&request.disk_path);
        let Some(bytes) = capture.read(&path)? else {
            return Err(CaptureError::Io {
                path,
                source: io::Error::new(
                    io::ErrorKind::NotFound,
                    "explicit resource input is missing",
                ),
            });
        };
        capture.add(
            ResourceRequest {
                archive_name: request.archive_name.clone(),
                disk_path: path,
            },
            bytes,
            None,
        )?;
    }
    let mut fingerprint = Sha256::new();
    fingerprint.update(b"dm-resources-v1\0");
    for input in &capture.inputs {
        let bytes = input
            .named
            .asset_bytes()
            .map_err(|source| CaptureError::Io {
                path: input.disk_path.clone(),
                source,
            })?;
        fingerprint.update((input.archive_name.len() as u64).to_le_bytes());
        fingerprint.update(input.archive_name.as_bytes());
        fingerprint.update((bytes.len() as u64).to_le_bytes());
        fingerprint.update(bytes);
    }
    Ok(CapturedResources {
        resources: ResourceSet {
            inputs: capture.inputs,
            fingerprint: fingerprint.finalize().into(),
        },
        context,
        lookups,
        observations: capture.observations,
        literals,
        source_literal_count,
        unsupported: capture.unsupported,
    })
}
#[derive(Clone)]
struct CapturedCandidate {
    bytes: Option<SharedBytes>,
    digest: Option<[u8; 32]>,
}
struct Capture<'a, P> {
    provider: &'a P,
    config: CaptureConfig<'a>,
    files: HashMap<PathBuf, CapturedCandidate>,
    failures: HashMap<PathBuf, CaptureError>,
    inputs: Vec<ResourceInput>,
    aliases: HashMap<String, usize>,
    observations: Vec<CandidateObservation>,
    unsupported: Vec<UnsupportedResource>,
}
impl<P: CaptureProvider> Capture<'_, P> {
    fn read(&mut self, path: &Path) -> Result<Option<SharedBytes>, CaptureError> {
        if let Some(error) = self.failures.remove(path) {
            return Err(error);
        }
        let CapturedCandidate { bytes, digest } = match self.files.get(path) {
            Some(captured) => captured.clone(),
            None => {
                let bytes =
                    self.provider
                        .read_candidate(path)
                        .map_err(|source| CaptureError::Io {
                            path: path.to_owned(),
                            source,
                        })?;
                let digest = bytes.as_ref().map(|bytes| Sha256::digest(bytes).into());
                self.files.insert(
                    path.to_owned(),
                    CapturedCandidate {
                        bytes: bytes.clone(),
                        digest,
                    },
                );
                CapturedCandidate { bytes, digest }
            }
        };
        self.observations.push(CandidateObservation {
            path: path.to_owned(),
            outcome: match &bytes {
                None => CandidateOutcome::Missing,
                Some(bytes) => CandidateOutcome::Captured {
                    digest: digest.ok_or_else(|| {
                        CaptureError::Invalid("captured resource has no source digest".into())
                    })?,
                    length: bytes.len(),
                },
            },
        });
        Ok(bytes)
    }
    fn add(
        &mut self,
        request: ResourceRequest,
        bytes: SharedBytes,
        span: Option<Span>,
    ) -> Result<CapturedResourceOutcome, CaptureError> {
        // add is reached only after read captured this immutable candidate.
        // Reuse its digest rather than hashing the same payload per alias twice.
        let source_digest = self
            .files
            .get(&request.disk_path)
            .and_then(|captured| captured.digest)
            .ok_or_else(|| {
                CaptureError::Invalid("resource input has no captured source digest".into())
            })?;
        let encoded = self.config.encoded.iter().find(|input| {
            input.input.archive_name == request.archive_name
                && normalize(&input.input.disk_path) == request.disk_path
        });
        let input = if let Some(encoded) = encoded {
            // Encoded payload may legitimately differ from source bytes. These
            // records must be supplied by the current encoding capture stage.
            if encoded.source_digest != source_digest {
                return Err(CaptureError::Invalid(
                    "encoded resource did not consume the current source payload".into(),
                ));
            }
            encoded.input.clone()
        } else if self.config.policy.raw_supported(&request.archive_name) {
            ResourceInput {
                content_digest: source_digest,
                named: crate::NamedResourceInput::from_shared_data(
                    crate::kind_for_name(&request.archive_name).as_byte(),
                    request.archive_name.as_bytes().to_vec(),
                    bytes.clone(),
                    0,
                    0,
                )
                .map_err(|source| CaptureError::Io {
                    path: request.disk_path.clone(),
                    source,
                })?,
                archive_name: request.archive_name.clone(),
                disk_path: request.disk_path.clone(),
            }
        } else {
            self.unsupported.push(UnsupportedResource {
                path: request.archive_name,
                span,
                reason:
                    "resource transformation has no captured encoder or explicit raw certification",
            });
            return Ok(CapturedResourceOutcome::Unsupported);
        };
        let payload = input
            .named
            .asset_bytes()
            .map_err(|error| CaptureError::Invalid(error.to_string()))?;
        if input.archive_name != request.archive_name
            || input.named.name != request.archive_name.as_bytes()
            // Raw records were constructed just above from these owned source
            // bytes. Recompute only caller-supplied encoder receipts here;
            // immutable resolver admission separately validates every record.
            || (encoded.is_some() && (input.content_digest != <[u8; 32]>::from(Sha256::digest(payload))
            || input.named.id
                != input
                    .named
                    .content_id()
                    .map_err(|error| CaptureError::Invalid(error.to_string()))?))
        {
            return Err(CaptureError::Invalid(
                "encoded resource output alias/digest/runtime identity is inconsistent".into(),
            ));
        }
        if let Some(&ordinal) = self.aliases.get(&request.archive_name) {
            let old = &self.inputs[ordinal];
            if old
                .named
                .asset_bytes()
                .map_err(|error| CaptureError::Invalid(error.to_string()))?
                != input
                    .named
                    .asset_bytes()
                    .map_err(|error| CaptureError::Invalid(error.to_string()))?
            {
                return Err(CaptureError::Invalid(
                    "one authored alias resolves to different captured payloads".into(),
                ));
            }
            return Ok(CapturedResourceOutcome::Found(ordinal));
        }
        let ordinal = self.inputs.len();
        self.aliases.insert(request.archive_name, ordinal);
        self.inputs.push(input);
        Ok(CapturedResourceOutcome::Found(ordinal))
    }
}

fn search_context(
    root: &Path,
    directories: &[PathBuf],
) -> Result<CapturedSearchContext, CaptureError> {
    let mut bytes = b"dm-terminal-resource-search-v1\0project-first/reverse-file-dir\0".to_vec();
    for path in std::iter::once(root).chain(directories.iter().map(PathBuf::as_path)) {
        let text = path
            .to_str()
            .ok_or_else(|| CaptureError::Invalid("resource search path is not UTF-8".into()))?
            .replace('\\', "/");
        bytes.extend_from_slice(&(text.len() as u64).to_le_bytes());
        bytes.extend_from_slice(text.as_bytes());
    }
    Ok(CapturedSearchContext::new(bytes))
}
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => match out.components().next_back() {
                Some(Component::Normal(_)) => {
                    out.pop();
                }
                Some(Component::RootDir | Component::Prefix(_)) => {}
                _ => out.push(".."),
            },
            component => out.push(component.as_os_str()),
        }
    }
    out
}

/// Resource tokens are selected by the DM lexer. Embedded string expressions
/// are bracket-delimited by lexical tokens and parsed before their tokens are
/// visited; arbitrary quoted string text never becomes a resource request.
pub fn discover_literals(source: &str) -> Result<Vec<LiteralRequest>, CaptureError> {
    let mut relevant = Vec::new();
    let diagnostics = dm_syntax::visit_tokens(source, |token| {
        if matches!(token.kind, TokenKind::Resource | TokenKind::String) {
            relevant.push(token);
        }
    });
    // Complete lexical validation precedes resource/interpolation admission,
    // including errors occurring after an earlier unsupported resource token.
    if let Some(error) = diagnostics.first() {
        return Err(CaptureError::Source {
            span: error.span,
            reason: format!("{:?}", error.kind),
        });
    }
    let mut found = Vec::new();
    collect_tokens(source, &relevant, 0, &mut found)?;
    Ok(found)
}
fn collect_tokens(
    source: &str,
    tokens: &[SpanToken],
    base: usize,
    found: &mut Vec<LiteralRequest>,
) -> Result<(), CaptureError> {
    for token in tokens {
        match token.kind {
            TokenKind::Resource => {
                let text = token.text(source);
                let path = &text[1..text.len() - 1];
                if path.contains(['\0', '\'', '[', ']']) {
                    return Err(CaptureError::UnsupportedExpression {span:Span {start:base+token.span.start,end:base+token.span.end},reason:"escaped/interpolated resource spelling requires a captured literal decoder"});
                }
                found.push(LiteralRequest {
                    path: path.into(),
                    span: Span {
                        start: base + token.span.start,
                        end: base + token.span.end,
                    },
                });
            }
            TokenKind::String => {
                collect_string(token.text(source), base + token.span.start, found)?
            }
            _ => {}
        }
    }
    Ok(())
}
fn collect_string(
    text: &str,
    base: usize,
    found: &mut Vec<LiteralRequest>,
) -> Result<(), CaptureError> {
    if text.starts_with('@') {
        return Ok(());
    }
    let mut at = if text.starts_with("{\"") { 2 } else { 1 };
    while at < text.len() {
        match text.as_bytes()[at] {
            b'\\' => at = (at + 2).min(text.len()),
            b'[' => {
                let start = at + 1;
                let lexed = dm_syntax::lex_spans(&text[start..]);
                let mut depth = 1;
                let mut end = None;
                for token in &lexed.tokens {
                    if token.kind != TokenKind::Punctuation {
                        continue;
                    }
                    match token.text(&text[start..]) {
                        "[" => depth += 1,
                        "]" => {
                            depth -= 1;
                            if depth == 0 {
                                end = Some(start + token.span.start);
                                break;
                            }
                        }
                        _ => {}
                    }
                }
                let end = end.ok_or_else(|| CaptureError::Source {
                    span: Span {
                        start: base + at,
                        end: base + text.len(),
                    },
                    reason: "unterminated string interpolation".into(),
                })?;
                // Resource discovery needs balanced lexical regions, not the
                // complete expression grammar. Lowering owns semantic parsing.
                // Reuse the existing lexical scan up to this interpolation's
                // closing bracket; nested strings recurse through collect_string.
                let count = lexed
                    .tokens
                    .iter()
                    .take_while(|token| token.span.end <= end - start)
                    .count();
                collect_tokens(&text[start..], &lexed.tokens[..count], base + start, found)?;
                at = end + 1;
            }
            _ => at += 1,
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
