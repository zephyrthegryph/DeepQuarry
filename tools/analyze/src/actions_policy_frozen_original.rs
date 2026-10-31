//! Whole exact ACTION row policy shared by original and native producers.
//! Native allocation/abort admission is optional; legacy behavior is unchanged.
use crate::{captured_generator_budget::Budget, sparse_slots_policy::Output};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
/// Vars every act carries: a typed field of this name is an error, except `origin`, which the design names for a move's turfs and which is the
/// ORIGIN_* of the act, so it is declared `origin_turf`.
const RESERVED: &[&str] = &[
    "holder",
    "cap",
    "activation",
    "source",
    "target",
    "actor",
    "origin",
    "provider",
    "authority",
    "rolled",
    "outcome",
    "reason",
    "args",
    "key",
    "held",
    "reply",
];

struct Action {
    name: String,
    /// (declared type text, name) in order, the parent's first.
    fields: Vec<(String, String)>,
    fixed: bool,
    query: bool,
    notice: String,
    parent: Option<String>,
    rel: String,
    line: u32,
}

fn split_notice_opt(arg: &str) -> Option<String> {
    let rest = arg
        .trim()
        .strip_prefix("notice")?
        .trim_start()
        .strip_prefix('=')?;
    if rest.starts_with('=') {
        return None;
    }
    Some(rest.trim().to_string())
}

/// The past tense of one word of an action name.
fn past_word(w: &str) -> String {
    match w {
        "fall" => "fell".into(),
        "speak" => "spoke".into(),
        "equip" | "unequip" => format!("{}ped", w),
        "hit" | "into" => w.into(),
        _ if w.ends_with("ed") => w.into(),
        _ if w.ends_with('e') => format!("{}d", w),
        _ => format!("{}ed", w),
    }
}

/// `fall` -> `fell`, `z_change` -> `z_changed`, `stumbled_into` kept, `hit/projectile` -> `hit/projectile`.
pub(crate) fn past_tense(name: &str) -> String {
    let segs: Vec<&str> = name.split('/').collect();
    if segs.len() > 1 {
        let mut out = vec![past_tense(segs[0])];
        out.extend(segs[1..].iter().map(|s| s.to_string()));
        return out.join("/");
    }
    let words: Vec<&str> = name.split('_').collect();
    let mut out: Vec<String> = words.iter().map(|w| w.to_string()).collect();
    if let Some(last) = words.last() {
        // `stumbled_into` and `thrown_hit` already read as past tense.
        if words.len() > 1 && (words[words.len() - 1] == "into" || words[words.len() - 1] == "hit")
        {
            return name.to_string();
        }
        let n = out.len();
        out[n - 1] = past_word(last);
    }
    out.join("_")
}

fn field_name(field: &str) -> String {
    field.rsplit('/').next().unwrap_or(field).trim().to_string()
}

/// The declared name of a field as written, with `origin` renamed.
fn dm_field(field: &str) -> (String, String) {
    let f = field.trim();
    let name = field_name(f);
    let ty = if f.contains('/') {
        f[..f.len() - name.len() - 1].to_string()
    } else {
        String::new()
    };
    let dm_name = if name == "origin" {
        "origin_turf".to_string()
    } else {
        name
    };
    (ty, dm_name)
}

