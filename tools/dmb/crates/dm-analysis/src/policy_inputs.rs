//! Revision-bound raw policy inputs, separate from compiled membership.
//!
//! This is an immutable, read-only boundary, not a filesystem crawler or a
//! self-certifying workspace snapshot. The host supplies extra captures through
//! its existing recorded-input ledger and proves directory/missing-file facts.
//! Captures retain existing SourceText owners; no DM parser or copied Tree runs.
use dm_preprocess::{regions::canonical_path, SourceText};
use dm_tree::frontend::{BodyArchive, ColdFrontend, SourceExportMapping};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Arc,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PolicyRole {
    DmSource,
    Configuration,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum TextView {
    CompilerDecoded,
    AnalyzeRaw,
}

/// An additional immutable input issued by the host's capture producer.
/// The producer, not this value, proves which filesystem revision it read.
#[derive(Clone)]
pub struct HostCapture {
    path: Arc<PathBuf>,
    role: PolicyRole,
    view: TextView,
    text: SourceText,
}
impl HostCapture {
    /// Shared decoded source from the existing preprocessor preparation owner.
    /// This does not claim Analyze's different raw decoding/newline contract.
    pub fn prepared_dm(
        path: Arc<PathBuf>,
        source: &dm_preprocess::regions::prepared_source::PreparedSource,
    ) -> Self {
        Self {
            path,
            role: PolicyRole::DmSource,
            view: TextView::CompilerDecoded,
            text: source.original().clone(),
        }
    }
    /// Host-issued Analyze raw view: UTF-8-lossy + universal newlines, matching
    /// Analyze Tree's read policy. For ordinary UTF-8/LF inputs the host can
    /// share the existing compiler SourceText; BOM/legacy encodings may differ.
    pub fn analyze_raw(path: Arc<PathBuf>, role: PolicyRole, text: SourceText) -> Self {
        Self {
            path,
            role,
            view: TextView::AnalyzeRaw,
            text,
        }
    }
    /// Host-issued compiler-decoded original, without another lexical prepare.
    pub fn compiler_decoded(path: Arc<PathBuf>, text: SourceText) -> Self {
        Self {
            path,
            role: PolicyRole::DmSource,
            view: TextView::CompilerDecoded,
            text,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CaptureError {
    ForeignCompilerInputs,
    DuplicateRole(PathBuf),
    ContradictoryText { path: PathBuf, view: TextView },
    MissingView { path: PathBuf, view: TextView },
    InvalidSourceLine { path: PathBuf, line: usize },
    EmptyPath,
}
impl std::fmt::Display for CaptureError {
    fn fmt(&self, out: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(out, "{self:?}")
    }
}
impl std::error::Error for CaptureError {}

pub struct PolicyFile {
    path: Arc<PathBuf>,
    role: PolicyRole,
    compiled: bool,
    views: BTreeMap<TextView, SourceText>,
}
impl PolicyFile {
    pub fn path(&self) -> &Arc<PathBuf> {
        &self.path
    }
    pub fn role(&self) -> PolicyRole {
        self.role
    }
    /// True only for an input from the authenticated compiler file roster.
    pub fn is_compiled(&self) -> bool {
        self.compiled
    }
    pub fn view(&self, view: TextView) -> Result<&SourceText, CaptureError> {
        self.views
            .get(&view)
            .ok_or_else(|| CaptureError::MissingView {
                path: self.path.as_ref().clone(),
                view,
            })
    }
    pub fn views(&self) -> impl Iterator<Item = (TextView, &SourceText)> {
        self.views.iter().map(|(&kind, text)| (kind, text))
    }

    /// Analyze's historical `engine_line` projection, using captured original
    /// text instead of rereading the mutable checkout. A lone CR adds a display
    /// line only when it precedes the native LF-based line, exactly as in the
    /// reference policy. This formats an origin; it does not authenticate one.
    pub fn analyze_display_line(&self, native_line: usize) -> Result<usize, CaptureError> {
        self.view(TextView::CompilerDecoded)?.analyze_display_line(native_line).ok_or_else(||CaptureError::InvalidSourceLine{path:self.path.as_ref().clone(),line:native_line})
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PolicyRevision {
    pub compiler_source: u128,
    pub policy_inputs: u128,
}

/// The descriptor deliberately cannot claim entire-workspace coverage. A
/// supplied file roster alone proves neither directory enumeration nor absence.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Coverage {
    CapturedFilesOnly,
}

pub struct PolicyInputs {
    archive: Arc<BodyArchive>,
    mapping: Arc<SourceExportMapping>,
    revision: PolicyRevision,
    semantic_revision: u128,
    files: BTreeMap<PathBuf, PolicyFile>,
}
impl PolicyInputs {
    /// Authenticate compiler public compatibility fields before borrowing any
    /// file text. Additional inputs are trusted host captures, not new compiler
    /// includes; they never modify the semantic tree or directive plan.
    pub fn capture(
        frontend: &ColdFrontend,
        extra: impl IntoIterator<Item = HostCapture>,
    ) -> Result<Self, CaptureError> {
        let mapping = frontend
            .source_export_mapping()
            .cloned()
            .ok_or(CaptureError::ForeignCompilerInputs)?;
        let archive = frontend
            .body_archive()
            .ok_or(CaptureError::ForeignCompilerInputs)?;
        let source_revision = frontend.source_export_revision();
        Self::capture_original_parts(archive, mapping, source_revision, &frontend.files, extra)
    }
    pub fn capture_diagnostic(
        frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
        extra: impl IntoIterator<Item = HostCapture>,
    ) -> Result<Self, CaptureError> {
        if frontend.preparation_purpose().is_structural() || !frontend.receipt().authenticates(frontend.tree())
            || !frontend.archive().matches_tree(frontend.tree())
        {
            return Err(CaptureError::ForeignCompilerInputs);
        }
        Self::capture_original_parts(
            Arc::clone(frontend.archive()),
            Arc::clone(frontend.mapping()),
            frontend.source_revision(),
            frontend.files(),
            extra,
        )
    }
    fn capture_original_parts(
        archive: Arc<BodyArchive>,
        mapping: Arc<SourceExportMapping>,
        source_revision: u128,
        source_files: &[dm_tree::frontend::SourceFile],
        extra: impl IntoIterator<Item = HostCapture>,
    ) -> Result<Self, CaptureError> {
        let mut files = BTreeMap::new();
        for source in source_files.iter().filter(|file| file.captured) {
            insert(
                &mut files,
                Arc::clone(&source.path),
                PolicyRole::DmSource,
                TextView::CompilerDecoded,
                source.text.clone(),
                true,
            )?;
        }
        for capture in extra {
            insert(
                &mut files,
                capture.path,
                capture.role,
                capture.view,
                capture.text,
                false,
            )?;
        }
        let semantic_revision = archive.tree().identity();
        let revision = PolicyRevision {
            compiler_source: source_revision,
            policy_inputs: digest(source_revision, semantic_revision, &files),
        };
        Ok(Self {
            archive,
            mapping,
            revision,
            semantic_revision,
            files,
        })
    }
    pub fn revision(&self) -> PolicyRevision {
        self.revision
    }
    pub fn semantic_revision(&self) -> u128 {
        self.semantic_revision
    }
    pub fn coverage(&self) -> Coverage {
        Coverage::CapturedFilesOnly
    }
    pub fn archive(&self) -> &Arc<BodyArchive> {
        &self.archive
    }
    pub fn mapping(&self) -> &Arc<SourceExportMapping> {
        &self.mapping
    }
    pub fn files(&self) -> impl Iterator<Item = &PolicyFile> {
        self.files.values()
    }
    /// Borrow an already-issued exact canonical key without path scratch.
    /// This only selects existing data; it grants no source or scope receipt.
    pub fn file_exact(&self,path:&Path)->Option<&PolicyFile>{self.files.get(path)}
    pub fn file(&self, path: &Path) -> Option<&PolicyFile> {
        self.file_exact(path).or_else(||self.files.get(&canonical_path(path)))
    }
    pub fn matches_revisions(&self, source: u128, policy: u128) -> bool {
        self.revision.compiler_source == source && self.revision.policy_inputs == policy
    }
    pub fn matches_archive(&self, archive: &BodyArchive) -> bool {
        std::ptr::eq(self.archive.as_ref(), archive)
    }
    pub fn matches_frontend(&self, frontend: &ColdFrontend) -> bool {
        frontend
            .source_export_mapping()
            .is_some_and(|mapping| Arc::ptr_eq(mapping, &self.mapping))
            && self.archive.matches_tree(&frontend.snapshot.tree)
    }
}

fn insert(
    files: &mut BTreeMap<PathBuf, PolicyFile>,
    original_path: Arc<PathBuf>,
    role: PolicyRole,
    view: TextView,
    text: SourceText,
    compiled: bool,
) -> Result<(), CaptureError> {
    let path = canonical_path(original_path.as_ref());
    if path.as_os_str().is_empty() {
        return Err(CaptureError::EmptyPath);
    }
    if let Some(current) = files.get_mut(&path) {
        if current.role != role {
            return Err(CaptureError::DuplicateRole(path));
        }
        if let Some(previous) = current.views.get(&view) {
            if previous.as_str() != text.as_str() {
                return Err(CaptureError::ContradictoryText { path, view });
            }
            // Keep the already-admitted compiler payload rather than an equal
            // separately allocated compatibility copy supplied by a caller.
        } else {
            current.views.insert(view, text);
        }
        current.compiled |= compiled;
    } else {
        let original_path = if original_path.as_ref() == &path {
            original_path
        } else {
            Arc::new(path.clone())
        };
        files.insert(
            path,
            PolicyFile {
                path: original_path,
                role,
                compiled,
                views: BTreeMap::from([(view, text)]),
            },
        );
    }
    Ok(())
}
fn digest(source: u128, semantic: u128, files: &BTreeMap<PathBuf, PolicyFile>) -> u128 {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(b"dm-native-policy-inputs-v1\0");
    hash.update(&source.to_le_bytes());
    hash.update(&semantic.to_le_bytes());
    hash.update(&(files.len() as u64).to_le_bytes());
    for (path, file) in files {
        let path = path.as_os_str().as_encoded_bytes();
        hash.update(&(path.len() as u64).to_le_bytes());
        hash.update(path);
        hash.update(&[
            match file.role {
                PolicyRole::DmSource => 0,
                PolicyRole::Configuration => 1,
            },
            u8::from(file.compiled),
        ]);
        hash.update(&(file.views.len() as u64).to_le_bytes());
        for (&view, text) in &file.views {
            hash.update(&[match view {
                TextView::CompilerDecoded => 0,
                TextView::AnalyzeRaw => 1,
            }]);
            hash.update(
                &text
                    .span_fingerprint(0..text.len())
                    .expect("whole captured view")
                    .to_le_bytes(),
            );
        }
    }
    hash.digest128()
}

#[cfg(test)]
#[path = "policy_inputs_tests.rs"]
mod tests;

/// Current borrowed/retained model DATA for the private handlers partial TU.
/// It cannot be converted to PolicyInputs, a full-source witness or compiler
/// inputs, even when bytes and tree match an independently prepared full root.
pub struct HandlersStructuralInputs{
 archive:Arc<BodyArchive>,mapping:Arc<SourceExportMapping>,source_revision:u128,
 purpose:dm_tree::frontend::DiagnosticPreparationPurpose,
}
impl HandlersStructuralInputs{
 pub fn capture(frontend:&dm_tree::frontend::HandlersStructuralSource<'_>)->Result<Self,CaptureError>{
  let view=frontend.view();if !view.preparation_purpose().is_structural()||!view.receipt().authenticates(view.tree())||!view.archive().matches_tree(view.tree())||!Arc::ptr_eq(view.archive().source_mapping(),view.mapping())||view.original_analysis_completeness().is_some(){return Err(CaptureError::ForeignCompilerInputs)}
  Ok(Self{archive:Arc::clone(view.archive()),mapping:Arc::clone(view.mapping()),source_revision:view.source_revision(),purpose:view.preparation_purpose()})
 }
 pub fn archive(&self)->&Arc<BodyArchive>{&self.archive}
 pub fn mapping(&self)->&Arc<SourceExportMapping>{&self.mapping}
 pub fn source_revision(&self)->u128{self.source_revision}
 pub fn preparation_purpose(&self)->dm_tree::frontend::DiagnosticPreparationPurpose{self.purpose}
 pub fn matches(&self,frontend:&dm_tree::frontend::HandlersStructuralSource<'_>)->bool{let view=frontend.view();self.purpose==view.preparation_purpose()&&self.source_revision==view.source_revision()&&Arc::ptr_eq(&self.archive,view.archive())&&Arc::ptr_eq(&self.mapping,view.mapping())}
}
