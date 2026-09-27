//! Declared DM fields and proc signatures for cross-proc checks.
use crate::contracts::{Contract, Visibility};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::io::{self, BufRead, Read};
use std::path::Path;

#[derive(Clone, Debug)]
pub struct ParameterSymbol {
    pub name: String,
    pub kind: String,
    pub nonnull: bool,
}
#[derive(Clone, Debug)]
pub struct ProcSymbol {
    pub return_kind: String,
    pub return_nonnull: bool,
    pub parameters: Vec<ParameterSymbol>,
    inferred_return: bool,
}
#[derive(Clone, Debug)]
pub struct FieldSymbol {
    pub kind: String,
    pub nonnull: bool,
}
#[derive(Default)]
pub struct Symbols {
    procs: HashMap<(String, String), ProcSymbol>,
    pub duplicate_procs: HashSet<(String, String)>,
    fields: HashMap<(String, String), FieldSymbol>,
    parents: HashMap<String, String>,
    declared_types: HashSet<String>,
    pub unresolved_parents: Vec<(String, String, usize)>,
    pub bridge_schema: u64,
    pub frontend_errors: Option<i64>,
    source_files: Vec<(String, String)>,
    compiler_dir: Option<std::path::PathBuf>,
    source_manifest_valid: bool,
    compiler_identity: bool,
    bridge_identity: bool,
}

fn default_parent(owner: &str) -> Option<String> {
    if owner == "/" || owner.is_empty() {
        return None;
    }
    if owner.ends_with("/proc") || owner.ends_with("/verb") {
        return Some("/".into());
    }
    let builtin = match owner {
        "/datum" => "/",
        "/atom" => "/datum",
        "/atom/movable" => "/atom",
        "/obj" | "/mob" => "/atom/movable",
        "/turf" | "/area" => "/atom",
        "/list" | "/client" | "/world" | "/proc" | "/verb" | "/num" | "/text" | "/file"
        | "/sound" | "/icon" => "/",
        _ => {
            let (parent, _) = owner.rsplit_once('/')?;
            return Some(if parent.is_empty() {
                "/datum".into()
            } else {
                parent.into()
            });
        }
    };
    Some(builtin.into())
}

pub fn declared_type(path: Option<&str>, value_type: Option<&str>) -> String {
    if let Some(path) = path {
        if let Some(value) = match path {
            "/num" => Some("num"),
            "/text" => Some("text"),
            "/list" => Some("/list"),
            "/file" => Some("file"),
            "/sound" => Some("sound"),
            "/icon" => Some("icon"),
            _ => None,
        } {
            return value.into();
        }
        return path.into();
    }
    let raw = value_type.unwrap_or("anything").trim_matches('"');
    // OpenDream's valueType is a comma-separated set of runtime value kinds.
    // A single kind plus null is still useful type information; preserve the
    // nullable part rather than throwing the entire declaration away.
    let (nullable, raw) = if let Some(rest) = raw.strip_prefix("null, ") {
        (true, rest)
    } else {
        (false, raw)
    };
    let kind = if let Some(path) = raw.strip_prefix("path, ") {
        path.to_owned()
    } else if let Some(path) = match raw {
        "mob" => Some("/mob"),
        "obj" => Some("/obj"),
        "turf" => Some("/turf"),
        "area" => Some("/area"),
        "list" => Some("/list"),
        _ => None,
    } {
        path.to_owned()
    } else if matches!(raw, "message" | "commandtext" | "color") {
        // These are DM text input modes, not separate runtime value kinds.
        "text".to_owned()
    } else if ["num", "text", "null", "file", "sound", "icon"].contains(&raw) {
        raw.to_owned()
    } else {
        "unknown".to_owned()
    };
    if nullable && kind != "unknown" && kind != "null" {
        return format!("{kind}?");
    }
    kind
}

