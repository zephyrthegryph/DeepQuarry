//! `analyze gen actions` -> `code/engine/_generated/actions.dm` (E4, actions and hooks).
//!
//! `ACTION(name, typed fields..., FIXED, notice = /datum/notice/x)` expands to nothing in DM (code/__defines/engine/markers.dm). This reads each
//! one from source and writes what DM cannot (doc/rewrite/final_api.html section 8, "World actions"):
//!
//! * the act type `/datum/act/<name>` (parent `/datum/act/action`, or the parent action for a `hit/projectile` style name) with the typed fields,
//!   and `act_<name>(holder, fields...)`, which the `ACT_TRY(E, name, fields...)` macro calls: ACT_PASS when nothing hooks the action and nothing
//!   listens for its notice, null when it was refused or taken over, else the pooled act;
//! * the past-tense notice `/datum/notice/<past>` with the same fields, and `make_notice()` on the act, which copies the act's final fields into it;
//! * for a FIXED action (nothing can refuse it) no act type: `publish_<name>(holder, fields...)`, which `PUBLISH(E, name, field = v)` calls.
//!
//! The notice name is the action's name in the past tense (fall -> fell, insert -> inserted); a name that already reads as past tense (hit,
//! stumbled_into, round_started) is kept, and `notice =` overrides. A name with a slash inherits its parent's fields and its proc and ACT_TRY token
//! use an underscore. The `op` action's act type is the op context (code/contracts/acts/context.dm), so only its notice is generated.
//! A field named `origin` is declared `origin_turf` (every act has an ORIGIN_* `origin`); any other reserved name is a diagnostic.
//! Declarations in files under `code/tests/` go in an `#if defined(UNIT_TESTS)` block.

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::gen::{GenCx, GenOut, Generator};

/// Vars every act carries: a typed field of this name is an error, except `origin`, which the design names for a move's turfs and which is the
/// ORIGIN_* of the act, so it is declared `origin_turf`.
const RESERVED: &[&str] = &["holder", "cap", "activation", "source", "target", "actor", "origin", "provider", "authority", "rolled", "outcome", "reason", "args", "key", "held", "reply"];

struct Action {
    name: String,
    /// (declared type text, name) in order, the parent's first.
    fields: Vec<(String, String)>,
    fixed: bool,
    notice: String,
    parent: Option<String>,
    rel: String,
    line: u32,
}

