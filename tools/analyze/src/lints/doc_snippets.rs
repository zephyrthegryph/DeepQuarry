//! Port of `tools/ci/doc_snippets.py`: the ```dm blocks of doc/rewrite/*.md (dx_conventions.md
//! section 9, design review H5 docs drift).
//!
//! A complete block (```dm) is real DM, a ```dm fragment is a sketch, ```dm before is skipped. For
//! complete and fragment blocks, `doc_unknown_name` flags a call that names nothing in `code/` (or
//! the block). The baseline also carries `doc_legacy_block` rows (complete blocks that predate the
//! lint), so the policy is custom: it checks the unknown-name ratchet and rewrites both row kinds.
//!
//! Not ported: `--write` (generates `tools/ci/generated/doc_snippets.dm`) and `--report`; they stay
//! in the Python script. Only the direct children of `doc/rewrite/` are read (`glob("*.md")`, not
//! recursive), which the lint applies itself because a `Select` root is recursive.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt::Write as _;
use std::path::PathBuf;

use crate::baseline::{self, Mode};
use crate::dm::dx::{lineage, DxIndex};
use crate::lint::{Cx, Lint, Meta, Policy, Registry, Run, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::strip::sanitize;
use crate::tree::{Select, SourceFile, Tree};
use crate::util::{normalize_ws, py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};

const LINT: &str = "doc_snippets";
const DOCS: &str = "doc/rewrite";
const BASELINE: &str = "tools/ci/doc_snippets_baseline.txt";
const LEGACY_RULE: &str = "doc_legacy_block";
const RULE: &str = "doc_unknown_name";
const HINT: &str = "the doc calls something that doesn't exist: use the real name, or build it first (docs drift, design review H5)";
const HEADER: &[&str] = &[
    "doc_snippets baseline (tools/ci/doc_snippets.py): doc_unknown_name is a ratchet (target 0);",
    "doc_legacy_block lists the complete blocks that predate the lint and aren't compiled (first line).",
];

static META: Meta = Meta {
    name: "doc_snippets",
    group: "",
    label: "doc_snippets",
    legacy: "tools/ci/doc_snippets.py",
    select: Select { roots: &[("doc/rewrite", "md"), ("code", "dm")], hidden: false },
    scan: ScanKind::Tree,
    policy: Policy::Custom,
    rules: &[RuleMeta { name: RULE, hint: HINT }],
    allow: &["doc_snippets"],
    lists: &[],
};

const KEYWORDS: &[&str] = &[
    "ASSERT", "CRASH", "EXCEPTION", "alist", "arglist", "as", "break", "call", "call_ext", "catch",
    "continue", "del", "do", "else", "for", "goto", "if", "in", "initial", "input", "issaved", "istype",
    "list", "locate", "nameof", "new", "proc", "return", "set", "sleep", "spawn", "step", "switch", "throw",
    "to", "try", "typesof", "var", "verb", "while",
];
const BUILTINS: &[&str] = &[
    "REGEX_QUOTE", "REGEX_QUOTE_REPLACEMENT", "abs", "addtext", "alert", "animate", "arccos", "arcsin",
    "arctan", "ascii2text", "astype", "block", "bound_pixloc", "bounds", "bounds_dist", "browse",
    "browse_rsc", "ceil", "ckey", "ckeyEx", "clamp", "cmptext", "cmptextEx", "copytext", "copytext_char",
    "cos", "fcopy", "fcopy_rsc", "fdel", "fexists", "file", "file2text", "filter", "findlasttext",
    "findlasttextEx", "findtext", "findtextEx", "flick", "flist", "floor", "fract", "ftime", "ftp",
    "generator", "get_dir", "get_dist", "get_step", "get_step_away", "get_step_rand", "get_step_to",
    "get_step_towards", "get_steps_to", "gradient", "hascall", "hearers", "html_decode", "html_encode",
    "icon", "icon_states", "image", "isarea", "isfile", "isicon", "isinf", "islist", "isloc", "ismob",
    "ismovable", "isnan", "isnull", "isnum", "isobj", "ispath", "ispointer", "istext", "isturf", "jointext",
    "json_decode", "json_encode", "length", "length_char", "lentext", "list2params", "load_ext",
    "load_resource", "log", "lowertext", "matrix", "max", "md5", "min", "noise_hash", "nonspantext",
    "num2text", "obounds", "ohearers", "orange", "output", "oview", "oviewers", "params2list", "pick",
    "pixloc", "prob", "rand", "rand_seed", "range", "ref", "refcount", "regex", "replacetext",
    "replacetextEx", "rgb", "rgb2num", "roll", "round", "run", "shell", "shutdown", "sign", "sin", "sorttext",
    "sorttextEx", "sound", "spantext", "spantext_char", "splicetext", "splicetext_char", "splittext", "sqrt",
    "startup", "stat", "statpanel", "step_away", "step_rand", "step_to", "step_towards", "tan", "text",
    "text2ascii", "text2file", "text2num", "text2path", "time2text", "trimtext", "trunc", "turn", "uppertext",
    "url_decode", "url_encode", "values_cut_over", "values_cut_under", "values_dot", "values_product",
    "values_sum", "vector", "view", "viewers", "walk", "walk_away", "walk_rand", "walk_to", "walk_towards",
    "winclone", "winexists", "winget", "winset", "winshow",
];
const MEMBER_BUILTINS: &[&str] = &[
    "Add", "AddCredits", "Blend", "Cache", "ClearMedal", "Close", "Columns", "Copy", "Crop", "Cut", "Del",
    "DrawBox", "ErrorMsg", "Execute", "Export", "Find", "Flip", "GetColumn", "GetConfig", "GetMedal",
    "GetPixel", "GetRowData", "GetScores", "Height", "IconStates", "Import", "Insert", "Interpolate",
    "Invert", "IsBanned", "Join", "MapColors", "MeasureText", "Multiply", "New", "NextRow", "Open",
    "OpenPort", "Profile", "Rand", "Read", "Reboot", "Remove", "RemoveAll", "Replace", "RowsAffected",
    "Scale", "SetConfig", "SetIntensity", "SetMedal", "SetScores", "Shift", "Splice", "Stat", "Subtract",
    "Swap", "SwapColor", "Topic", "Translate", "Turn", "Width", "Write",
];

// ---- blocks -----------------------------------------------------------------------------------

#[derive(Clone, Debug)]
struct Block {
    rel: String,
    /// 1-based line of the opening fence (only `--write` used it).
    #[allow(dead_code)]
    start: usize,
    tag: Option<String>,
    lines: Vec<String>,
    code_start: usize,
}

impl Block {
    fn kind(&self) -> &'static str {
        match self.tag.as_deref() {
            None => "complete",
            Some("before") => "before",
            Some(_) => "fragment",
        }
    }

    fn first_line(&self) -> String {
        for line in &self.lines {
            if !py_strip(line).is_empty() {
                return normalize_ws(line);
            }
        }
        String::new()
    }
}

