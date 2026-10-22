//! Proven-equivalent rewrites of rendered code lines, applied to both sides before `compare_code` reports a
//! difference. Each rule removes an encoding difference whose runtime effect is identical (see EQUIVALENCE.md,
//! "Encoding rules"). Lines are the non-debug canonical instructions; branch targets are `L<n>` ordinals.

/// Positions and values of the `L<n>` branch targets in a line, ignoring quoted text.
fn label_spans(line: &str) -> Vec<(usize, usize, usize)> {
    let b = line.as_bytes();
    let mut out = Vec::new();
    let (mut i, mut quoted) = (0, false);
    while i < b.len() {
        let c = b[i];
        if quoted {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                quoted = false;
            }
        } else if c == b'"' {
            quoted = true;
        } else if c == b'L'
            && i + 1 < b.len()
            && b[i + 1].is_ascii_digit()
            && (i == 0 || !(b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'_'))
        {
            let mut j = i + 1;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            if let Ok(n) = line[i + 1..j].parse::<usize>() {
                out.push((i, j, n));
            }
            i = j;
            continue;
        }
        i += 1;
    }
    out
}

fn targets(line: &str) -> Vec<usize> {
    label_spans(line).into_iter().map(|s| s.2).collect()
}

fn op(line: &str) -> &str {
    line.split(' ').next().unwrap_or("")
}

fn string_const(line: &str) -> Option<String> {
    let r = line.strip_prefix("PushVal \"")?;
    r.strip_suffix('"').map(str::to_string)
}

/// Whether a line mentions the local `k` (a whole name, `local1` is not `local12`).
fn is_local(line: &str, k: &str) -> bool {
    let mut from = 0;
    while let Some(p) = line[from..].find(k) {
        let s = from + p;
        let e = s + k.len();
        let before = s == 0 || !line.as_bytes()[s - 1].is_ascii_alphanumeric();
        let after = e >= line.len() || !line.as_bytes()[e].is_ascii_digit();
        if before && after {
            return true;
        }
        from = e;
    }
    false
}

/// Remove the lines flagged in `drop`, renumbering every branch target.
fn remove(lines: &[String], drop: &[bool]) -> Vec<String> {
    let mut kept_before = vec![0usize; lines.len() + 1];
    for i in 0..lines.len() {
        kept_before[i + 1] = kept_before[i] + usize::from(!drop[i]);
    }
    let mut out = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        if drop[i] {
            continue;
        }
        let mut text = String::new();
        let mut last = 0;
        for (s, e, n) in label_spans(line) {
            text.push_str(&line[last..s]);
            text.push('L');
            text.push_str(&kept_before[n.min(lines.len())].to_string());
            last = e;
        }
        text.push_str(&line[last..]);
        out.push(text);
    }
    out
}

