//! Independent original legacy generator versus original-owner native producer.
//! Only generated text and diagnostics are compared, never models.
pub use dq_analyze::sem;
#[path = "support/sparse_slots_original.rs"]
mod original;
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::{
    captured_sparse_slots::CapturedSparseSlots,
    run::{registry, Engine, Options},
};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Arc,
};
#[derive(Default)]
struct Files {
    bytes: RefCell<BTreeMap<PathBuf, Vec<u8>>>,
    acquired: RefCell<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
}
impl Files {
    fn bytes(&self, path: &Path) -> Result<Vec<u8>, String> {
        if !self.bytes.borrow().contains_key(path) {
            self.bytes
                .borrow_mut()
                .insert(path.into(), std::fs::read(path).map_err(|e| e.to_string())?);
        }
        Ok(self.bytes.borrow()[path].clone())
    }
    fn raw(&self, path: &Path, native: Option<&SourceText>) -> Result<SourceText, String> {
        let bytes = self.bytes(path)?;
        let raw = String::from_utf8_lossy(&bytes)
            .replace("\r\n", "\n")
            .replace('\r', "\n");
        Ok(match native {
            Some(native) if native.as_str() == raw => native.clone(),
            _ => raw.into(),
        })
    }
}
impl SourceProvider for Files {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("original acquisition required".into())
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.acquired.borrow().contains_key(path) {
            self.acquired.borrow_mut().insert(
                path.into(),
                dm_preprocess::AcquiredSource::from_original_bytes(self.bytes(path)?, ()),
            );
        }
        Ok(self.acquired.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.acquired
            .borrow()
            .get(path)
            .filter(|s| s.lease().source_text().same_view(text))
            .cloned()
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(std::env::args().nth(1).ok_or("fixture root required")?);
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let old = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root.clone()),
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let mut old_generators = Vec::new();
    original::register(&mut old_generators);
    let (expected_text, expected_diags) = sem::gen::render(
        old_generators[0].as_ref(),
        &sem::gen::GenCx::new(&old.tree, &root),
    );
    let expected_diags = expected_diags
        .into_iter()
        .map(|d| (d.rel, d.line, d.msg))
        .collect::<Vec<_>>();
    let provider = Files::default();
    let frontend = dm_tree::frontend::build(
        &root.join("deepquarry.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .map_err(|e| format!("native frontend fixture: {e:?}"))?;
    let mut extra = Vec::new();
    for file in frontend.files.iter().filter(|f| f.captured) {
        extra.push(HostCapture::analyze_raw(
            Arc::clone(&file.path),
            PolicyRole::DmSource,
            provider.raw(&file.path, Some(&file.text))?,
        ));
    }
    let roster: toml::Value =
        std::str::from_utf8(&provider.bytes(&root.join("raw_inputs.toml"))?)?.parse()?;
    for name in roster["sources"]
        .as_array()
        .ok_or("raw source roster missing")?
    {
        let path = root.join(name.as_str().ok_or("raw source name must be text")?);
        let native = frontend
            .files
            .iter()
            .find(|f| f.captured && f.path.as_ref() == &path)
            .map(|f| &f.text);
        extra.push(HostCapture::analyze_raw(
            Arc::new(path.clone()),
            PolicyRole::DmSource,
            provider.raw(&path, native)?,
        ));
    }
    let expected_rows = roster["expected_rows"]
        .as_integer()
        .ok_or("expected row count missing")? as usize;
    let expected_diagnostics = roster["expected_diagnostics"]
        .as_integer()
        .ok_or("expected diagnostic count missing")? as usize;
    if expected_text.matches("\t\tlist(").count() != expected_rows
        || expected_diags.len() != expected_diagnostics
    {
        return Err("original generator fixture lacks intended positive/error coverage".into());
    }
    let inputs = PolicyInputs::capture(&frontend, extra)?;
    let generated =
        CapturedSparseSlots::capture(&root, inputs.archive(), &inputs)?.generate(|| Ok(()))?;
    let shared_raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(
        &root,
        &inputs,
        dq_analyze::captured_raw_policy::Configuration::ProvenMissing,
    )?;
    let budget = dq_analyze::captured_generator_budget::Budget::new(64 * 1024 * 1024)?;
    let borrowed = dq_analyze::captured_sparse_slots::BorrowedSparseSlots::capture(
        &shared_raw,
        &inputs,
        budget.clone(),
    )?
    .generate(|| Ok(()))?;
    let borrowed_text = borrowed.captured_file_text(&budget)?;
    let borrowed_diags = borrowed
        .diags
        .iter()
        .map(|d| (d.rel.clone(), d.line, d.msg.clone()))
        .collect::<Vec<_>>();
    if borrowed_text != expected_text || borrowed_diags != expected_diags {
        return Err(
            "borrowed shared-file generator differs from independent original Engine oracle".into(),
        );
    }
    let actual_diags = generated
        .diags
        .iter()
        .map(|d| (d.rel.clone(), d.line, d.msg.clone()))
        .collect::<Vec<_>>();
    if expected_text != generated.file_text() || expected_diags != actual_diags {
        eprintln!(
            "{}",
            serde_json::to_string_pretty(
                &serde_json::json!({"old":{"text":expected_text,"diagnostics":expected_diags},"native":{"text":generated.file_text(),"diagnostics":actual_diags}})
            )?
        );
        return Err("native whole sparse generator differs from original legacy backend".into());
    }
    println!(
        "{}",
        serde_json::json!({"generator":"sparse_slots","scope":"explicit_seeded_captured_files","matched":true,"output_bytes":expected_text.len(),"diagnostics":actual_diags.len(),"full_workspace_coverage":false})
    );
    Ok(())
}
