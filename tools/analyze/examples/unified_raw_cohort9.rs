//! Independent original legacy generator versus original-owner native producer.
//! Only generated text and diagnostics are compared, never models.
pub use dq_analyze::{dm, incr, lint, parity, pat, pat_match, scopes, tree, util};
#[path = "support/raw9_original/read_back.rs"] mod old_read_back;
#[path = "support/raw9_original/latent.rs"] mod old_latent;
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
    let input = PathBuf::from(std::env::args().nth(1).ok_or("raw9 fixture parent required")?);
    let base = if input.is_absolute() { input } else { std::env::current_dir()?.join(input) };
    let oracle_only = std::env::args().nth(2).as_deref() == Some("--oracle-only");
    let mut summaries = Vec::new();
    for &name in dq_analyze::captured_raw_cohort::LINTS {
        let root = base.join(name);
        let mut registry = dq_analyze::run::registry();
        registry.lints.retain(|l| l.meta().name != "latent" && l.meta().name != "read_back");
        old_read_back::register(&mut registry); old_latent::register(&mut registry);
        let old = Engine::new(registry, Options { root: root.clone(), scopes_from: Some(root.clone()),
            lints: vec![name.into()], raw: true, no_cache: true, ..Default::default() })?;
        let (run, allow, _) = old.scan(old.reg.find(name).ok_or("original lint missing")?);
        let required: &[&str] = match name {
            "cooldown" => &["raw_compare"], "declaration_block" => &["bundle", "backslash_list", "two_blocks"],
            "duplicate_input_key" => &["duplicate_input_key"], "entry_slots" => &["positional_overflow"],
            "interactions" => &["shadow"], "latent" => &["raw_walks"], "pollers" => &["process", "start", "step_coverage"],
            "read_back" => &["undeclared_read_back"], "cap_bits" => &["outside_registry", "bit_range", "bit_shared", "raw_write"],
            _ => return Err("unissued oracle coverage contract".into()),
        };
        if required.iter().any(|rule| !run.sites.iter().any(|s| s.rule == *rule)) {
            eprintln!("{}", serde_json::to_string_pretty(&serde_json::json!({"name":name,"sites":run.sites,"notes":run.notes,"allow_used":allow}))?);
            return Err(format!("original {name} fixture lacks intended positive rule coverage").into());
        }
        if ["cooldown", "interactions", "latent", "pollers", "read_back"].contains(&name) && allow.is_empty() {
            return Err(format!("original {name} fixture lacks intended ALLOW-use coverage").into());
        }
        let expected = serde_json::json!({"sites":run.sites,"notes":run.notes,"allow_used":allow});
        if oracle_only { summaries.push(serde_json::json!({"name":name,"original":expected})); continue; }
        let provider = Files::default();
        let front = dm_tree::frontend::build(&root.join("deepquarry.dme"), &provider, &Default::default(), 1)
            .map_err(|e|format!("original native frontend {name}: {e:?}"))?;
        let mut captures = Vec::new();
        for file in front.files.iter().filter(|f| f.captured) {
            captures.push(HostCapture::analyze_raw(Arc::clone(&file.path), PolicyRole::DmSource,
                provider.raw(&file.path, Some(&file.text))?));
        }
        for file in ["code/a.dm", "code/b.dm"] {
            let path = root.join(file);
            captures.push(HostCapture::analyze_raw(Arc::new(path.clone()), PolicyRole::DmSource,
                provider.raw(&path, None)?));
        }
        let inputs = PolicyInputs::capture(&front, captures)?;
        let config = provider.bytes(&root.join("tools/ci/lint_scopes.toml"))?;
        let raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(&root, &inputs,
            dq_analyze::captured_raw_policy::Configuration::Captured(&config))?;
        let limit = 64*1024*1024;
        let actual = dq_analyze::captured_raw_cohort::BorrowedRawCohort::capture(&raw, &inputs)
            .scan(name, dq_analyze::captured_generator_budget::Budget::new(limit)?, limit, 10_000, ||Ok(()))?;
        let actual = serde_json::json!({"sites":actual.run.sites,"notes":actual.run.notes,"allow_used":actual.allow_used});
        if actual != expected {
            eprintln!("{}",serde_json::to_string_pretty(&serde_json::json!({"name":name,"original":expected,"native":actual}))?);
            return Err(format!("{name}: exact independent old Engine row/message/note/ALLOW trace mismatch").into());
        }
        summaries.push(serde_json::json!({"name":name,"matched":true,"scope":"explicit_bounded_captured_files","full_workspace_coverage":false}));
    }
    println!("{}",serde_json::to_string(&summaries)?); Ok(())
}