/// `PushVal "A"; PushVal "B"; E...; Add` (E a run of pushes, reads, `Format` and `Add`, with B consumed only as
/// the left operand of an `Add`) is `A + (B + ...)` over strings, equal to `(A+B) + ...`: DreamMaker keeps the
/// right-nested form, native folds the adjacent literals.
fn merge_literals(lines: Vec<String>) -> Vec<String> {
    let mut lines = lines;
    loop {
        let mut changed = false;
        let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
        'scan: for i in 0..lines.len().saturating_sub(1) {
            let (Some(a), Some(b)) = (string_const(&lines[i]), string_const(&lines[i + 1])) else {
                continue;
            };
            let mut depth = 1usize;
            let mut j = i + 2;
            // Open conditional expressions: (join label, depth at the end of the then-branch).
            let mut open: Vec<(usize, usize)> = Vec::new();
            let mut else_depth: Vec<usize> = Vec::new();
            let mut elses: Vec<usize> = Vec::new();
            while j < lines.len() {
                if let Some(pos) = open.iter().position(|(l, _)| *l == j) {
                    // The join of a ternary: both branches leave one value.
                    let (_, then_depth) = open.remove(pos);
                    if then_depth != depth {
                        continue 'scan;
                    }
                } else if elses.contains(&j) {
                    // The else-branch of a conditional starts here.
                } else if tg.contains(&j) {
                    continue 'scan;
                }
                let l = &lines[j];
                let o = op(l);
                if o == "PushVal" || o == "GetVar" {
                    depth += 1;
                } else if o == "Test" || o == "Pop" {
                    if depth < 2 {
                        continue 'scan;
                    }
                    depth -= 1;
                } else if matches!(o, "Teq" | "Tne" | "Tl" | "Tle" | "Tg" | "Tge") {
                    if depth < 3 {
                        continue 'scan;
                    }
                    depth -= 1;
                } else if o == "Jz" {
                    if targets(l).len() != 1 {
                        continue 'scan;
                    }
                    else_depth.push(depth);
                    elses.extend(targets(l));
                } else if o == "Jmp" {
                    let tl = targets(l);
                    let (Some(&d), [t]) = (else_depth.last(), tl.as_slice()) else {
                        continue 'scan;
                    };
                    if *t <= j {
                        continue 'scan;
                    }
                    open.push((*t, depth));
                    else_depth.pop();
                    depth = d;
                } else if o == "Call" || o == "CallGlob" {
                    // A call takes its arguments off the stack and leaves its result.
                    let n: Option<usize> = if o == "Call" {
                        l.rsplit(", ").next().and_then(|x| x.parse().ok())
                    } else {
                        l["CallGlob ".len()..].split(',').next().and_then(|x| x.parse().ok())
                    };
                    match n {
                        Some(n) if n < depth => depth = depth + 1 - n,
                        _ => continue 'scan,
                    }
                } else if o == "Format" {
                    let n: usize = l
                        .rsplit(", ")
                        .next()
                        .and_then(|x| x.parse().ok())
                        .unwrap_or(usize::MAX);
                    if n == 0 || n >= depth {
                        continue 'scan;
                    }
                    depth = depth + 1 - n;
                } else if o == "Add" {
                    if depth == 1 && open.is_empty() && else_depth.is_empty() {
                        break;
                    }
                    if depth < 2 {
                        continue 'scan;
                    }
                    depth -= 1;
                } else {
                    continue 'scan;
                }
                j += 1;
            }
            if !open.is_empty() || !else_depth.is_empty() {
                continue;
            }
            // Every branch target inside the chain must come from inside it.
            let sources_inside = lines.iter().enumerate().all(|(k, l)| {
                targets(l).iter().all(|t| !(*t > i + 1 && *t <= j) || (k > i + 1 && k < j))
            });
            if !sources_inside {
                continue;
            }
            if j >= lines.len() || tg.contains(&(i + 1)) || tg.contains(&j) {
                continue;
            }
            lines[i + 1] = format!("PushVal \"{a}{b}\"");
            let mut drop = vec![false; lines.len()];
            drop[i] = true;
            drop[j] = true;
            lines = remove(&lines, &drop);
            changed = true;
            break;
        }
        if !changed {
            return lines;
        }
    }
}

/// Whether the straight-line code from `from` stores `store` (a `SetVar localK` line) before any read of the local:
/// no branch, return or branch target in between, so the earlier null store can never be seen, in a loop or not.
fn overwritten_before_use(lines: &[String], from: usize, store: &str, tg: &[usize]) -> bool {
    let name = &store["SetVar ".len()..];
    for (j, l) in lines.iter().enumerate().skip(from) {
        if tg.contains(&j) {
            return false;
        }
        if l == store {
            return true;
        }
        let o = op(l);
        if !targets(l).is_empty() || o == "Ret" || o == "End" || is_local(l, name) {
            return false;
        }
    }
    false
}