fn split_notice_opt(arg: &str) -> Option<String> {
    let rest = arg.trim().strip_prefix("notice")?.trim_start().strip_prefix('=')?;
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
fn past_tense(name: &str) -> String {
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
        if words.len() > 1 && (words[words.len() - 1] == "into" || words[words.len() - 1] == "hit") {
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
    let ty = if f.contains('/') { f[..f.len() - name.len() - 1].to_string() } else { String::new() };
    let dm_name = if name == "origin" { "origin_turf".to_string() } else { name };
    (ty, dm_name)
}

fn var_line(ty: &str, name: &str) -> String {
    if ty.is_empty() {
        format!("\tvar/{}", name)
    } else {
        format!("\tvar/{}/{}", ty, name)
    }
}

fn param(ty: &str, name: &str) -> String {
    if ty.is_empty() {
        name.to_string()
    } else {
        format!("{}/{}", ty, name)
    }
}

struct Actions;

impl Generator for Actions {
    fn name(&self) -> &'static str {
        "actions"
    }

    fn output(&self) -> &'static str {
        "actions.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let mut acts: BTreeMap<String, Action> = BTreeMap::new();
        for m in cx.markers("ACTION") {
            let Some(name) = m.args.first().cloned() else {
                out.diag(&m.rel, m.line, "ACTION(name, fields...) needs a name");
                continue;
            };
            let mut fields = Vec::new();
            let mut fixed = false;
            let mut notice = None;
            for a in &m.args[1..] {
                if a == "FIXED" {
                    fixed = true;
                } else if let Some(n) = split_notice_opt(a) {
                    notice = Some(n);
                } else if a.chars().next().map(|c| c.is_alphabetic()).unwrap_or(false) {
                    let (ty, nm) = dm_field(a);
                    if RESERVED.contains(&nm.as_str()) && name != "op" {
                        out.diag(&m.rel, m.line, format!("action `{}`: field `{}` is a field every act carries; pick another name", name, nm));
                        continue;
                    }
                    fields.push((ty, nm));
                } else {
                    out.diag(&m.rel, m.line, format!("action `{}`: `{}` is neither a typed field, FIXED nor notice =", name, a));
                }
            }
            let parent = name.rfind('/').map(|i| name[..i].to_string());
            let notice = notice.unwrap_or_else(|| format!("/datum/notice/{}", past_tense(&name)));
            if acts.contains_key(&name) {
                out.diag(&m.rel, m.line, format!("action `{}` is declared twice (also {}:{})", name, acts[&name].rel, acts[&name].line));
                continue;
            }
            if fixed && name.contains('/') {
                out.diag(&m.rel, m.line, format!("action `{}`: a FIXED action has no subtypes", name));
            }
            acts.insert(name.clone(), Action { name, fields, fixed, notice, parent, rel: m.rel.clone(), line: m.line });
        }
        // A subtype inherits its parent's fields.
        let names: Vec<String> = acts.keys().cloned().collect();
        for n in &names {
            let mut chain = Vec::new();
            let mut cur = acts[n].parent.clone();
            while let Some(p) = cur {
                match acts.get(&p) {
                    Some(pa) => {
                        chain.push(pa.fields.clone());
                        cur = pa.parent.clone();
                    }
                    None => {
                        let a = &acts[n];
                        out.diag(&a.rel, a.line, format!("action `{}`: its parent action `{}` is not declared", a.name, p));
                        break;
                    }
                }
            }
            let mut all: Vec<(String, String)> = Vec::new();
            for f in chain.into_iter().rev() {
                all.extend(f);
            }
            all.extend(acts[n].fields.clone());
            acts.get_mut(n).unwrap().fields = all;
        }
        let (tests, content): (Vec<&Action>, Vec<&Action>) = acts.values().partition(|a| crate::sem::gen::test_only(&a.rel));
        emit(cx, out, &content, &acts, "action_notice_types");
        if !tests.is_empty() {
            out.line(crate::sem::gen::TEST_GUARD);
            out.blank();
            emit(cx, out, &tests, &acts, "action_notice_types_tests");
            out.line("#endif");
        }
    }
}

/// The ownership annotation of an assignment of a typed (entity) field into a pooled act or notice, which holds it for one trigger.
fn owned(ty: &str) -> &'static str {
    if ty.is_empty() {
        ""
    } else {
        " // ALLOW(ownership): a pooled act or notice holds its entities for one trigger and is reset on release"
    }
}

fn path_of(name: &str) -> String {
    format!("/datum/act/{}", name)
}

fn proc_name(name: &str) -> String {
    name.replace('/', "_")
}

