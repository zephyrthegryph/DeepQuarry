//! Canonical form of a compiled world.
//!
//! Every table reference is replaced by the content it names: types by path,
//! procedures by a stable key (path plus semantic rank, or the referrer for
//! anonymous bodies), strings by text, resources by NQCRC content ID, variables
//! by name, instances by type and initializer. Table positions never appear in
//! the canonical form except where `ORDER_POLICY` documents that the order is
//! observable at runtime.
use byond_dmb::bytecode::{self, Instruction, Operand};
use byond_dmb::dmb::Dmb;
use byond_dmb::ids::NONE;
use byond_dmb::operands::{Value, ValueKind, Variable};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt::Write;
use xxhash_rust::xxh3::xxh3_64;

/// One comparable field of a canonical record. `family` groups report
/// categories ("var", "proc_list", ...); `label` names the exact field.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Field {
    pub family: &'static str,
    pub label: String,
    pub value: String,
}

/// Canonical procedure body: one hash per non-debug instruction plus one hash
/// over the debug stream (DbgFile/DbgLine positioned by instruction ordinal).
#[derive(Clone, Debug, Default)]
pub struct Code {
    pub instructions: Vec<u64>,
    pub debug: u64,
    pub decode_error: Option<String>,
}

pub(crate) fn esc(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() + 2);
    for &b in bytes {
        match b {
            b'\\' => out.push_str("\\\\"),
            b'"' => out.push_str("\\\""),
            b'\n' => out.push_str("\\n"),
            0x20..=0x7e => out.push(b as char),
            _ => {
                let _ = write!(out, "\\x{b:02x}");
            }
        }
    }
    out
}

pub(crate) fn num(bits: u32) -> String {
    let f = f32::from_bits(bits);
    if f.is_nan() {
        format!("nan({bits:#010x})")
    } else {
        format!("{f:?}")
    }
}

pub struct Ctx<'a> {
    pub dmb: &'a Dmb,
    /// RSC content ID to the first archive name with that content (None without an RSC).
    pub rsc_names: Option<HashMap<u32, Vec<u8>>>,
    pub proc_keys: Vec<String>,
    pub global_keys: HashMap<u32, String>,
    pub hidden: HashMap<u32, String>,
    /// Instance initializer proc ID -> inline canonical body (short bodies).
    pub inline_inits: HashMap<u32, String>,
}

const CYCLE: &str = "<cycle>";

impl<'a> Ctx<'a> {
    pub fn new(dmb: &'a Dmb, rsc_names: Option<HashMap<u32, Vec<u8>>>) -> Self {
        let mut ctx = Ctx {
            dmb,
            rsc_names,
            proc_keys: vec![String::new(); dmb.procs.len()],
            global_keys: HashMap::new(),
            hidden: HashMap::new(),
            inline_inits: HashMap::new(),
        };
        ctx.named_proc_keys();
        ctx.referrer_proc_keys();
        ctx.global_keys();
        ctx.hidden_tokens();
        ctx.inline_instance_initializers();
        let mut visiting = HashSet::new();
        for p in 0..dmb.procs.len() {
            if ctx.proc_keys[p].is_empty() && !dmb.is_reserved_proc_slot(p) {
                ctx.ensure_content_key(p, &mut visiting);
            }
        }
        ctx
    }

    pub fn string_bytes(&self, id: u32) -> Option<&[u8]> {
        if id == NONE {
            return None;
        }
        self.dmb.string(id)
    }
    /// Quoted string text, `null` for NONE.
    pub fn s(&self, id: u32) -> String {
        if id == NONE {
            return "null".into();
        }
        match self.dmb.string(id) {
            Some(b) => format!("\"{}\"", esc(b)),
            None => format!("<bad-string>"),
        }
    }
    /// Unquoted text (names, paths).
    pub fn t(&self, id: u32) -> String {
        match self.string_bytes(id) {
            Some(b) => esc(b),
            None if id == NONE => "null".into(),
            None => "<bad-string>".into(),
        }
    }
    pub fn ty(&self, class: u32) -> String {
        if class == NONE {
            return "null".into();
        }
        match self.dmb.classes.get(class as usize) {
            Some(c) => self.t(c.path_string_id()),
            None => "<bad-type>".into(),
        }
    }
    pub fn mob(&self, mob: u32) -> String {
        if mob == NONE {
            return "null".into();
        }
        match self.dmb.mobs.get(mob as usize) {
            Some(m) => self.ty(m.class),
            None => "<bad-mob>".into(),
        }
    }
    pub fn proc_key(&self, p: u32) -> String {
        if p == NONE {
            return "null".into();
        }
        match self.proc_keys.get(p as usize) {
            Some(k) if !k.is_empty() => k.clone(),
            Some(_) => CYCLE.into(),
            None => "<bad-proc>".into(),
        }
    }
    pub fn res(&self, r: u32) -> String {
        if r == NONE {
            return "null".into();
        }
        match self.dmb.resources.get(r as usize) {
            Some(rr) => {
                let name = self
                    .rsc_names
                    .as_ref()
                    .and_then(|m| m.get(&rr.id))
                    .map(|n| format!(" '{}'", esc(n)))
                    .unwrap_or_default();
                format!("rsc({}:{:08x}{name})", rr.kind, rr.id)
            }
            None => "<bad-resource>".into(),
        }
    }
    pub fn var_name(&self, v: u32) -> String {
        match self.dmb.variables.get(v as usize) {
            Some(var) => self.t(var.name),
            None => "<bad-var>".into(),
        }
    }
    pub fn global(&self, v: u32) -> String {
        match self.global_keys.get(&v) {
            Some(k) => k.clone(),
            None => self.var_name(v),
        }
    }
    pub fn instance(&self, i: u32) -> String {
        if i == NONE {
            return "null".into();
        }
        let Some(inst) = self.dmb.instances.get(i as usize) else {
            return "<bad-instance>".into();
        };
        let ty = if inst.kind == 8 {
            self.mob(inst.class)
        } else {
            self.ty(inst.class)
        };
        if inst.initializer == NONE {
            format!("{}:{ty}", inst.kind)
        } else if let Some(body) = self.inline_inits.get(&inst.initializer) {
            format!("{}:{ty}{{{body}}}", inst.kind)
        } else {
            format!("{}:{ty}{{{}}}", inst.kind, self.proc_key(inst.initializer))
        }
    }
    /// Render a variable operand against the incoming Cache (`cache`) and
    /// return the Cache afterwards. `a->b` sets the Cache to `a`; a bare
    /// field or proc name reads from it; initial()/issaved() wrap the whole
    /// access so `src->initial(.x)` and `initial(.x)` with Cache=src agree.
    pub fn var_chain(&self, v: &Variable, cache: &Option<String>) -> (String, Option<String>) {
        use Variable::*;
        let on = |name: String| match cache {
            Some(c) => format!("{c}->{name}"),
            None => name,
        };
        match v {
            Field(id) => (on(format!(".{}", self.t(*id))), cache.clone()),
            DynamicProc(id) => (on(format!("dproc:{}", self.t(*id))), cache.clone()),
            DynamicVerb(id) => (on(format!("dverb:{}", self.t(*id))), cache.clone()),
            StaticProc(_) | StaticVerb(_) => {
                let mut text = String::new();
                self.variable(v, &mut text);
                (on(text), cache.clone())
            }
            Initial(x) => {
                let (t, c) = self.var_chain(x, cache);
                (format!("initial({t})"), c)
            }
            IsSaved(x) => {
                let (t, c) = self.var_chain(x, cache);
                (format!("issaved({t})"), c)
            }
            SetCache(a, b) => {
                // The head is evaluated (a bare field head reads the Cache),
                // then becomes the Cache for the rest of the chain.
                let (head, _) = self.var_chain(a, cache);
                self.var_chain(b, &Some(head))
            }
            other => {
                let mut text = String::new();
                self.variable(other, &mut text);
                (text, cache.clone())
            }
        }
    }

