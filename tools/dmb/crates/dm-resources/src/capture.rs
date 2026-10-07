//! Filesystem capture for qualified immutable resource queries.
//!
//! Only this boundary reads candidate files. Search order matches the preserved
//! compiler: project-direct first, then terminal FILE_DIR roots in reverse order.
//! Raw payload encoding requires explicit caller certification; storage support
//! in ResourceSet alone does not certify DreamMaker's resource transformations.
use crate::native_resolver::{
    CapturedResourceLookup, CapturedResourceOutcome, CapturedSearchContext, NativeResourceResolver,
};
use crate::{ResourceInput, ResourceRequest, ResourceSet};
use dm_preprocess::regions::{DirectivePlan, ExpandedRegions};
use dm_syntax::{Span, SpanToken, TokenKind};
use sha2::{Digest, Sha256};
use std::collections::{BTreeSet, HashMap};
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

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
    pub unsupported: Vec<UnsupportedResource>,
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
    fn read_candidate(&self, path: &Path) -> io::Result<Option<Arc<[u8]>>>;
}
pub struct FileSystemCapture;
impl CaptureProvider for FileSystemCapture {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<Arc<[u8]>>> {
        match std::fs::metadata(path) {
            Ok(metadata) if !metadata.is_file() => return Ok(None),
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        }
        // Disappearance after observing a file is an IO failure, not a fabricated
        // negative snapshot of a candidate that was never captured.
        std::fs::read(path).map(|bytes| Some(Arc::from(bytes)))
    }
}

