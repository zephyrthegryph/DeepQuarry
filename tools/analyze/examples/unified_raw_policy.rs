//! Independent loader-path oracle: actual Engine.scan versus native captured raw runner.
//! Compares exact findings/ALLOW/notes, not models or full Analyze admission.
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RAW_FILE_LINTS},
    run::{registry, Engine, Options},
};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Arc,
};
#[derive(Default)]
struct Files(RefCell<BTreeMap<PathBuf, Vec<u8>>>);
impl Files {
    fn bytes(&self, path: &Path) -> Result<Vec<u8>, String> {
        if !self.0.borrow().contains_key(path) {
            self.0.borrow_mut().insert(
                path.into(),
                std::fs::read(path).map_err(|error| error.to_string())?,
            );
        }
        Ok(self.0.borrow()[path].clone())
    }
    fn raw(&self, path: &Path, compiler: Option<&SourceText>) -> Result<SourceText, String> {
        let bytes = self.bytes(path)?;
        let text = String::from_utf8_lossy(&bytes)
            .replace("\r\n", "\n")
            .replace('\r', "\n");
        Ok(match compiler {
            Some(native) if native.as_str() == text => native.clone(),
            _ => text.into(),
        })
    }
}
impl SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        Ok(dm_preprocess::decode_source_bytes(&self.bytes(path)?))
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(
        std::env::args()
            .nth(1)
            .ok_or("expected explicit fixture root")?,
    );
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let names = RAW_FILE_LINTS
        .iter()
        .map(|name| name.to_string())
        .collect::<Vec<_>>();
    // The old Engine owns its unchanged filesystem discovery, views and scan path.
    // It never shares a semantic model or raw source roster with the native side.
    let old = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root.clone()),
            lints: names.clone(),
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let mut expected = BTreeMap::new();
    for name in &names {
        let lint = old.reg.find(name).ok_or("old lint missing")?;
        let (run, allow, _) = old.scan(lint);
        expected.insert(
            name.clone(),
            serde_json::json!({"sites":run.sites,"allow_used":allow,"notes":run.notes}),
        );
    }
    let files = Files::default();
    let frontend =
        dm_tree::frontend::build(&root.join("deepquarry.dme"), &files, &Default::default(), 1)
            .map_err(|e| format!("native fixture failed: {e:?}"))?;
    let mut captures = Vec::new();
    for file in frontend.files.iter().filter(|file| file.captured) {
        captures.push(HostCapture::analyze_raw(
            Arc::clone(&file.path),
            PolicyRole::DmSource,
            files.raw(&file.path, Some(&file.text))?,
        ));
    }
    let roster: toml::Value =
        String::from_utf8(files.bytes(&root.join("raw_inputs.toml"))?)?.parse()?;
    for name in roster
        .get("sources")
        .and_then(toml::Value::as_array)
        .ok_or("explicit raw source roster missing")?
    {
        let path = root.join(name.as_str().ok_or("raw roster member is not text")?);
        let compiled = frontend
            .files
            .iter()
            .find(|file| file.path.as_ref() == &path && file.captured)
            .map(|file| &file.text);
        captures.push(HostCapture::analyze_raw(
            Arc::new(path.clone()),
            PolicyRole::DmSource,
            files.raw(&path, compiled)?,
        ));
    }
    let inputs = PolicyInputs::capture(&frontend, captures)?;
    let config = files.bytes(&root.join("tools/ci/lint_scopes.toml"))?;
    let captured = CapturedRawPolicy::capture(&root, &inputs, Configuration::Captured(&config))?;
    let actual = captured.scan(&names, || Ok(()))?;
    let mut observed = BTreeMap::new();
    for result in actual {
        observed.insert(result.name,serde_json::json!({"sites":result.run.sites,"allow_used":result.allow_used,"notes":result.run.notes}));
    }
    if expected != observed {
        eprintln!(
            "{}",
            serde_json::to_string_pretty(
                &serde_json::json!({"reference":expected,"native":observed})
            )?
        );
        return Err("captured raw policy differs from old Engine.scan".into());
    }
    let sites = expected
        .values()
        .map(|run| run["sites"].as_array().unwrap().len())
        .sum::<usize>();
    if sites == 0 {
        return Err("empty seeded oracle cannot certify the raw cohort".into());
    }
    println!(
        "{}",
        serde_json::json!({"scope":"raw27/explicit-seeded-fixture","lints":expected.len(),"sites":sites,"matched":true,"full_policy_parity":false,"baseline_applied":false})
    );
    Ok(())
}