    fn display_name(&self, p: u32) -> Option<String> {
        let pr = self.dmb.procs.get(p as usize)?;
        self.string_bytes(pr.strings[1]).map(esc)
    }
    fn hidden_token(&self, token: u32) -> String {
        match self.hidden.get(&token) {
            Some(site) => format!("hidden<{site}>"),
            None => "hidden<unbound>".into(),
        }
    }

    /// A tagged constant (`Value`) or a variable record's (kind, value) pair.
    pub fn tagged(&self, tag: u8, id: u32, number_bits: Option<u32>) -> String {
        match ValueKind::from_tag(tag) {
            ValueKind::Null => "null".into(),
            ValueKind::Number => num(number_bits.unwrap_or(id)),
            ValueKind::String => self.s(id),
            ValueKind::MobPath => format!("mobpath {}", self.mob(id)),
            ValueKind::ClientPath if id == 0 => "path /client".into(),
            ValueKind::ListPath if id == 0 => "path /list".into(),
            ValueKind::FilePath if id == 0 => "path /file".into(),
            ValueKind::SavefilePath if id == 0 => "path /savefile".into(),
            ValueKind::MovablePath
            | ValueKind::AtomPath
            | ValueKind::AreaPath
            | ValueKind::DatumPath
            | ValueKind::SavefilePath
            | ValueKind::FilePath
            | ValueKind::ListPath
            | ValueKind::ImagePath
            | ValueKind::ClientPath
            | ValueKind::BuiltinPath => format!("path{tag} {}", self.ty(id)),
            ValueKind::Resource => self.res(id),
            ValueKind::ProcPath => format!("procpath {}", self.proc_key(id)),
            ValueKind::InstanceTypePath => format!("inst {}", self.instance(id)),
            ValueKind::HiddenInitializer => self.hidden_token(id),
            ValueKind::GlobalVars => format!("global.vars({id})"),
            ValueKind::Other(t) => format!("tag{t}({id:#x})"),
        }
    }
    pub fn value(&self, v: &Value) -> String {
        let base = self.tagged(v.tag(), v.id(), v.number_bits());
        // Bits outside the tag/ID fields are kept verbatim.
        let high_tag = v.tag_word >> 16;
        let high_data = if v.kind() == ValueKind::Number {
            0
        } else {
            v.data_word >> 16
        };
        if high_tag != 0 || high_data != 0 {
            format!("{base}[{high_tag:#x}:{high_data:#x}]")
        } else {
            base
        }
    }
    pub fn variable(&self, v: &Variable, out: &mut String) {
        use Variable::*;
        match v {
            Field(id) => {
                out.push('.');
                out.push_str(&self.t(*id));
            }
            Global(id) => {
                out.push_str("global:");
                out.push_str(&self.global(*id));
            }
            Arg(n) => {
                let _ = write!(out, "arg{n}");
            }
            Local(n) => {
                let _ = write!(out, "local{n}");
            }
            DynamicProc(id) => {
                let _ = write!(out, "dproc:{}", self.t(*id));
            }
            DynamicVerb(id) => {
                let _ = write!(out, "dverb:{}", self.t(*id));
            }
            // The VM converts a static ProcID to its descriptor's display
            // StringID and then dispatches exactly like DynamicProc/Verb.
            StaticProc(id) => match self.display_name(*id) {
                Some(name) => {
                    let _ = write!(out, "dproc:{name}");
                }
                None => {
                    let _ = write!(out, "sproc:{}", self.proc_key(*id));
                }
            },
            StaticVerb(id) => match self.display_name(*id) {
                Some(name) => {
                    let _ = write!(out, "dverb:{name}");
                }
                None => {
                    let _ = write!(out, "sverb:{}", self.proc_key(*id));
                }
            },
            SetCache(a, b) => {
                self.variable(a, out);
                out.push_str("->");
                self.variable(b, out);
            }
            Initial(x) => {
                out.push_str("initial(");
                self.variable(x, out);
                out.push(')');
            }
            IsSaved(x) => {
                out.push_str("issaved(");
                self.variable(x, out);
                out.push(')');
            }
            Usr => out.push_str("usr"),
            Src => out.push_str("src"),
            Args => out.push_str("args"),
            Dot => out.push_str("."),
            Cache => out.push_str("cache"),
            CacheKey => out.push_str("cache-key"),
            CacheIndex => out.push_str("cache-index"),
            World => out.push_str("world"),
            Caller => out.push_str("caller"),
            Callee => out.push_str("callee"),
            Null => out.push_str("null-ref"),
        }
    }

