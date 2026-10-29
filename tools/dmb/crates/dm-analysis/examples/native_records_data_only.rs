//! Complete named-rule fixture driver, not a production Analyze frontend.
//! The comparator is this fixture's resolved-config host; only policy values,
//! never a serialized DM model, arrive in its small configuration envelope.
use dm_analysis::{
    policy_inputs::{HostCapture, PolicyInputs, PolicyRole},
    records_data_only,
};
use dm_preprocess::SourceText;
use dm_tree::frontend::{build_with_config, FrontendConfig};
use std::{
    borrow::Cow,
    cell::RefCell,
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Arc,
};
#[path = "support/reference_hierarchy.rs"]
mod reference_hierarchy;
#[derive(Default)]
struct Files(RefCell<BTreeMap<PathBuf, Vec<u8>>>);
impl Files {
    fn read_once(&self, path: &Path) -> Result<(), String> {
        if !self.0.borrow().contains_key(path) {
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            self.0.borrow_mut().insert(path.to_owned(), bytes);
        }
        Ok(())
    }
    fn raw(&self, path: &Path, compiler: Option<&SourceText>) -> Result<SourceText, String> {
        self.read_once(path)?;
        let captures = self.0.borrow();
        let bytes = captures.get(path).ok_or("captured raw input absent")?;
        let decoded = String::from_utf8_lossy(bytes);
        let normalized = if decoded.contains('\r') {
            Cow::Owned(decoded.replace("\r\n", "\n").replace('\r', "\n"))
        } else {
            decoded
        };
        Ok(match compiler {
            Some(compiler) if compiler.as_str() == normalized.as_ref() => compiler.clone(),
            _ => normalized.into_owned().into(),
        })
    }
    fn same_bytes(&self, path: &Path, expected: &str) -> Result<bool, String> {
        self.read_once(path)?;
        Ok(self
            .0
            .borrow()
            .get(path)
            .ok_or("captured configuration absent")?
            .as_slice()
            == expected.as_bytes())
    }
}
impl dm_preprocess::SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.read_once(path)?;
        Ok(dm_preprocess::decode_source_bytes(
            self.0
                .borrow()
                .get(path)
                .ok_or("captured compiler input absent")?,
        ))
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut arguments = std::env::args().skip(1);
    let root = PathBuf::from(arguments.next().ok_or("expected fixture root")?);
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let config: serde_json::Value = serde_json::from_str(
        &arguments
            .next()
            .ok_or("expected resolved fixture configuration")?,
    )?;
    let config_raw = config
        .get("raw")
        .and_then(|v| v.as_str())
        .ok_or("captured configuration text missing")?;
    let prefixes = config
        .get("accessor_prefixes")
        .and_then(|v| v.as_array())
        .ok_or("resolved accessor prefixes missing")?
        .iter()
        .map(|v| {
            v.as_str()
                .map(str::to_owned)
                .ok_or("resolved prefix is not text")
        })
        .collect::<Result<Vec<_>, _>>()?;
    let files = Files::default();
    let seed = reference_hierarchy::seed();
    let frontend = build_with_config(
        &root.join("deepquarry.dme"),
        &files,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("native frontend: {e:?}"))?;
    let mut raw = Vec::new();
    for source in frontend.files.iter().filter(|file| file.captured) {
        raw.push(HostCapture::analyze_raw(
            Arc::clone(&source.path),
            PolicyRole::DmSource,
            files.raw(&source.path, Some(&source.text))?,
        ));
    }
    let config_path = root.join("tools/ci/lint_scopes.toml");
    if !files.same_bytes(&config_path, config_raw)? {
        return Err("resolved fixture configuration differs from the captured file".into());
    }
    raw.push(HostCapture::analyze_raw(
        Arc::new(config_path.clone()),
        PolicyRole::Configuration,
        files.raw(&config_path, None)?,
    ));
    let inputs = PolicyInputs::capture(&frontend, raw)?;
    for row in records_data_only::findings(&inputs, &root, &prefixes)? {
        println!(
            "{}",
            serde_json::json!({"rule":row.rule,"rel":row.rel,"line":row.line,"msg":row.msg,"key":row.key,"ident":row.ident})
        );
    }
    Ok(())
}
