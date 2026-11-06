//! Ordered DME/DM preprocessing with explicit dependencies and source maps.
//!
//! This is a prototype front end. Unsupported conditional syntax is diagnosed; it is never
//! silently interpreted as false. The source provider makes this usable with Salsa inputs,
//! in-memory fixtures, and the filesystem without hiding reads from the incremental engine.

use dm_syntax::{lex, lex_spans, quoted_end, Span, SpanToken, TokenKind};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Uncached include-region pipeline for the native-v2 compiler. The legacy
/// entrypoints below remain available solely for preserved baseline callers.
pub mod regions;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Diagnostic {
    pub path: PathBuf,
    pub line: usize,
    pub kind: DiagnosticKind,
    pub message: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum DiagnosticKind {
    Io,
    Include,
    Conditional,
    Macro,
    Directive,
    UserError,
    /// A native language/domain feature the prototype has not implemented.
    /// Never infer this classification from user-provided diagnostic wording.
    Unsupported,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Origin {
    pub output_line: usize,
    pub path: Arc<PathBuf>,
    pub source_line: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Unit {
    pub path: PathBuf,
    pub output_span: Span,
    pub source_lines: usize,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct PreprocessedProject {
    pub text: String,
    pub units: Vec<Unit>,
    /// Exact expanded content identities, in the same order as `units`.
    pub unit_digests: Vec<[u8; 32]>,
    pub origins: Vec<Origin>,
    pub dependencies: BTreeSet<PathBuf>,
    /// Active DMM includes in source order, after conditional evaluation.
    pub map_includes: Vec<PathBuf>,
    /// Active interface skins; these are assets rather than DM source.
    pub skin_includes: Vec<PathBuf>,
    /// Active FILE_DIR search roots in directive order. BYOND retains each
    /// definition rather than only the last macro value.
    pub file_dirs: Vec<PathBuf>,
    pub diagnostics: Vec<Diagnostic>,
    pub final_macros: BTreeMap<String, Macro>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
enum FileDirChange {
    Push(PathBuf, Macro),
    Pop,
}

#[derive(Clone, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
pub struct Macro {
    pub parameters: Option<Vec<String>>,
    pub variadic: bool,
    pub replacement: String,
}

/// Borrowed lookup keeps expansion independent of a concrete snapshot storage.
pub(crate) trait MacroLookup {
    fn initial_environment(&self) -> InitialEnvironment { InitialEnvironment::Native5161687 }
    /// The original directive evaluator buffers a condition; ordinary token
    /// iteration drains its output and therefore has no defined-name guard.
    fn condition_expansion(&self)->bool{false}
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)>;
    fn location_read(&self, _file: bool) {}
    fn contains_key(&self, name: &str) -> bool {
        self.get_key_value(name).is_some()
    }
    fn get(&self, name: &str) -> Option<&Macro> {
        self.get_key_value(name).map(|(_, definition)| definition)
    }
}
impl MacroLookup for BTreeMap<String, Macro> {
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)> {
        BTreeMap::get_key_value(self, name).map(|(name, definition)| (name.as_str(), definition))
    }
}

/// Immutable text paired with an opaque receipt issued by its source provider.
/// The receipt is deliberately not a content hash or filesystem stamp API.
#[derive(Clone)]
pub struct RetainedText {
    text: Arc<str>,
    identity: u128,
    receipt: Arc<dyn std::any::Any + Send + Sync>,
}
impl RetainedText {
    pub fn text(&self) -> &Arc<str> {
        &self.text
    }
    pub fn text_identity(&self) -> u128 {
        self.identity
    }
    pub fn issued<T: std::any::Any + Send + Sync>(text: Arc<str>, receipt: T) -> Self {
        let identity = xxhash_rust::xxh3::xxh3_128(text.as_bytes());
        Self {
            text,
            identity,
            receipt: Arc::new(receipt),
        }
    }
    pub fn receipt<T: std::any::Any>(&self) -> Option<&T> {
        self.receipt.downcast_ref()
    }
    /// Refresh a receipt after its provider has authenticated the same bytes.
    pub fn reissued<T: std::any::Any + Send + Sync>(&self, receipt: T) -> Self {
        Self {
            text: self.text.clone(),
            identity: self.identity,
            receipt: Arc::new(receipt),
        }
    }
}

/// Where a provider learns what changed between two input revisions (the session's query
/// database).
pub trait SourceChanges {
    fn revision(&self) -> u64;
    fn changes_since(&self, revision: u64) -> Option<Arc<BTreeSet<PathBuf>>>;
}

pub mod source_acquisition;
pub use source_acquisition::{
    AcquiredSource, SourceAcquisitionIdentity, SourceAcquisitionLease, SourceEncoding,
    SourcePreparationDemand,
};

mod initial_environment;
pub use initial_environment::InitialEnvironment;

/// Decision on the SAME genuinely opened/captured reader, before payload
/// size/admission/read/decode. Suppression is not absence or source EOF.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalRawOpenDecision{Read,Suppress}
pub enum OriginalRawReadOutcome{Absent,Suppressed,SourceOpenFailed(std::io::Error),Acquired(SourceAcquisitionLease)}
pub trait SourceProvider {
    /// Optional borrowed attempt observer. This descriptor issues no absence
    /// witness; only a genuine opaque root-failure loan plus recorder facts can.
    fn original_root_open_observer(&self)->Option<&dyn regions::OriginalRootOpenObserver>{None}

    /// Metadata-only path presence on the SAME recorder; no payload or source grant.
    fn path_presence_admitted(&self,_path:&Path,_work:&dyn crate::source_arena_credit::SourceArenaWork)->std::io::Result<bool>{Err(std::io::Error::new(std::io::ErrorKind::NotConnected,"provider cannot issue admitted path presence"))}

    /// Opt-in loan only from a concrete statically safe Original batch issuer.
    /// Generic and single-thread providers remain unissued; no unsafe Sync cast.
    fn original_batch_source(&self)->std::io::Result<Option<&(dyn SourceProvider+Sync)>> { Ok(None) }
    /// Exact initial macro dialect requested by this actual pipeline. This is
    /// configuration only; it cannot issue a current source or completed frame.
    fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::Native5161687}

    fn read(&self, path: &Path) -> Result<String, String>;
    /// Actual Original token demand bypasses native whole-line preparation.
    /// The caller supplies its existing input-family headroom and predecode
    /// admission. A max scalar alone is NOT an allocation/resource grant.
    /// Unsupported issuer is NotConnected; None is actual recorded absence.
    /// The Original driver must never fall back to Native preparation.
    fn original_raw_source_checked(&self,_path:&Path,_max_bytes:usize,_before_decode:&mut dyn FnMut(usize,bool,bool)->std::io::Result<()>)->std::io::Result<Option<SourceAcquisitionLease>>{Err(std::io::Error::new(std::io::ErrorKind::NotConnected,"provider cannot issue actual Original raw source"))}
    /// Both hooks belong to the actual raw issuer. Unknown providers must not
    /// implement this by calling an unadmitted read and funding it afterward.
    fn original_raw_source_admitted(&self,_path:&Path,_max_bytes:usize,_before_read:&mut dyn FnMut(usize)->std::io::Result<()>,_before_decode:&mut dyn FnMut(OriginalRawAllocationPlan<'_>)->std::io::Result<()>,_acquired:&mut dyn FnMut(&SourceAcquisitionLease)->std::io::Result<()>)->std::io::Result<Option<SourceAcquisitionLease>>{Err(std::io::Error::new(std::io::ErrorKind::NotConnected,"provider cannot issue pre-allocation admitted Original raw source"))}
    fn original_raw_source_open_admitted(&self,_path:&Path,_max_bytes:usize,_work:&dyn source_arena_credit::SourceArenaWork,_after_open:&mut dyn FnMut()->std::io::Result<OriginalRawOpenDecision>,_before_read:&mut dyn FnMut(usize)->std::io::Result<()>,_before_decode:&mut dyn FnMut(OriginalRawAllocationPlan<'_>)->std::io::Result<()>,_acquired:&mut dyn FnMut(&SourceAcquisitionLease)->std::io::Result<()>)->std::io::Result<OriginalRawReadOutcome>{Err(std::io::Error::new(std::io::ErrorKind::NotConnected,"provider cannot issue actual open-before-payload Original source"))}

    /// Lend raw bytes from that SAME current acquisition. No reconstruction,
    /// filesystem reopen, parser or PreparedSource is permitted at this seam.
    fn original_source_bytes<'a>(&'a self,_lease:&'a SourceAcquisitionLease)->std::io::Result<Option<&'a[u8]>>{Ok(None)}

    /// Optional primary read with original-byte provenance. Unknown providers
    /// retain existing compiler behavior; they grant no semantic parity proof.
    fn acquired_source(&self, _path: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(None)
    }
    /// Current already-authenticated lease for this exact source owner. Must
    /// never reread or fabricate provenance from decoded identity alone.
    fn source_acquisition(&self, _path: &Path, _text: &SourceText) -> Option<AcquiredSource> {
        None
    }

    /// Refresh a provider-issued immutable nontext capture. A provider must
    /// validate its receipt against current input facts before returning it.
    /// Ordinary providers decline and retain the existing read boundary.
    fn retained_nontext(
        &self,
        _path: &Path,
        _previous: Option<&RetainedText>,
    ) -> Result<Option<RetainedText>, String> {
        Ok(None)
    }

    /// Optional immutable lexical preparation of the same captured bytes that
    /// `read` returns. Directive interpretation and include selection stay ordered.
    fn prepared_source(
        &self,
        _path: &Path,
    ) -> Option<std::sync::Arc<regions::prepared_source::PreparedSource>> {
        None
    }

    /// A monotone token for the input state this provider serves (a query-database revision).
    /// A plan records it; a later request asks `changes_since` with it.
    fn revision(&self) -> Option<u64> {
        None
    }

    /// The files whose text may differ from what this provider served at `revision`, or `None`
    /// when it cannot say. Lets a planner re-plan only what changed instead of comparing every
    /// file it read.
    fn changes_since(&self, _revision: u64) -> Option<Arc<BTreeSet<PathBuf>>> {
        None
    }

    /// Identity of the exact text returned by the preceding read. Snapshot
    /// providers can reuse their recorded digest; ordinary providers hash bytes.
    fn fingerprint_read(&self, _path: &Path, source: &str) -> [u8; 32] {
        Sha256::digest(source.as_bytes()).into()
    }

    /// Exact source-content identity. Providers retaining a verified input snapshot
    /// can return its saved digest without cloning and hashing the entire source.
    fn fingerprint(&self, path: &Path) -> Result<[u8; 32], String> {
        self.read(path)
            .map(|source| Sha256::digest(source.as_bytes()).into())
    }
}

/// DM sources may contain legacy Windows-1252 bytes alongside UTF-8 text.
/// Preserve valid UTF-8 sequences and decode only invalid bytes as legacy text.
mod source_decode;
pub mod source_arena_credit;
pub use source_decode::{decode_source_bytes, decode_source_bytes_admitted, visit_decoded_source, DecodedSourcePiece};

pub fn read_source_file(path: &Path) -> std::io::Result<String> {
    fs::read(path).map(|bytes| decode_source_bytes(&bytes))
}

pub struct FileSystem;
impl SourceProvider for FileSystem {
    fn read(&self, path: &Path) -> Result<String, String> {
        read_source_file(path).map_err(|e| e.to_string())
    }
}

mod cache_items;
pub use cache_items::PreprocessCache;
use cache_items::*;

mod project_context;
use project_context::*;
pub use project_context::{preprocess_project, preprocess_project_cached};

mod source_lines;
use source_lines::*;
mod logical_arena;
mod source_text;
pub use source_text::{SourceText, SourceTextStorage, WeakSourceText};

mod macro_expansion;
use macro_expansion::*;

mod condition_parser;
use condition_parser::*;

#[cfg(test)]
mod tests {
    include!("lib_tests_1.rs");
    include!("lib_tests_2.rs");
}

#[cfg(test)]
mod logical_state_tests {
    use super::*;
    fn old_state(source: &str) -> LogicalState {
        let literal = lex_spans(source);
        let open_literal = literal.tokens.last().is_some_and(|token| {
            token.kind == TokenKind::String
                && literal
                    .diagnostics
                    .iter()
                    .any(|diagnostic| diagnostic.span.start == token.span.start)
        });
        let block = lex_spans(source);
        let open_block_string = block.tokens.last().is_some_and(|token| {
            token.kind == TokenKind::String
                && token.text(source).starts_with("{\"")
                && token.span.end == source.len()
                && !token.text(source).ends_with("\"}")
        });
        let mut depth = 0isize;
        for token in lex_spans(source).tokens {
            match token.text(source) {
                "(" | "[" => depth += 1,
                ")" | "]" => depth -= 1,
                _ => {}
            }
        }
        LogicalState {
            open_literal,
            open_block_string,
            open_expression: depth > 0,
        }
    }
    #[test]
    fn consolidated_state_matches_separate_scans_at_every_utf8_prefix() {
        for source in [
            "call(\n list(1, 2)\n)\n",
            "{\"block\n#literal \\\ntext\"}",
            "\"outer [call(\"nested [1]\")] end\"",
            "@{\"raw \\\n\"}",
            "'icons/日本.dmi'",
            "call(/* ( */ 1) // [\n",
            "#define X(a) a \\\n + 1\n",
            "\"unterminated",
        ] {
            for end in (0..=source.len()).filter(|end| source.is_char_boundary(*end)) {
                assert_eq!(
                    logical_state(&source[..end]),
                    old_state(&source[..end]),
                    "{source:?} at {end}"
                );
            }
        }
    }
    #[test]
    fn cached_join_state_preserves_directive_and_block_continuations() {
        let lines = logical_lines(
            "call(\n#warning marker\n)\n#define X a \\\n b\n{\"text \\\n#not_directive\n\"}\n",
        );
        let actual: Vec<_> = lines
            .iter()
            .map(|line| (line.text.as_str(), line.source_lines))
            .collect();
        assert_eq!(
            actual,
            vec![
                ("call(\n", 1),
                ("#warning marker\n", 1),
                (")\n", 1),
                ("#define X a  b\n", 2),
                // String decoding owns escaped newlines and indentation.
                ("{\"text \\\n#not_directive\n\"}\n", 3)
            ]
        );
    }
}

/// Provider-issued allocation geometry over the SAME actual read buffer.
/// Readonly DATA: constructor bytes/byte slices grant no source/model role.
#[derive(Clone,Copy)]pub struct OriginalRawAllocationPlan<'a>{original:&'a[u8],capacity:usize,constructor_bytes:usize,decoded_bytes:usize,exceptional:bool,needs_decode:bool}
impl<'a>OriginalRawAllocationPlan<'a>{
 pub fn new(original:&'a[u8],capacity:usize,constructor_bytes:usize,decoded_bytes:usize,exceptional:bool,needs_decode:bool)->Self{Self{original,capacity,constructor_bytes,decoded_bytes,exceptional,needs_decode}}
 pub fn original(self)->&'a[u8]{self.original}pub fn capacity(self)->usize{self.capacity}pub fn constructor_bytes(self)->usize{self.constructor_bytes}pub fn decoded_bytes(self)->usize{self.decoded_bytes}pub fn exceptional(self)->bool{self.exceptional}pub fn needs_decode(self)->bool{self.needs_decode}
}