    // ---- procedure keys -------------------------------------------------

    fn named_proc_keys(&mut self) {
        let dmb = self.dmb;
        // Anchor: (owner path, list kind, position). The position inside an
        // owner's proc/verb list is definition precedence, which is semantic.
        let mut anchor: Vec<Option<(Vec<u8>, u8, usize)>> = vec![None; dmb.procs.len()];
        let mut consider = |p: u32, cand: (Vec<u8>, u8, usize)| {
            if let Some(slot) = anchor.get_mut(p as usize) {
                if slot.as_ref().map_or(true, |cur| cand < *cur) {
                    *slot = Some(cand);
                }
            }
        };
        for class in &dmb.classes {
            let owner = self
                .string_bytes(class.path_string_id())
                .unwrap_or(b"?")
                .to_vec();
            for (kind, lid) in [(1u8, class.verb_list_id()), (2u8, class.proc_list_id())] {
                if let Some(list) = (lid != NONE).then(|| dmb.lists.get(lid as usize)).flatten() {
                    for (pos, &p) in list.iter().enumerate() {
                        consider(p, (owner.clone(), kind, pos));
                    }
                }
            }
        }
        let wl = dmb.world.proc_list_id();
        if let Some(list) = (wl != NONE).then(|| dmb.lists.get(wl as usize)).flatten() {
            for (pos, &p) in list.iter().enumerate() {
                consider(p, (Vec::new(), 0, pos));
            }
        }
        let mut groups: HashMap<&[u8], Vec<usize>> = HashMap::new();
        for (p, proc_) in dmb.procs.iter().enumerate() {
            if dmb.is_reserved_proc_slot(p) || proc_.strings[0] == NONE {
                continue;
            }
            if let Some(path) = dmb.string(proc_.strings[0]) {
                groups.entry(path).or_default().push(p);
            }
        }
        for (path, mut members) in groups {
            let text = esc(path);
            if members.len() == 1 {
                self.proc_keys[members[0]] = text;
                continue;
            }
            members.sort_by(|&a, &b| {
                (anchor[a].is_none(), &anchor[a]).cmp(&(anchor[b].is_none(), &anchor[b]))
            });
            let mut rank = 0;
            for p in members {
                if anchor[p].is_some() {
                    self.proc_keys[p] = format!("{text}#{rank}");
                    rank += 1;
                }
                // Unanchored duplicates receive a content key later.
            }
        }
    }

    fn referrer_proc_keys(&mut self) {
        let dmb = self.dmb;
        let set = |keys: &mut Vec<String>, p: u32, key: String| {
            if let Some(slot) = keys.get_mut(p as usize) {
                if slot.is_empty() {
                    *slot = key;
                }
            }
        };
        // Class `<init>` bodies and argument `in <expression>` sources are keyed by content, not by the type or
        // procedure that refers to them: DreamMaker shares one body between types whose defaults are identical
        // (2,855 per-type bodies in the production build), this compiler emits one per type. A body whose content
        // differs still shows up as a missing/extra anonymous procedure and as a different `initializer` field.
        let _ = &set;
        let g = dmb.world.global_initializer_proc_id();
        if g != NONE && self.proc_keys.get(g as usize).is_some_and(|k| k.is_empty()) {
            self.proc_keys[g as usize] = "<global-init>".into();
        }
    }

    /// Procedure IDs a body references (calls, proc paths, instance initializers).
    fn referenced_procs(&self, p: usize) -> Vec<u32> {
        let mut out = Vec::new();
        let Some(words) = self.dmb.proc_code_words(p) else {
            return out;
        };
        let Ok(instructions) = bytecode::decode(words) else {
            return out;
        };
        let value = |v: &Value, out: &mut Vec<u32>| match v.kind() {
            ValueKind::ProcPath => out.push(v.id()),
            ValueKind::InstanceTypePath => {
                if let Some(i) = self.dmb.instances.get(v.id() as usize) {
                    if i.initializer != NONE {
                        out.push(i.initializer);
                    }
                }
            }
            _ => {}
        };
        fn var(v: &Variable, out: &mut Vec<u32>) {
            match v {
                Variable::StaticProc(p) | Variable::StaticVerb(p) => out.push(*p),
                Variable::SetCache(a, b) => {
                    var(a, out);
                    var(b, out);
                }
                Variable::Initial(x) | Variable::IsSaved(x) => var(x, out),
                _ => {}
            }
        }
        for ins in &instructions {
            if matches!(ins.opcode, 0x30) {
                if let Some(&w) = ins.operands.get(1) {
                    out.push(w);
                }
            }
            if ins.opcode == 0xcd {
                if let Some(&w) = ins.operands.first() {
                    out.push(w);
                }
            }
            if let Ok(ops) = ins.typed_operands() {
                for op in ops {
                    match op {
                        Operand::Value(v) => value(&v, &mut out),
                        Operand::Variable(v) => var(&v, &mut out),
                        Operand::Switch { cases, .. } => {
                            cases.iter().for_each(|(v, _)| value(v, &mut out))
                        }
                        Operand::RangeSwitch { ranges, exact, .. } => {
                            ranges.iter().for_each(|(a, b, _)| {
                                value(a, &mut out);
                                value(b, &mut out)
                            });
                            exact.iter().for_each(|(v, _)| value(v, &mut out));
                        }
                        _ => {}
                    }
                }
            }
        }
        out
    }

