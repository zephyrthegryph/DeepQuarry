//! The unique source-neutral reactive writer algorithm, independent of the legacy semantic module.
//! Borrowed original Proc/body DATA only; this module cannot issue source/EOF authority.
use std::collections::HashSet;
use crate::{dm::dx::Proc,pat,pat_match,pat::Pat,util::py_strip};
pub fn writer_call() -> &'static Pat {
    pat!(r"(?<![\w./:])(?:changed|cap_set|timed_set|timed_cancel|own_set|own_add|own_put|own_take|own_take_all|own_take_member|own_remove|own_clear|own_transfer|own_move|rel_set|rel_add|rel_remove|rel_clear|om_set|qdel|forceMove|set_light|update_icon|add_fingerprint|to_chat|playsound|set_\w+)\s*\(")
}

pub fn member_writer() -> &'static Pat {
    pat!(r"(?<![\w.])([A-Za-z_]\w*|\.)((?:\s*\??\.\s*[A-Za-z_]\w*)*?)\s*\??\.\s*(set_\w+|forceMove|qdel|set_light|update_icon|add_fingerprint|Add|Cut|Remove|RemoveAll|Insert|Swap|Splice)\s*\(")
}

pub(crate) fn local_decl() -> &'static Pat {
    pat!(r"\bvar/(?:[\w/]+/)?(\w+)")
}

/// `write_op_at`: the length of an assignment operator at `b[k]` (the Python's WRITE_OP matched
/// at that offset, lookbehind included), or None.
fn write_op_at(b: &[u8], k: usize) -> Option<usize> {
    const BEHIND: &[u8] = b"=!<>+-*/|&^%";
    if k > 0 && BEHIND.contains(&b[k - 1]) {
        return None;
    }
    let c = b[k];
    if c == b'=' {
        return if b.get(k + 1) != Some(&b'=') { Some(1) } else { None };
    }
    if matches!(c, b'+' | b'-' | b'*' | b'/' | b'|' | b'&' | b'^') && b.get(k + 1) == Some(&b'=') {
        return Some(2);
    }
    if (c == b'<' || c == b'>') && b.get(k + 1) == Some(&c) && b.get(k + 2) == Some(&b'=') {
        return Some(3);
    }
    None
}

/// `top_level_ops`: offsets of assignment operators outside parentheses/brackets.
fn top_level_ops(text: &str) -> Vec<usize> {
    let b = text.as_bytes();
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut k = 0usize;
    while k < b.len() {
        let c = b[k];
        if c == b'(' || c == b'[' {
            depth += 1;
        } else if c == b')' || c == b']' {
            depth -= 1;
        } else if depth == 0 {
            if let Some(len) = write_op_at(b, k) {
                out.push(k);
                k += len;
                continue;
            }
        }
        k += 1;
    }
    out
}

/// `write_target_bad`: an assignment target that is state (not a local, parameter, `.` or `look`).
fn write_target_bad(target: &str, locals: &HashSet<String>) -> bool {
    let target = py_strip(target);
    if target.is_empty() || target.starts_with("var/") || pat!(r"\bvar/").is_match(target) {
        return false;
    }
    let Some(m) = pat_match!(r"(\.|[A-Za-z_]\w*)").captures(target) else { return false };
    let root = m.s(1);
    let rest = py_strip(&target[m.end(0)..]);
    if root == "." || root == "look" {
        return false;
    }
    if rest.is_empty() {
        return !locals.contains(root); // a bare var: a src var unless it is a local or parameter
    }
    if rest.starts_with('[') {
        return !locals.contains(root) && root != "src"; // an index of a local/param list is fine
    }
    true // a member write: another object's (or src's) state
}



