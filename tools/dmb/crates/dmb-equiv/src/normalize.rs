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
        let Some(path) = ["PushVal mobpath ", "PushVal path"].iter().find_map(|p| {
            let rest = lines[i].strip_prefix(p)?;
            // `path9 /obj/x` carries a tag number before the path.
            let rest = if p.ends_with("path") { rest.split_once(' ')?.1 } else { rest };
            rest.starts_with('/').then(|| rest.to_string())
        }) else {
            continue;
        };
        // The register holds that very constant (`canon::cache_states_full` labels it with the pushed value), so the
        // read renders as `initial(<value>->.field)`.
        let label = &lines[i]["PushVal ".len()..];
        let Some(field) = lines[i + 2]
            .strip_prefix("GetVar initial(")
            .and_then(|r| r.strip_suffix(')'))
            .and_then(|r| r.strip_prefix(label))
            .and_then(|r| r.strip_prefix("->."))
        else {
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

/// `GetFlag; Test` leaves the stack and the comparison flag as they were: `GetFlag` pushes the flag as 0 or 1 and
/// `Test` pops that value and sets the flag to its truthiness, which is the flag again (FORMAT.md: a conditional reads
/// the flag directly after the comparison that set it; DreamMaker emits `IsIn; Jz` where native emits
/// `IsIn; GetFlag; Test; Jz`). Applies only when `Test` is not a branch target, so no other path reaches it with a value.
fn drop_flag_roundtrip(lines: Vec<String>) -> Vec<String> {
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    let mut drop = vec![false; lines.len()];
    for i in 0..lines.len().saturating_sub(1) {
        if lines[i] == "GetFlag" && lines[i + 1] == "Test" && !tg.contains(&(i + 1)) && !drop[i] {
            drop[i] = true;
            drop[i + 1] = true;
        }
    }
    if drop.iter().any(|d| *d) {
        remove(&lines, &drop)
    } else {
        lines
    }
}

/// `GetVar X` reads variables only: a proc operand would call it. The canonical receiver text of a Cache that holds a
/// call result, `(Call ...)->.f`, names that earlier call and runs nothing, so parenthesised labels are skipped.
fn is_pure_read(line: &str) -> bool {
    let mut depth = 0usize;
    let mut outside = String::new();
    for c in line.chars() {
        match c {
            '(' => depth += 1,
            ')' => depth = depth.saturating_sub(1),
            _ if depth == 0 => outside.push(c),
            _ => {}
        }
    }
    !outside.contains("dproc:") && !outside.contains("dverb:")
}

/// Instructions that only move the receiver Cache register. `canon::cache_states_full` carries the register through
/// them as a symbolic label that every reader (a bare field or proc operand, `GetVar cache`) renders, so the
/// instructions themselves have no other effect and a difference in how often a compiler saves, restores or reloads
/// the register is not a difference in behaviour:
/// * `PushCache` / `PopCache` save and restore the register on a stack of its own (balanced on every path, else
///   `canon` leaves a `?` on them and they stay);
/// * `GetVar X; SetVar cache` with a pure read `X` (no call) loads the register with the value of `X`: Dream Maker
///   reloads `src` this way where native names `src` in each operand.
fn drop_cache_register_ops(lines: Vec<String>) -> Vec<String> {
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    let mut drop = vec![false; lines.len()];
    for i in 0..lines.len() {
        if lines[i] == "PushCache" || lines[i] == "PopCache" {
            drop[i] = true;
        } else if i + 1 < lines.len()
            && lines[i].starts_with("GetVar ")
            && is_pure_read(&lines[i])
            && !lines[i].starts_with("GetVar cache")
            && lines[i + 1] == "SetVar cache"
            && !tg.contains(&(i + 1))
        {
            drop[i] = true;
            drop[i + 1] = true;
        }
    }
    if drop.iter().any(|d| *d) {
        remove(&lines, &drop)
    } else {
        lines
    }
}

fn retarget(line: &str, to: usize) -> String {
    match label_spans(line).first() {
        Some(&(s, e, _)) => format!("{}L{to}{}", &line[..s], &line[e..]),
        None => line.to_string(),
    }
}

/// A jump that lands on another jump that is certain to be taken continues to the final destination; compilers differ
/// in how far they route a chain of short-circuit or null-guard exits (DreamMaker sends every exit of `a || b || c`
/// to the end, native to the next test). The target is certain to jump again when it reads the state the first jump
/// leaves unchanged:
/// * any jump onto an unconditional `Jmp` (it reads nothing);
/// * `Jz`/`Jnz` onto the same instruction (the flag is unchanged);
/// * `JmpOr` onto `JmpOr`, `JmpAnd` onto `JmpAnd` (the value stays on top and is still true, or false);
/// * `SetCacheJmpIfNull` onto `SetCacheJmpIfNull` or `SetCachePopJmpIfNull` (the value is the null it just left; the
///   second guard's cache write is the same null write, and its pop-or-not is the only difference, kept by naming the
///   target's own instruction kind) and onto a bare `Pop` (a pop-guard jumping past it).
fn thread_jumps(lines: Vec<String>) -> Vec<String> {
    let mut lines = lines;
    // Every destination of every instruction (case tables and loop jumps included) that is an unconditional `Jmp`
    // continues to that jump's destination: running the `Jmp` reads and changes nothing but the program counter.
    for i in 0..lines.len() {
        let spans = label_spans(&lines[i]);
        if spans.is_empty() {
            continue;
        }
        let mut text = String::new();
        let mut last = 0;
        for (s, e, n) in spans {
            text.push_str(&lines[i][last..s]);
            let mut dest = n;
            for _ in 0..16 {
                match lines.get(dest).map(|l| (op(l), targets(l))) {
                    Some(("Jmp", t)) if t.len() == 1 && t[0] != dest => dest = t[0],
                    _ => break,
                }
            }
            text.push('L');
            text.push_str(&dest.to_string());
            last = e;
        }
        text.push_str(&lines[i][last..]);
        lines[i] = text;
    }
    for i in 0..lines.len() {
        for _ in 0..16 {
            let o = op(&lines[i]).to_string();
            let tl = targets(&lines[i]);
            let [t] = tl.as_slice() else { break };
            if *t >= lines.len() || *t == i || !matches!(o.as_str(), "Jmp" | "Jz" | "Jnz" | "JmpOr" | "JmpAnd" | "SetCacheJmpIfNull" | "SetCachePopJmpIfNull") {
                break;
            }
            let target = lines[*t].clone();
            let to = op(&target).to_string();
            let tt = targets(&target);
            let next = match (o.as_str(), to.as_str()) {
                (_, "Jmp") if tt.len() == 1 => Some((lines[i].clone(), tt[0])),
                ("Jz", "Jz") | ("Jnz", "Jnz") | ("JmpOr", "JmpOr") | ("JmpAnd", "JmpAnd") | ("SetCacheJmpIfNull", "SetCacheJmpIfNull")
                    if tt.len() == 1 =>
                {
                    Some((lines[i].clone(), tt[0]))
                }
                ("SetCacheJmpIfNull", "SetCachePopJmpIfNull") if tt.len() == 1 => {
                    Some((lines[i].replacen("SetCacheJmpIfNull", "SetCachePopJmpIfNull", 1), tt[0]))
                }
                ("SetCacheJmpIfNull", "Pop") if *t + 1 < lines.len() => {
                    Some((lines[i].replacen("SetCacheJmpIfNull", "SetCachePopJmpIfNull", 1), *t + 1))
                }
                _ => None,
            };
            let Some((line, dest)) = next else { break };
            lines[i] = retarget(&line, dest);
        }
    }
    lines
}

/// `End` returns the proc's `.` value, so `GetVar .; Ret` is `End`: Dream Maker ends `. = 1` with `PushVal 1; SetVar .;
/// End`, which would return null if `End` did not read `.`.
fn fold_return_dot(lines: Vec<String>) -> Vec<String> {
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    let mut lines = lines;
    let mut i = 0;
    while i + 1 < lines.len() {
        if lines[i] == "GetVar ." && lines[i + 1] == "Ret" && !tg.contains(&(i + 1)) {
            lines[i] = "End".into();
            let mut drop = vec![false; lines.len()];
            drop[i + 1] = true;
            // `Ret` stood at i + 1; targets at i + 1 are excluded above, so only later labels renumber.
            lines = remove(&lines, &drop);
            return fold_return_dot(lines);
        }
        i += 1;
    }
    lines
}

/// Splits `{k=>L1;k=>L2;else=>L3}` into its entries, honouring quoted keys. None when the text is not that shape.
fn split_cases(line: &str) -> Option<(&str, Vec<(String, String)>)> {
    let open = line.find('{')?;
    let body = line[open + 1..].strip_suffix('}')?;
    let mut entries = Vec::new();
    let (mut key, mut cur) = (String::new(), String::new());
    let (mut quoted, mut in_label) = (false, false);
    let chars: Vec<char> = body.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if in_label {
            if c == ';' {
                entries.push((std::mem::take(&mut key), std::mem::take(&mut cur)));
                in_label = false;
            } else {
                cur.push(c);
            }
        } else if quoted {
            cur.push(c);
            if c == '\\' && i + 1 < chars.len() {
                i += 1;
                cur.push(chars[i]);
            } else if c == '"' {
                quoted = false;
            }
        } else if c == '"' {
            quoted = true;
            cur.push(c);
        } else if c == '=' && chars.get(i + 1) == Some(&'>') {
            key = std::mem::take(&mut cur);
            in_label = true;
            i += 1;
        } else {
            cur.push(c);
        }
        i += 1;
    }
    if in_label && key == "else" {
        entries.push((key, cur));
        cur = String::new();
    }
    if quoted || !cur.is_empty() || entries.last().map(|e| e.0.as_str()) != Some("else") {
        return None;
    }
    Some((&line[..open], entries))
}

