//! Independent original legacy generator versus original-owner native producer.
//! Only generated text and diagnostics are compared, never models.
pub use dq_analyze::{incr, lint, parity, pat, scopes, tree, util};
#[path = "support/pool_original.rs"]
mod original;
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::run::{Engine, Options};
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
    let mut registry = lint::Registry::default();
    original::register(&mut registry);
    let old = Engine::new(
        registry,
        Options {
            root: root.clone(),
            scopes_from: Some(root.clone()),
            lints: vec!["pool".into()],
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let (old_run, old_allow, _) =
        old.scan(old.reg.find("pool").ok_or("frozen original lint absent")?);
    let expected =
        serde_json::json!({"sites":old_run.sites,"notes":old_run.notes,"allow_used":old_allow});
    let provider = Files::default();
    let frontend = dm_tree::frontend::build(
        &root.join("deepquarry.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .map_err(|e| format!("original native frontend:{e:?}"))?;
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
        .ok_or("source roster missing")?
    {
        let path = root.join(name.as_str().ok_or("source path not text")?);
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
    let count = roster["expected_sites"]
        .as_integer()
        .ok_or("expected coverage count missing")? as usize;
    if old_run.sites.len() != count || old_run.notes != [format!("pool_lint: {} problem(s)", count)]
    {
        eprintln!("{}", serde_json::to_string_pretty(&expected)?);
        return Err("original pool fixture lacks expected positive/negative coverage".into());
    }
    if std::env::args().nth(2).as_deref() == Some("--oracle-only") {
        println!(
            "{}",
            serde_json::json!([{"name":"pool","sites":old_run.sites,"notes":old_run.notes,"allow_used":old_allow}])
        );
        return Ok(());
    }
    let inputs = PolicyInputs::capture(&frontend, extra)?;
    let config = provider.bytes(&root.join("tools/ci/lint_scopes.toml"))?;
    let raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(
        &root,
        &inputs,
        dq_analyze::captured_raw_policy::Configuration::Captured(&config),
    )?;
    let budget = dq_analyze::captured_generator_budget::Budget::new(64 * 1024 * 1024)?;
    let output = dq_analyze::captured_pool::BorrowedPool::capture(&raw, &inputs)?.scan(
        budget,
        10_000,
        || Ok(()),
    )?;
    let actual = serde_json::json!({"sites":output.run.sites,"notes":output.run.notes,"allow_used":output.allow_used});
    if actual != expected {
        eprintln!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({"old":expected,"native":actual}))?
        );
        return Err("native pool policy differs from independent frozen original Engine".into());
    }
    println!(
        "{}",
        serde_json::json!({"lint":"pool","matched":true,"sites":count,"scope":"explicit_seeded_captured_files","full_workspace_coverage":false})
    );
    Ok(())
}