struct Input<'a> {
    rel: &'a str,
    line: u32,
    args: &'a [String],
}
#[derive(Default)]
pub struct Builder {
    acts: BTreeMap<String, Action>,
    out: Output,
    budget: Option<Arc<Budget>>,
    markers: usize,
}
pub struct Prepared {
    acts: BTreeMap<String, Action>,
    out: Output,
    budget: Option<Arc<Budget>>,
}
fn admit(budget: Option<&Budget>, bytes: Option<usize>) -> Result<(), String> {
    if let Some(b) = budget {
        let Some(bytes) = bytes else {
            b.deny();
            return Err("action allocation accounting overflow".into());
        };
        b.charge(bytes)?;
    }
    Ok(())
}
fn clone_fields(
    fields: &[(String, String)],
    budget: Option<&Budget>,
) -> Result<Vec<(String, String)>, String> {
    let bytes = fields.iter().try_fold(0usize, |n, (t, v)| {
        n.checked_add(t.len())?.checked_add(v.len())
    });
    admit(
        budget,
        bytes
            .and_then(|n| n.checked_mul(2))
            .and_then(|n| {
                n.checked_add(
                    fields
                        .len()
                        .checked_mul(3 * std::mem::size_of::<(String, String)>())?,
                )
            })
            .and_then(|n| n.checked_add(256)),
    )?;
    Ok(fields.to_vec())
}
impl Builder {
    pub fn captured(budget: Arc<Budget>) -> Self {
        Self {
            out: Output::captured(budget.clone()),
            budget: Some(budget),
            ..Default::default()
        }
    }
    pub fn push(&mut self, rel: &str, line: u32, args: &[String]) -> Result<(), String> {
        self.markers = self
            .markers
            .checked_add(1)
            .ok_or("action marker overflow")?;
        if let Some(b) = &self.budget {
            if self.markers > crate::captured_generator_budget::MAX_ROWS {
                b.deny();
                return b.require();
            }
        }
        // Preflight ORIGINAL field/name/past-tense parsing temporaries: split
        // fat-pointer/owned segment vectors, path Strings, BTree query schema,
        // and original field Vec growth, before invoking those same helpers.
        let width = args.iter().try_fold(0usize, |n, a| n.checked_add(a.len()));
        admit(
            self.budget.as_deref(),
            width
                .and_then(|n| n.checked_mul(128))
                .and_then(|n| n.checked_add(args.len().checked_mul(512)?))
                .and_then(|n| n.checked_add(rel.len().checked_mul(4)?))
                .and_then(|n| n.checked_add(2048)),
        )?;
        let acts = &mut self.acts;
        let out = &mut self.out;
        for m in std::iter::once(Input { rel, line, args }) {
            let Some(name) = m.args.first().cloned() else {
                out.diag(m.rel, m.line, "ACTION(name, fields...) needs a name");
                continue;
            };
            let mut fields = Vec::new();
            let mut malformed = false;
            let mut fixed = false;
            let mut query = false;
            let mut notice = None;
            for a in &m.args[1..] {
                if a == "QUERY" {
                    query = true;
                } else if a == "FIXED" {
                    fixed = true;
                } else if let Some(n) = split_notice_opt(a) {
                    notice = Some(n);
                } else if a.chars().next().map(|c| c.is_alphabetic()).unwrap_or(false) {
                    let (ty, nm) = dm_field(a);
                    if RESERVED.contains(&nm.as_str()) && name != "op" {
                        out.diag(m.rel, m.line, format_args!("action `{}`: field `{}` is a field every act carries; pick another name", name, nm));
                        malformed = true;
                        continue;
                    }
                    fields.push((ty, nm));
                } else {
                    out.diag(
                        m.rel,
                        m.line,
                        format_args!(
                            "action `{}`: `{}` is neither a typed field, FIXED nor notice =",
                            name, a
                        ),
                    );
                    malformed = true;
                }
            }
            if query && malformed {
                continue;
            }
            if query {
                let allowed = [
                    ("mob", "wearer"),
                    ("mob", "mover"),
                    ("datum", "destination"),
                    ("", "slot_id"),
                    ("", "requirement_channel"),
                    ("list", "query_options"),
                ];
                if fields
                    .iter()
                    .map(|(_, name)| name)
                    .collect::<BTreeSet<_>>()
                    .len()
                    != fields.len()
                    || fields
                        .iter()
                        .any(|(ty, name)| !allowed.iter().any(|(t, n)| ty == t && name == n))
                {
                    out.diag(
                        m.rel,
                        m.line,
                        "QUERY fields must match the typed synchronous op admission schema",
                    );
                    continue;
                }
            }
            if query && (fixed || notice.is_some() || name.contains('/')) {
                out.diag(
                    m.rel,
                    m.line,
                    "QUERY cannot be FIXED, declare a notice, or inherit an action",
                );
                continue;
            }
            let parent = name.rfind('/').map(|i| name[..i].to_string());
            let notice = notice.unwrap_or_else(|| format!("/datum/notice/{}", past_tense(&name)));
            if acts.contains_key(&name) {
                out.diag(
                    m.rel,
                    m.line,
                    format_args!(
                        "action `{}` is declared twice (also {}:{})",
                        name, acts[&name].rel, acts[&name].line
                    ),
                );
                continue;
            }
            if fixed && name.contains('/') {
                out.diag(
                    m.rel,
                    m.line,
                    format_args!("action `{}`: a FIXED action has no subtypes", name),
                );
            }
            acts.insert(
                name.clone(),
                Action {
                    name,
                    fields,
                    fixed,
                    query,
                    notice,
                    parent,
                    rel: m.rel.to_owned(),
                    line: m.line,
                },
            );
        }
        if let Some(b) = &self.budget {
            b.require()?;
        }
        Ok(())
    }
    pub fn prepare(
        mut self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Prepared, String> {
        checkpoint()?;
        let names_bytes = self
            .acts
            .keys()
            .try_fold(0usize, |n, k| n.checked_add(k.len()));
        admit(
            self.budget.as_deref(),
            names_bytes
                .and_then(|n| n.checked_mul(2))
                .and_then(|n| {
                    n.checked_add(
                        self.acts
                            .len()
                            .checked_mul(3 * std::mem::size_of::<String>())?,
                    )
                })
                .and_then(|n| n.checked_add(256)),
        )?;
        let names: Vec<String> = self.acts.keys().cloned().collect();
        // This preserves the original sorted, progressively expanded parent
        // policy (including repeated deep ancestors). It does not replace it
        // with an equivalent-looking fresh DFS that changes generated bytes.
        for n in &names {
            checkpoint()?;
            let mut chain = Vec::new();
            admit(
                self.budget.as_deref(),
                Some(n.len().saturating_mul(2).saturating_add(64)),
            )?;
            let mut cur = self.acts[n].parent.clone();
            while let Some(p) = cur {
                checkpoint()?;
                match self.acts.get(&p) {
                    Some(pa) => {
                        if let Some(b) = &self.budget {
                            if !b.row(&mut chain) {
                                return Err("captured action allocation denied".into());
                            }
                        }
                        chain.push(clone_fields(&pa.fields, self.budget.as_deref())?);
                        admit(
                            self.budget.as_deref(),
                            Some(
                                pa.parent
                                    .as_ref()
                                    .map_or(0, |p| p.len())
                                    .saturating_mul(2)
                                    .saturating_add(64),
                            ),
                        )?;
                        cur = pa.parent.clone();
                    }
                    None => {
                        let a = &self.acts[n];
                        self.out.diag_fmt(
                            &a.rel,
                            a.line,
                            format_args!(
                                "action `{}`: its parent action `{}` is not declared",
                                a.name, p
                            ),
                        );
                        break;
                    }
                }
            }
            let mut all: Vec<(String, String)> = Vec::new();
            for fields in chain.into_iter().rev() {
                for field in fields {
                    if let Some(b) = &self.budget {
                        if !b.row(&mut all) {
                            return Err("captured action allocation denied".into());
                        }
                    }
                    all.push(field);
                }
            }
            for field in clone_fields(&self.acts[n].fields, self.budget.as_deref())? {
                if let Some(b) = &self.budget {
                    if !b.row(&mut all) {
                        return Err("captured action allocation denied".into());
                    }
                }
                all.push(field);
            }
            self.acts.get_mut(n).unwrap().fields = all;
        }
        checkpoint()?;
        if let Some(b) = &self.budget {
            b.require()?;
        }
        Ok(Prepared {
            acts: self.acts,
            out: self.out,
            budget: self.budget,
        })
    }
}
impl Prepared {
    pub fn notices(&self) -> impl Iterator<Item = &str> {
        self.acts
            .values()
            .filter(|a| !a.query)
            .map(|a| a.notice.as_str())
    }
    pub fn requests(&self) -> impl Iterator<Item = (&str, &str)> {
        self.acts.values().filter(|a| !a.query).flat_map(|a| {
            let parent_n = a
                .parent
                .as_ref()
                .and_then(|p| self.acts.get(p))
                .map(|p| p.fields.len())
                .unwrap_or(0);
            a.fields
                .iter()
                .skip(parent_n)
                .map(move |(_, name)| (a.notice.as_str(), name.as_str()))
        })
    }
    pub fn finish(
        mut self,
        mut membership: impl FnMut(&str, &str) -> bool,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Output, String> {
        emit(
            &mut self.out,
            &self.acts,
            false,
            "action_notice_types",
            &mut membership,
            &mut checkpoint,
            self.budget.as_deref(),
        )?;
        if self
            .acts
            .values()
            .any(|a| crate::generator_test_scope::test_only(&a.rel))
        {
            self.out.line(crate::generator_test_scope::TEST_GUARD);
            self.out.blank();
            emit(
                &mut self.out,
                &self.acts,
                true,
                "action_notice_types_tests",
                &mut membership,
                &mut checkpoint,
                self.budget.as_deref(),
            )?;
            self.out.line("#endif");
        }
        checkpoint()?;
        if let Some(b) = &self.budget {
            b.require()?;
        }
        Ok(self.out)
    }
}
fn owned(ty: &str) -> &'static str {
    if ty.is_empty() {
        ""
    } else {
        " // ALLOW(ownership): a pooled act or notice holds its entities for one trigger and is reset on release"
    }
}
struct ActPath<'a>(&'a str);
impl std::fmt::Display for ActPath<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "/datum/act/{}", self.0)
    }
}
struct ProcName<'a>(&'a str);
impl std::fmt::Display for ProcName<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        use std::fmt::Write;
        for c in self.0.chars() {
            f.write_char(if c == '/' { '_' } else { c })?;
        }
        Ok(())
    }
}
struct Field<'a> {
    ty: &'a str,
    name: &'a str,
}
impl std::fmt::Display for Field<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if !self.ty.is_empty() {
            write!(f, "{}/", self.ty)?;
        }
        f.write_str(self.name)
    }
}
struct Params<'a>(&'a Action);
impl std::fmt::Display for Params<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("datum/holder")?;
        for (t, n) in &self.0.fields {
            write!(f, ", {}", Field { ty: t, name: n })?;
        }
        Ok(())
    }
}
struct QueryParams<'a>(&'a Action);
impl std::fmt::Display for QueryParams<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("datum/holder, atom/movable/target, mob/actor")?;
        for (t, n) in &self.0.fields {
            write!(f, ", {}", Field { ty: t, name: n })?;
        }
        write!(f, ", query_type = {}", ActPath(&self.0.name))
    }
}
fn var_line(out: &mut Output, ty: &str, name: &str) {
    out.line_fmt(format_args!("\tvar/{}", Field { ty, name }));
}