pub fn capture_expanded<P: CaptureProvider>(
    plan: &DirectivePlan,
    expanded: &ExpandedRegions,
    config: CaptureConfig<'_>,
    provider: &P,
) -> Result<CapturedResources, CaptureError> {
    if !plan.diagnostics.is_empty()
        || !expanded.diagnostics.is_empty()
        || !expanded.lexical_diagnostics.is_empty()
    {
        return Err(CaptureError::Invalid(
            "resource capture requires successful directive/expansion output".into(),
        ));
    }
    let literals = discover_literals(&expanded.text)?;
    let root = normalize(&plan.project_dir);
    let directories = plan
        .file_dirs
        .iter()
        .map(|directory| normalize(&root.join(directory)))
        .collect::<Vec<_>>();
    let context = search_context(&root, &directories)?;
    let mut capture = Capture {
        provider,
        config,
        files: HashMap::new(),
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
        unsupported: capture.unsupported,
    })
}
struct Capture<'a, P> {
    provider: &'a P,
    config: CaptureConfig<'a>,
    files: HashMap<PathBuf, Option<Arc<[u8]>>>,
    inputs: Vec<ResourceInput>,
    aliases: HashMap<String, usize>,
    observations: Vec<CandidateObservation>,
    unsupported: Vec<UnsupportedResource>,
}
impl<P: CaptureProvider> Capture<'_, P> {
    fn read(&mut self, path: &Path) -> Result<Option<Arc<[u8]>>, CaptureError> {
        let bytes = match self.files.get(path) {
            Some(bytes) => bytes.clone(),
            None => {
                let bytes =
                    self.provider
                        .read_candidate(path)
                        .map_err(|source| CaptureError::Io {
                            path: path.to_owned(),
                            source,
                        })?;
                self.files.insert(path.to_owned(), bytes.clone());
                bytes
            }
        };
        self.observations.push(CandidateObservation {
            path: path.to_owned(),
            outcome: match &bytes {
                None => CandidateOutcome::Missing,
                Some(bytes) => CandidateOutcome::Captured {
                    digest: Sha256::digest(bytes).into(),
                    length: bytes.len(),
                },
            },
        });
        Ok(bytes)
    }
    fn add(
        &mut self,
        request: ResourceRequest,
        bytes: Arc<[u8]>,
        span: Option<Span>,
    ) -> Result<CapturedResourceOutcome, CaptureError> {
        let encoded = self.config.encoded.iter().find(|input| {
            input.input.archive_name == request.archive_name
                && normalize(&input.input.disk_path) == request.disk_path
        });
        let input = if let Some(encoded) = encoded {
            // Encoded payload may legitimately differ from source bytes. These
            // records must be supplied by the current encoding capture stage.
            if encoded.source_digest != <[u8; 32]>::from(Sha256::digest(&bytes)) {
                return Err(CaptureError::Invalid(
                    "encoded resource did not consume the current source payload".into(),
                ));
            }
            encoded.input.clone()
        } else if self.config.policy.raw_supported(&request.archive_name) {
            ResourceInput {
                content_digest: Sha256::digest(&bytes).into(),
                named: byond_dmb::rsc::NamedResource::from_data(
                    crate::kind_for_name(&request.archive_name).as_byte(),
                    request.archive_name.as_bytes().to_vec(),
                    bytes.to_vec(),
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
            || input.content_digest != <[u8; 32]>::from(Sha256::digest(payload))
            || input.named.id
                != input
                    .named
                    .content_id()
                    .map_err(|error| CaptureError::Invalid(error.to_string()))?
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
    let lexed = dm_syntax::lex_spans(source);
    if let Some(error) = lexed.diagnostics.first() {
        return Err(CaptureError::Source {
            span: error.span,
            reason: format!("{:?}", error.kind),
        });
    }
    let mut found = Vec::new();
    collect_tokens(source, &lexed.tokens, 0, &mut found)?;
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
                let expression = &text[start..end];
                let parsed = dm_syntax::parse_expression(expression);
                if !parsed.diagnostics.is_empty() || parsed.expr.is_none() {
                    return Err(CaptureError::UnsupportedExpression {
                        span: Span {
                            start: base + start,
                            end: base + end,
                        },
                        reason:
                            "string interpolation expression is unsupported by the syntax parser",
                    });
                }
                let lexed = dm_syntax::lex_spans(expression);
                collect_tokens(expression, &lexed.tokens, base + start, found)?;
                at = end + 1;
            }
            _ => at += 1,
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    struct Memory {
        files: HashMap<PathBuf, Arc<[u8]>>,
        reads: RefCell<Vec<PathBuf>>,
    }
    impl CaptureProvider for Memory {
        fn read_candidate(&self, path: &Path) -> io::Result<Option<Arc<[u8]>>> {
            self.reads.borrow_mut().push(path.to_owned());
            Ok(self.files.get(path).cloned())
        }
    }
    fn memory(files: &[(&str, &[u8])]) -> Memory {
        Memory {
            files: files
                .iter()
                .map(|(name, bytes)| (PathBuf::from(name), Arc::from(*bytes)))
                .collect(),
            reads: RefCell::new(vec![]),
        }
    }
    fn plan() -> DirectivePlan {
        DirectivePlan {
            project_dir: PathBuf::from("game"),
            file_dirs: vec![PathBuf::from("early"), PathBuf::from("late")],
            ..Default::default()
        }
    }
    fn expanded(source: &str) -> ExpandedRegions {
        ExpandedRegions {
            text: source.into(),
            ..Default::default()
        }
    }
    fn policy() -> CapturePolicy {
        CapturePolicy {
            certified_raw_extensions: BTreeSet::from(["txt".into()]),
        }
    }
    #[test]
    fn grammar_discovers_only_resource_tokens_and_parsed_interpolation() {
        let source="/proc/p()\n    // 'comment.txt'\n    var/a = @\"['raw.txt']\"\n    var/b = \"plain 'text.txt' [icon('embedded.txt')] [\"nested [file('deep.txt')]\"]\"\n    return 'direct.txt'\n";
        let found = discover_literals(source).unwrap();
        assert_eq!(
            found
                .iter()
                .map(|literal| literal.path.as_str())
                .collect::<Vec<_>>(),
            ["embedded.txt", "deep.txt", "direct.txt"]
        );
        for literal in &found {
            assert_eq!(&source[literal.span.range()], format!("'{}'", literal.path));
        }
    }
    #[test]
    fn terminal_roots_use_project_then_reverse_stack_and_record_negatives() {
        let provider = memory(&[
            ("game/late/found.txt", b"late"),
            ("game/early/found.txt", b"early"),
            ("game/direct.txt", b"direct"),
            ("game/late/direct.txt", b"shadowed"),
        ]);
        let source = expanded(
            "/proc/p()\n    return list('found.txt','direct.txt','missing.txt','found.txt')\n",
        );
        let policy = policy();
        let captured = capture_expanded(
            &plan(),
            &source,
            CaptureConfig {
                policy: &policy,
                encoded: &[],
                additional: &[],
            },
            &provider,
        )
        .unwrap();
        assert_eq!(
            captured
                .resources
                .inputs
                .iter()
                .map(|input| input.archive_name.as_str())
                .collect::<Vec<_>>(),
            ["found.txt", "direct.txt"]
        );
        assert_eq!(
            captured.resources.inputs[0].named.asset_bytes().unwrap(),
            b"late"
        );
        assert_eq!(captured.lookups.len(), 3);
        assert_eq!(
            captured.lookups[2].outcome,
            CapturedResourceOutcome::Missing
        );
        assert_eq!(
            provider.reads.borrow().as_slice(),
            [
                PathBuf::from("game/found.txt"),
                PathBuf::from("game/late/found.txt"),
                PathBuf::from("game/direct.txt"),
                PathBuf::from("game/missing.txt"),
                PathBuf::from("game/late/missing.txt"),
                PathBuf::from("game/early/missing.txt")
            ]
        );
        assert!(matches!(
            captured.observations[0].outcome,
            CandidateOutcome::Missing
        ));
    }
    #[test]
    fn unknown_transformation_is_unsupported_not_raw_or_missing() {
        let provider = memory(&[("game/picture.png", b"not silently raw")]);
        let policy = CapturePolicy::default();
        let captured = capture_expanded(
            &plan(),
            &expanded("/proc/p()\n    return 'picture.png'\n"),
            CaptureConfig {
                policy: &policy,
                encoded: &[],
                additional: &[],
            },
            &provider,
        )
        .unwrap();
        assert_eq!(
            captured.lookups[0].outcome,
            CapturedResourceOutcome::Unsupported
        );
        assert!(captured.resources.inputs.is_empty());
        assert!(captured.require_complete().is_err());
    }
    #[test]
    fn encoded_record_requires_current_source_digest_and_retains_encoded_bytes() {
        let provider = memory(&[("game/picture.png", b"source")]);
        let named = byond_dmb::rsc::NamedResource::from_data(
            6,
            b"picture.png".to_vec(),
            b"encoded".to_vec(),
            0,
            0,
        )
        .unwrap();
        let mut encoded = [EncodedResourceInput {
            input: ResourceInput {
                archive_name: "picture.png".into(),
                disk_path: PathBuf::from("game/picture.png"),
                content_digest: Sha256::digest(b"encoded").into(),
                named,
            },
            source_digest: Sha256::digest(b"source").into(),
        }];
        let policy = CapturePolicy::default();
        let source = expanded("/proc/p()\n    return 'picture.png'\n");
        let result = capture_expanded(
            &plan(),
            &source,
            CaptureConfig {
                policy: &policy,
                encoded: &encoded,
                additional: &[],
            },
            &provider,
        )
        .unwrap();
        assert_eq!(
            result.resources.inputs[0].named.asset_bytes().unwrap(),
            b"encoded"
        );
        encoded[0].source_digest = [0; 32];
        assert!(matches!(
            capture_expanded(
                &plan(),
                &source,
                CaptureConfig {
                    policy: &policy,
                    encoded: &encoded,
                    additional: &[]
                },
                &provider
            ),
            Err(CaptureError::Invalid(_))
        ));
    }
    #[test]
    fn candidate_io_failure_never_becomes_a_negative_lookup() {
        struct Denied;
        impl CaptureProvider for Denied {
            fn read_candidate(&self, _: &Path) -> io::Result<Option<Arc<[u8]>>> {
                Err(io::Error::new(io::ErrorKind::PermissionDenied, "denied"))
            }
        }
        let policy = policy();
        assert!(
            matches!(capture_expanded(&plan(),&expanded("/proc/p()\n    return 'x.txt'\n"),CaptureConfig {policy:&policy,encoded:&[],additional:&[]},&Denied),Err(CaptureError::Io {source,..}) if source.kind()==io::ErrorKind::PermissionDenied)
        );
    }
}