fn blocks_in(rel: &str, text: &str) -> Vec<Block> {
    let mut out = Vec::new();
    let lines: Vec<&str> = text.split('\n').collect();
    let mut i = 0usize;
    while i < lines.len() {
        let Some(m) = pat_match!(r"(\s*)```dm(?:\s+(\w+))?\s*$").captures(lines[i]) else {
            i += 1;
            continue;
        };
        let indent = m.s(1).chars().count();
        let tag = m.get(2).map(|s| s.to_string());
        let mut j = i + 1;
        let mut body = Vec::new();
        while j < lines.len() && !pat_match!(r"\s*```\s*$").is_match(lines[j]) {
            let line = lines[j];
            let head: String = line.chars().take(indent).collect();
            if py_strip(&head).is_empty() {
                body.push(line.chars().skip(indent).collect::<String>());
            } else {
                body.push(py_lstrip(line).to_string());
            }
            j += 1;
        }
        out.push(Block { rel: rel.to_string(), start: i + 1, tag, lines: body, code_start: i + 2 });
        i = j + 1;
    }
    out
}

/// A doc file of the lint's scope: a direct child of `doc/rewrite/`.
fn is_doc(f: &SourceFile) -> bool {
    f.ext() == "md" && f.rel.strip_prefix(&format!("{}/", DOCS)[..]).map(|rest| !rest.contains('/')).unwrap_or(false)
}