/// `PushVal null; SetVar localK` outside every backward-jump span, with no earlier use of `localK`: locals start
/// null and the pair runs at most once, so it stores what is already there. Native omits it (a declaration with no
/// initializer outside a loop); DreamMaker emits it, also before a declaration's own initializer.
fn drop_first_null_stores(lines: Vec<String>) -> Vec<String> {
    let mut spans = Vec::new();
    for (i, l) in lines.iter().enumerate() {
        for t in targets(l) {
            if t <= i {
                spans.push((t, i));
            }
        }
    }
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    let mut drop = vec![false; lines.len()];
    for i in 0..lines.len().saturating_sub(1) {
        if lines[i] != "PushVal null" || !lines[i + 1].starts_with("SetVar local") {
            continue;
        }
        let name = lines[i + 1]["SetVar ".len()..].to_string();
        if name.contains(' ') || name.contains('-') {
            continue;
        }
        if overwritten_before_use(&lines, i + 2, &lines[i + 1], &tg) {
            drop[i] = true;
            drop[i + 1] = true;
            continue;
        }
        if spans.iter().any(|&(s, e)| s <= i && i <= e) {
            continue;
        }
        if lines[..i].iter().any(|l| is_local(l, &name)) {
            continue;
        }
        drop[i] = true;
        drop[i + 1] = true;
    }
    if drop.iter().any(|d| *d) {
        remove(&lines, &drop)
    } else {
        lines
    }
}

/// Instructions after `Ret`, `End` or an unconditional jump that nothing branches to never run.
fn drop_unreachable(lines: Vec<String>) -> Vec<String> {
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    let mut drop = vec![false; lines.len()];
    let mut dead = false;
    for (i, l) in lines.iter().enumerate() {
        if tg.contains(&i) {
            dead = false;
        }
        if dead {
            drop[i] = true;
            continue;
        }
        let o = op(l);
        if o == "Ret" || o == "End" || ((o == "Jmp" || o == "JmpLoop") && !targets(l).is_empty()) {
            dead = true;
        }
    }
    if drop.iter().any(|d| *d) {
        remove(&lines, &drop)
    } else {
        lines
    }
}

/// An unconditional jump to the next instruction does nothing.
fn drop_jump_to_next(lines: Vec<String>) -> Vec<String> {
    let mut lines = lines;
    loop {
        let found = lines
            .iter()
            .enumerate()
            .position(|(i, l)| op(l) == "Jmp" && targets(l) == [i + 1]);
        let Some(i) = found else {
            return lines;
        };
        let mut drop = vec![false; lines.len()];
        drop[i] = true;
        lines = remove(&lines, &drop);
    }
}

/// `/T::field` is the field's initial value. DreamMaker folds it to the constant; native pushes the type and reads
/// `initial()` through the Cache register, which is what the VM defines the constant as. Where the default is a
/// constant of the class tables, the three-instruction read is that constant.
fn fold_static_reads(lines: Vec<String>, default: &dyn Fn(&str, &str) -> Option<String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::with_capacity(lines.len());
    let mut drop = vec![false; lines.len()];
    let mut rewrite: Vec<Option<String>> = vec![None; lines.len()];
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    for i in 0..lines.len().saturating_sub(2) {
        if lines[i + 1] != "SetVar cache" || tg.contains(&(i + 1)) || tg.contains(&(i + 2)) {
            continue;
        }
        let Some(field) = lines[i + 2]
            .strip_prefix("GetVar initial(src->.")
            .and_then(|r| r.strip_suffix(')'))
        else {
            continue;
        };
        let Some(path) = ["PushVal mobpath ", "PushVal path"].iter().find_map(|p| {
            let rest = lines[i].strip_prefix(p)?;
            // `path9 /obj/x` carries a tag number before the path.
            let rest = if p.ends_with("path") { rest.split_once(' ')?.1 } else { rest };
            rest.starts_with('/').then(|| rest.to_string())
        }) else {
            continue;
        };
        if let Some(value) = default(&path, field) {
            rewrite[i + 2] = Some(format!("PushVal {value}"));
            drop[i] = true;
            drop[i + 1] = true;
        }
    }
    let lines: Vec<String> = lines
        .into_iter()
        .enumerate()
        .map(|(i, l)| rewrite[i].take().unwrap_or(l))
        .collect();
    out.extend(if drop.iter().any(|d| *d) { remove(&lines, &drop) } else { lines });
    out
}

