//! Independent original legacy generator versus original-owner native producer.
//! Only generated text and diagnostics are compared, never models.
pub use dq_analyze::{incr, pat, pat_match, sem, tree, util};
#[path = "support/tracked_lists_original.rs"]
mod original;
#[path="../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
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
    let reference=sem::sem_for(&old.tree).ok_or("independent old semantic owner is unavailable")?;
    if !reference.errors.is_empty(){return Err(format!("independent old fixture parse errors: {:?}",reference.errors).into());}
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
    let seed=reference_hierarchy::seed();
    let executor=dm_exec::BuildExecutor::new(1)?;
    let frontend=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),&provider,&Default::default(),
        dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},
        None,&executor,None,true).map_err(|e|format!("native frontend: {e:?}"))?;
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
    if expected_text.matches("/// TRACKED(").count() != expected_rows
        || expected_diags.len() != expected_diagnostics
    {
        eprintln!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "stage": "independent_original_generator_coverage",
                "expected_rows": expected_rows,
                "actual_rows": expected_text.matches("/// TRACKED(").count(),
                "expected_diagnostics": expected_diagnostics,
                "actual_diagnostics": expected_diags.len(),
                "original_text": expected_text,
                "original_diagnostics": expected_diags,
            }))?
        );
        return Err("original generator fixture lacks intended positive/error coverage".into());
    }
    let inputs = PolicyInputs::capture(&frontend, extra)?;
    let shared_raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(
        &root,
        &inputs,
        dq_analyze::captured_raw_policy::Configuration::ProvenMissing,
    )?;
    let budget = dq_analyze::captured_generator_budget::Budget::new(64 * 1024 * 1024)?;
    let borrowed = dq_analyze::captured_tracked_lists::BorrowedTrackedLists::capture(
        &shared_raw,
        &inputs,
        budget.clone(),
    )?
    .generate(|| Ok(()))?;
    let borrowed_text = borrowed.captured_named_file_text("tracked_lists", "tracked_lists.dm", &budget)?;
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
    struct Pages(Vec<dq_analyze::captured_raw_file::File>);
    impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages {
        fn for_each(&self,visit:&mut dyn FnMut(&str,dq_analyze::captured_raw_file::RawPolicyViews<'_>)->Result<bool,dq_analyze::captured_reactive_reads::Failure>)->Result<bool,dq_analyze::captured_reactive_reads::Failure>{for file in &self.0{if !file.with_policy_views(visit)?{return Ok(false)}}Ok(true)}
    }
    let selected=old.tree.select(&dq_analyze::tree::CODE_DM).iter().map(|file|file.rel.clone()).collect::<std::collections::BTreeSet<_>>();
    let mut page_files=Vec::new();let mut seen=std::collections::BTreeSet::new();
    let mut test_collector=dq_analyze::generator_test_scope::TestTypeCollector::default();
    for file in &old.tree.files{test_collector.observe(&file.rel,file.text(),&mut dq_analyze::key_policy_control::Compatibility).unwrap();}
    for file in inputs.files().filter(|file|file.role()==PolicyRole::DmSource){let relative=dm_preprocess::regions::relative_filesystem_path(file.path(),&root).ok_or("page source outside root")?.to_string_lossy().replace('\\',"/");if !selected.contains(relative.as_str())||!seen.insert(relative){continue}let raw=file.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).map_err(|_|"original raw page unavailable")?;page_files.push(dq_analyze::captured_raw_file::File::capture(&root,file.path(),raw.clone())?);}
    let page_budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024)?;
    let pages=match dq_analyze::captured_tracked_lists_pages::generate_from_pages(&inputs,&root,&Pages(page_files),&test_collector.finish(),&page_budget,&||Ok(())){Ok(value)=>value,Err(dq_analyze::captured_reactive_reads::Failure::Operational(actual))=>return Err(Box::new(actual)),Err(dq_analyze::captured_reactive_reads::Failure::Unsupported(message))=>return Err(message.into())};
    let page_text=pages.captured_named_file_text("tracked_lists","tracked_lists.dm",&page_budget)?;
    let page_diags=pages.diags.iter().map(|d|(d.rel.clone(),d.line,d.msg.clone())).collect::<Vec<_>>();
    if page_text!=expected_text||page_diags!=expected_diags{return Err("original-loan full tracked-list output or ordered diagnostics differ from frozen whole Engine".into())}
    println!(
        "{}",
        serde_json::json!({"generator":"tracked_lists","scope":"explicit_seeded_captured_files","matched":true,"output_bytes":expected_text.len(),"diagnostics":borrowed_diags.len(),"full_workspace_coverage":false})
    );
    Ok(())
}
