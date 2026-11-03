//! Actual selected old enclosing-call body, independent test authority.
use crate::{pat,util::py_rstrip};
#[derive(Debug,PartialEq)]pub struct Enclosing{pub name:String,pub index:usize,pub key:Option<String>,pub member:bool}
pub fn enclosing_call(text: &str, i: usize) -> Option<Enclosing> {
    let b = text.as_bytes();
    let mut depth = 0i32;
    let mut commas = 0usize;
    let mut j = i as isize - 1;
    while j >= 0 {
        let ju = j as usize;
        let c = b[ju];
        if c == b')' || c == b']' {
            depth += 1;
        } else if c == b'(' || c == b'[' {
            if depth == 0 {
                if c == b'[' {
                    return None;
                }
                let before = &text[..ju];
                let m = pat!(r"([A-Za-z_]\w*)\s*$").captures(before)?;
                // the start of this argument, to spot `key = value`
                let mut seg_start = ju + 1;
                let mut d2 = 0i32;
                for k in ju + 1..i {
                    match b[k] {
                        b'(' | b'[' => d2 += 1,
                        b')' | b']' => d2 -= 1,
                        b',' if d2 == 0 => seg_start = k + 1,
                        _ => {}
                    }
                }
                let key = pat!(r"\A\s*([A-Za-z_]\w*)\s*=(?!=)")
                    .captures(&text[seg_start..i])
                    .map(|k| k.s(1).to_string());
                let head = py_rstrip(&text[..m.start(0)]);
                return Some(Enclosing {
                    name: m.s(1).to_string(),
                    index: commas,
                    key,
                    member: head.ends_with('.') || head.ends_with(':'),
                });
            }
            depth -= 1;
        } else if c == b',' && depth == 0 {
            commas += 1;
        }
        j -= 1;
    }
    None
}