    fn ensure_content_key(&mut self, p: usize, visiting: &mut HashSet<usize>) {
        if !self.proc_keys[p].is_empty() || !visiting.insert(p) {
            return;
        }
        for r in self.referenced_procs(p) {
            let r = r as usize;
            if r < self.proc_keys.len() && self.proc_keys[r].is_empty() && r != p {
                self.ensure_content_key(r, visiting);
            }
        }
        let mut text = String::new();
        for f in self.proc_fields(p) {
            let _ = writeln!(text, "{}={}", f.label, f.value);
        }
        if let Some(words) = self.dmb.proc_code_words(p) {
            // Debug streams are compared separately; identity is code only.
            render_code_text(self, words, &mut text, false);
        }
        let name = self
            .dmb
            .procs
            .get(p)
            .and_then(|pr| (pr.strings[0] != NONE).then(|| self.t(pr.strings[0])))
            .unwrap_or_default();
        self.proc_keys[p] = format!("{name}<anon {:016x}>", xxh3_64(text.as_bytes()));
        visiting.remove(&p);
    }

    /// Map/modified-type instance initializers are usually a few constant
    /// assignments. Render short unnamed bodies inline into the instance, so a
    /// difference shows where the instance is used instead of as an unrelated
    /// anonymous procedure. Their debug lines are not compared.
    fn inline_instance_initializers(&mut self) {
        let dmb = self.dmb;
        let mut out = HashMap::new();
        for inst in &dmb.instances {
            let p = inst.initializer;
            if p == NONE || out.contains_key(&p) {
                continue;
            }
            let Some(pr) = dmb.procs.get(p as usize) else {
                continue;
            };
            if pr.strings[0] != NONE || !self.proc_keys[p as usize].is_empty() {
                continue;
            }
            let Some(words) = dmb.proc_code_words(p as usize) else {
                continue;
            };
            let Ok(lines) = render_code_lines(self, words) else {
                continue;
            };
            let code: Vec<String> = lines
                .into_iter()
                .filter(|(d, _)| !d)
                .map(|(_, l)| l)
                .collect();
            if code.len() <= 24 {
                out.insert(
                    p,
                    constant_assignments(&code).unwrap_or_else(|| code.join("; ")),
                );
            }
        }
        for (&p, body) in &out {
            self.proc_keys[p as usize] = format!("<inline-init {:016x}>", xxh3_64(body.as_bytes()));
        }
        self.inline_inits = out;
    }

    // ---- globals and hidden initializer tokens --------------------------

    pub fn footer_pairs(&self) -> Vec<(u32, u32)> {
        self.dmb.global_variable_flags().unwrap_or_default()
    }

    fn global_keys(&mut self) {
        let dmb = self.dmb;
        let mut ids: BTreeSet<u32> = self.footer_pairs().iter().map(|p| p.0).collect();
        // Every Global(VarID) operand names a global variable record.
        let referrers = scan_global_refs(self);
        ids.extend(referrers.keys().copied());
        let mut by_name: HashMap<String, Vec<u32>> = HashMap::new();
        for &v in &ids {
            by_name.entry(self.var_name(v)).or_default().push(v);
        }
        for (name, members) in by_name {
            if members.len() == 1 {
                self.global_keys.insert(members[0], name);
                continue;
            }
            // Same-named globals (static locals of different procs): identify each
            // by its named referencing procedures, then its default value.
            let mut keyed: Vec<(String, u32)> = members
                .iter()
                .map(|&v| {
                    let refs = referrers
                        .get(&v)
                        .map(|s| s.iter().cloned().collect::<Vec<_>>().join(","))
                        .unwrap_or_default();
                    let var = &dmb.variables[v as usize];
                    let default = if var.kind == 62 {
                        "hidden".into()
                    } else {
                        self.tagged(var.kind, var.value, None)
                    };
                    (format!("{name}@[{refs}]={default}"), v)
                })
                .collect();
            keyed.sort();
            let mut count: HashMap<String, usize> = HashMap::new();
            for (k, v) in keyed {
                let n = count.entry(k.clone()).or_insert(0);
                let key = if *n == 0 {
                    k.clone()
                } else {
                    format!("{k}#{n}")
                };
                *n += 1;
                self.global_keys.insert(v, key);
            }
        }
    }

    fn hidden_tokens(&mut self) {
        let dmb = self.dmb;
        let mut sites: HashMap<u32, String> = HashMap::new();
        let mut add = |token: u32, site: String| {
            let e = sites.entry(token).or_insert_with(|| site.clone());
            if site < *e {
                *e = site;
            }
        };
        for (ci, class) in dmb.classes.iter().enumerate() {
            let path = self.t(class.path_string_id());
            for (v, _) in dmb.class_variable_declarations(ci).unwrap_or_default() {
                if let Some(var) = dmb.variables.get(v as usize) {
                    if var.kind == 62 {
                        add(var.value, format!("{path}.{}", self.t(var.name)));
                    }
                }
            }
            for iv in dmb.class_initial_values(ci).unwrap_or_default() {
                if iv.value.kind() == ValueKind::HiddenInitializer {
                    add(
                        iv.value.id(),
                        format!("{path}.{}", self.var_name(iv.variable_id)),
                    );
                }
            }
        }
        for (v, _) in self.footer_pairs() {
            if let Some(var) = dmb.variables.get(v as usize) {
                if var.kind == 62 {
                    add(var.value, format!("global:{}", self.global(v)));
                }
            }
        }
        self.hidden = sites;
    }

    // ---- records --------------------------------------------------------