/// Same unique old writer judgment over current borrowed original body lines.
/// This helper issues neither source nor body/semantic completion.
pub fn reactive_writes_lines_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(proc:&Proc,lines:&[(usize,&str)],keep:&mut C,temp:&mut T)->Result<Vec<usize>,C::Error>{
 keep.checkpoint()?;let mut width=0usize;for(_,line)in lines{keep.checkpoint()?;width=width.checked_add(line.len()).and_then(|n|n.checked_add(1)).ok_or_else(||keep.overflow())?;}for name in &proc.params{keep.checkpoint()?;width=width.checked_add(name.len()).ok_or_else(||keep.overflow())?;}crate::key_policy_control::reserve(temp,||width.checked_mul(256)?.checked_add(lines.len().checked_mul(4*std::mem::size_of::<(usize,&str)>())?)?.checked_add(4096))?;
    let mut declared: HashSet<String> = HashSet::new();
    for (_n, text) in lines {
        keep.checkpoint()?;
        for m in local_decl().captures_iter(text) {
            keep.checkpoint()?;
            declared.insert(m.s(1).to_string());
        }
    }
    let mut locals: HashSet<String> = declared.clone();
    locals.extend(proc.params.iter().cloned());
    let mut mutable: HashSet<&str> = declared.iter().map(|s| s.as_str()).collect();
    mutable.extend([".", "look", "data"]);
    let splitter = pat!(r"[;{]|\bin\b|^\s*(?:if|while|else if)\s*\(.*\)\s*");
    let incdec = pat!(r#"(\+\+|--)\s*([A-Za-z_.][\w.?\[\]]*)|([A-Za-z_.][\w.?\[\]"]*?)\s*(\+\+|--)"#);
    let mut out = Vec::new();
    for (number, code) in lines {
        keep.checkpoint()?;
        let code: &str = code;
        let mut bad = writer_call().is_match(code);
        if !bad {
            for m in member_writer().captures_iter(code) {
                keep.checkpoint()?;
                let root = m.s(1);
                let through = py_strip(m.s(2));
                // `L.Add(x)` on a local list and `look.set_icon()` are fine; `holder.verbs.Remove()`
                // or `cell.set_charge()` mutate another object.
                if !through.is_empty() || !mutable.contains(root) {
                    bad = true;
                    break;
                }
            }
        }
        if !bad {
            let stripped = py_strip(code);
            if !(stripped.starts_with("var/") || stripped.starts_with("for(") || stripped.starts_with("for (")) {
                for k in top_level_ops(code) {
                    keep.checkpoint()?;
                    // the target is the text since the statement start (after `if(...)` etc.)
                    let lhs = &code[..k];
                    let lhs = match splitter.find_iter(lhs).last() {
                        Some(m) => &lhs[m.end..],
                        None => lhs,
                    };
                    if write_target_bad(lhs, &locals) {
                        bad = true;
                        break;
                    }
                }
            }
        }
        if !bad {
            for m in incdec.captures_iter(code) {
                keep.checkpoint()?;
                let target = if m.matched(2) { m.s(2) } else { m.s(3) };
                if !target.is_empty() && write_target_bad(target, &locals) {
                    bad = true;
                    break;
                }
            }
        }
        if bad {
            crate::raw_tree_report::row(keep,&mut out)?;out.push(*number);
        }
    }
    keep.checkpoint()?;Ok(out)
}


#[cfg(test)]mod tests{use super::*;#[test]fn native_reactive_writer_kernel_accepts_original_proc_without_legacy_model(){let file=crate::tree::SourceFile::from_text("code/kernel-writer.dm","/obj/control/proc/appearance_overlays(value)\n\tvar/list/parts = list()\n\tparts += value\n\tparts.Add(value)\n\tlook.set_icon(value)\n\tstate = value\n\tcell.set_charge(value)\n");let proc=crate::dm::dx::procs_in(&file).into_iter().next().expect("real original Proc");let clean=file.clean();let lines:Vec<_>=(0..proc.body_len).map(|k|(proc.body_start+k,clean.line(proc.body_start+k))).collect();let result=reactive_writes_lines_using(&proc,&lines,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).unwrap();assert_eq!(result,vec![6,7]);}}
