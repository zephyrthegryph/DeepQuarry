//! Independent original legacy generator versus original-owner native producer.
//! Only generated text and diagnostics are compared, never models.
pub use dq_analyze::{incr, pat, sem, tree, util};
#[path = "support/declare_original.rs"]
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
    let (expected_text, expected_diags) = sem::gen::render(
        old_generators[1].as_ref(),
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
    // Guard that the independent original actually exercises all output families
    // and diagnostics before comparing the entire unmodified text/row order.
    for required in [
        "/proc/cover(",
        "/datum/capdef_decl/c_cover/spec()",
        "/datum/cap_keys_decl/k_cover/spec()",
        "/datum/stage_def/work_start/spec()",
        "/datum/source_def/hand/spec()",
        "/datum/graph_decl/g_graph_work/spec()",
        "/datum/holder/declared_entries(list/into)",
        "/proc/declared_static_blocks()",
        "/proc/declared_keyed_targets()",
        "/datum/holder/proc/target()",
        "lifeform_declared = TRUE",
        "/proc/make(",
        "#if defined(UNIT_TESTS)",
    ] {
        if !expected_text.contains(required) {
            eprintln!(
                "{}",
                serde_json::json!({"stage":"original_coverage","missing":required,"text":expected_text,"diags":expected_diags})
            );
            return Err("independent original declaration fixture lacks required branch".into());
        }
    }
    for required in [
        "var assignment inside the CAPABILITIES",
        "has no entries",
        "declared twice",
    ] {
        if !expected_diags.iter().any(|d| d.2.contains(required)) {
            eprintln!(
                "{}",
                serde_json::json!({"stage":"original_diagnostic_coverage","missing":required,"diags":expected_diags})
            );
            return Err("independent original declaration diagnostics lack required branch".into());
        }
    }
    let inputs = PolicyInputs::capture(&frontend, extra)?;
    let shared_raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(
        &root,
        &inputs,
        dq_analyze::captured_raw_policy::Configuration::ProvenMissing,
    )?;
    let budget = dq_analyze::captured_generator_budget::Budget::new(64 * 1024 * 1024)?;
    let borrowed = dq_analyze::captured_declare::BorrowedDeclare::capture(
        &shared_raw,
        &inputs,
        budget.clone(),
    )?
    .generate(|| Ok(()))?;
    let borrowed_text = borrowed.captured_named_file_text("declare", "declare.dm", &budget)?;
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
    // Source-neutral file loans exercise the actual-growth Declare producer.
    // This fixture intentionally grants no workspace/domain completion witness.
    struct Pages(Vec<dq_analyze::captured_raw_file::File>);
    impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages {
        fn for_each(&self, visit:&mut dyn FnMut(&str,dq_analyze::captured_raw_file::RawPolicyViews<'_>)->Result<bool,dq_analyze::captured_reactive_reads::Failure>)->Result<bool,dq_analyze::captured_reactive_reads::Failure>{
            for file in &self.0{if !file.with_policy_views(visit)?{return Ok(false)}}Ok(true)
        }
    }
    let mut page_files=Vec::new();
    let selected_names=old.tree.select(&dq_analyze::tree::CODE_DM).iter().map(|file|file.rel.clone()).collect::<std::collections::BTreeSet<_>>();
    let mut page_names=std::collections::BTreeSet::new();
    for file in inputs.files().filter(|file|file.role()==PolicyRole::DmSource){
        let relative=dm_preprocess::regions::relative_filesystem_path(file.path(),&root).ok_or("page fixture source outside root")?.to_string_lossy().replace('\\',"/");
        if !selected_names.contains(relative.as_str())||!page_names.insert(relative){continue}
        let source=file.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).map_err(|_|"page fixture needs original AnalyzeRaw")?;
        page_files.push(dq_analyze::captured_raw_file::File::capture(&root,file.path(),source.clone())?);
    }
    let manifest=provider.bytes(&root.join("deepquarry.dme"))?;
    let manifest_text=String::from_utf8_lossy(&manifest).replace("\r\n","\n").replace('\r',"\n");
    let order=dq_analyze::raw_marker_policy::dme_include_order_view(&manifest_text,manifest.starts_with(&[0xef,0xbb,0xbf]));
    let page_budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024)?;
    let pages=dq_analyze::captured_declare_pages::generate_from_pages(&Pages(page_files),&order,&page_budget,&||Ok(())).map_err(|failure|->Box<dyn std::error::Error>{match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>Box::new(actual),dq_analyze::captured_reactive_reads::Failure::Unsupported(reason)=>reason.into()}})?;
    let page_text=pages.captured_named_file_text("declare","declare.dm",&page_budget)?;
    let page_diags=pages.diags.iter().map(|row|(row.rel.clone(),row.line,row.msg.clone())).collect::<Vec<_>>();
    if page_text!=expected_text||page_diags!=expected_diags{return Err("actual-growth original-loan Declare differs from complete frozen Engine oracle".into())}
    println!(
        "{}",
        serde_json::json!({"generator":"declare","scope":"explicit_seeded_captured_files","matched":true,"output_bytes":expected_text.len(),"diagnostics":borrowed_diags.len(),"full_workspace_coverage":false})
    );
    Ok(())
}
