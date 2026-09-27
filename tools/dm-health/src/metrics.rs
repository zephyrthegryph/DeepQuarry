//! Project and per-proc metrics derived from OpenDream's AST.
use crate::Finding;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::io::{self, BufRead};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ProcMetric {
    pub owner: String,
    pub name: String,
    pub path: String,
    pub line: usize,
    pub lines: usize,
    pub statements: usize,
    pub branches: usize,
    pub max_nesting: usize,
    pub parameters: usize,
    pub locals: usize,
    pub returns: usize,
    pub calls: usize,
    pub distinct_calls: usize,
    pub global_reads: usize,
    pub global_writes: usize,
    pub type_references: usize,
    pub null_literals: usize,
    pub safe_dereferences: usize,
    pub unsafe_dereferences: usize,
    pub allocations: usize,
    pub spawns: usize,
    pub sleeps: usize,
    pub dynamic_calls: usize,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct FileMetric {
    pub path: String,
    pub module: String,
    pub module_root: String,
    pub lines: usize,
    pub code_lines: usize,
    pub comment_lines: usize,
    pub blank_lines: usize,
    pub procs: usize,
    pub fields: usize,
    pub findings: usize,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ModuleMetric {
    pub name: String,
    pub parent: String,
    pub depth: usize,
    pub direct_files: usize,
    pub documented: bool,
    pub boundary: bool,
    pub files: usize,
    pub lines: usize,
    pub code_lines: usize,
    pub comment_lines: usize,
    pub blank_lines: usize,
    pub procs: usize,
    pub fields: usize,
    pub findings: usize,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ProjectMetrics {
    pub procs: Vec<ProcMetric>,
    pub files: Vec<FileMetric>,
    pub modules: Vec<ModuleMetric>,
    pub coupling: Vec<CouplingMetric>,
    #[serde(skip)]
    owner_modules: HashMap<String, BTreeSet<String>>,
    #[serde(skip)]
    references: Vec<ProcReferences>,
    pub totals: BTreeMap<String, usize>,
    pub global_writers: BTreeMap<String, usize>,
    pub global_readers: BTreeMap<String, usize>,
    pub call_fan_in: BTreeMap<String, usize>,
}

#[derive(Clone, Debug, Default)]
struct ProcReferences {
    from: String,
    types: BTreeSet<String>,
    reads: BTreeSet<String>,
    writes: BTreeSet<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct CouplingMetric {
    pub from: String,
    pub to: String,
    pub kind: String,
    pub references: usize,
}

pub fn module_for(path: &str) -> String {
    path.rsplit_once('/')
        .map_or("<root>", |(parent, _)| parent)
        .into()
}

pub fn module_root_for(path: &str, root: &std::path::Path) -> String {
    let directory = module_for(path);
    let mut current = directory.as_str();
    loop {
        if readme_exists(&root.join(current)) {
            return current.into();
        }
        current = match current.rsplit_once('/') {
            Some((parent, _)) => parent,
            None => return "<unassigned>".into(),
        };
    }
}

fn readme_exists(directory: &std::path::Path) -> bool {
    ["README.md", "readme.md", "Readme.md"]
        .into_iter()
        .map(|name| directory.join(name))
        .any(|path| path.is_file())
}

fn readme_path(directory: &std::path::Path) -> Option<std::path::PathBuf> {
    std::fs::read_dir(directory)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| {
            path.file_name()
                .is_some_and(|name| name.to_string_lossy().eq_ignore_ascii_case("readme.md"))
                && path.is_file()
        })
}

fn module_ancestors(path: &str, root: &str) -> Vec<String> {
    let mut names = vec![root.to_owned()];
    let mut current = root.to_owned();
    let suffix = path
        .strip_prefix(root)
        .unwrap_or("")
        .trim_start_matches('/');
    for part in suffix.split('/').filter(|part| !part.is_empty()) {
        current.push('/');
        current.push_str(part);
        names.push(current.clone());
    }
    names
}

pub fn source_lines(bytes: &[u8]) -> (usize, usize, usize, usize) {
    let source = String::from_utf8_lossy(bytes);
    let mut lines = 0;
    let mut code = 0;
    let mut comments = 0;
    let mut blank = 0;
    let mut in_block = false;
    let mut in_string = false;
    for raw in source.lines() {
        lines += 1;
        let text = raw.as_bytes();
        let mut i = 0;
        let mut has_code = false;
        let mut has_comment = in_block;
        while i < text.len() {
            if in_block {
                if text[i..].starts_with(b"*/") {
                    in_block = false;
                    i += 2;
                } else {
                    i += 1;
                }
            } else if in_string {
                has_code = true;
                if text[i] == b'\\' {
                    i += 2;
                    continue;
                }
                if text[i] == b'"' {
                    in_string = false;
                }
                i += 1;
            } else if text[i..].starts_with(b"//") {
                has_comment = true;
                break;
            } else if text[i..].starts_with(b"/*") {
                has_comment = true;
                in_block = true;
                i += 2;
            } else {
                if text[i] == b'"' {
                    in_string = true;
                }
                if !text[i].is_ascii_whitespace() {
                    has_code = true;
                }
                i += 1;
            }
        }
        if has_code {
            code += 1;
        } else if has_comment {
            comments += 1;
        } else {
            blank += 1;
        }
    }
    (lines, code, comments, blank)
}

pub fn finalize_sources(project: &mut ProjectMetrics, root: &std::path::Path) {
    let mut modules = BTreeMap::<String, ModuleMetric>::new();
    for file in &mut project.files {
        file.module = module_for(&file.path);
        file.module_root = module_root_for(&file.path, root);
        let top = file.module.split('/').next().unwrap_or(&file.module);
        for name in module_ancestors(&file.module, top) {
            let parent = if name == top {
                String::new()
            } else {
                name.rsplit_once('/').map_or("", |(p, _)| p).into()
            };
            let module = modules.entry(name.clone()).or_insert_with(|| ModuleMetric {
                name: name.clone(),
                parent,
                depth: name.matches('/').count(),
                documented: readme_exists(&root.join(&name)),
                ..ModuleMetric::default()
            });
            module.files += 1;
            module.lines += file.lines;
            module.code_lines += file.code_lines;
            module.comment_lines += file.comment_lines;
            module.blank_lines += file.blank_lines;
            module.procs += file.procs;
            module.fields += file.fields;
            module.findings += file.findings;
            if module.documented {
                module.boundary = true;
            }
            if name == file.module {
                module.direct_files += 1;
            }
        }
    }
    project.modules = modules.into_values().collect();
    project
        .totals
        .insert("modules".into(), project.modules.len());
    project.totals.insert(
        "module_roots".into(),
        project.modules.iter().filter(|m| m.boundary).count(),
    );
    project.totals.insert(
        "documented_modules".into(),
        project
            .modules
            .iter()
            .filter(|m| m.boundary && m.documented)
            .count(),
    );
    for (key, value) in [
        ("lines", project.files.iter().map(|f| f.lines).sum()),
        (
            "code_lines",
            project.files.iter().map(|f| f.code_lines).sum(),
        ),
        (
            "comment_lines",
            project.files.iter().map(|f| f.comment_lines).sum(),
        ),
        (
            "blank_lines",
            project.files.iter().map(|f| f.blank_lines).sum(),
        ),
    ] {
        project.totals.insert(key.into(), value);
    }
}

pub fn documentation_diagnostics(project: &ProjectMetrics, root: &std::path::Path) -> Vec<Finding> {
    let mut marked = BTreeSet::<String>::new();
    for file in &project.files {
        marked.insert(module_root_for(&file.path, root));
    }
    let mut findings = Vec::new();
    for module in marked {
        if let Some(path) = readme_path(&root.join(&module)) {
            if let Ok(content) = std::fs::read_to_string(&path) {
                if content.trim().chars().count() < 120 {
                    findings.push(Finding {
                        rule: "module-readme-thin",
                        path: path
                            .strip_prefix(root)
                            .unwrap_or(&path)
                            .to_string_lossy()
                            .replace('\\', "/"),
                        line: 1,
                        severity: "warning",
                        message: "module README needs at least 120 characters of documentation"
                            .into(),
                    });
                }
            }
        }
    }
    findings
}

pub fn finalize_coupling(
    project: &mut ProjectMetrics,
    root: &std::path::Path,
) -> std::io::Result<()> {
    let macro_re = regex::Regex::new(
        r"(?m)^\s*GLOBAL_(?:VAR|LIST|ALIST|DATUM)(?:_[A-Z_]+)?\(\s*([A-Za-z_]\w*)",
    )
    .expect("static regex");
    let mut globals = HashMap::<String, BTreeSet<String>>::new();
    for file in &project.files {
        let source = std::fs::read_to_string(root.join(&file.path)).unwrap_or_default();
        for capture in macro_re.captures_iter(&source) {
            globals
                .entry(capture[1].into())
                .or_default()
                .insert(module_root_for(&file.path, root));
        }
    }
    let mut edges = BTreeMap::<(String, String, String), usize>::new();
    for reference in &project.references {
        for ty in &reference.types {
            if let Some(targets) = project.owner_modules.get(ty) {
                if targets.len() == 1 {
                    let target = targets.iter().next().expect("one target");
                    if *target != reference.from {
                        *edges
                            .entry((reference.from.clone(), target.clone(), "type".into()))
                            .or_default() += 1;
                    }
                }
            }
        }
        for (names, kind) in [
            (&reference.reads, "global read"),
            (&reference.writes, "global write"),
        ] {
            for name in names {
                if let Some(targets) = globals.get(name) {
                    if targets.len() == 1 {
                        let target = targets.iter().next().expect("one target");
                        if *target != reference.from {
                            *edges
                                .entry((reference.from.clone(), target.clone(), kind.into()))
                                .or_default() += 1;
                        }
                    }
                }
            }
        }
    }
    project.coupling = edges
        .into_iter()
        .map(|((from, to, kind), references)| CouplingMetric {
            from,
            to,
            kind,
            references,
        })
        .collect();
    project.totals.insert(
        "cross_module_references".into(),
        project.coupling.iter().map(|e| e.references).sum(),
    );
    project
        .totals
        .insert("cross_module_edges".into(), project.coupling.len());
    Ok(())
}

#[derive(Default)]
struct ProcAccumulator {
    metric: ProcMetric,
    end_line: usize,
    reads: BTreeSet<String>,
    writes: BTreeSet<String>,
    calls: BTreeSet<String>,
    types: BTreeSet<String>,
}

fn field<'a>(node: &'a Value, key: &str) -> &'a Value {
    &node["fields"][key]
}
fn kind(node: &Value) -> &str {
    node["kind"].as_str().unwrap_or("")
}
fn children(node: &Value) -> Vec<&Value> {
    node["fields"]
        .as_object()
        .into_iter()
        .flat_map(|fields| fields.values())
        .flat_map(|value| {
            value
                .as_array()
                .map(|array| array.iter().collect::<Vec<_>>())
                .unwrap_or_else(|| vec![value])
        })
        .filter(|value| value.is_object() && value.get("kind").is_some())
        .collect()
}
fn global_member(node: &Value) -> Option<&str> {
    if kind(node) != "DMASTDereference"
        || kind(field(node, "Expression")) != "DMASTIdentifier"
        || field(field(node, "Expression"), "Identifier").as_str() != Some("GLOB")
    {
        return None;
    }
    field(node, "Operations").as_array()?.first()?["fields"]["Identifier"].as_str()
}
fn call_name(node: &Value) -> Option<&str> {
    if kind(node) == "DMASTProcCall" {
        return field(field(node, "Callable"), "Identifier").as_str();
    }
    None
}
fn walk(node: &Value, depth: usize, current_proc: &mut ProcAccumulator) {
    let node_kind = kind(node);
    if let Some(line) = node["line"].as_u64() {
        if node["file"].as_str() == Some(current_proc.metric.path.as_str()) {
            current_proc.end_line = current_proc.end_line.max(line as usize);
        }
    }
    let is_statement = node_kind.starts_with("DMASTProcStatement");
    if is_statement {
        current_proc.metric.statements += 1;
    }
    let branch = matches!(
        node_kind,
        "DMASTProcStatementIf"
            | "DMASTProcStatementFor"
            | "DMASTProcStatementWhile"
            | "DMASTProcStatementDoWhile"
            | "DMASTProcStatementSwitch"
            | "DMASTProcStatementTryCatch"
    );
    if branch {
        current_proc.metric.branches += 1;
        current_proc.metric.max_nesting = current_proc.metric.max_nesting.max(depth + 1);
    }
    if node_kind == "DMASTProcStatementVarDeclaration" {
        current_proc.metric.locals += 1;
    }
    if node_kind == "DMASTProcStatementReturn" {
        current_proc.metric.returns += 1;
    }
    if node_kind == "DMASTConstantNull" {
        current_proc.metric.null_literals += 1;
    }
    if node_kind.starts_with("DMASTNew") {
        current_proc.metric.allocations += 1;
    }
    if node_kind == "DMASTProcStatementSpawn" {
        current_proc.metric.spawns += 1;
    }
    if let Some(member) = global_member(node) {
        current_proc.reads.insert(member.into());
    }
    if node_kind.ends_with("Assign") {
        if let Some(member) = global_member(field(node, "LHS")) {
            current_proc.writes.insert(member.into());
        }
    }
    if let Some(name) = call_name(node) {
        current_proc.metric.calls += 1;
        current_proc.calls.insert(name.into());
        if name == "sleep" {
            current_proc.metric.sleeps += 1;
        }
    }
    if node_kind == "DMASTCall" {
        current_proc.metric.dynamic_calls += 1;
    }
    if node_kind == "DMASTConstantPath" {
        if let Some(path) = field(field(node, "Value"), "Path").as_str() {
            current_proc.types.insert(path.into());
        }
    }
    if node_kind == "DMASTDereference" {
        let safe = field(node, "Operations")
            .as_array()
            .and_then(|ops| ops.first())
            .and_then(|op| field(op, "Safe").as_bool())
            .unwrap_or(false);
        if safe {
            current_proc.metric.safe_dereferences += 1;
        } else {
            current_proc.metric.unsafe_dereferences += 1;
        }
        if let Some(ops) = field(node, "Operations").as_array() {
            for op in ops {
                if kind(op) == "CallOperation" {
                    current_proc.metric.calls += 1;
                    if let Some(name) = field(op, "Identifier").as_str() {
                        current_proc.calls.insert(name.into());
                    }
                }
            }
        }
    }
    for child in children(node) {
        walk(child, depth + usize::from(branch), current_proc);
    }
}

pub fn collect<R: BufRead>(reader: R, root: &std::path::Path) -> io::Result<ProjectMetrics> {
    collect_in_files(reader, root, None)
}

pub fn collect_in_files<R: BufRead>(
    reader: R,
    root: &std::path::Path,
    included: Option<&HashSet<String>>,
) -> io::Result<ProjectMetrics> {
    let mut project = ProjectMetrics::default();
    let mut files: HashMap<String, FileMetric> = HashMap::new();
    let mut module_by_file = HashMap::<String, Option<String>>::new();
    for line in reader.lines() {
        let line = line?;
        let mut deserializer = serde_json::Deserializer::from_str(&line);
        deserializer.disable_recursion_limit();
        let item = Value::deserialize(&mut deserializer)?;
        let path = item["file"]
            .as_str()
            .unwrap_or("<unknown>")
            .replace('\\', "/");
        if included.is_some_and(|files| !files.contains(&path)) {
            continue;
        }
        let module = module_by_file
            .entry(path.clone())
            .or_insert_with(|| {
                root.join(&path)
                    .is_file()
                    .then(|| module_root_for(&path, root))
            })
            .clone();
        let Some(module) = module else {
            continue;
        };
        if let Some(owner) = item["owner"].as_str() {
            project
                .owner_modules
                .entry(owner.into())
                .or_default()
                .insert(module.clone());
        }
        if item["kind"] == "field" {
            files.entry(path.clone()).or_default().fields += 1;
            files.entry(path.clone()).or_default().path = path.clone();
            continue;
        }
        if item["kind"] != "proc" {
            continue;
        }
        let owner = item["owner"].as_str().unwrap_or("").to_owned();
        let line = item["line"].as_u64().unwrap_or(1) as usize;
        let mut accum = ProcAccumulator {
            metric: ProcMetric {
                owner: owner.clone(),
                name: item["name"].as_str().unwrap_or("").into(),
                path: path.clone(),
                line,
                parameters: item["parameters"].as_array().map_or(0, Vec::len),
                ..ProcMetric::default()
            },
            end_line: line,
            ..ProcAccumulator::default()
        };
        walk(&item["body"], 0, &mut accum);
        accum.metric.lines = accum.end_line.saturating_sub(line) + 1;
        accum.metric.distinct_calls = accum.calls.len();
        accum.metric.global_reads = accum.reads.len();
        accum.metric.global_writes = accum.writes.len();
        accum.metric.type_references = accum.types.len();
        project.references.push(ProcReferences {
            from: module,
            types: accum.types.clone(),
            reads: accum.reads.clone(),
            writes: accum.writes.clone(),
        });
        for name in accum.reads {
            *project.global_readers.entry(name).or_default() += 1;
        }
        for name in accum.writes {
            *project.global_writers.entry(name).or_default() += 1;
        }
        for name in accum.calls {
            *project.call_fan_in.entry(name).or_default() += 1;
        }
        files.entry(path.clone()).or_default().procs += 1;
        files.entry(path.clone()).or_default().path = path.clone();
        project.procs.push(accum.metric);
    }
    project.files = files.into_values().collect();
    project.files.sort_by(|a, b| a.path.cmp(&b.path));
    for (name, amount) in [
        ("procs", project.procs.len()),
        ("files", project.files.len()),
        ("fields", project.files.iter().map(|f| f.fields).sum()),
        (
            "statements",
            project.procs.iter().map(|p| p.statements).sum(),
        ),
        ("branches", project.procs.iter().map(|p| p.branches).sum()),
        ("calls", project.procs.iter().map(|p| p.calls).sum()),
        (
            "null_literals",
            project.procs.iter().map(|p| p.null_literals).sum(),
        ),
        (
            "safe_dereferences",
            project.procs.iter().map(|p| p.safe_dereferences).sum(),
        ),
        (
            "unsafe_dereferences",
            project.procs.iter().map(|p| p.unsafe_dereferences).sum(),
        ),
        (
            "allocations",
            project.procs.iter().map(|p| p.allocations).sum(),
        ),
        ("spawns", project.procs.iter().map(|p| p.spawns).sum()),
        ("sleeps", project.procs.iter().map(|p| p.sleeps).sum()),
        (
            "dynamic_calls",
            project.procs.iter().map(|p| p.dynamic_calls).sum(),
        ),
        ("global_fields_read", project.global_readers.len()),
        ("global_fields_written", project.global_writers.len()),
    ] {
        project.totals.insert(name.into(), amount);
    }
    Ok(project)
}

pub fn diagnostics(project: &ProjectMetrics) -> Vec<Finding> {
    let mut result = Vec::new();
    for proc in &project.procs {
        for (trigger, rule, detail) in [
            (
                matches!(proc.name.as_str(), "Initialize" | "Destroy") && proc.sleeps > 0,
                "sleep-in-lifecycle",
                format!("{} sleep calls in lifecycle proc", proc.sleeps),
            ),
            (
                matches!(proc.name.as_str(), "Initialize" | "Destroy") && proc.spawns > 0,
                "spawn-in-lifecycle",
                format!("{} spawn statements in lifecycle proc", proc.spawns),
            ),
            (
                proc.dynamic_calls > 10,
                "reflection-heavy-proc",
                format!("{} dynamic call() expressions", proc.dynamic_calls),
            ),
            (
                proc.branches > 30,
                "high-complexity",
                format!("{} branches; threshold 30", proc.branches),
            ),
            (
                proc.max_nesting > 8,
                "deep-nesting",
                format!("{} levels; threshold 8", proc.max_nesting),
            ),
            (
                proc.parameters > 9,
                "many-parameters",
                format!("{} parameters; threshold 9", proc.parameters),
            ),
            (
                proc.locals > 35,
                "many-locals",
                format!("{} locals; threshold 35", proc.locals),
            ),
            (
                proc.distinct_calls > 25,
                "high-fan-out",
                format!("{} distinct calls; threshold 25", proc.distinct_calls),
            ),
            (
                proc.global_writes > 8,
                "global-write-coupling",
                format!(
                    "{} distinct globals written; threshold 8",
                    proc.global_writes
                ),
            ),
            (
                proc.null_literals > 30,
                "null-heavy-proc",
                format!("{} null literals; threshold 30", proc.null_literals),
            ),
            (
                proc.unsafe_dereferences > 100,
                "deref-heavy-proc",
                format!(
                    "{} direct dereferences; threshold 100",
                    proc.unsafe_dereferences
                ),
            ),
        ] {
            if trigger {
                result.push(Finding {
                    rule,
                    path: proc.path.clone(),
                    line: proc.line,
                    severity: "info",
                    message: format!("{}/{}: {detail}", proc.owner, proc.name),
                });
            }
        }
    }
    for (global, writers) in &project.global_writers {
        if *writers > 20 {
            result.push(Finding {
                rule: "widely-written-global",
                path: "<project>".into(),
                line: 1,
                severity: "info",
                message: format!("GLOB.{global} is written by {writers} procs"),
            });
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn source_loc_and_module_rollup() {
        let (lines, code, comments, blank) =
            source_lines(b"// heading\nvar/x = 1 /* inline */\n/* block\nend */\n\nproc/Foo()\n");
        assert_eq!((lines, code, comments, blank), (6, 2, 3, 1));
        assert_eq!(
            source_lines(b"var/x = \"/* not a comment */\"\nvar/y = 2\n"),
            (2, 2, 0, 0)
        );
        let mut project = ProjectMetrics {
            files: vec![FileMetric {
                path: "code/modules/admin/a.dm".into(),
                lines,
                code_lines: code,
                comment_lines: comments,
                blank_lines: blank,
                procs: 1,
                findings: 2,
                ..FileMetric::default()
            }],
            ..ProjectMetrics::default()
        };
        finalize_sources(&mut project, std::path::Path::new("."));
        assert_eq!(project.modules[0].name, "code");
        assert_eq!(project.modules[0].code_lines, 2);
        assert_eq!(project.totals["lines"], 6);
    }
    #[test]
    fn only_readmes_define_module_boundaries() {
        let root = std::env::temp_dir().join(format!(
            "dm-health-readme-boundaries-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(root.join("code/modules/feature/nested")).unwrap();
        std::fs::write(root.join("code/README.md"), "root module").unwrap();
        assert_eq!(
            module_root_for("code/modules/feature/nested/a.dm", &root),
            "code"
        );
        std::fs::write(
            root.join("code/modules/feature/README.md"),
            "feature module",
        )
        .unwrap();
        assert_eq!(
            module_root_for("code/modules/feature/nested/a.dm", &root),
            "code/modules/feature"
        );
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn measures_procs_and_global_writes() {
        let input = r#"{"kind":"proc","owner":"/datum","name":"Run","file":"src/metrics.rs","line":1,"parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementExpression","file":"src/metrics.rs","line":2,"fields":{"Expression":{"kind":"DMASTAssign","fields":{"LHS":{"kind":"DMASTDereference","fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"GLOB"}},"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"counter"}}]}}}}}}]}}}"#;
        let metrics = collect(
            input.as_bytes(),
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")),
        )
        .unwrap();
        assert_eq!(metrics.procs.len(), 1);
        assert_eq!(metrics.procs[0].statements, 1);
        assert_eq!(metrics.global_writers["counter"], 1);
    }
    #[test]
    fn excludes_external_opendream_standard_files() {
        let input = r#"{"kind":"proc","owner":"/list","name":"Copy","file":"Types/List.dm","line":1,"parameters":[],"body":{}}"#;
        let metrics = collect(
            input.as_bytes(),
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")),
        )
        .unwrap();
        assert!(metrics.files.is_empty());
        assert!(metrics.procs.is_empty());
    }
}