fn doc_blocks(files: &[&SourceFile]) -> Vec<Block> {
    files.iter().filter(|f| is_doc(f)).flat_map(|f| blocks_in(&f.rel, f.text())).collect()
}

// ---- names ------------------------------------------------------------------------------------

struct Names {
    global_procs: HashSet<String>,
    type_procs: HashMap<String, HashSet<String>>,
    defines: HashSet<String>,
}

impl Names {
    fn build(tree: &Tree, files: &[&SourceFile]) -> Names {
        let dm: Vec<&SourceFile> = files.iter().copied().filter(|f| f.ext() == "dm").collect();
        let idx = DxIndex::get(tree, &dm);
        let mut names = Names { global_procs: HashSet::new(), type_procs: HashMap::new(), defines: HashSet::new() };
        for p in &idx.procs {
            if p.is_global() {
                names.global_procs.insert(p.name.clone());
            } else {
                names.type_procs.entry(p.name.clone()).or_default().insert(p.path.clone());
            }
        }
        // Per-file facts: the `#define` names a file declares (cached by content).
        let defs: Vec<Vec<String>> = crate::incr::facts("doc-snippets-defines", &dm, |f| {
            let mut v: Vec<String> = Vec::new();
            if f.text().contains("#define") {
                for line in f.raw().lines() {
                    if let Some(m) = pat_match!(r"\s*#define\s+(\w+)").captures(line) {
                        v.push(m.s(1).to_string());
                    }
                }
            }
            v.sort();
            v.dedup();
            v
        });
        for d in defs {
            names.defines.extend(d);
        }
        names
    }
}

fn flush_left(code: &str) -> bool {
    code.chars().next().map(|c| c != ' ' && c != '\t').unwrap_or(false)
}

/// `[(md line, name)]` for each call in the block that resolves to nothing.
fn unknown_names(block: &Block, names: &Names) -> Vec<(usize, String)> {
    let clean_text = sanitize(&block.lines.join("\n"));
    let clean: Vec<&str> = clean_text.split('\n').collect();
    let mut own_procs: HashSet<String> = HashSet::new();
    let mut own_types: HashMap<String, HashSet<String>> = HashMap::new();
    let mut own_defines: HashSet<String> = HashSet::new();
    for line in &block.lines {
        if let Some(m) = pat_match!(r"\s*#define\s+(\w+)").captures(line) {
            own_defines.insert(m.s(1).to_string());
        }
    }
    let mut heads: HashMap<usize, String> = HashMap::new();
    for (k, code) in clean.iter().enumerate() {
        let Some(m) = pat_match!(r"(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\((.*)\)\s*(?:as\s+[\w/|]+\s*)?$").captures(py_rstrip(code)) else { continue };
        if !flush_left(code) {
            continue;
        }
        let path = if m.s(1).is_empty() { "/" } else { m.s(1) };
        let path = if path == "/proc" || path == "/verb" { "/" } else { path };
        own_procs.insert(m.s(2).to_string());
        own_types.entry(m.s(2).to_string()).or_default().insert(path.to_string());
        heads.insert(k, path.to_string());
    }
    let mut out = Vec::new();
    let mut current: Option<String> = None;
    for (k, code) in clean.iter().enumerate() {
        if let Some(h) = heads.get(&k) {
            current = Some(h.clone());
            continue;
        }
        if flush_left(code) && !py_strip(code).is_empty() {
            current = None;
        }
        if py_lstrip(code).starts_with("#define") {
            continue;
        }
        for m in pat!(r"(?<![\w./:@$#])([A-Za-z_]\w*)\s*\(").captures_iter(code) {
            let name = m.s(1);
            if KEYWORDS.contains(&name) || BUILTINS.contains(&name) || own_procs.contains(name) || own_defines.contains(name) {
                continue;
            }
            if pat!(r"\bnew\s+$").is_match(&code[..m.start(0)]) {
                continue; // `new some_type_var(args)`: a type held in a var, not a call
            }
            if names.global_procs.contains(name) || names.defines.contains(name) {
                continue;
            }
            match current.as_deref() {
                Some(cur) if cur != "/" => {
                    let chain = lineage(cur);
                    let known = names.type_procs.get(name);
                    let own = own_types.get(name);
                    if chain.iter().any(|p| known.map(|s| s.contains(p)).unwrap_or(false) || own.map(|s| s.contains(p)).unwrap_or(false)) {
                        continue;
                    }
                }
                _ => {
                    if names.type_procs.contains_key(name) {
                        continue;
                    }
                }
            }
            out.push((block.code_start + k, name.to_string()));
        }
        for m in pat!(r"(?:(?:\?\.|\.)\s*|(?<=[\w\])]):)([A-Za-z_]\w*)\s*\(").captures_iter(code) {
            let name = m.s(1);
            if MEMBER_BUILTINS.contains(&name) || names.type_procs.contains_key(name) || own_procs.contains(name) || names.global_procs.contains(name) {
                continue;
            }
            out.push((block.code_start + k, name.to_string()));
        }
    }
    out
}