    pub fn proc_fields(&self, p: usize) -> Vec<Field> {
        let dmb = self.dmb;
        let pr = &dmb.procs[p];
        let mut f = Vec::new();
        let mut push = |family: &'static str, label: &str, value: String| {
            f.push(Field {
                family,
                label: label.into(),
                value,
            })
        };
        push("proc_meta", "path", self.s(pr.strings[0]));
        push("proc_meta", "name", self.s(pr.strings[1]));
        push("proc_meta", "desc", self.s(pr.strings[2]));
        push("proc_meta", "category", self.s(pr.strings[3]));
        push("proc_meta", "src", format!("{:?}", pr.source_location()));
        push("proc_meta", "flags", format!("{:#x}", pr.effective_flags()));
        push(
            "proc_meta",
            "invisibility",
            format!("{:?}", pr.invisibility_setting()),
        );
        let args = dmb
            .proc_arguments_iter(p)
            .map(|it| {
                it.map(|a| {
                    let src = match dmb.argument_source_proc_id(&a) {
                        Some(sp) => format!("in {}", self.proc_key(sp)),
                        None => format!("src {:#x}", a.value_source),
                    };
                    format!(
                        "{} as {:#x} {src} r{}",
                        self.var_name(a.variable_id),
                        a.type_flags,
                        a.reserved
                    )
                })
                .collect::<Vec<_>>()
                .join("; ")
            })
            .unwrap_or_else(|| "<malformed>".into());
        push("proc_args", "args", args);
        let locals = dmb
            .lists
            .get(pr.code_locals_args[1] as usize)
            .filter(|_| pr.code_locals_args[1] != NONE)
            .map(|l| {
                l.iter()
                    .map(|&v| {
                        // Local names are not observable; compiler temporaries
                        // (DM: empty name, native: __dmb_*) are the same slot kind.
                        let name = self.var_name(v);
                        if name.starts_with("__dmb_") {
                            String::new()
                        } else {
                            name
                        }
                    })
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default();
        push("proc_locals", "locals", locals);
        f
    }
}

/// VarID -> keys of named procedures that reference it as `Global(VarID)`.
fn scan_global_refs(ctx: &Ctx<'_>) -> HashMap<u32, BTreeSet<String>> {
    let dmb = ctx.dmb;
    let n = dmb.procs.len();
    let threads = std::thread::available_parallelism()
        .map_or(4, |n| n.get())
        .min(16);
    let chunk = n.div_ceil(threads).max(1);
    let parts: Vec<HashMap<u32, BTreeSet<String>>> = std::thread::scope(|s| {
        (0..n)
            .step_by(chunk)
            .map(|start| {
                s.spawn(move || {
                    let mut out: HashMap<u32, BTreeSet<String>> = HashMap::new();
                    fn var(v: &Variable, f: &mut impl FnMut(u32)) {
                        match v {
                            Variable::Global(id) => f(*id),
                            Variable::SetCache(a, b) => {
                                var(a, f);
                                var(b, f);
                            }
                            Variable::Initial(x) | Variable::IsSaved(x) => var(x, f),
                            _ => {}
                        }
                    }
                    for p in start..(start + chunk).min(n) {
                        let Some(words) = dmb.proc_code_words(p) else {
                            continue;
                        };
                        let Ok(ins) = bytecode::decode(words) else {
                            continue;
                        };
                        let key = &ctx.proc_keys[p];
                        for i in &ins {
                            if let Ok(ops) = i.typed_operands() {
                                for op in ops {
                                    if let Operand::Variable(v) = op {
                                        var(&v, &mut |id| {
                                            let e = out.entry(id).or_default();
                                            if !key.is_empty() {
                                                e.insert(key.clone());
                                            }
                                        });
                                    }
                                }
                            }
                        }
                    }
                    out
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|h| h.join().unwrap())
            .collect()
    });
    let mut all: HashMap<u32, BTreeSet<String>> = HashMap::new();
    for part in parts {
        for (k, v) in part {
            all.entry(k).or_default().extend(v);
        }
    }
    all
}

/// Label map: instruction word offset -> non-debug instruction ordinal.
fn labels(instructions: &[Instruction], end: usize) -> HashMap<usize, usize> {
    let mut map = HashMap::with_capacity(instructions.len() + 1);
    let mut pending = Vec::new();
    let mut index = 0;
    for ins in instructions {
        pending.push(ins.offset);
        if !is_debug(ins.opcode) {
            for o in pending.drain(..) {
                map.insert(o, index);
            }
            index += 1;
        }
    }
    for o in pending.drain(..) {
        map.insert(o, index);
    }
    map.insert(end, index);
    map
}

/// A body made only of statements `<constant pushes and list constructors>;
/// SetVar src->.<field>` (then End) to distinct fields assigns independent
/// constants: its order is not observable, so it is rendered sorted by field.
fn constant_assignments(code: &[String]) -> Option<String> {
    let (end, body) = code.split_last()?;
    if end != "End" {
        return None;
    }
    let mut out: Vec<(&str, String)> = Vec::new();
    let mut pending: Vec<&str> = Vec::new();
    for line in body {
        if let Some(field) = line.strip_prefix("SetVar src->.") {
            if pending.is_empty() || field.contains("->") {
                return None;
            }
            out.push((field, pending.join(" ")));
            pending.clear();
        } else if (line.starts_with("PushVal ") && !line.starts_with("PushVal inst "))
            || line.starts_with("NewList ")
            || line.starts_with("NewAssocList ")
            || line == "EmptyList"
        {
            pending.push(line);
        } else {
            return None;
        }
    }
    if !pending.is_empty() {
        return None;
    }
    out.sort();
    if out.windows(2).any(|w| w[0].0 == w[1].0) {
        return None;
    }
    Some(
        out.iter()
            .map(|(f, v)| format!(".{f}={v}"))
            .collect::<Vec<_>>()
            .join("; "),
    )
}

/// Opcodes after which control never reaches the next instruction.
fn no_fallthrough(op: u32) -> bool {
    matches!(op, 0x00 | 0x0f | 0x12 | 0xf8 | 0x78 | 0x79 | 0x7a | 0xb1)
}

/// Symbolic content of the receiver Cache register before each instruction.
///
/// A bare field or proc operand reads the Cache: Dream Maker omits the
/// receiver when the Cache already holds it (initially `src`), while the
/// native compiler may set it again. Forward dataflow over the control-flow
/// graph gives each instruction's incoming Cache as the canonical text of the
/// object it holds, or None when paths disagree (then operands stay bare).
/// Two encodings therefore compare equal only when they read the same
/// receiver expression on every path.
pub(crate) fn cache_states(ctx: &Ctx<'_>, ins: &[Instruction]) -> Vec<Option<String>> {
    let n = ins.len();
    let index: HashMap<usize, usize> = ins.iter().enumerate().map(|(k, i)| (i.offset, k)).collect();
    let mut state: Vec<Option<Option<String>>> = vec![None; n];
    if n == 0 {
        return Vec::new();
    }
    state[0] = Some(Some("src".into()));
    let mut work = vec![0usize];
    let mut queued = vec![false; n];
    queued[0] = true;
    while let Some(k) = work.pop() {
        queued[k] = false;
        let mut cache = state[k].clone().unwrap_or(None);
        let i = &ins[k];
        if !is_debug(i.opcode) {
            if let Ok(ops) = i.typed_operands() {
                for op in &ops {
                    if let Operand::Variable(v) = op {
                        cache = ctx.var_chain(v, &cache).1;
                    }
                }
            }
            if matches!(i.opcode, 0x13d | 0x13e) {
                cache = None;
            }
        }
        let mut succ: Vec<usize> = Vec::new();
        if !no_fallthrough(i.opcode) && k + 1 < n {
            succ.push(k + 1);
        }
        match i.branch_targets() {
            Ok(targets) => succ.extend(
                targets
                    .iter()
                    .filter_map(|t| index.get(&(*t as usize)).copied()),
            ),
            Err(_) => {}
        }
        for s in succ {
            let merged = match &state[s] {
                None => Some(cache.clone()),
                Some(prev) if *prev == cache => continue,
                Some(None) => continue,
                Some(Some(_)) => Some(None),
            };
            state[s] = merged;
            if !queued[s] {
                queued[s] = true;
                work.push(s);
            }
        }
    }
    // Unreachable instructions keep an unknown Cache.
    state.into_iter().map(|s| s.unwrap_or(None)).collect()
}

/// Canonical debug stream: each DbgLine with its instruction ordinal and the
/// file in effect. A DbgFile that only repeats the current file, or that is not
/// followed by a DbgLine, has no observable effect and disappears.
pub(crate) fn debug_entries(lines: &[(bool, String)]) -> Vec<String> {
    let mut file = String::from("DbgFile ?");
    let mut ordinal = 0;
    let mut out = Vec::new();
    for (dbg, text) in lines {
        if !dbg {
            ordinal += 1;
        } else if text.starts_with("DbgFile") {
            file.clone_from(text);
        } else {
            out.push(format!("@{ordinal} {file} {text}"));
        }
    }
    out
}

pub(crate) fn is_debug(op: u32) -> bool {
    matches!(op, 0x84 | 0x85)
}

fn label(map: &HashMap<usize, usize>, target: u32, out: &mut String) {
    match map.get(&(target as usize)) {
        Some(i) => {
            let _ = write!(out, "L{i}");
        }
        None => {
            let _ = write!(out, "L?{target}");
        }
    }
}

/// Render one instruction canonically.
pub(crate) fn render_instruction(
    ctx: &Ctx<'_>,
    ins: &Instruction,
    map: &HashMap<usize, usize>,
    cache: &mut Option<String>,
    out: &mut String,
) {
    if ins.opcode == 0x50 {
        // PushInt n == PushVal n for 0..=65535 (native zero-extends a u16).
        out.push_str("PushVal ");
        out.push_str(&num((ins.operands[0] as u16 as f32).to_bits()));
        if ins.operands[0] >> 16 != 0 {
            let _ = write!(out, " [hi {:#x}]", ins.operands[0] >> 16);
        }
        return;
    }
    // Reading the `null` variable pushes null, exactly what `PushVal null` pushes; DreamMaker uses either form.
    if ins.name == "GetVar" && ins.operands.len() == 1 && matches!(ins.typed_operands().as_deref(), Ok([Operand::Variable(Variable::Null)])) {
        out.push_str("PushVal null");
        return;
    }
    out.push_str(ins.name);
    let ops = match ins.typed_operands() {
        Ok(ops) => ops,
        Err(e) => {
            let _ = write!(out, " <bad operands: {} {:?}>", e.reason, ins.operands);
            return;
        }
    };
    for (index, op) in ops.iter().enumerate() {
        out.push_str(if index == 0 { " " } else { ", " });
        match op {
            Operand::Word(w) => {
                let w = *w;
                if index == 0 && bytecode::is_branch_opcode(ins.opcode) {
                    label(map, w, out);
                } else if index == 0 && matches!(ins.opcode, 0x02 | 0x04 | 0x84) {
                    out.push_str(&ctx.s(w));
                } else if (ins.opcode == 0x30 && index == 1) || (ins.opcode == 0xcd && index == 0) {
                    out.push_str(&ctx.proc_key(w));
                } else {
                    let _ = write!(out, "{w}");
                }
            }
            Operand::Value(v) => out.push_str(&ctx.value(v)),
            Operand::Variable(v) => {
                let (text, next) = ctx.var_chain(v, cache);
                out.push_str(&text);
                *cache = next;
            }
            Operand::Switch { cases, default } => {
                out.push('{');
                for (v, t) in cases {
                    out.push_str(&ctx.value(v));
                    out.push_str("=>");
                    label(map, *t, out);
                    out.push(';');
                }
                out.push_str("else=>");
                label(map, *default, out);
                out.push('}');
            }
            Operand::PickSwitch { cases, default } => {
                out.push('{');
                for (w, t) in cases {
                    let _ = write!(out, "{w}=>");
                    label(map, *t, out);
                    out.push(';');
                }
                out.push_str("else=>");
                label(map, *default, out);
                out.push('}');
            }
            Operand::RangeSwitch {
                ranges,
                exact,
                default,
            } => {
                out.push('{');
                for (a, b, t) in ranges {
                    let _ = write!(out, "{}..{}=>", ctx.value(a), ctx.value(b));
                    label(map, *t, out);
                    out.push(';');
                }
                for (v, t) in exact {
                    out.push_str(&ctx.value(v));
                    out.push_str("=>");
                    label(map, *t, out);
                    out.push(';');
                }
                out.push_str("else=>");
                label(map, *default, out);
                out.push('}');
            }
            Operand::PickProb(targets) => {
                out.push('[');
                for t in targets {
                    label(map, *t, out);
                    out.push(';');
                }
                out.push(']');
            }
        }
    }
}

/// Full readable listing (used for content keys and for diff excerpts).
pub(crate) fn render_code_lines(
    ctx: &Ctx<'_>,
    words: &[u32],
) -> Result<Vec<(bool, String)>, String> {
    let ins = bytecode::decode(words)
        .map_err(|e| format!("decode error at {}: {}", e.offset, e.reason))?;
    let map = labels(&ins, words.len());
    let states = cache_states(ctx, &ins);
    Ok(ins
        .iter()
        .zip(states)
        .map(|(i, mut cache)| {
            let mut s = String::new();
            render_instruction(ctx, i, &map, &mut cache, &mut s);
            (is_debug(i.opcode), s)
        })
        .collect())
}

fn render_code_text(ctx: &Ctx<'_>, words: &[u32], out: &mut String, debug: bool) {
    match render_code_lines(ctx, words) {
        Ok(lines) => {
            for (_, l) in lines.into_iter().filter(|(d, _)| debug || !d) {
                out.push_str(&l);
                out.push('\n');
            }
        }
        Err(e) => out.push_str(&e),
    }
}

pub(crate) fn code_hashes(ctx: &Ctx<'_>, p: usize) -> Code {
    let Some(words) = ctx.dmb.proc_code_words(p) else {
        return Code::default();
    };
    let ins = match bytecode::decode(words) {
        Ok(i) => i,
        Err(e) => {
            return Code {
                decode_error: Some(format!("decode error at {}: {}", e.offset, e.reason)),
                instructions: vec![xxh3_64(
                    &words
                        .iter()
                        .flat_map(|w| w.to_le_bytes())
                        .collect::<Vec<_>>(),
                )],
                debug: 0,
            }
        }
    };
    let map = labels(&ins, words.len());
    let mut code = Code {
        instructions: Vec::with_capacity(ins.len()),
        ..Default::default()
    };
    let mut buf = String::new();
    let mut debug = String::new();
    let mut file = String::from("DbgFile ?");
    let states = cache_states(ctx, &ins);
    for (i, mut cache) in ins.iter().zip(states) {
        buf.clear();
        render_instruction(ctx, i, &map, &mut cache, &mut buf);
        if i.opcode == 0x84 {
            file.clone_from(&buf);
        } else if i.opcode == 0x85 {
            let _ = writeln!(debug, "@{} {file} {buf}", code.instructions.len());
        } else {
            code.instructions.push(xxh3_64(buf.as_bytes()));
        }
    }
    code.debug = xxh3_64(debug.as_bytes());
    code
}

/// Ordered record fields for one class.
pub(crate) fn class_fields(ctx: &Ctx<'_>, ci: usize) -> Vec<Field> {
    let dmb = ctx.dmb;
    let c = &dmb.classes[ci];
    let mut f = Vec::new();
    let mut push = |family: &'static str, label: String, value: String| {
        f.push(Field {
            family,
            label,
            value,
        })
    };
    push("type_meta", "parent".into(), ctx.ty(c.parent_class_id()));
    push("type_appearance", "name".into(), ctx.s(c.name_string_id()));
    push(
        "type_appearance",
        "desc".into(),
        ctx.s(c.description_string_id()),
    );
    push(
        "type_appearance",
        "icon".into(),
        ctx.res(c.icon_resource_id()),
    );
    push(
        "type_appearance",
        "icon_state".into(),
        ctx.s(c.icon_state_string_id()),
    );
    push("type_appearance", "dir".into(), c.direction.to_string());
    push(
        "type_meta",
        "interface".into(),
        format!("{:?}", c.native_interface()),
    );
    push("type_appearance", "text".into(), ctx.s(c.text));
    push("type_appearance", "maptext".into(), ctx.s(c.maptext));
    push(
        "type_appearance",
        "maptext_geometry".into(),
        format!("{:?}", c.maptext_geometry),
    );
    push("type_appearance", "suffix".into(), ctx.s(c.suffix));
    push("type_flags", "flags".into(), format!("{:#x}", c.flags));
    push("type_appearance", "layer".into(), num(c.layer_bits));
    push(
        "type_appearance",
        "transform".into(),
        format!("{:?}", c.transform.map(|t| t.map(num))),
    );
    push(
        "type_appearance",
        "color_matrix".into(),
        format!("{:?}", c.color_matrix.map(|t| t.map(num))),
    );
    push(
        "type_meta",
        "slot5".into(),
        format!("{:#x}", c.lists_and_procs[5]),
    );
    let list = |lid: u32| -> String {
        dmb.lists
            .get(lid as usize)
            .filter(|_| lid != NONE)
            .map(|l| {
                l.iter()
                    .map(|&p| ctx.proc_key(p))
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default()
    };
    // The verb list order only changes the order a client lists verbs in (the verb panel sorts them),
    // so compare it as a set; the length and members still must match.
    let verbs = {
        let text = list(c.verb_list_id());
        let mut keys: Vec<&str> = text.split(", ").collect();
        keys.sort_unstable();
        keys.join(", ")
    };
    push("type_verbs", "verbs".into(), verbs);
    // Proc lists: dispatch is by name, so only the order among same-named
    // entries (precedence) is observable (DD probe: regrouping by name leaves
    // calls and typesof unchanged). Compare per name, in list order.
    let mut groups: BTreeMap<String, Vec<String>> = BTreeMap::new();
    if let Some(l) = dmb
        .lists
        .get(c.proc_list_id() as usize)
        .filter(|_| c.proc_list_id() != NONE)
    {
        for &p in l {
            let name = dmb
                .procs
                .get(p as usize)
                .and_then(|pr| ctx.string_bytes(pr.strings[0]))
                .map(|path| esc(path.rsplit(|b| *b == b'/').next().unwrap_or(path)))
                .unwrap_or_default();
            groups.entry(name).or_default().push(ctx.proc_key(p));
        }
    }
    push(
        "type_procs",
        "procs".into(),
        groups
            .iter()
            .map(|(n, ks)| format!("{n}=[{}]", ks.join(" > ")))
            .collect::<Vec<_>>()
            .join(", "),
    );
    push(
        "type_meta",
        "initializer".into(),
        ctx.proc_key(c.initializer_proc_id()),
    );
    // Declarations: the loader re-sorts declaration pairs by name (FORMAT.md),
    // so wire order is not observable; key by name.
    let mut decls: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for (v, flags) in dmb.class_variable_declarations(ci).unwrap_or_default() {
        let Some(var) = dmb.variables.get(v as usize) else {
            decls
                .entry("<bad-var>".into())
                .or_default()
                .push(String::new());
            continue;
        };
        let default = ctx.tagged(var.kind, var.value, None);
        decls
            .entry(ctx.t(var.name))
            .or_default()
            .push(format!("flags {flags:#x} = {default}"));
    }
    for (name, values) in decls {
        push("type_var_decl", format!("var {name}"), values.join(" | "));
    }
    let mut inits: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for iv in dmb.class_initial_values(ci).unwrap_or_default() {
        inits
            .entry(ctx.var_name(iv.variable_id))
            .or_default()
            .push(ctx.value(&iv.value));
    }
    for (name, values) in inits {
        push(
            "type_var_default",
            format!("default {name}"),
            values.join(" | "),
        );
    }
    let mut overrides: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for o in dmb.class_builtin_overrides(ci).unwrap_or_default() {
        overrides
            .entry(ctx.t(o.name_string_id))
            .or_default()
            .push(ctx.value(&o.value));
    }
    // Builtin overrides apply in order; a later entry wins (DD probe:
    // prepending a duplicate with another value changes nothing).
    for (name, values) in overrides {
        push(
            "type_builtin_override",
            format!("override {name}"),
            values.last().cloned().unwrap_or_default(),
        );
    }
    f
}

/// Public listing for diagnostics: (is_debug, text) per instruction.
pub fn render_code_lines_pub(ctx: &Ctx<'_>, words: &[u32]) -> Result<Vec<(bool, String)>, String> {
    render_code_lines(ctx, words)
}

/// Escaped byte text, for diagnostics.
pub fn esc_pub(bytes: &[u8]) -> String {
    esc(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn independent_constant_assignments_compare_in_any_order() {
        let a = [
            "PushVal 1.0",
            "SetVar src->.b",
            "PushVal \"x\"",
            "NewList 1",
            "SetVar src->.a",
            "End",
        ]
        .map(String::from);
        let b = [
            "PushVal \"x\"",
            "NewList 1",
            "SetVar src->.a",
            "PushVal 1.0",
            "SetVar src->.b",
            "End",
        ]
        .map(String::from);
        assert_eq!(constant_assignments(&a), constant_assignments(&b));
        assert!(constant_assignments(&a).is_some());
        // Repeated fields and effectful statements keep their order.
        let dup = [
            "PushVal 1.0",
            "SetVar src->.a",
            "PushVal 2.0",
            "SetVar src->.a",
            "End",
        ]
        .map(String::from);
        assert_eq!(constant_assignments(&dup), None);
        let call = ["Call dproc:x, 0", "SetVar src->.a", "End"].map(String::from);
        assert_eq!(constant_assignments(&call), None);
    }

    #[test]
    fn bare_cache_field_equals_explicit_receiver() {
        let dmb = Dmb::from_bytes(include_bytes!("../tests/fixtures/order_probe.dmb")).unwrap();
        let ctx = Ctx::new(&dmb, None);
        let field = dmb.strings.iter().position(|s| s.data == b"zz").unwrap() as u32;
        let src = Some("src".to_string());
        let bare = ctx.var_chain(&Variable::Field(field), &src);
        let explicit = ctx.var_chain(
            &Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(field))),
            &None,
        );
        assert_eq!(bare, explicit);
        // initial() wraps the whole access in both spellings.
        let wrapped = ctx.var_chain(&Variable::Initial(Box::new(Variable::Field(field))), &src);
        let inner = ctx.var_chain(
            &Variable::SetCache(
                Box::new(Variable::Src),
                Box::new(Variable::Initial(Box::new(Variable::Field(field)))),
            ),
            &None,
        );
        assert_eq!(wrapped, inner);
        // An unknown Cache never matches an explicit receiver.
        assert_ne!(ctx.var_chain(&Variable::Field(field), &None).0, explicit.0);
    }
    #[test]
    fn reading_the_null_variable_renders_as_push_null() {
        let dmb = Dmb::from_bytes(include_bytes!("../tests/fixtures/order_probe.dmb")).unwrap();
        let ctx = Ctx::new(&dmb, None);
        let render = |words: &[u32]| -> Vec<String> {
            render_code_lines_pub(&ctx, words)
                .unwrap()
                .into_iter()
                .map(|(_, line)| line)
                .collect()
        };
        let mut get_null = vec![0x33u32];
        get_null.extend(Variable::Null.encode());
        assert_eq!(render(&get_null), vec!["PushVal null".to_string()]);
    }
}