fn emit(cx: &GenCx, out: &mut GenOut, list: &[&Action], all: &BTreeMap<String, Action>, registry_name: &str) {
    // The act -> notice registry.
    let mut registry: Vec<(String, String)> = Vec::new();
    for a in list {
        if !a.fixed && a.name != "op" {
            registry.push((path_of(&a.name), a.notice.clone()));
        }
    }
    if !registry.is_empty() {
        out.line(format!("GLOBAL_LIST_INIT({}, list(", registry_name));
        for (i, (act, notice)) in registry.iter().enumerate() {
            out.line(format!("	{} = {}{}", act, notice, if i + 1 == registry.len() { "" } else { "," }));
        }
        out.line("))");
        out.blank();
    }
    for a in list {
        out.doc(format!("ACTION({}) at {}:{}", a.name, a.rel, a.line));
        let parent_n = a.parent.as_ref().and_then(|p| all.get(p)).map(|pa| pa.fields.len()).unwrap_or(0);
        let own_fields: Vec<&(String, String)> = a.fields.iter().skip(parent_n).collect();
        let is_op = a.name == "op";
        if !a.fixed && !is_op {
            out.line(path_of(&a.name));
            if a.parent.is_none() {
                out.line("	parent_type = /datum/act/action");
            }
            for (ty, nm) in &own_fields {
                out.line(var_line(ty, nm));
            }
        }
        // The notice carries the same fields (a var the tree already declares on that type is not declared twice).
        let elsewhere = declared_elsewhere(cx, &a.notice);
        out.line(a.notice.clone());
        for (ty, nm) in &own_fields {
            if !elsewhere.contains(nm) {
                out.line(var_line(ty, nm));
            }
        }
        let params: Vec<String> = std::iter::once("datum/holder".to_string()).chain(a.fields.iter().map(|(t, n)| param(t, n))).collect();
        if !a.fixed && !is_op {
            out.blank();
            out.line(format!("{}/make_notice()", path_of(&a.name)));
            out.line(format!("	RETURN_TYPE({})", a.notice));
            out.line(format!("	var/{}/N = notice_take({})", a.notice.trim_start_matches('/'), a.notice));
            for (ty, nm) in &a.fields {
                out.line(format!("	N.{} = {}{}", nm, nm, owned(ty)));
            }
            out.line("	return N");
            out.blank();
            out.line(format!("/proc/act_{}({})", proc_name(&a.name), params.join(", ")));
            out.line(format!("	RETURN_TYPE({})", path_of(&a.name)));
            out.line(format!("	if(!act_wanted(holder, {}))", path_of(&a.name)));
            out.line("		return ACT_PASS");
            out.line(format!("	var/{}/A = act_begin({}, holder)", path_of(&a.name).trim_start_matches('/'), path_of(&a.name)));
            out.line("	if(!A)");
            out.line("		return null");
            for (ty, nm) in &a.fields {
                out.line(format!("	A.{} = {}{}", nm, nm, owned(ty)));
            }
            out.line("	return act_resolve(A)");
        } else if a.fixed {
            out.blank();
            out.line(format!("/proc/publish_{}({})", proc_name(&a.name), params.join(", ")));
            out.line(format!("	if(!notice_wanted(holder, {}, ACT_COMMITTED))", a.notice));
            out.line("		return");
            out.line(format!("	var/{}/N = notice_take({})", a.notice.trim_start_matches('/'), a.notice));
            for (ty, nm) in &a.fields {
                out.line(format!("	N.{} = {}{}", nm, nm, owned(ty)));
            }
            out.line("	notice_publish(holder, N, ACT_COMMITTED)");
        }
        out.blank();
    }
}

/// The vars a notice type already has from a declaration outside the generated file.
fn declared_elsewhere(cx: &GenCx, notice: &str) -> BTreeSet<String> {
    const PREFIX: &str = "/datum/notice/";
    // Which files mention a notice type: per-file facts (the runs of name characters after each `/datum/notice/`), read once per
    // content change. `contains(notice)` on the comment-stripped text is true exactly when some run starts with the notice's name.
    let mentions: std::sync::Arc<Vec<(String, Vec<String>)>> = cx.tree.memo("gen/notice_mentions", || {
        let all = cx.tree.select(&crate::tree::CODE_DM);
        let facts: Vec<Vec<String>> = crate::incr::facts("notice-mentions", &all, |f| {
            let text = &f.code().text;
            let mut out: Vec<String> = Vec::new();
            let mut from = 0;
            while let Some(i) = text[from..].find(PREFIX) {
                let start = from + i + PREFIX.len();
                let run: String = text[start..].chars().take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '/').collect();
                out.push(run);
                from = start;
            }
            out.sort();
            out.dedup();
            out
        });
        all.iter().zip(facts).map(|(f, m)| (f.rel.clone(), m)).collect()
    });
    let name_chars = |s: &str| s.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '/');
    let files: Vec<&crate::tree::SourceFile> = match notice.strip_prefix(PREFIX) {
        Some(rest) if name_chars(rest) => mentions.iter().filter(|(rel, m)| rel != "code/engine/_generated/actions.dm" && m.iter().any(|run| run.starts_with(rest))).filter_map(|(rel, _)| cx.tree.get(rel)).collect(),
        _ => cx.tree.select(&crate::tree::CODE_DM).into_iter().filter(|f| f.rel != "code/engine/_generated/actions.dm" && f.code().text.contains(notice)).collect(),
    };
    let table = crate::dm::dx::type_vars(&files);
    table.get(notice).map(|v| v.iter().cloned().collect()).unwrap_or_default()
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Actions));
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::sem::gen::render;
    use crate::tree::{SourceFile, Tree};
    use std::path::Path;

    fn gen(src: &str) -> (String, Vec<String>) {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", src)]);
        let cx = GenCx::new(&tree, Path::new("."));
        let (text, diags) = render(&Actions, &cx);
        (text, diags.into_iter().map(|d| d.msg).collect())
    }

    const SRC: &str = "ACTION(fall, turf/landing, mob/living/landed_on)