/// A type initializer made only of pure constructions stored to distinct fields of `src` (`PushVal`/`NewList`/
/// `NewAList`/`NewAssocList`/`EmptyList` ... `SetVar src->.f`, then `End`), optionally with `New` constructions. Such
/// stores read nothing of `src`, so their order cannot be observed: the result is the pure stores sorted by field,
/// then the constructing stores in their original order. `None` for any other body.
pub fn sorted_pure_initializer(lines: &[String]) -> Option<Vec<String>> {
    let (last, body) = lines.split_last()?;
    if last != "End" {
        return None;
    }
    // (field, lines, calls a constructor)
    let mut chunks: Vec<(String, Vec<String>, bool)> = Vec::new();
    let mut current: Vec<String> = Vec::new();
    let mut constructs = false;
    for l in body {
        if let Some(field) = l.strip_prefix("SetVar src->.") {
            if field.contains(|c: char| !(c.is_alphanumeric() || c == '_')) {
                return None;
            }
            current.push(l.clone());
            chunks.push((field.to_string(), std::mem::take(&mut current), constructs));
            constructs = false;
        } else if matches!(op(l), "PushVal" | "NewList" | "NewAList" | "NewAssocList" | "EmptyList")
            && targets(l).is_empty()
        {
            current.push(l.clone());
        } else if op(l) == "New" {
            // A constructor runs arbitrary code, so constructor-running stores keep their order among themselves.
            // Nothing here reads a field of `src`, so a pure store may still move across them.
            constructs = true;
            current.push(l.clone());
        } else {
            return None;
        }
    }
    if !current.is_empty() {
        return None;
    }
    let mut fields: Vec<&String> = chunks.iter().map(|c| &c.0).collect();
    fields.sort();
    if fields.windows(2).any(|w| w[0] == w[1]) {
        return None;
    }
    let (mut calls, mut pure): (Vec<_>, Vec<_>) = chunks.into_iter().partition(|c| c.2);
    pure.sort_by(|x, y| x.0.cmp(&y.0));
    let mut out: Vec<String> = pure.into_iter().flat_map(|c| c.1).collect();
    out.extend(calls.drain(..).flat_map(|c| c.1));
    out.push("End".into());
    Some(out)
}

