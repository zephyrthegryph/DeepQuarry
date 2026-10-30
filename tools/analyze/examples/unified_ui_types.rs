//! Independent original legacy generator versus original-owner native producer.
//! Only generated text and diagnostics are compared, never models.
pub use dq_analyze::{incr, pat, sem, tree, util};
#[path = "support/ui_types_original.rs"]
mod original;
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::run::{registry, Engine, Options};
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
    let mut original_out = sem::gen::GenOut::default();
    let expected_files =
        old_generators[0].files(&sem::gen::GenCx::new(&old.tree, &root), &mut original_out);
    let expected_diags = original_out.diags;
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
    for required in ["Panel.d.ts", "Bundle.d.ts"] {
        if !expected_files.iter().any(|(p, _)| p.ends_with(required)) {
            eprintln!(
                "{}",
                serde_json::json!({"stage":"old_coverage","missing":required,"files":expected_files,"diags":expected_diags})
            );
            return Err("independent old UI fixture lacks file branch".into());
        }
    }
    for excluded in ["Ignored.d.ts", "Forward.d.ts", "Empty.d.ts"] {
        if expected_files.iter().any(|(p, _)| p.ends_with(excluded)) {
            return Err("old fixture unexpectedly emitted forwarding/nonentry/empty window".into());
        }
    }
    for required in ["has no schema", "nothing to type"] {
        if !expected_diags.iter().any(|d| d.2.contains(required)) {
            eprintln!(
                "{}",
                serde_json::json!({"stage":"old_coverage","missing":required,"diags":expected_diags})
            );
            return Err("independent old UI fixture lacks error branch".into());
        }
    }
    let inputs = PolicyInputs::capture(&frontend, extra)?;
    let shared_raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(
        &root,
        &inputs,
        dq_analyze::captured_raw_policy::Configuration::ProvenMissing,
    )?;
    let budget = dq_analyze::captured_generator_budget::Budget::new(64 * 1024 * 1024)?;
    let borrowed = dq_analyze::captured_ui_types::BorrowedUiTypes::capture(
        &shared_raw,
        &inputs,
        budget.clone(),
    )?
    .generate(|| Ok(()))?;

    let borrowed_diags = borrowed
        .diags
        .iter()
        .map(|d| (d.rel.clone(), d.line, d.msg.clone()))
        .collect::<Vec<_>>();
    if borrowed.files != expected_files || borrowed_diags != expected_diags {
        return Err(
            "borrowed shared-file generator differs from independent original Engine oracle".into(),
        );
    }
    println!(
        "{}",
        serde_json::json!({"generator":"ui_types","scope":"explicit_seeded_captured_files","matched":true,"files":expected_files.iter().map(|(p,t)|(p,t.len())).collect::<Vec<_>>(),"diagnostics":borrowed_diags.len(),"full_workspace_coverage":false})
    );
    Ok(())
}