/// `analyse`: the sites, as `(rel, line)` in block order.
fn analyse(blocks: &[Block], names: &Names, mut allowed: impl FnMut(&str, usize) -> bool) -> Vec<(String, usize)> {
    let mut sites = Vec::new();
    for block in blocks {
        if block.kind() == "before" {
            continue;
        }
        for (line, _name) in unknown_names(block, names) {
            if !allowed(&block.rel, line) {
                sites.push((block.rel.clone(), line));
            }
        }
    }
    sites
}

fn legacy_keys(path: &std::path::Path) -> HashSet<(String, String)> {
    baseline::read_sites(path).get(LEGACY_RULE).map(|c| c.keys().cloned().collect()).unwrap_or_default()
}

fn baseline_path(tree: &Tree) -> PathBuf {
    tree.root.join(BASELINE)
}

// ---- the lint ---------------------------------------------------------------------------------

struct DocSnippets;

impl Lint for DocSnippets {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let names = Names::build(cx.tree, &files);
        let blocks = doc_blocks(&files);
        let sites = analyse(&blocks, &names, |rel, line| match cx.tree.get(rel) {
            Some(f) => out.allowed(f, line, LINT),
            None => false,
        });
        // `analyse` borrowed `out` through the closure; record the sites afterwards.
        for (rel, line) in sites {
            out.site_in(RULE, &rel, line);
        }
    }

    fn finish_raw(&self, cx: &Cx, run: &Run, text: &mut String, raw: bool) -> bool {
        let files = cx.files();
        let blocks = doc_blocks(&files);
        let path = if raw { PathBuf::new() } else { baseline_path(cx.tree) };
        let legacy = legacy_keys(&path);
        let complete: Vec<&Block> = blocks.iter().filter(|b| b.kind() == "complete").collect();
        let compiled = complete.iter().filter(|b| !legacy.contains(&(b.rel.clone(), b.first_line()))).count();
        let mut kinds: BTreeMap<&str, usize> = BTreeMap::new();
        for b in &blocks {
            *kinds.entry(b.kind()).or_insert(0) += 1;
        }
        let kinds_text = kinds.iter().map(|(k, v)| format!("{} {}", k, v)).collect::<Vec<_>>().join(", ");
        let _ = writeln!(
            text,
            "doc_snippets: {} block(s): {}; {} complete block(s) compiled under -DDOC_SNIPPETS, {} legacy",
            blocks.len(),
            kinds_text,
            compiled,
            complete.len() - compiled
        );
        let by_rule = run.by_rule(cx.meta);
        let hints = |_r: &str| HINT.to_string();
        baseline::check_sites(META.label, cx.tree, &by_rule, &hints, &path, &[], text)
    }

    fn update_baseline(&self, cx: &Cx, run: &Run, mode: Mode) -> std::io::Result<String> {
        let files = cx.files();
        let blocks = doc_blocks(&files);
        let complete: Vec<&Block> = blocks.iter().filter(|b| b.kind() == "complete").collect();
        let path = baseline_path(cx.tree);
        let legacy = legacy_keys(&path);
        let keep: Vec<&&Block> = if mode == Mode::Update {
            complete.iter().filter(|b| legacy.contains(&(b.rel.clone(), b.first_line()))).collect()
        } else {
            complete.iter().collect()
        };
        let by_rule = run.by_rule(cx.meta);
        let n = baseline::write_sites(&path, HEADER, cx.tree, &by_rule, &[RULE], mode)?;
        let text = std::fs::read_to_string(&path)?;
        let text = text.trim_end_matches('\n');
        let rows: BTreeSet<String> = keep.iter().map(|b| format!("{}\t{}\t{}", LEGACY_RULE, b.rel, b.first_line())).collect();
        let mut out = text.to_string();
        if !rows.is_empty() {
            out.push('\n');
            out.push_str(&rows.iter().cloned().collect::<Vec<_>>().join("\n"));
        }
        out.push('\n');
        std::fs::write(&path, out)?;
        Ok(format!("doc_snippets: baseline {} ({} unknown-name rows, {} legacy blocks)", BASELINE, n, rows.len()))
    }

    fn selftest(&self) -> Result<String, String> {
        selftest()
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/doc_snippets.py"],
            old_raw: &[],
            blank: &["tools/ci/doc_snippets_baseline.txt"],
            parse: ParseKind::Tagged,
            update: Some(&["tools/ci/doc_snippets.py", "--update"]),
            seed: Some(&["tools/ci/doc_snippets.py", "--seed"]),
            files: &["tools/ci/doc_snippets_baseline.txt"],
            selftest: Some(&["tools/ci/doc_snippets.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DocSnippets);
}

// ---- self-test --------------------------------------------------------------------------------

const SELFTEST_DOC: &str = "# Doc

```dm fragment
/obj/machinery/power/apc/capabilities()
\t. = ..()
\t. += cap_cover(open_tool = TOOL_CROWBAR)
\t. += wall_machine(board = /obj/item/circuitboard/apc)
\t. += lock(access = list(ACCESS_ENGINE))
```

  ```dm
  /obj/machinery/pump/proc/act_set_pressure(mob/user, pressure)
  \tpressure = ui_number(pressure, 0, 100)
  \tlook.gauge(\"x\", level = 1)
  \tlook.shine(\"y\")
  \thelper_of_block(pressure)
  \tset_target_pressure(pressure)
  /obj/machinery/pump/proc/helper_of_block(value)
  \treturn round(value)
  ```

```dm before
/obj/machinery/pump/proc/ui_act(action, params)
\tnonexistent_old_thing(params)
```
";

fn selftest() -> Result<String, String> {
    let code = "/proc/cap_cover(open_tool)\n\treturn\n/proc/ui_number(value, min_value, max_value)\n\treturn\n/datum/look/proc/gauge(name, level)\n\treturn\n/obj/machinery/proc/set_target_pressure(value)\n\treturn\n/obj/machinery/door/airlock/proc/lock(forced)\n\treturn\n#define TOOL_CROWBAR \"crowbar\"";
    let tree = Tree::from_files(vec![SourceFile::from_text("code/x.dm", code)]);
    let files: Vec<&SourceFile> = tree.files.iter().collect();
    let names = Names::build(&tree, &files);
    let blocks = blocks_in("doc/rewrite/x.md", SELFTEST_DOC);
    let kinds: Vec<&str> = blocks.iter().map(|b| b.kind()).collect();
    if kinds != ["fragment", "complete", "before"] {
        return Err(format!("block kinds {:?}", kinds));
    }
    if !blocks[1].lines[0].starts_with("/obj/machinery/pump/proc/act_set_pressure") {
        return Err(format!("block 1 first line {:?}", blocks[1].lines[0]));
    }
    let raw: Vec<&str> = SELFTEST_DOC.split('\n').collect();
    let sites = analyse(&blocks, &names, |_rel, line| {
        // the raw-doc `allowed`: the selftest doc has no ALLOW annotations
        let _ = line;
        false
    });
    let at = |snippet: &str| raw.iter().position(|l| l.contains(snippet)).unwrap() + 1;
    let mut got: Vec<usize> = sites.iter().map(|(_, l)| *l).collect();
    got.sort();
    let mut want = vec![at("wall_machine("), at("lock(access"), at("look.shine")];
    want.sort();
    if got != want {
        return Err(format!("unknown names at {:?}, wanted {:?}", got, want));
    }
    let complete: Vec<&Block> = blocks.iter().filter(|b| b.kind() == "complete").collect();
    if complete.len() != 1 || !complete[0].first_line().starts_with("/obj/machinery/pump/proc/act_set_pressure") {
        return Err("complete blocks".to_string());
    }
    Ok("doc_snippets selftest ok".to_string())
}
