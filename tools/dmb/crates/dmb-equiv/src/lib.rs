//! Semantic equivalence of two BYOND compiled worlds (DMB, optionally with RSC).
//!
//! Two worlds are equivalent when their canonical forms (see `canon`) are
//! equal: table IDs and table order are erased except for the orders that
//! `ORDER_POLICY` documents as observable at runtime. See EQUIVALENCE.md.
pub mod canon;
pub mod permute;

use byond_dmb::dmb::Dmb;
use byond_dmb::ids::NONE;
use byond_dmb::rsc;
use canon::{class_fields, code_hashes, esc, num, Code, Ctx, Field};
use std::collections::{BTreeMap, HashMap};
use std::fmt::Write;
use std::io;
use xxhash_rust::xxh3::xxh3_64;

/// Which table/list orders are compared. `true` = observable at runtime and
/// therefore part of equivalence; `false` = compared only with `strict_order`.
/// Evidence for each entry is recorded in EQUIVALENCE.md.
pub const ORDER_POLICY: &[(&str, bool)] = &[
    // typesof(/datum) lists types in class-table order (DD probe: permuting
    // classes reorders the output).
    ("type_table", true),
    // typesof(/T/proc) lists procs in proc-table order (DD probe). Only named
    // procedures are reachable that way; anonymous bodies are excluded.
    ("proc_table", true),
    // `vars` and `global.vars` iterate declarations sorted by the name's
    // StringID (DD probe: permuting user strings reorders vars output).
    ("var_name_strings", true),
    // Global footer wire order: reversing it changes nothing (DD probe).
    ("global_footer", false),
    // Archive order matters only among equal-content aliases, which are
    // compared separately as `rsc.rsc_alias_order`.
    ("rsc_archive", false),
];

pub fn order_is_semantic(name: &str) -> bool {
    ORDER_POLICY
        .iter()
        .find(|(n, _)| *n == name)
        .map_or(true, |(_, s)| *s)
}

#[derive(Clone, Debug)]
pub struct Options {
    /// Maximum stored examples per category (all differences are still counted).
    pub max_examples: usize,
    /// Also compare orders marked non-observable in `ORDER_POLICY`.
    pub strict_order: bool,
    /// Ignore DbgFile/DbgLine streams.
    pub ignore_debug: bool,
}
impl Default for Options {
    fn default() -> Self {
        Self {
            max_examples: 25,
            strict_order: false,
            ignore_debug: false,
        }
    }
}

pub struct Canon<'a> {
    pub ctx: Ctx<'a>,
    /// (kind, key) -> fields.
    pub records: BTreeMap<(&'static str, String), Vec<Field>>,
    /// Procedure key -> (table index, canonical code).
    pub code: HashMap<String, (usize, Code)>,
    /// Named sequences whose order may be observable.
    pub orders: BTreeMap<String, Vec<String>>,
    /// Map cells: per-cell content hash, with dimensions.
    pub cells: Vec<u64>,
    pub dims: [u16; 3],
}

fn rsc_entries(bytes: &[u8]) -> io::Result<Vec<rsc::NamedResource>> {
    let mut reader = io::Cursor::new(bytes);
    let mut out = Vec::new();
    while let Some(entry) = rsc::read_entry(&mut reader)? {
        if let rsc::Entry::Named(n) = entry {
            out.push(n);
        }
    }
    Ok(out)
}