pub fn normalize(lines: Vec<String>, default: &dyn Fn(&str, &str) -> Option<String>) -> Vec<String> {
    let lines = fold_static_reads(lines, default);
    drop_first_null_stores(merge_literals(drop_jump_to_next(drop_unreachable(lines))))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn none(_: &str, _: &str) -> Option<String> {
        None
    }

    #[test]
    fn static_field_read_is_the_default_constant() {
        let table = |p: &str, f: &str| (p == "/obj/x" && f == "y").then(|| "\"font\"".to_string());
        let nat = v(&["PushVal path9 /obj/x", "SetVar cache", "GetVar initial(src->.y)", "Ret"]);
        assert_eq!(normalize(nat, &table), v(&["PushVal \"font\"", "Ret"]));
        let other = v(&["PushVal path9 /obj/x", "SetVar cache", "GetVar initial(src->.z)", "Ret"]);
        assert_eq!(normalize(other.clone(), &table), other);
    }

    fn v(s: &[&str]) -> Vec<String> {
        s.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn right_nested_literals_equal_folded() {
        let dm = v(&["PushVal \"a\"", "PushVal \"b\"", "GetVar src->.x", "Add", "PushVal \"c\"", "Add", "Add", "Ret"]);
        let nat = v(&["PushVal \"ab\"", "GetVar src->.x", "Add", "PushVal \"c\"", "Add", "Ret"]);
        assert_eq!(normalize(dm, &none), normalize(nat, &none));
    }

    #[test]
    fn calls_inside_the_chain_do_not_disturb_the_merge() {
        let dm = v(&["PushVal \"a\"", "PushVal \"b\"", "Call src->dproc:f, 0", "Add", "Add", "Ret"]);
        assert_eq!(normalize(dm, &none), v(&["PushVal \"ab\"", "Call src->dproc:f, 0", "Add", "Ret"]));
        // A call that would consume the literal B itself is left alone.
        let eats = v(&["PushVal \"a\"", "PushVal \"b\"", "CallGlob 1, /proc/f", "Add", "Ret"]);
        assert_eq!(normalize(eats.clone(), &none), eats);
    }

    #[test]
    fn null_store_before_initializer_is_dead() {
        let dm = v(&["PushVal null", "SetVar local0", "PushVal 1.0", "SetVar local0", "End"]);
        assert_eq!(normalize(dm, &none), v(&["PushVal 1.0", "SetVar local0", "End"]));
    }

    #[test]
    fn null_store_before_initializer_in_a_loop_is_dead() {
        let dm = v(&["GetVar src", "Test", "Jz L8", "PushVal null", "SetVar local0", "PushVal 1.0", "SetVar local0", "JmpLoop L0", "End"]);
        assert_eq!(
            normalize(dm, &none),
            v(&["GetVar src", "Test", "Jz L6", "PushVal 1.0", "SetVar local0", "JmpLoop L0", "End"])
        );
    }

    #[test]
    fn literals_merge_across_a_conditional_operand() {
        let dm = v(&[
            "PushVal \"a\"", "PushVal \"b\"", "GetVar arg1", "Test", "Jz L7", "PushVal \"x\"", "Jmp L8",
            "PushVal \"y\"", "Add", "PushVal \"c\"", "Add", "Add", "Ret",
        ]);
        let nat = v(&[
            "PushVal \"ab\"", "GetVar arg1", "Test", "Jz L6", "PushVal \"x\"", "Jmp L7", "PushVal \"y\"",
            "Add", "PushVal \"c\"", "Add", "Ret",
        ]);
        assert_eq!(normalize(dm, &none), normalize(nat, &none));
    }

    #[test]
    fn jump_to_the_next_instruction_is_dropped() {
        let nat = v(&["Jz L3", "Jmp L2", "Jmp L3", "PushVal null", "End"]);
        assert_eq!(normalize(nat, &none), v(&["Jz L1", "PushVal null", "End"]));
    }

    #[test]
    fn pure_initializers_compare_in_any_order() {
        let a = v(&["NewList 0", "SetVar src->.a", "PushVal 1.0", "SetVar src->.b", "End"]);
        let b = v(&["PushVal 1.0", "SetVar src->.b", "NewList 0", "SetVar src->.a", "End"]);
        assert_eq!(sorted_pure_initializer(&a), sorted_pure_initializer(&b));
        assert!(sorted_pure_initializer(&a).is_some());
        // Constructors keep their relative order, a pure store may move across them.
        let e = v(&["PushVal path32 /a", "New 0", "SetVar src->.p", "NewList 0", "SetVar src->.q", "End"]);
        let f = v(&["NewList 0", "SetVar src->.q", "PushVal path32 /a", "New 0", "SetVar src->.p", "End"]);
        assert_eq!(sorted_pure_initializer(&e), sorted_pure_initializer(&f));
        let g = v(&["PushVal path32 /a", "New 0", "SetVar src->.p", "PushVal path32 /b", "New 0", "SetVar src->.r", "End"]);
        let h = v(&["PushVal path32 /b", "New 0", "SetVar src->.r", "PushVal path32 /a", "New 0", "SetVar src->.p", "End"]);
        assert_ne!(sorted_pure_initializer(&g), sorted_pure_initializer(&h));
        // A read or a call in the body keeps the order significant.
        let c = v(&["GetVar src->.a", "SetVar src->.b", "End"]);
        assert_eq!(sorted_pure_initializer(&c), None);
        // The same field stored twice is order dependent.
        let d = v(&["PushVal 1.0", "SetVar src->.a", "PushVal 2.0", "SetVar src->.a", "End"]);
        assert_eq!(sorted_pure_initializer(&d), None);
    }

    #[test]
    fn null_store_in_a_loop_stays() {
        let dm = v(&["GetVar src", "Test", "Jz L7", "PushVal null", "SetVar local0", "GetVar local0", "JmpLoop L0", "End"]);
        assert_eq!(normalize(dm.clone(), &none), dm);
    }

    #[test]
    fn dead_jump_after_return_is_dropped_and_labels_shift() {
        let dm = v(&["Jz L3", "Ret", "Jmp L3", "PushVal 1.0", "PushVal 2.0", "Ret"]);
        assert_eq!(normalize(dm, &none), v(&["Jz L2", "Ret", "PushVal 1.0", "PushVal 2.0", "Ret"]));
    }
}