ACTION(move, turf/origin, turf/destination)
ACTION(hit, datum/damage_packet/packet)
ACTION(hit/projectile)
ACTION(slash, mob/living/slasher, FIXED)
ACTION(body_status, notice = /datum/notice/body_status_changed)
";

    #[test]
    fn an_action_gets_a_type_a_proc_and_a_notice() {
        let (text, diags) = gen(SRC);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(text.contains("/datum/act/fall
	parent_type = /datum/act/action
	var/turf/landing
	var/mob/living/landed_on"), "{}", text);
        assert!(text.contains("/datum/notice/fell
	var/turf/landing"), "the notice is the past tense: {}", text);
        assert!(text.contains("/proc/act_fall(datum/holder, turf/landing, mob/living/landed_on)"), "{}", text);
        assert!(text.contains("	return act_resolve(A)"), "{}", text);
        assert!(text.contains("/datum/act/move
	parent_type = /datum/act/action
	var/turf/origin_turf"), "origin is the act's ORIGIN_*: {}", text);
    }

    #[test]
    fn a_slash_name_inherits_and_a_fixed_action_has_no_act() {
        let (text, _) = gen(SRC);
        assert!(text.contains("/proc/act_hit_projectile(datum/holder, datum/damage_packet/packet)"), "{}", text);
        assert!(text.contains("/datum/notice/hit/projectile"), "{}", text);
        assert!(!text.contains("/datum/act/slash"), "a FIXED action has no act type: {}", text);
        assert!(text.contains("/proc/publish_slash(datum/holder, mob/living/slasher)"), "{}", text);
        assert!(text.contains("/datum/notice/slashed"), "{}", text);
        assert!(text.contains("/datum/notice/body_status_changed"), "notice = overrides the name: {}", text);
    }

    #[test]
    fn a_reserved_field_and_an_orphan_subtype_are_reported() {
        let (_, diags) = gen("ACTION(poke, mob/actor)
ACTION(nowhere/child)
ACTION(poke, atom/x)
");
        assert!(diags.iter().any(|d| d.contains("every act carries")), "{:?}", diags);
        assert!(diags.iter().any(|d| d.contains("parent action `nowhere`")), "{:?}", diags);
        assert!(diags.iter().any(|d| d.contains("declared twice")), "{:?}", diags);
    }

    #[test]
    fn past_tense_rules() {
        assert_eq!(past_tense("fall"), "fell");
        assert_eq!(past_tense("move"), "moved");
        assert_eq!(past_tense("z_change"), "z_changed");
        assert_eq!(past_tense("insert"), "inserted");
        assert_eq!(past_tense("stumbled_into"), "stumbled_into");
        assert_eq!(past_tense("thrown_hit"), "thrown_hit");
        assert_eq!(past_tense("hit/projectile"), "hit/projectile");
        assert_eq!(past_tense("round_started"), "round_started");
        assert_eq!(past_tense("speak"), "spoke");
        assert_eq!(past_tense("equip"), "equipped");
        assert_eq!(past_tense("unequip"), "unequipped");
    }
}
