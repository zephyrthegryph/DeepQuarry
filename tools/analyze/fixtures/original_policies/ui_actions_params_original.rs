use crate::{pat,util::py_strip};
pub fn split_top(text: &str, sep: char) -> Vec<String> {
    let mut parts = Vec::new();
    let mut depth: i32 = 0;
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    for c in text.chars() {
        if let Some(q) = quote {
            cur.push(c);
            if c == q {
                quote = None;
            }
            continue;
        }
        if c == '"' || c == '\'' {
            quote = Some(c);
        } else if c == '(' || c == '[' || c == '{' {
            depth += 1;
        } else if c == ')' || c == ']' || c == '}' {
            depth -= 1;
        } else if c == sep && depth == 0 {
            parts.push(std::mem::take(&mut cur));
            continue;
        }
        cur.push(c);
    }
    parts.push(cur);
    parts
}

/// `param_names`: the parameter names of a proc head's argument text.
pub fn param_names(params: &str) -> Vec<String> {
    let mut names = Vec::new();
    for part in split_top(params, ',') {
        let name = py_strip(part.split('=').next().unwrap_or(""));
        let name = pat!(r"\bas\b.*$").replace_all(name, "");
        let name = py_strip(py_strip(&name).rsplit('/').next().unwrap_or("")).to_string();
        if !name.is_empty() && name != "..." {
            names.push(name);
        }
    }
    names
}