fn single_return(expression: &Value) -> Option<String> {
    let body = &expression["body"];
    let statements = body["fields"]["Statements"].as_array()?;
    if statements.len() != 1 || statements[0]["kind"] != "DMASTProcStatementReturn" {
        return None;
    }
    fn infer(value: &Value) -> Option<String> {
        match value["kind"].as_str()? {
            "DMASTConstantInteger" | "DMASTConstantFloat" => Some("num".into()),
            "DMASTConstantString" | "DMASTStringFormat" => Some("text".into()),
            "DMASTList" | "DMASTNewList" => Some("/list".into()),
            "DMASTNewPath" => value["fields"]["Path"]["fields"]["Value"]["fields"]["Path"]
                .as_str()
                .map(str::to_owned),
            "DMASTExpressionWrapped" => infer(&value["fields"]["Value"]),
            _ => None,
        }
    }
    infer(&statements[0]["fields"]["Value"])
}

impl Symbols {
    pub fn included_dm_files(&self, root: &Path) -> io::Result<Vec<std::path::PathBuf>> {
        let root = root.canonicalize()?;
        let standard_dir = self
            .compiler_dir
            .as_ref()
            .and_then(|path| path.join("DMStandard").canonicalize().ok());
        let mut files = Vec::new();
        let mut seen = HashSet::new();
        for (path, _) in &self.source_files {
            let path = Path::new(path);
            if !path
                .extension()
                .is_some_and(|extension| extension.eq_ignore_ascii_case("dm"))
            {
                continue;
            }
            let canonical = path.canonicalize().map_err(|error| {
                io::Error::new(error.kind(), format!("{}: {error}", path.display()))
            })?;
            if canonical.starts_with(&root)
                && !standard_dir
                    .as_ref()
                    .is_some_and(|dir| canonical.starts_with(dir))
                && seen.insert(canonical.clone())
            {
                files.push(canonical);
            }
        }
        files.sort();
        if files.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "OpenDream source manifest contains no DM files under the repository root",
            ));
        }
        Ok(files)
    }

    pub fn verify_export_file(path: &Path) -> io::Result<()> {
        let mut sidecar = path.as_os_str().to_os_string();
        sidecar.push(".sha256");
        let expected = std::fs::read_to_string(sidecar)?;
        let mut file = std::fs::File::open(path)?;
        let mut digest = Sha256::new();
        let mut chunk = [0_u8; 65536];
        loop {
            let count = file.read(&mut chunk)?;
            if count == 0 {
                break;
            }
            digest.update(&chunk[..count]);
        }
        if format!("{:x}", digest.finalize()) != expected.trim() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "OpenDream AST checksum does not match its sidecar; regenerate the export",
            ));
        }
        Ok(())
    }

    pub fn verify_sources(&self) -> io::Result<()> {
        if self.bridge_schema < 4
            || self.frontend_errors != Some(0)
            || self.source_files.is_empty()
            || !self.source_manifest_valid
            || !self.compiler_identity
            || !self.bridge_identity
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "AST needs OpenDreamBridge schema 4, zero frontend errors, and included-file hashes",
            ));
        }
        for (path, expected) in &self.source_files {
            let mut file = std::fs::File::open(path)?;
            let mut digest = Sha256::new();
            let mut chunk = [0_u8; 65536];
            loop {
                let count = file.read(&mut chunk)?;
                if count == 0 {
                    break;
                }
                digest.update(&chunk[..count]);
            }
            let actual = format!("{:x}", digest.finalize());
            if actual != *expected {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("AST source changed since export: {path}"),
                ));
            }
        }
        Ok(())
    }

    pub fn collect<R: BufRead>(reader: R, contracts: &[Contract]) -> io::Result<Self> {
        let mut symbols = Self::default();
        for line in reader.lines() {
            let line = line?;
            let mut deserializer = serde_json::Deserializer::from_str(&line);
            deserializer.disable_recursion_limit();
            let item = Value::deserialize(&mut deserializer)?;
            let owner = item["owner"].as_str().unwrap_or("").to_owned();
            if owner.starts_with('/') && owner != "/" {
                symbols.declared_types.insert(owner.clone());
            }
            let name = item["name"].as_str().unwrap_or("").to_owned();
            if item["kind"] == "bridge-meta" {
                symbols.bridge_schema = item["schemaVersion"].as_u64().unwrap_or(0);
                symbols.frontend_errors = item["frontendErrors"].as_i64();
                if let Some(entries) = item["sourceFiles"].as_array() {
                    symbols.source_manifest_valid = !entries.is_empty();
                    let mut seen = HashSet::new();
                    for entry in entries {
                        match (entry["path"].as_str(), entry["sha256"].as_str()) {
                            (Some(path), Some(hash))
                                if !path.is_empty()
                                    && hash.len() == 64
                                    && hash.bytes().all(|b| b.is_ascii_hexdigit())
                                    && seen.insert(path) =>
                            {
                                symbols.source_files.push((path.into(), hash.into()));
                            }
                            _ => symbols.source_manifest_valid = false,
                        }
                    }
                }
                if let (Some(path), Some(hash)) = (
                    item["compilerPath"].as_str(),
                    item["compilerSha256"].as_str(),
                ) {
                    if !path.is_empty()
                        && hash.len() == 64
                        && hash.bytes().all(|b| b.is_ascii_hexdigit())
                    {
                        symbols.source_files.push((path.into(), hash.into()));
                        symbols.compiler_identity = true;
                        symbols.compiler_dir = Path::new(path).parent().map(Path::to_path_buf);
                    }
                }
                if let (Some(path), Some(hash)) =
                    (item["bridgePath"].as_str(), item["bridgeSha256"].as_str())
                {
                    if !path.is_empty()
                        && hash.len() == 64
                        && hash.bytes().all(|b| b.is_ascii_hexdigit())
                    {
                        symbols.source_files.push((path.into(), hash.into()));
                        symbols.bridge_identity = true;
                    }
                }
            } else if item["kind"] == "type-parent" {
                let parent = item["parent"]
                    .as_str()
                    .or_else(|| item["expression"]["fields"]["Value"]["fields"]["Path"].as_str())
                    .or_else(|| item["expression"]["fields"]["Path"].as_str());
                if let Some(parent) = parent.filter(|parent| parent.starts_with('/')) {
                    symbols.parents.insert(owner, parent.into());
                } else {
                    symbols.unresolved_parents.push((
                        owner,
                        item["file"].as_str().unwrap_or("<unknown>").into(),
                        item["line"].as_u64().unwrap_or(1) as usize,
                    ));
                }
            } else if item["kind"] == "field" {
                let nonnull = contracts.iter().any(|c| {
                    c.owner == owner
                        && c.member == name
                        && c.parameter.is_none()
                        && c.visibility == Visibility::NonNull
                });
                symbols.fields.insert(
                    (owner, name),
                    FieldSymbol {
                        kind: declared_type(item["type"].as_str(), item["valueType"].as_str()),
                        nonnull,
                    },
                );
            } else if item["kind"] == "proc" {
                let inferred_return = if item["returnType"].is_null() {
                    single_return(&item)
                } else {
                    None
                };
                let inferred = inferred_return.is_some();
                let return_nonnull = inferred
                    || contracts.iter().any(|c| {
                        c.owner == owner
                            && c.member == name
                            && c.parameter.is_none()
                            && c.visibility == Visibility::NonNull
                    });
                let parameters = item["parameters"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|p| {
                        let param_name = p["Name"].as_str().unwrap_or("").to_owned();
                        let nonnull = contracts.iter().any(|c| {
                            c.owner == owner
                                && c.member == name
                                && c.parameter.as_deref() == Some(&param_name)
                                && c.visibility == Visibility::NonNull
                        });
                        ParameterSymbol {
                            name: param_name,
                            kind: declared_type(p["type"].as_str(), p["valueType"].as_str()),
                            nonnull,
                        }
                    })
                    .collect();
                if symbols.procs.contains_key(&(owner.clone(), name.clone())) {
                    symbols
                        .duplicate_procs
                        .insert((owner.clone(), name.clone()));
                }
                symbols.procs.insert(
                    (owner, name),
                    ProcSymbol {
                        return_kind: inferred_return
                            .unwrap_or_else(|| declared_type(None, item["returnType"].as_str())),
                        return_nonnull,
                        parameters,
                        inferred_return: inferred,
                    },
                );
            }
        }
        let declarations: Vec<_> = symbols.procs.keys().cloned().collect();
        let overridden: Vec<_> = symbols
            .procs
            .iter()
            .filter(|(_, proc)| proc.inferred_return)
            .filter(|((owner, name), _)| {
                declarations.iter().any(|(other_owner, other_name)| {
                    other_owner != owner
                        && other_name == name
                        && symbols.is_subtype(other_owner, owner)
                })
            })
            .map(|((owner, name), _)| (owner.clone(), name.clone()))
            .collect();
        for (owner, name) in overridden {
            let Some(proc) = symbols.procs.get_mut(&(owner.clone(), name.clone())) else {
                continue;
            };
            proc.return_kind = "unknown".into();
            proc.return_nonnull = contracts.iter().any(|contract| {
                contract.owner == owner
                    && contract.member == name
                    && contract.parameter.is_none()
                    && contract.visibility == Visibility::NonNull
            });
        }
        Ok(symbols)
    }
    pub fn proc(&self, owner: &str, name: &str) -> Option<&ProcSymbol> {
        let mut current = owner.to_owned();
        let mut seen = std::collections::HashSet::new();
        loop {
            if !seen.insert(current.clone()) {
                break;
            }
            if let Some(found) = self.procs.get(&(current.clone(), name.to_owned())) {
                return Some(found);
            }
            if current == "/" {
                break;
            }
            current = self.parent(&current).unwrap_or_else(|| "/".into());
        }
        self.procs.get(&("/".into(), name.into()))
    }
    pub fn field(&self, owner: &str, name: &str) -> Option<&FieldSymbol> {
        let mut current = owner.to_owned();
        let mut seen = std::collections::HashSet::new();
        loop {
            if !seen.insert(current.clone()) {
                break;
            }
            if let Some(found) = self.fields.get(&(current.clone(), name.to_owned())) {
                return Some(found);
            }
            if current == "/" {
                break;
            }
            current = self.parent(&current).unwrap_or_else(|| "/".into());
        }
        self.fields.get(&("/".into(), name.into()))
    }
    pub fn parent(&self, owner: &str) -> Option<String> {
        self.parents
            .get(owner)
            .cloned()
            .or_else(|| default_parent(owner))
    }
    pub fn is_subtype(&self, actual: &str, expected: &str) -> bool {
        let mut current = actual.to_owned();
        let mut seen = std::collections::HashSet::new();
        loop {
            if current == expected {
                return true;
            }
            if !seen.insert(current.clone()) {
                return false;
            }
            let Some(parent) = self.parent(&current) else {
                return false;
            };
            current = parent;
        }
    }
    pub fn common_ancestor(&self, a: &str, b: &str) -> Option<String> {
        if !a.starts_with('/') || !b.starts_with('/') {
            return None;
        }
        let mut current = a.to_owned();
        let mut seen = std::collections::HashSet::new();
        loop {
            if self.is_subtype(b, &current) {
                return Some(current);
            }
            if !seen.insert(current.clone()) {
                return None;
            }
            current = self.parent(&current)?;
        }
    }
    pub fn has_declared_descendant(&self, owner: &str) -> bool {
        self.declared_types
            .iter()
            .any(|candidate| candidate != owner && self.is_subtype(candidate, owner))
    }

    /// Owners with at least one distinct declared type below them. Compute this
    /// once when checking many fields instead of scanning every declared type
    /// for every field.
    pub fn declared_descendant_owners(&self) -> HashSet<String> {
        let mut owners = HashSet::new();
        for candidate in &self.declared_types {
            let mut current = self.parent(candidate);
            let mut seen = HashSet::new();
            while let Some(owner) = current {
                if owner == *candidate || !seen.insert(owner.clone()) {
                    break;
                }
                owners.insert(owner.clone());
                current = self.parent(&owner);
            }
        }
        owners
    }
}

