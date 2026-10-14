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

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Macro {
    pub parameters: Option<Vec<String>>,
    pub variadic: bool,
    pub replacement: String,
}

/// Borrowed lookup keeps expansion independent of a concrete snapshot storage.
pub(crate) trait MacroLookup {
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

pub trait SourceProvider {
    fn read(&self, path: &Path) -> Result<String, String>;

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
pub fn decode_source_bytes(mut bytes: &[u8]) -> String {
    if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
        bytes = &bytes[3..];
    }
    let mut output = String::new();
    const C1: [char; 32] = [
        '\u{20ac}', '\u{81}', '\u{201a}', '\u{192}', '\u{201e}', '\u{2026}', '\u{2020}',
        '\u{2021}', '\u{2c6}', '\u{2030}', '\u{160}', '\u{2039}', '\u{152}', '\u{8d}', '\u{17d}',
        '\u{8f}', '\u{90}', '\u{2018}', '\u{2019}', '\u{201c}', '\u{201d}', '\u{2022}', '\u{2013}',
        '\u{2014}', '\u{2dc}', '\u{2122}', '\u{161}', '\u{203a}', '\u{153}', '\u{9d}', '\u{17e}',
        '\u{178}',
    ];
    while !bytes.is_empty() {
        match std::str::from_utf8(bytes) {
            Ok(text) => {
                output.push_str(text);
                break;
            }
            Err(error) => {
                let valid = error.valid_up_to();
                output.push_str(std::str::from_utf8(&bytes[..valid]).unwrap());
                let invalid = error.error_len().unwrap_or(bytes.len() - valid);
                for &byte in &bytes[valid..valid + invalid] {
                    output.push(if (0x80..=0x9f).contains(&byte) {
                        C1[(byte - 0x80) as usize]
                    } else {
                        char::from(byte)
                    });
                }
                bytes = &bytes[valid + invalid..];
            }
        }
    }
    output
}

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