/// A `Switch` over distinct constant keys selects the one case equal to the selector, so the order its entries are
/// written in cannot matter (DreamMaker lists the cases of a text switch in another order than native). Entries are
/// sorted by key; `else` stays last. A switch with a repeated key, or with ranges (`SwitchRange`), is left alone.
fn sort_switch_cases(lines: Vec<String>) -> Vec<String> {
    lines
        .into_iter()
        .map(|line| {
            if op(&line) != "Switch" {
                return line;
            }
            let Some((head, mut entries)) = split_cases(&line) else {
                return line;
            };
            let default = entries.pop().unwrap();
            let mut keys: Vec<&String> = entries.iter().map(|e| &e.0).collect();
            keys.sort();
            if keys.windows(2).any(|w| w[0] == w[1]) {
                return line;
            }
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            entries.push(default);
            let body: Vec<String> = entries.iter().map(|(k, l)| format!("{k}=>{l}")).collect();
            format!("{head}{{{}}}", body.join(";"))
        })
        .collect()
}

/// `PushCacheKey; E...; PopCacheKey` saves the list-index key/index registers around `E` and puts them back. When no
/// instruction of `E` reads or writes either register (no line mentions `cache-key` or `cache-index`), `E` is straight
/// code (no jump or jump target between the pair), and a call or constructor in it runs in a frame of its own (the
/// registers belong to the frame), the registers are the same after the pair as before it: the pair does nothing.
fn drop_idle_cache_key_saves(lines: Vec<String>) -> Vec<String> {
    let tg: Vec<usize> = lines.iter().flat_map(|l| targets(l)).collect();
    let mut drop = vec![false; lines.len()];
    let mut i = 0;
    while i < lines.len() {
        if lines[i] == "PushCacheKey" {
            let mut j = i + 1;
            let mut idle = true;
            while j < lines.len() && lines[j] != "PopCacheKey" {
                let l = &lines[j];
                if !targets(l).is_empty()
                    || tg.contains(&j)
                    || l.contains("cache-key")
                    || l.contains("cache-index")
                    || l.starts_with("PushCacheKey")
                    || matches!(op(l), "Ret" | "End")
                {
                    idle = false;
                    break;
                }
                j += 1;
            }
            if idle && j < lines.len() && !tg.contains(&j) && !tg.contains(&i) {
                drop[i] = true;
                drop[j] = true;
                i = j;
            }
        }
        i += 1;
    }
    if drop.iter().any(|d| *d) {
        remove(&lines, &drop)
    } else {
        lines
    }
}