#[cfg(test)]
mod tests {
    use super::{declared_type, Symbols};

    #[test]
    fn descendant_index_matches_individual_queries() {
        let mut symbols = Symbols::default();
        symbols.declared_types.extend(
            ["/datum/custom", "/datum/custom/sub", "/obj/foo"]
                .into_iter()
                .map(str::to_owned),
        );
        symbols
            .parents
            .insert("/datum/custom".into(), "/obj".into());
        let indexed = symbols.declared_descendant_owners();
        for owner in [
            "/",
            "/datum",
            "/obj",
            "/datum/custom",
            "/datum/custom/sub",
            "/obj/foo",
            "/other",
        ] {
            assert_eq!(
                indexed.contains(owner),
                symbols.has_declared_descendant(owner),
                "{owner}"
            );
        }
    }

    #[test]
    fn source_inventory_uses_frontend_manifest_not_include_text() {
        let root = std::env::temp_dir().join(format!(
            "dm-health-manifest-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(root.join("code")).unwrap();
        std::fs::create_dir_all(root.join("compiler")).unwrap();
        std::fs::create_dir_all(root.join("compiler/DMStandard")).unwrap();
        let manifest = root.join("project.dme");
        let included = root.join("code/real.dm");
        let compiler = root.join("compiler/DMCompiler.dll");
        let standard = root.join("compiler/DMStandard/_Globals.dm");
        std::fs::write(&manifest, b"#include \"missing.dm\"\n").unwrap();
        std::fs::write(&included, b"/datum/test\n").unwrap();
        std::fs::write(&compiler, b"compiler").unwrap();
        std::fs::write(&standard, b"var/global/test\n").unwrap();
        let digest = |bytes: &[u8]| format!("{:x}", <sha2::Sha256 as sha2::Digest>::digest(bytes));
        let meta = serde_json::json!({"kind":"bridge-meta","schemaVersion":4,
            "frontendErrors":0,"sourceFiles":[
                {"path":manifest,"sha256":digest(b"#include \"missing.dm\"\n")},
                {"path":included,"sha256":digest(b"/datum/test\n")},
                {"path":standard,"sha256":digest(b"var/global/test\n")}],
            "compilerPath":compiler,"compilerSha256":digest(b"compiler"),
            "bridgePath":manifest,"bridgeSha256":digest(b"#include \"missing.dm\"\n")});
        let symbols = Symbols::collect(meta.to_string().as_bytes(), &[]).unwrap();
        assert!(symbols.verify_sources().is_ok());
        assert_eq!(
            symbols.included_dm_files(&root).unwrap(),
            vec![included.canonicalize().unwrap()]
        );
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn detects_source_changes_after_ast_export() {
        let path = std::env::temp_dir().join(format!(
            "dm-health-source-hash-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&path, b"original").unwrap();
        let digest = <sha2::Sha256 as sha2::Digest>::digest(b"original");
        let hash = format!("{digest:x}");
        let meta = serde_json::json!({"kind":"bridge-meta","schemaVersion":4,
            "frontendErrors":0,"sourceFiles":[{"path":path,"sha256":hash}],
            "compilerPath":path,"compilerSha256":hash,
            "bridgePath":path,"bridgeSha256":hash});
        let symbols = Symbols::collect(meta.to_string().as_bytes(), &[]).unwrap();
        assert!(symbols.verify_sources().is_ok());
        std::fs::write(&path, b"changed").unwrap();
        assert!(symbols.verify_sources().is_err());
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn rejects_incomplete_source_manifest() {
        let meta = serde_json::json!({"kind":"bridge-meta","schemaVersion":4,
            "frontendErrors":0,"sourceFiles":[{"path":"missing.dm"}],
            "compilerPath":"compiler.dll","compilerSha256":"0".repeat(64)});
        let symbols = Symbols::collect(meta.to_string().as_bytes(), &[]).unwrap();
        assert!(symbols.verify_sources().is_err());
    }

    #[test]
    fn records_frontend_error_count() {
        let input = "{\"kind\":\"bridge-meta\",\"schemaVersion\":3,\"frontendErrors\":2}\n";
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        assert_eq!(symbols.bridge_schema, 3);
        assert_eq!(symbols.frontend_errors, Some(2));
    }

    #[test]
    fn tracks_reopened_proc_definitions() {
        let proc = r#"{"kind":"proc","owner":"/datum/test","name":"Run","parameters":[],"body":{"fields":{"Statements":[]}}}"#;
        let input = format!("{proc}\n{proc}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        assert!(symbols
            .duplicate_procs
            .contains(&("/datum/test".into(), "Run".into())));
    }

    #[test]
    fn parses_opendream_path_return_type() {
        assert_eq!(
            declared_type(None, Some("\"path, /datum/example\"")),
            "/datum/example"
        );
        assert_eq!(declared_type(None, Some("\"mob\"")), "/mob");
        assert_eq!(declared_type(None, Some("\"null, num\"")), "num?");
        assert_eq!(declared_type(None, Some("\"null, text\"")), "text?");
        assert_eq!(declared_type(None, Some("\"null, path, /list\"")), "/list?");
        assert_eq!(declared_type(None, Some("\"message\"")), "text");
        assert_eq!(declared_type(None, Some("\"commandtext\"")), "text");
        assert_eq!(declared_type(None, Some("\"null, color\"")), "text?");
        assert_eq!(declared_type(None, Some("\"obj, mob\"")), "unknown");
    }

    #[test]
    fn retains_nullable_frontend_symbol_types() {
        let input = [
            r#"{"kind":"field","owner":"/datum","name":"label","type":null,"valueType":"\"null, text\""}"#,
            r#"{"kind":"proc","owner":"/datum","name":"Count","returnType":"\"null, num\"","parameters":[{"Name":"limit","type":null,"valueType":"\"null, num\""}],"body":null}"#,
        ]
        .join("\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        assert_eq!(symbols.field("/datum", "label").unwrap().kind, "text?");
        let count = symbols.proc("/datum", "Count").unwrap();
        assert_eq!(count.return_kind, "num?");
        assert_eq!(count.parameters[0].kind, "num?");
        assert!(!count.return_nonnull);
    }

    #[test]
    fn infers_only_a_simple_nonnull_return() {
        let input = r#"{"kind":"proc","owner":"/datum","name":"GetCount","returnType":null,"parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementReturn","fields":{"Value":{"kind":"DMASTConstantInteger","fields":{"Value":5}}}}]}}}"#;
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let proc = symbols.proc("/datum", "GetCount").unwrap();
        assert_eq!(proc.return_kind, "num");
        assert!(proc.return_nonnull);
    }
    #[test]
    fn does_not_trust_inferred_return_with_override() {
        let input = [
            r#"{"kind":"proc","owner":"/datum","name":"GetCount","returnType":null,"parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementReturn","fields":{"Value":{"kind":"DMASTConstantInteger","fields":{"Value":5}}}}]}}}"#,
            r#"{"kind":"proc","owner":"/datum/child","name":"GetCount","returnType":null,"parameters":[],"body":null}"#,
        ].join("\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let proc = symbols.proc("/datum", "GetCount").unwrap();
        assert_eq!(proc.return_kind, "unknown");
        assert!(!proc.return_nonnull);
    }

    #[test]
    fn parent_type_override_controls_subtyping_and_lookup() {
        let input = [
            r#"{"kind":"type-parent","owner":"/turf/simulated","parent":"/turf/open"}"#,
            r#"{"kind":"field","owner":"/turf/open","name":"air","type":"/datum/gas_mixture","valueType":"anything"}"#,
        ].join("\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        assert!(symbols.is_subtype("/turf/simulated", "/turf/open"));
        assert!(!symbols.is_subtype("/turf/simulated", "/turf/closed"));
        assert!(symbols.field("/turf/simulated", "air").is_some());
    }
}