fn emit(
    out: &mut Output,
    all: &BTreeMap<String, Action>,
    test_only: bool,
    registry_name: &str,
    membership: &mut impl FnMut(&str, &str) -> bool,
    checkpoint: &mut impl FnMut() -> Result<(), String>,
    budget: Option<&Budget>,
) -> Result<(), String> {
    let selected = || {
        all.values()
            .filter(|a| crate::generator_test_scope::test_only(&a.rel) == test_only)
    };
    let registry = selected()
        .filter(|a| !a.query && !a.fixed && a.name != "op")
        .count();
    if registry > 0 {
        out.line_fmt(format_args!("GLOBAL_LIST_INIT({}, list(", registry_name));
        for (i, a) in selected()
            .filter(|a| !a.query && !a.fixed && a.name != "op")
            .enumerate()
        {
            checkpoint()?;
            out.line_fmt(format_args!(
                "\t{} = {}{}",
                ActPath(&a.name),
                a.notice,
                if i + 1 == registry { "" } else { "," }
            ));
        }
        out.line("))");
        out.blank();
    }
    for a in selected() {
        checkpoint()?;
        if let Some(b) = budget {
            b.require()?;
        }
        out.doc_fmt(format_args!("ACTION({}) at {}:{}", a.name, a.rel, a.line));
        let parent_n = a
            .parent
            .as_ref()
            .and_then(|p| all.get(p))
            .map(|p| p.fields.len())
            .unwrap_or(0);
        let own_fields = || a.fields.iter().skip(parent_n);
        let is_op = a.name == "op";
        if !a.fixed && !is_op {
            out.line_fmt(format_args!("{}", ActPath(&a.name)));
            if a.parent.is_none() {
                out.line(if a.query {
                    "\tparent_type = /datum/act/op"
                } else {
                    "\tparent_type = /datum/act/action"
                });
            }
            for (ty, name) in own_fields() {
                checkpoint()?;
                if !a.query {
                    var_line(out, ty, name);
                }
            }
        }
        if a.query {
            emit_query(out, a, checkpoint, budget)?;
            continue;
        }
        out.line(&a.notice);
        for (ty, name) in own_fields() {
            checkpoint()?;
            if !membership(&a.notice, name) {
                var_line(out, ty, name);
            }
        }
        if !a.fixed && !is_op {
            out.blank();
            out.line_fmt(format_args!("{}/make_notice()", ActPath(&a.name)));
            out.line_fmt(format_args!("\tRETURN_TYPE({})", a.notice));
            out.line_fmt(format_args!(
                "\tvar/{}/N = notice_take({})",
                a.notice.trim_start_matches('/'),
                a.notice
            ));
            for (ty, name) in &a.fields {
                checkpoint()?;
                out.line_fmt(format_args!("\tN.{} = {}{}", name, name, owned(ty)));
            }
            out.line("\treturn N");
            out.blank();
            out.line_fmt(format_args!(
                "/proc/act_{}({}, act_answer = FALSE)",
                ProcName(&a.name),
                Params(a)
            ));
            out.line_fmt(format_args!("\tRETURN_TYPE({})", ActPath(&a.name)));
            out.line_fmt(format_args!(
                "\tif(!act_wanted(holder, {}))",
                ActPath(&a.name)
            ));
            out.line("\t\treturn ACT_PASS");
            out.line_fmt(format_args!(
                "\tvar/datum/act/{}/A = act_begin({}, holder)",
                a.name,
                ActPath(&a.name)
            ));
            out.line("\tif(!A)");
            out.line("\t\treturn act_answer ? act_refusal_of(ACT_REFUSED, /datum/msg/act/too_deeply_nested) : null");
            for (ty, name) in &a.fields {
                checkpoint()?;
                out.line_fmt(format_args!("\tA.{} = {}{}", name, name, owned(ty)));
            }
            out.line("\treturn act_resolve(A, act_answer)");
        } else if a.fixed {
            out.blank();
            out.line_fmt(format_args!(
                "/proc/publish_{}({})",
                ProcName(&a.name),
                Params(a)
            ));
            out.line_fmt(format_args!(
                "\tif(!notice_wanted(holder, {}, ACT_COMMITTED))",
                a.notice
            ));
            out.line("\t\treturn");
            out.line_fmt(format_args!(
                "\tvar/{}/N = notice_take({})",
                a.notice.trim_start_matches('/'),
                a.notice
            ));
            for (ty, name) in &a.fields {
                checkpoint()?;
                out.line_fmt(format_args!("\tN.{} = {}{}", name, name, owned(ty)));
            }
            out.line("\tnotice_publish(holder, N, ACT_COMMITTED)");
        }
        out.blank();
    }
    if let Some(b) = budget {
        b.require()?;
    }
    Ok(())
}
fn emit_query(
    out: &mut Output,
    a: &Action,
    checkpoint: &mut impl FnMut() -> Result<(), String>,
    budget: Option<&Budget>,
) -> Result<(), String> {
    out.line_fmt(format_args!(
        "/proc/query_{}({})",
        ProcName(&a.name),
        QueryParams(a)
    ));
    out.line_fmt(format_args!("\tRETURN_TYPE({})", ActPath(&a.name)));
    out.line_fmt(format_args!(
        "\tif(!ispath(query_type, {}))",
        ActPath(&a.name)
    ));
    out.line("\t\tCRASH(\"query binder needs its declared pooled act type\")");
    out.line("\tif(!holder || !istype(holder, /datum))");
    out.line("\t\tCRASH(\"query needs a declaration holder\")");
    for (ty, name) in [("atom/movable", "target"), ("mob", "actor")]
        .into_iter()
        .chain(
            a.fields
                .iter()
                .filter(|(ty, _)| !ty.is_empty() && ty != "list")
                .map(|(t, n)| (t.as_str(), n.as_str())),
        )
    {
        checkpoint()?;
        out.line_fmt(format_args!(
            "\tif(!isnull({}) && !istype({}, /{}))",
            name, name, ty
        ));
        out.line("\t\tCRASH(\"query input does not match its declared entity type\")");
    }
    for (ty, name) in &a.fields {
        checkpoint()?;
        if ty == "list" {
            out.line_fmt(format_args!(
                "\tvar/list/copied_{} = op_query_input_copy({})",
                name, name
            ));
        }
    }
    for name in ["holder", "target", "actor"].into_iter().chain(
        a.fields
            .iter()
            .filter(|(t, _)| !t.is_empty() && t != "list")
            .map(|(_, n)| n.as_str()),
    ) {
        checkpoint()?;
        out.line_fmt(format_args!(
            "\tif(istype({}, /datum/pooled) || (isdatum({}) && QDELETED({})))",
            name, name, name
        ));
        out.line("\t\tCRASH(\"query inputs must be live world entities, not transient contexts\")");
    }
    out.line_fmt(format_args!(
        "\tvar/datum/act/{}/A = act_context(query_type, holder, target, actor)",
        a.name
    ));
    out.line("\tA.target_atom = target");
    for (ty, name) in &a.fields {
        checkpoint()?;
        out.line_fmt(format_args!(
            "\tA.{} = {}{}",
            name,
            if ty == "list" { "copied_" } else { "" },
            name
        ));
    }
    out.line("\treturn A");
    out.blank();
    if let Some(b) = budget {
        b.require()?;
    }
    Ok(())
}
/// Same old notice-mention selection, including prefix false positives and the
/// nonplain fallback. This returns a bool; no new source parser/table is built.
pub fn notice_suffix(notice: &str) -> Option<&str> {
    notice.strip_prefix("/datum/notice/").filter(|s| {
        s.chars()
            .all(|c| c.is_alphanumeric() || c == '_' || c == '/')
    })
}
pub fn visit_notice_mentions(code: &str, mut visit: impl FnMut(&str)) {
    const PREFIX: &str = "/datum/notice/";
    let mut from = 0;
    while let Some(i) = code[from..].find(PREFIX) {
        let start = from + i + PREFIX.len();
        let width = code[start..]
            .chars()
            .take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '/')
            .map(char::len_utf8)
            .sum::<usize>();
        visit(&code[start..start + width]);
        from = start;
    }
}
pub fn file_mentions_notice(code: &str, notice: &str) -> bool {
    match notice_suffix(notice) {
        Some(rest) => {
            let mut found = false;
            visit_notice_mentions(code, |run| found |= run.starts_with(rest));
            found
        }
        None => code.contains(notice),
    }
}