/// A body made only of independent initializer statements (`E...; SetVar global:g`, then `End`) that both sides run in
/// another order. None unless the two bodies hold exactly the same statements. The statements are reported rather than
/// compared as a set because they are not free to move: those that run code (`New`, calls, reads of other globals) can
/// observe each other's effects, so the order is DreamMaker's (ascending variable id, which is the order in which a
/// name first appears in the compiled procedures) and the difference stays visible.
pub fn initializer_order_difference(a: &[String], b: &[String]) -> Option<String> {
    fn statements(lines: &[String]) -> Option<Vec<Vec<String>>> {
        let (last, body) = lines.split_last()?;
        if last != "End" {
            return None;
        }
        let mut out = Vec::new();
        let mut current = Vec::new();
        for line in body {
            if !targets(line).is_empty() {
                return None;
            }
            current.push(line.clone());
            if line.starts_with("SetVar ") {
                out.push(std::mem::take(&mut current));
            }
        }
        current.is_empty().then_some(out)
    }
    let (sa, sb) = (statements(a)?, statements(b)?);
    if sa.len() != sb.len() || sa.len() < 2 {
        return None;
    }
    let mut position: std::collections::HashMap<&Vec<String>, Vec<usize>> = std::collections::HashMap::new();
    for (i, statement) in sa.iter().enumerate() {
        position.entry(statement).or_default().push(i);
    }
    let mut order = Vec::with_capacity(sb.len());
    for statement in &sb {
        let slots = position.get_mut(statement)?;
        if slots.is_empty() {
            return None;
        }
        order.push(slots.remove(0));
    }
    // Statements outside the longest run that keeps its order are the ones that moved.
    let longest_increasing = |values: &[usize]| {
        let mut tails: Vec<usize> = Vec::new();
        for &value in values {
            let at = tails.partition_point(|&t| t < value);
            if at == tails.len() {
                tails.push(value);
            } else {
                tails[at] = value;
            }
        }
        tails.len()
    };
    let runs_code = |statement: &Vec<String>| {
        statement.iter().any(|l| {
            matches!(op(l), "New" | "Call" | "CallGlob" | "CallStatement" | "CallGlobalArgList" | "RegexNew" | "NewArgList")
                || l.starts_with("GetVar global:")
        })
    };
    let code_order: Vec<usize> = order.iter().copied().filter(|&i| runs_code(&sa[i])).collect();
    let moved = order.len() - longest_increasing(&order);
    if moved == 0 {
        return None;
    }
    Some(format!(
        "{} of {} initializer statements run in another order; {} of the {} that run code (constructors, calls, reads of globals) run in another order relative to each other",
        moved,
        order.len(),
        code_order.len() - longest_increasing(&code_order),
        code_order.len(),
    ))
}