fn insert(
    records: &mut BTreeMap<(&'static str, String), Vec<Field>>,
    kind: &'static str,
    key: String,
    fields: Vec<Field>,
) {
    if !records.contains_key(&(kind, key.clone())) {
        records.insert((kind, key), fields);
        return;
    }
    let mut n = 1;
    loop {
        let k = format!("{key}#dup{n}");
        if !records.contains_key(&(kind, k.clone())) {
            records.insert((kind, k), fields);
            return;
        }
        n += 1;
    }
}

fn field(family: &'static str, label: impl Into<String>, value: impl Into<String>) -> Field {
    Field {
        family,
        label: label.into(),
        value: value.into(),
    }
}

impl<'a> Canon<'a> {
    pub fn build(dmb: &'a Dmb, rsc_bytes: Option<&[u8]>) -> io::Result<Self> {
        let entries = rsc_bytes.map(rsc_entries).transpose()?;
        let rsc_names = entries.as_ref().map(|entries| {
            let mut m = HashMap::new();
            for e in entries {
                if let Ok(id) = e.content_id() {
                    m.entry(id).or_insert_with(|| e.name.clone());
                }
            }
            m
        });
        let ctx = Ctx::new(dmb, rsc_names);
        let mut records = BTreeMap::new();
        let mut orders = BTreeMap::new();

        // Header: the ID-width bit is encoding, not semantics.
        let h = &dmb.header;
        insert(
            &mut records,
            "header",
            "header".into(),
            vec![
                field("header", "version_line", esc(&h.version_line)),
                field("header", "compatibility_line", esc(&h.compatibility_line)),
                field(
                    "header",
                    "executor",
                    h.executor_line.as_deref().map(esc).unwrap_or_default(),
                ),
                field(
                    "header_flags",
                    "flags",
                    format!("{:#x}", h.flags & !0x4000_0000),
                ),
                field(
                    "header_flags",
                    "extended_flags",
                    format!("{:?}", h.extended_flags),
                ),
            ],
        );

        // Types.
        let mut type_order = Vec::with_capacity(dmb.classes.len());
        let mut mob_fields: HashMap<u32, Vec<Field>> = HashMap::new();
        for m in &dmb.mobs {
            mob_fields.entry(m.class).or_default().extend([
                field("type_mob", "mob key", ctx.s(m.key)),
                field(
                    "type_mob",
                    "mob sight",
                    format!("{} {:?}", m.sight, m.extended_sight),
                ),
            ]);
        }
        for (ci, c) in dmb.classes.iter().enumerate() {
            let path = ctx.t(c.path_string_id());
            type_order.push(path.clone());
            let mut fields = class_fields(&ctx, ci);
            if let Some(m) = mob_fields.get(&(ci as u32)) {
                fields.extend(m.iter().cloned());
            }
            insert(&mut records, "type", path, fields);
        }
        orders.insert("type_table".into(), type_order);

        // Procedures.
        let mut proc_order = Vec::new();
        let mut proc_ids = Vec::new();
        for p in 0..dmb.procs.len() {
            if dmb.is_reserved_proc_slot(p) {
                continue;
            }
            let key = ctx.proc_keys[p].clone();
            if !key.contains('<') {
                proc_order.push(key.clone());
            }
            // Identical anonymous bodies share a content key and are
            // interchangeable: compare them as a set.
            if key.contains("<anon ") && records.contains_key(&("proc", key.clone())) {
                continue;
            }
            // Short instance initializers are compared inline at their uses.
            if key.starts_with("<inline-init ") {
                continue;
            }
            proc_ids.push(p);
            insert(&mut records, "proc", key, ctx.proc_fields(p));
        }
        orders.insert("proc_table".into(), proc_order);
        let code = parallel_code(&ctx, &proc_ids);

        // Globals.
        let mut footer = Vec::new();
        for (v, flags) in ctx.footer_pairs() {
            let key = ctx.global(v);
            footer.push(key.clone());
            let default = dmb
                .variables
                .get(v as usize)
                .map(|var| ctx.tagged(var.kind, var.value, None))
                .unwrap_or_else(|| "<bad-var>".into());
            insert(
                &mut records,
                "global",
                key,
                vec![
                    field("global_flags", "flags", format!("{flags:#x}")),
                    field("global_default", "default", default),
                ],
            );
        }
        orders.insert("global_footer".into(), footer);

        // Declared variable names (class declarations and globals) in StringID order.
        let mut names: std::collections::BTreeSet<u32> = std::collections::BTreeSet::new();
        for ci in 0..dmb.classes.len() {
            for (v, _) in dmb.class_variable_declarations(ci).unwrap_or_default() {
                if let Some(var) = dmb.variables.get(v as usize) {
                    names.insert(var.name);
                }
            }
        }
        for (v, _) in ctx.footer_pairs() {
            if let Some(var) = dmb.variables.get(v as usize) {
                names.insert(var.name);
            }
        }
        orders.insert(
            "var_name_strings".into(),
            names
                .into_iter()
                .filter(|&id| id != NONE)
                .map(|id| ctx.t(id))
                .collect(),
        );

        // Builtin names are addressed by fixed StringID: the seeded prefix of
        // the string table (through "pixloc" in 516.1687) is positional.
        let prefix = dmb
            .strings
            .iter()
            .position(|s| s.data == b"pixloc")
            .map_or(0, |i| i + 1);
        let mut prefix_fields = vec![field("string_prefix", "length", prefix.to_string())];
        prefix_fields.extend(dmb.strings[..prefix].iter().enumerate().map(|(i, s)| {
            field(
                "string_prefix",
                format!("string[{i}]"),
                format!("\"{}\"", esc(&s.data)),
            )
        }));
        insert(
            &mut records,
            "string_prefix",
            "builtin".into(),
            prefix_fields,
        );

        // World.
        let w = &dmb.world;
        let world_procs = dmb
            .lists
            .get(w.proc_list_id() as usize)
            .filter(|_| w.proc_list_id() != NONE)
            .map(|l| {
                l.iter()
                    .map(|&p| ctx.proc_key(p))
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default();
        insert(
            &mut records,
            "world",
            "world".into(),
            vec![
                field("world", "mob", ctx.mob(w.mob_type_id())),
                field("world", "turf", ctx.ty(w.turf_class_id())),
                field("world", "area", ctx.ty(w.area_class_id())),
                field("world_procs", "procs", world_procs),
                field(
                    "world",
                    "global_initializer",
                    ctx.proc_key(w.global_initializer_proc_id()),
                ),
                field("world", "domain", ctx.s(w.domain_string_id())),
                field("world", "name", ctx.s(w.name_string_id())),
                field("world", "tick_lag", w.tick_lag.to_string()),
                field("world", "client", ctx.ty(w.client)),
                field("world", "image", ctx.ty(w.image)),
                field(
                    "world",
                    "savefile_byond_version",
                    w.savefile_byond_version.to_string(),
                ),
                field("world", "eye", w.eye.to_string()),
                field("world", "dir", w.direction.to_string()),
                field("world", "control", w.control.to_string()),
                field("world", "client_import", w.unknown_byte.to_string()),
                field("world", "client_script", ctx.s(w.client_script)),
                field(
                    "world",
                    "client_script_files",
                    w.client_script_files
                        .iter()
                        .map(|&r| ctx.res(r))
                        .collect::<Vec<_>>()
                        .join(", "),
                ),
                field("world", "view", format!("{:?}", w.view_encoding())),
                field("world", "hub_password", ctx.s(w.hub_password)),
                field("world", "status", ctx.s(w.server_name)),
                field("world", "hub_number", w.hub_number.to_string()),
                field("world", "version", w.version.to_string()),
                field("world", "cache_lifespan", w.cache_lifespan.to_string()),
                field("world", "command_text", ctx.s(w.command_ids[0])),
                field("world", "command_prompt", ctx.s(w.command_ids[1])),
                field("world", "hub", ctx.s(w.hub_channel_skin[0])),
                field("world", "channel", ctx.s(w.hub_channel_skin[1])),
                field("world", "skin", ctx.res(w.hub_channel_skin[2])),
                field(
                    "world",
                    "icon_size_format",
                    format!("{:?}", w.icon_dimensions_format),
                ),
            ],
        );

        // Map: expanded cells (run grouping is encoding), objects per cell in order.
        let mut cells = Vec::new();
        let mut cell_text = HashMap::<(u32, u32, u32), u64>::new();
        for run in &dmb.grid {
            let h = *cell_text
                .entry((run.turf, run.area, run.contents))
                .or_insert_with(|| {
                    xxh3_64(cell_render(&ctx, run.turf, run.area, run.contents).as_bytes())
                });
            cells.extend(std::iter::repeat_n(h, run.copies as usize));
        }
        let dims = dmb.dimensions;
        let mut at = 0usize;
        let mut objects: BTreeMap<usize, Vec<String>> = BTreeMap::new();
        for o in &dmb.map_objects {
            at += usize::from(o.offset);
            objects
                .entry(at)
                .or_default()
                .push(ctx.instance(o.instance));
        }
        for (cell, list) in objects {
            insert(
                &mut records,
                "map_objects",
                coord(dims, cell),
                vec![field("map_objects", "objects", list.join(", "))],
            );
        }

        // Resources (DMB table): content ID is identity; kind follows the first alias.
        let mut res: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for r in &dmb.resources {
            res.entry(format!("{:08x}", r.id))
                .or_default()
                .push(r.kind.to_string());
        }
        for (k, kinds) in res {
            insert(
                &mut records,
                "resource",
                k,
                vec![field("resource", "kind", kinds.join(","))],
            );
        }

        // RSC archive: named entries by exact name; alias order per content ID.
        if let Some(entries) = &entries {
            let mut aliases: BTreeMap<u32, Vec<String>> = BTreeMap::new();
            let mut archive = Vec::new();
            for e in entries {
                let id = e.content_id().unwrap_or(0);
                let name = esc(&e.name);
                aliases.entry(id).or_default().push(name.clone());
                archive.push(name.clone());
                insert(
                    &mut records,
                    "rsc",
                    name,
                    vec![
                        field("rsc", "kind", e.kind.to_string()),
                        field(
                            "rsc",
                            "content",
                            format!("{id:08x} size {}", e.declared_size),
                        ),
                    ],
                );
            }
            for (id, names) in aliases {
                if names.len() > 1 {
                    // Resource-to-text returns the first-inserted alias (FORMAT.md).
                    insert(
                        &mut records,
                        "rsc",
                        format!("<aliases {id:08x}>"),
                        vec![field("rsc_alias_order", "order", names.join(", "))],
                    );
                }
            }
            orders.insert("rsc_archive".into(), archive);
        }

        Ok(Canon {
            ctx,
            records,
            code,
            orders,
            cells,
            dims,
        })
    }
}

fn coord(dims: [u16; 3], cell: usize) -> String {
    let (x, y) = (dims[0].max(1) as usize, dims[1].max(1) as usize);
    format!(
        "({},{},{})",
        cell % x + 1,
        (cell / x) % y + 1,
        cell / (x * y) + 1
    )
}

fn cell_render(ctx: &Ctx<'_>, turf: u32, area: u32, contents: u32) -> String {
    let list = if contents == NONE {
        String::new()
    } else {
        ctx.dmb
            .lists
            .get(contents as usize)
            .map(|l| {
                l.iter()
                    .map(|&i| {
                        if (i as usize) < ctx.dmb.instances.len() {
                            ctx.instance(i)
                        } else {
                            format!("word {i:#x}")
                        }
                    })
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_else(|| "<bad-list>".into())
    };
    format!(
        "turf {} area {} contents [{list}]",
        ctx.instance(turf),
        ctx.instance(area)
    )
}

fn parallel_code(ctx: &Ctx<'_>, ids: &[usize]) -> HashMap<String, (usize, Code)> {
    let threads = std::thread::available_parallelism()
        .map_or(4, |n| n.get())
        .min(16);
    let chunk = ids.len().div_ceil(threads).max(1);
    let parts: Vec<Vec<(usize, Code)>> = std::thread::scope(|s| {
        ids.chunks(chunk)
            .map(|part| {
                s.spawn(move || {
                    part.iter()
                        .map(|&p| (p, code_hashes(ctx, p)))
                        .collect::<Vec<_>>()
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|h| h.join().unwrap())
            .collect()
    });
    let mut out = HashMap::with_capacity(ids.len());
    for (p, c) in parts.into_iter().flatten() {
        let mut key = ctx.proc_keys[p].clone();
        let mut n = 1;
        while out.contains_key(&key) {
            key = format!("{}#dup{n}", ctx.proc_keys[p]);
            n += 1;
        }
        out.insert(key, (p, c));
    }
    out
}

// ---- report ---------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct Diff {
    pub category: String,
    pub path: String,
    pub detail: String,
}

#[derive(Default, Debug)]
pub struct CategorySummary {
    pub count: usize,
    pub examples: Vec<Diff>,
}

#[derive(Debug, Default)]
pub struct Report {
    pub categories: BTreeMap<String, CategorySummary>,
    pub total: usize,
    /// Informational notes (e.g. non-semantic orders that differ).
    pub notes: Vec<String>,
    /// Per category, abstracted first-differing instruction pairs
    /// ("GetVar .F vs GetVar src->.F"), for triage.
    pub signatures: BTreeMap<String, BTreeMap<String, usize>>,
    max_examples: usize,
}

impl Report {
    pub fn equivalent(&self) -> bool {
        self.total == 0
    }
    fn add(
        &mut self,
        category: impl Into<String>,
        path: impl Into<String>,
        detail: impl Into<String>,
    ) {
        let category = category.into();
        let entry = self.categories.entry(category.clone()).or_default();
        entry.count += 1;
        self.total += 1;
        if entry.examples.len() < self.max_examples {
            entry.examples.push(Diff {
                category,
                path: path.into(),
                detail: detail.into(),
            });
        }
    }
    pub fn render_text(&self) -> String {
        let mut out = String::new();
        if self.equivalent() {
            out.push_str("EQUIVALENT\n");
        } else {
            let _ = writeln!(out, "NOT EQUIVALENT: {} differences", self.total);
        }
        let mut cats: Vec<_> = self.categories.iter().collect();
        cats.sort_by(|a, b| b.1.count.cmp(&a.1.count).then(a.0.cmp(b.0)));
        for (name, cat) in &cats {
            let _ = writeln!(out, "  {:>9}  {name}", cat.count);
        }
        for (name, cat) in cats {
            let _ = writeln!(out, "\n== {name} ({}) ==", cat.count);
            for d in &cat.examples {
                let _ = writeln!(out, "{}: {}", d.path, d.detail);
            }
            if cat.count > cat.examples.len() {
                let _ = writeln!(out, "... {} more", cat.count - cat.examples.len());
            }
        }
        for (category, sigs) in &self.signatures {
            let mut sigs: Vec<_> = sigs.iter().collect();
            sigs.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));
            let _ = writeln!(
                out,
                "
== {category} first-difference signatures (top 40 of {}) ==",
                sigs.len()
            );
            for (sig, n) in sigs.into_iter().take(40) {
                let _ = writeln!(out, "  {n:>7}  {}", clip(sig));
            }
        }
        for n in &self.notes {
            let _ = writeln!(out, "note: {n}");
        }
        out
    }
    pub fn to_json(&self) -> serde_json::Value {
        let cats: serde_json::Map<String, serde_json::Value> = self
            .categories
            .iter()
            .map(|(k, v)| {
                (
                    k.clone(),
                    serde_json::json!({
                        "count": v.count,
                        "examples": v.examples.iter().map(|d| serde_json::json!({"path": d.path, "detail": d.detail})).collect::<Vec<_>>(),
                    }),
                )
            })
            .collect();
        serde_json::json!({
            "schema": 1,
            "equivalent": self.equivalent(),
            "total": self.total,
            "categories": cats,
            "notes": self.notes,
            "signatures": self.signatures,
            "order_policy": ORDER_POLICY.iter().map(|(n, s)| serde_json::json!({"order": n, "semantic": s})).collect::<Vec<_>>(),
        })
    }
}

fn clip(s: &str) -> String {
    if s.len() > 300 {
        let mut end = 300;
        while !s.is_char_boundary(end) {
            end -= 1;
        }
        format!("{}...", &s[..end])
    } else {
        s.to_string()
    }
}

fn first_list_divergence(a: &str, b: &str) -> String {
    let la: Vec<&str> = a.split(", ").collect();
    let lb: Vec<&str> = b.split(", ").collect();
    let i = la
        .iter()
        .zip(&lb)
        .position(|(x, y)| x != y)
        .unwrap_or(la.len().min(lb.len()));
    format!(
        "lengths {} vs {}; first difference at [{i}]: {} vs {}",
        la.len(),
        lb.len(),
        clip(la.get(i).unwrap_or(&"<end>")),
        clip(lb.get(i).unwrap_or(&"<end>"))
    )
}

fn compare_fields(report: &mut Report, kind: &str, key: &str, a: &[Field], b: &[Field]) {
    let map = |fs: &[Field]| {
        let mut m: BTreeMap<String, (&'static str, String)> = BTreeMap::new();
        for f in fs {
            m.insert(f.label.clone(), (f.family, f.value.clone()));
        }
        m
    };
    let (ma, mb) = (map(a), map(b));
    for (label, (family, va)) in &ma {
        match mb.get(label) {
            Some((_, vb)) if va == vb => {}
            Some((_, vb)) => {
                let detail = if matches!(
                    *family,
                    "type_procs"
                        | "type_verbs"
                        | "world_procs"
                        | "proc_locals"
                        | "map_objects"
                        | "rsc_alias_order"
                ) {
                    format!("{label}: {}", first_list_divergence(va, vb))
                } else {
                    format!("{label}: {} vs {}", clip(va), clip(vb))
                };
                report.add(format!("{kind}.{family}"), key, detail);
            }
            None => report.add(
                format!("{kind}.{family}"),
                key,
                format!("{label}: {} vs <absent>", clip(va)),
            ),
        }
    }
    for (label, (family, vb)) in &mb {
        if !ma.contains_key(label) {
            report.add(
                format!("{kind}.{family}"),
                key,
                format!("{label}: <absent> vs {}", clip(vb)),
            );
        }
    }
}

/// Abstract an instruction for grouping: strings -> S, numbers -> N, field
/// names -> .F, paths -> P, labels -> L, dynamic names -> X.
fn abstract_instruction(text: &str) -> String {
    let b: Vec<char> = text.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    let ident = |c: char| c.is_alphanumeric() || c == '_' || c == ' ';
    while i < b.len() {
        let c = b[i];
        if c == '"' {
            i += 1;
            while i < b.len() && b[i] != '"' {
                if b[i] == '\\' {
                    i += 1;
                }
                i += 1;
            }
            i += 1;
            out.push('S');
        } else if c == '.' && i + 1 < b.len() && (b[i + 1].is_alphabetic() || b[i + 1] == '_') {
            i += 1;
            while i < b.len() && (b[i].is_alphanumeric() || b[i] == '_') {
                i += 1;
            }
            out.push_str(".F");
        } else if c == '/' && i + 1 < b.len() && (b[i + 1].is_alphanumeric() || b[i + 1] == '_') {
            while i < b.len()
                && (b[i].is_alphanumeric() || b[i] == '_' || b[i] == '/' || b[i] == '#')
            {
                i += 1;
            }
            out.push('P');
        } else if c == 'L'
            && i + 1 < b.len()
            && b[i + 1].is_ascii_digit()
            && (i == 0 || !b[i - 1].is_alphanumeric())
        {
            i += 1;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            out.push('L');
        } else if (c.is_ascii_digit() || (c == '-' && i + 1 < b.len() && b[i + 1].is_ascii_digit()))
            && (i == 0 || !b[i - 1].is_alphanumeric())
        {
            i += 1;
            while i < b.len()
                && (b[i].is_ascii_digit() || b[i] == '.' || b[i] == 'e' || b[i] == '-')
            {
                i += 1;
            }
            out.push('N');
        } else if b[i..].starts_with(&['p', 'r', 'o', 'c', ':'])
            || b[i..].starts_with(&['v', 'e', 'r', 'b', ':'])
        {
            out.extend(&b[i..i + 5]);
            i += 5;
            while i < b.len() && ident(b[i]) {
                i += 1;
            }
            out.push('X');
        } else {
            out.push(c);
            i += 1;
        }
    }
    out
}

fn line_of(lines: &[(bool, String)], upto: usize) -> String {
    // Nearest preceding DbgLine for an instruction ordinal (non-debug index).
    let mut seen = 0;
    let mut line = String::new();
    for (dbg, text) in lines {
        if *dbg {
            if text.starts_with("DbgLine") {
                line = text.clone();
            }
        } else {
            if seen == upto {
                break;
            }
            seen += 1;
        }
    }
    line
}

/// One code difference: (category, detail, triage signature).
type CodeDiff = (&'static str, String, String);

fn strip_labels(text: &str) -> String {
    let b: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == 'L'
            && i + 1 < b.len()
            && b[i + 1].is_ascii_digit()
            && (i == 0 || !b[i - 1].is_alphanumeric())
        {
            out.push('L');
            i += 1;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    out
}

fn compare_code(
    a: (&Ctx<'_>, usize, &Code),
    b: (&Ctx<'_>, usize, &Code),
    opts: &Options,
) -> Option<CodeDiff> {
    let (ca, cb) = (a.2, b.2);
    if ca.decode_error.is_some() || cb.decode_error.is_some() {
        if ca.decode_error != cb.decode_error || ca.instructions != cb.instructions {
            return Some((
                "proc.decode_error",
                format!("{:?} vs {:?}", ca.decode_error, cb.decode_error),
                String::new(),
            ));
        }
        return None;
    }
    let code_differs = ca.instructions != cb.instructions;
    if !code_differs && (opts.ignore_debug || ca.debug == cb.debug) {
        return None;
    }
    let render = |ctx: &Ctx<'_>, p: usize| {
        ctx.dmb
            .proc_code_words(p)
            .map(|w| canon::render_code_lines(ctx, w).unwrap_or_default())
            .unwrap_or_default()
    };
    let (la, lb) = (render(a.0, a.1), render(b.0, b.1));
    if code_differs {
        let nd = |l: &[(bool, String)]| {
            l.iter()
                .filter(|x| !x.0)
                .map(|x| x.1.clone())
                .collect::<Vec<_>>()
        };
        let (na, nb) = (nd(&la), nd(&lb));
        let first = ca
            .instructions
            .iter()
            .zip(&cb.instructions)
            .position(|(x, y)| x != y)
            .unwrap_or(ca.instructions.len().min(cb.instructions.len()));
        // Report the first difference that is not only a shifted branch label:
        // label numbers move whenever an earlier or later block changes size.
        let i = (0..na.len().max(nb.len()))
            .find(|&k| na.get(k).map(|x| strip_labels(x)) != nb.get(k).map(|x| strip_labels(x)))
            .unwrap_or(first);
        let at = |v: &[String], k: usize| v.get(k).map_or("<end>".to_string(), |s| s.clone());
        let sig = format!(
            "{} vs {}",
            abstract_instruction(&at(&na, i)),
            abstract_instruction(&at(&nb, i))
        );
        let detail = format!(
            "bytecode differs at stmt {i} of {}/{} ({}): `{}` vs `{}`",
            na.len(),
            nb.len(),
            line_of(&la, i),
            clip(&at(&na, i)),
            clip(&at(&nb, i)),
        );
        return Some(("proc.bytecode", detail, sig));
    }
    let (da, db) = (canon::debug_entries(&la), canon::debug_entries(&lb));
    let k = da
        .iter()
        .zip(&db)
        .position(|(x, y)| x != y)
        .unwrap_or(da.len().min(db.len()));
    let show = |v: &[String]| v.get(k).cloned().unwrap_or_else(|| "<none>".to_string());
    let sig = format!(
        "{} vs {}",
        abstract_instruction(&show(&da)),
        abstract_instruction(&show(&db))
    );
    let detail = format!(
        "debug entries {}/{}; first difference at entry {k}: `{}` vs `{}`",
        da.len(),
        db.len(),
        clip(&show(&da)),
        clip(&show(&db))
    );
    Some(("proc.debug_info", detail, sig))
}

/// Elements of the common subsequence whose relative order differs: the
/// complement of a longest increasing subsequence of B's positions in A.
fn moved_elements(a: &[String], b: &[String]) -> Vec<(String, String)> {
    let pos_a: HashMap<&String, usize> = a.iter().enumerate().map(|(i, x)| (x, i)).collect();
    let common: Vec<(usize, &String)> = b
        .iter()
        .filter_map(|x| pos_a.get(x).map(|&i| (i, x)))
        .collect();
    // Patience LIS over A-positions in B order.
    let mut tails: Vec<usize> = Vec::new();
    let mut tail_idx: Vec<usize> = Vec::new();
    let mut prev: Vec<Option<usize>> = vec![None; common.len()];
    for (k, &(p, _)) in common.iter().enumerate() {
        let j = tails.partition_point(|&t| t < p);
        if j == tails.len() {
            tails.push(p);
            tail_idx.push(k);
        } else {
            tails[j] = p;
            tail_idx[j] = k;
        }
        prev[k] = if j > 0 { Some(tail_idx[j - 1]) } else { None };
    }
    let mut keep = vec![false; common.len()];
    let mut cur = tail_idx.last().copied();
    while let Some(k) = cur {
        keep[k] = true;
        cur = prev[k];
    }
    let pos_b: HashMap<&String, usize> = b.iter().enumerate().map(|(i, x)| (x, i)).collect();
    common
        .iter()
        .zip(keep)
        .filter(|(_, k)| !k)
        .map(|(&(p, x), _)| {
            (
                x.clone(),
                format!(
                    "relative order differs (position {p} in A, {} in B)",
                    pos_b[x]
                ),
            )
        })
        .collect()
}

/// Compare two canonical forms.
pub fn compare_canon(a: &Canon<'_>, b: &Canon<'_>, opts: &Options) -> Report {
    let mut report = Report {
        max_examples: opts.max_examples,
        ..Default::default()
    };
    for ((kind, key), fa) in &a.records {
        match b.records.get(&(*kind, key.clone())) {
            Some(fb) => compare_fields(&mut report, kind, key, fa, fb),
            None => report.add(format!("{kind}.missing"), key, "present in A only"),
        }
    }
    for (kind, key) in b.records.keys() {
        if !a.records.contains_key(&(*kind, key.clone())) {
            report.add(format!("{kind}.extra"), key, "present in B only");
        }
    }
    let mut keys: Vec<&String> = a.code.keys().filter(|k| b.code.contains_key(*k)).collect();
    keys.sort();
    let threads = std::thread::available_parallelism()
        .map_or(4, |n| n.get())
        .min(16);
    let chunk = keys.len().div_ceil(threads).max(1);
    let diffs: Vec<Vec<(&String, CodeDiff)>> = std::thread::scope(|s| {
        keys.chunks(chunk)
            .map(|part| {
                s.spawn(move || {
                    part.iter()
                        .filter_map(|key| {
                            let (pa, ca) = &a.code[*key];
                            let (pb, cb) = &b.code[*key];
                            compare_code((&a.ctx, *pa, ca), (&b.ctx, *pb, cb), opts)
                                .map(|d| (*key, d))
                        })
                        .collect::<Vec<_>>()
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|h| h.join().unwrap())
            .collect()
    });
    for (key, (category, detail, sig)) in diffs.into_iter().flatten() {
        if !sig.is_empty() {
            *report
                .signatures
                .entry(category.to_string())
                .or_default()
                .entry(sig)
                .or_insert(0) += 1;
        }
        report.add(category, key.clone(), detail);
    }
    // Map cells.
    if a.dims != b.dims {
        report.add(
            "map.dimensions",
            "/map",
            format!("{:?} vs {:?}", a.dims, b.dims),
        );
    }
    if a.cells.len() != b.cells.len() {
        report.add(
            "map.cells",
            "/map",
            format!("cell count {} vs {}", a.cells.len(), b.cells.len()),
        );
    } else if a.cells != b.cells {
        // Cell hashes come from the same text, so re-render only mismatching cells.
        let expand = |c: &Canon<'_>| {
            c.ctx
                .dmb
                .grid
                .iter()
                .flat_map(|r| std::iter::repeat_n((r.turf, r.area, r.contents), r.copies as usize))
                .collect::<Vec<_>>()
        };
        let (ea, eb) = (expand(a), expand(b));
        for (i, (x, y)) in a.cells.iter().zip(&b.cells).enumerate() {
            if x != y {
                let ta = cell_render(&a.ctx, ea[i].0, ea[i].1, ea[i].2);
                let tb = cell_render(&b.ctx, eb[i].0, eb[i].1, eb[i].2);
                report.add(
                    "map.cell",
                    coord(a.dims, i),
                    format!("{} vs {}", clip(&ta), clip(&tb)),
                );
            }
        }
    }
    for (name, sa) in &a.orders {
        let Some(sb) = b.orders.get(name) else {
            continue;
        };
        if sa == sb {
            continue;
        }
        let moved = moved_elements(sa, sb);
        if moved.is_empty() {
            continue;
        }
        if order_is_semantic(name) || opts.strict_order {
            for (element, detail) in moved {
                report.add(format!("order.{name}"), element, detail);
            }
        } else {
            report.notes.push(format!(
                "non-semantic order {name}: {} elements moved",
                moved.len()
            ));
        }
    }
    report
}

/// Compare two DMB images (and optional RSC images).
pub fn compare_bytes(
    a_dmb: &[u8],
    a_rsc: Option<&[u8]>,
    b_dmb: &[u8],
    b_rsc: Option<&[u8]>,
    opts: &Options,
) -> io::Result<Report> {
    let (da, db) = std::thread::scope(|s| {
        let ha = s.spawn(|| Dmb::from_bytes(a_dmb));
        let hb = s.spawn(|| Dmb::from_bytes(b_dmb));
        (ha.join().unwrap(), hb.join().unwrap())
    });
    let (da, db) = (da?, db?);
    compare_dmbs(&da, a_rsc, &db, b_rsc, opts)
}

pub fn compare_dmbs(
    a: &Dmb,
    a_rsc: Option<&[u8]>,
    b: &Dmb,
    b_rsc: Option<&[u8]>,
    opts: &Options,
) -> io::Result<Report> {
    let (ca, cb) = std::thread::scope(|s| {
        let ha = s.spawn(|| Canon::build(a, a_rsc));
        let hb = s.spawn(|| Canon::build(b, b_rsc));
        (ha.join().unwrap(), hb.join().unwrap())
    });
    Ok(compare_canon(&ca?, &cb?, opts))
}

/// Test helper: panic with a readable report unless the two output pairs are
/// semantically equivalent. Intended for retained-vs-fresh compiler tests.
pub fn assert_equivalent_bytes(
    a_dmb: &[u8],
    a_rsc: Option<&[u8]>,
    b_dmb: &[u8],
    b_rsc: Option<&[u8]>,
    context: &str,
) {
    let report = compare_bytes(a_dmb, a_rsc, b_dmb, b_rsc, &Options::default())
        .unwrap_or_else(|e| panic!("{context}: decode failed: {e}"));
    if !report.equivalent() {
        panic!(
            "{context}: outputs are not semantically equivalent\n{}",
            report.render_text()
        );
    }
}

#[doc(hidden)]
pub fn _num(bits: u32) -> String {
    num(bits)
}
