//! What dreammaker's parse returns: the object tree, its file list and diagnostics. Only DreamChecker's default path reads it now
//! (`crate::dreamchecker`, `super::parse_for_checker`); the semantic model is built from the compiler's front end (`crate::model`), so
//! the store that kept this parse between runs is gone.

use dreammaker::objtree::ObjectTree;

use crate::tree::Hash;

/// A checker parse's diagnostics (`super::parse_source`'s `checker`), in the order the standalone checker prints them.
pub struct CheckerDiagnostics {
    /// Preprocessor and parser, in stream order.
    pub stream: Vec<dreammaker::DMError>,
    /// The parser's "parsed N/M proc bodies" line, printed after `stream`.
    pub summary: Option<String>,
    /// What finishing the object tree registered.
    pub finish: Vec<dreammaker::DMError>,
}

pub struct Parsed {
    pub objtree: ObjectTree,
    pub files: dreammaker::FileList,
    pub errors: Vec<String>,
    /// The macro environment, when known.
    pub env: Option<Hash>,
    /// The structure digest, when known.
    pub structure: Option<u128>,
    /// A full parse's macro history: the macro state at the start of every file.
    pub defines: Option<dreammaker::preprocessor::StoredDefineHistory>,
    /// A checker parse's diagnostics, every severity, in source order (`parse_source`'s `checker`).
    pub raw: Option<CheckerDiagnostics>,
    /// The parser stopped on a fatal error.
    pub fatal: bool,
}

/// The tree stores proc bodies encoded and decodes one when something reads it (`dreammaker::objtree::LazyCode`): bincode both ways.
pub fn ensure_codec() {
    fn enc(c: &Option<dreammaker::ast::Block>) -> Vec<u8> {
        bincode::serialize(c).unwrap_or_default()
    }
    fn dec(b: &[u8]) -> Option<dreammaker::ast::Block> {
        bincode::deserialize(b).expect("a stored proc body decodes")
    }
    dreammaker::objtree::set_code_codec(enc, dec);
}