pub fn normalize(lines: Vec<String>, default: &dyn Fn(&str, &str) -> Option<String>) -> Vec<String> {
    let mut lines = fold_static_reads(lines, default);
    // Each pass can expose another (a folded short-circuit leaves dead code, a dropped jump exposes a literal pair).
    for _ in 0..8 {
        let before = lines.clone();
        lines = fold_return_dot(lines);
        lines = drop_flag_roundtrip(lines);
        lines = drop_cache_register_ops(lines);
        lines = drop_idle_cache_key_saves(lines);
        lines = thread_jumps(lines);
        lines = drop_unreachable(lines);
        lines = sort_switch_cases(lines);
        lines = drop_jump_to_next(lines);
        lines = merge_literals(lines);
        lines = drop_first_null_stores(lines);
        if lines == before {
            break;
        }
    }
    lines
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
        let nat = v(&["PushVal path9 /obj/x", "SetVar cache", "GetVar initial(path9 /obj/x->.y)", "Ret"]);
        assert_eq!(normalize(nat, &table), v(&["PushVal \"font\"", "Ret"]));
        let other = v(&["PushVal path9 /obj/x", "SetVar cache", "GetVar initial(path9 /obj/x->.z)", "Ret"]);
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
    fn flag_roundtrip_before_a_conditional_is_dropped() {
        let nat = v(&["GetVar arg0", "IsIn 5", "GetFlag", "Test", "Jz L6", "End", "End"]);
        assert_eq!(normalize(nat, &none), v(&["GetVar arg0", "IsIn 5", "Jz L4", "End", "End"]));
        // A jump to the Test arrives with a value of its own: keep it.
        let kept = v(&["Jz L2", "GetFlag", "Test", "Jz L5", "End", "End"]);
        assert_eq!(normalize(kept.clone(), &none), kept);
    }

    #[test]
    fn get_dot_return_is_end() {
        let nat = v(&["PushVal 1.0", "SetVar .", "GetVar .", "Ret"]);
        assert_eq!(normalize(nat, &none), v(&["PushVal 1.0", "SetVar .", "End"]));
    }

    #[test]
    fn cache_save_restore_and_register_reloads_are_dropped() {
        let dm = v(&["GetVar usr", "SetCacheJmpIfNull L7", "PushCache", "GetVar src", "SetVar cache", "PopCache", "Pop", "End"]);
        assert_eq!(
            normalize(dm, &none),
            v(&["GetVar usr", "SetCacheJmpIfNull L3", "Pop", "End"])
        );
        // An unbalanced save stack is marked by canon and stays.
        let marked = v(&["PushCache?", "End"]);
        assert_eq!(normalize(marked.clone(), &none), marked);
    }

    #[test]
    fn jumps_thread_through_jumps_that_must_be_taken() {
        // JmpOr onto JmpOr, a case table onto a Jmp, a null guard onto a pop-guard.
        let a = v(&["JmpOr L2", "End", "JmpOr L4", "End", "Ret"]);
        assert_eq!(thread_jumps(a)[0], "JmpOr L4");
        let b = v(&["Switch {1.0=>L2;else=>L3}", "End", "Jmp L4", "End", "Ret"]);
        assert_eq!(thread_jumps(b)[0], "Switch {1.0=>L4;else=>L3}");
        let c = v(&["SetCacheJmpIfNull L2", "End", "SetCachePopJmpIfNull L4", "End", "End"]);
        assert_eq!(thread_jumps(c)[0], "SetCachePopJmpIfNull L4");
        // A conditional jump onto a different kind of test is not threaded.
        let d = v(&["Jz L2", "End", "JmpOr L4", "End", "Ret"]);
        assert_eq!(thread_jumps(d.clone()), d);
    }

    #[test]
    fn switch_entries_with_distinct_keys_compare_in_any_order() {
        let a = v(&["Switch {\"b\"=>L1;\"a\"=>L2;else=>L3}", "End", "End", "End"]);
        let b = v(&["Switch {\"a\"=>L2;\"b\"=>L1;else=>L3}", "End", "End", "End"]);
        assert_eq!(normalize(a, &none), normalize(b, &none));
        let dup = v(&["Switch {1.0=>L1;1.0=>L2;else=>L3}", "End", "End", "End"]);
        assert_eq!(normalize(dup.clone(), &none), dup);
    }

    #[test]
    fn idle_cache_key_saves_are_dropped_and_busy_ones_stay() {
        let idle = v(&["PushCacheKey", "PushVal 8.0", "New 1", "PopCacheKey", "End"]);
        assert_eq!(normalize(idle, &none), v(&["PushVal 8.0", "New 1", "End"]));
        let busy = v(&["PushCacheKey", "GetVar cache-index", "PopCacheKey", "End"]);
        assert_eq!(normalize(busy.clone(), &none), busy);
    }

    #[test]
    fn initializer_order_is_reported_not_hidden() {
        let a = v(&["PushVal 1.0", "SetVar global:a", "New 0", "SetVar global:b", "End"]);
        let b = v(&["New 0", "SetVar global:b", "PushVal 1.0", "SetVar global:a", "End"]);
        assert!(initializer_order_difference(&a, &b).unwrap().contains("1 of 2"));
        assert_eq!(initializer_order_difference(&a, &a), None);
        // Different statements are a different program, not an order difference.
        let c = v(&["PushVal 2.0", "SetVar global:a", "New 0", "SetVar global:b", "End"]);
        assert_eq!(initializer_order_difference(&a, &c), None);
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
