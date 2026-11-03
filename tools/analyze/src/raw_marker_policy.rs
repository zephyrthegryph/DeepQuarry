//! Existing raw marker policy over one retained source view; no Decls model.
pub fn strip_comments_keep_strings(text:&str)->String{match strip_comments_keep_strings_using(text,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
/// The SAME original comment-mask algorithm with typed current operation work.
/// Compatibility delegates this kernel; no alternate spelling scanner is added.
pub fn strip_comments_keep_strings_using<C:crate::key_policy_control::Control>(text:&str,c:&mut C)->Result<String,C::Error>{
    use crate::key_policy_control as kc;
    c.checkpoint()?;kc::reserve(c,||text.len().checked_mul(2)?.checked_add(128))?;
    let b = text.as_bytes();
    let mut out = b.to_vec();
    let mut i = 0;
    let n = b.len();
    while i < n {
        c.checkpoint()?;
        match b[i] {
            b'"' => {
                // A string: skip to the closing quote ("\\" escapes; `[ ]` interpolation is left alone).
                i += 1;
                while i < n && b[i] != b'"' && b[i] != b'\n' {
        c.checkpoint()?;
                    if b[i] == b'\\' && i + 1 < n {
                        i += 1;
                    }
                    i += 1;
                }
                i += 1;
            }
            b'\'' => {
                i += 1;
                while i < n && b[i] != b'\'' && b[i] != b'\n' {
        c.checkpoint()?;
                    i += 1;
                }
                i += 1;
            }
            b'/' if i + 1 < n && b[i + 1] == b'/' => {
                while i < n && b[i] != b'\n' {
        c.checkpoint()?;
                    out[i] = b' ';
                    i += 1;
                }
            }
            b'/' if i + 1 < n && b[i + 1] == b'*' => {
                let mut depth = 0;
                while i < n {
        c.checkpoint()?;
                    if i + 1 < n && b[i] == b'/' && b[i + 1] == b'*' {
                        depth += 1;
                        out[i] = b' ';
                        out[i + 1] = b' ';
                        i += 2;
                    } else if i + 1 < n && b[i] == b'*' && b[i + 1] == b'/' {
                        depth -= 1;
                        out[i] = b' ';
                        out[i + 1] = b' ';
                        i += 2;
                        if depth == 0 {
                            break;
                        }
                    } else {
                        if b[i] != b'\n' {
                            out[i] = b' ';
                        }
                        i += 1;
                    }
                }
            }
            _ => i += 1,
        }
    }
    c.checkpoint()?;Ok(String::from_utf8(out).unwrap_or_default())
}

/// Borrowed spelling slices from the SAME original argument grammar.
pub struct Arguments<'a>{source:&'a str,chars:std::str::CharIndices<'a>,from:usize,depth:i32,in_str:bool,prev:char,emitted:bool,done:bool}
pub fn argument_slices(source:&str)->Arguments<'_>{Arguments{source,chars:source.char_indices(),from:0,depth:0,in_str:false,prev:'\0',emitted:false,done:false}}
impl<'a> Arguments<'a>{fn next_using<C:crate::key_policy_control::Control>(&mut self,c:&mut C)->Result<Option<&'a str>,C::Error>{c.checkpoint()?;if self.done{return Ok(None)}while let Some((i,ch))=self.chars.next(){c.checkpoint()?;let token=ch;if self.in_str{if token=='"'&&self.prev!='\\'{self.in_str=false}self.prev=token;continue}match token{'"'=>self.in_str=true,'('| '['|'{' =>self.depth+=1,')'|']'|'}'=>self.depth-=1,',' if self.depth==0=>{let value=self.source[self.from..i].trim();self.from=i+1;self.prev=token;self.emitted=true;return Ok(Some(value))},_=>{}}self.prev=token;}self.done=true;let last=self.source[self.from..].trim();if !last.is_empty()||self.emitted{Ok(Some(last))}else{Ok(None)}}}
impl<'a> Iterator for Arguments<'a>{type Item=&'a str;fn next(&mut self)->Option<Self::Item>{match self.next_using(&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}}
pub fn split_args(s:&str)->Vec<String>{match split_args_using(s,&mut crate::key_policy_control::Compatibility){Ok(rows)=>rows,Err(never)=>match never{}}}
pub fn split_args_using<C:crate::key_policy_control::Control>(s:&str,c:&mut C)->Result<Vec<String>,C::Error>{let mut args=argument_slices(s);let mut rows=Vec::new();while let Some(value)=args.next_using(c)?{crate::key_policy_control::row(c,&mut rows)?;rows.push(crate::key_policy_control::own(c,value)?);}c.checkpoint()?;Ok(rows)}

pub fn matching_paren(s:&str,open:usize)->Option<usize>{match matching_paren_using(s,open,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn matching_paren_using<C:crate::key_policy_control::Control>(s:&str,open:usize,c:&mut C)->Result<Option<usize>,C::Error>{
 c.checkpoint()?;
    let b = s.as_bytes();
    let mut depth = 0i32;
    let mut in_str = false;
    let mut i = open;
    while i < b.len() {
        c.checkpoint()?;
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                in_str = false;
            }
        } else {
            match c {
                b'"' => in_str = true,
                b'(' => depth += 1,
                b')' => {
                    depth -= 1;
                    if depth == 0 {
                        return Ok(Some(i));
                    }
                }
                _ => {}
            }
        }
        i += 1;
    }
    c.checkpoint()?;Ok(None)
}

pub(crate) struct StatementMarker<'a> {
    pub name: &'a str,
    pub open: usize,
    pub close: usize,
}
pub(crate) fn statement_marker<'a>(
    text: &str,
    line_offset: usize,
    line: &'a str,
    names: &[&str],
) -> Option<StatementMarker<'a>> {
    let t = line.trim_start();
    if t.starts_with('#') || t.is_empty() {
        return None;
    }
    let name_end = t
        .find(|c: char| !(c.is_alphanumeric() || c == '_'))
        .unwrap_or(t.len());
    let name = &t[..name_end];
    if !names.contains(&name) || !t[name_end..].trim_start().starts_with('(') {
        return None;
    }
    let open = line_offset + line.len() - t.len() + name_end + t[name_end..].find('(')?;
    Some(StatementMarker {
        name,
        open,
        close: matching_paren(text, open)?,
    })
}

/// Original strict UTF8 read_to_string include-order policy.
pub fn dme_include_order(text: &str) -> std::collections::HashMap<String, usize> {
    dme_include_order_view(text, false)
}
/// Acquisition may strip exactly the initial UTF8 BOM; do not copy a source
/// buffer to put it back. Old trim() leaves BOM, so only first line is skipped.
pub fn dme_include_order_view(text:&str,had_bom:bool)->std::collections::HashMap<String,usize>{
    match dme_include_order_controlled(text,had_bom,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}
}
/// SAME include-order policy with actual observed path/table growth admitted.
/// Generic data does not certify that these bytes are an original manifest.
pub fn dme_include_order_controlled<C:crate::key_policy_control::Control>(text:&str,had_bom:bool,control:&mut C)->Result<std::collections::HashMap<String,usize>,C::Error>{
    let mut out=std::collections::HashMap::new();
    for(index,line)in text.lines().enumerate(){
        control.checkpoint()?;
        if index==0&&had_bom{continue}
        let line=line.trim();let Some(rest)=line.strip_prefix("#include")else{continue};let rest=rest.trim();let Some(path)=rest.strip_prefix('"').and_then(|r|r.split('"').next())else{continue};
        crate::key_policy_control::reserve(control,||path.len().checked_mul(4)?.checked_add(128))?;
        let rel=path.replace('\\',"/");
        if C::CHECKED&&rel.capacity()>path.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||control.overflow())?{return Err(control.allocation_failed())}
        if C::CHECKED&&!out.contains_key(&rel)&&out.len()==out.capacity(){
            let target=out.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||control.overflow())?;let bound=target.checked_mul(4).ok_or_else(||control.overflow())?;
            let bytes=bound.checked_mul(std::mem::size_of::<(String,usize)>()+2*std::mem::size_of::<usize>()).and_then(|n|n.checked_add(256)).ok_or_else(||control.overflow())?;control.reserve(bytes)?;
            out.try_reserve(1).map_err(|_|control.allocation_failed())?;if out.capacity()>bound{return Err(control.allocation_failed())}
        }
        let n=out.len();out.entry(rel).or_insert(n);
    }
    control.checkpoint()?;Ok(out)
}

pub fn block_extent(text: &str, close: usize) -> Option<usize> {
    let rest = &text[close + 1..];
    let eol = rest.find('\n').unwrap_or(rest.len());
    if !rest[..eol].trim().is_empty() {
        return None;
    }
    let mut pos = close + 1 + eol;
    let mut end: Option<usize> = None;
    while pos < text.len() {
        // `pos` is at a newline; the next line starts after it.
        let ls = pos + 1;
        if ls > text.len() {
            break;
        }
        let le = text[ls..].find('\n').map(|i| ls + i).unwrap_or(text.len());
        let line = &text[ls..le];
        if line.trim().is_empty() {
            pos = le;
            continue;
        }
        if !line.starts_with(|c: char| c.is_whitespace()) {
            break;
        }
        end = Some(ls + line.trim_end().len());
        pos = le;
    }
    end
}

/// The marker body of a block: `text[from..end]` with the header's `)` and each top-level entry-ending newline replaced by a comma
/// (same length, so offsets and lines are unchanged). The engine then reads one argument list in either form.
pub fn block_body(text: &str, from: usize, close: usize, end: usize) -> String {
    let b = text.as_bytes();
    let mut out: Vec<u8> = b[from..end].to_vec();
    out[close - from] = b',';
    let mut depth = 0i32;
    let mut in_str = false;
    let mut pending: Option<usize> = None; // the last depth-0 newline since the previous entry's text
    let mut seen_entry = false;
    let mut i = close + 1;
    while i < end {
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if depth == 0 && !c.is_ascii_whitespace() {
            // An entry starts here: the newline before it ended the previous one.
            if let Some(nl) = pending.take() {
                if seen_entry {
                    out[nl - from] = b',';
                }
            }
            seen_entry = true;
        }
        match c {
            b'"' => in_str = true,
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth -= 1,
            b'\n' if depth == 0 => pending = Some(i),
            _ => {}
        }
        i += 1;
    }
    String::from_utf8(out).unwrap_or_default()
}

/// Original unique declaration DSL marker, not a compiler type/procedure model.
pub const ENTRY_PROC:&str="ENTRY_PROC";

pub fn stages_op_args(body:&str)->Vec<String>{
    match stages_op_args_controlled(body,&mut crate::key_policy_control::Compatibility){Ok(rows)=>rows,Err(never)=>match never{}}
}
pub fn stages_op_args_controlled<C:crate::key_policy_control::Control>(body:&str,c:&mut C)->Result<Vec<String>,C::Error>{
    use crate::key_policy_control as kc;
    c.checkpoint()?;kc::split(c,body.len())?;
    let args=split_args(body);if args.len()<2{return Ok(Vec::new())}
    let var=args[0].trim();let var_name=var.strip_prefix("nameof(").and_then(|s|s.strip_suffix(')')).unwrap_or(var).trim().trim_matches('"');
    let var_name=var_name.rsplit(|c|c==':'||c=='.'||c=='/').next().unwrap_or(var_name);
    let var_name=kc::own(c,var_name)?;let mut out=Vec::new();
    for step in &args[1..]{
        c.checkpoint()?;let step=step.trim();let Some(inner)=step.strip_prefix("stage_step(").and_then(|s|s.strip_suffix(')'))else{continue};
        kc::split(c,inner.len())?;let parts=split_args(inner);if parts.len()<2{continue}
        let(from,to)=(parts[0].trim(),parts[1].trim());
        let mut key=kc::format(c,format_args!("\"{}_{}_{}\"",var_name,from.trim_matches('"'),to.trim_matches('"')))?;
        let mut rest=Vec::new();
        for p in &parts[2..]{
            c.checkpoint()?;let p=p.trim();match p.split_once('='){
                Some((name,value))if name.trim()=="key"&&!p.contains('(')=>key=kc::own(c,value.trim())?,
                _=>{kc::row(c,&mut rest)?;rest.push(kc::own(c,p)?);}
            }
        }
        let mut op=Vec::new();kc::row(c,&mut op)?;op.push(key);
        kc::row(c,&mut op)?;op.push(kc::format(c,format_args!("when(req_stage({}, {}))",var,from))?);
        kc::row(c,&mut op)?;op.push(kc::format(c,format_args!("sets({}, {})",var,to))?);
        for value in rest{kc::row(c,&mut op)?;op.push(value);}
        kc::reserve(c,||op.iter().try_fold(0usize,|n,v|n.checked_add(v.len()))?.checked_add(op.len().saturating_sub(1).checked_mul(2)?)?.checked_mul(2)?.checked_add(128))?;
        let joined=op.join(", ");kc::row(c,&mut out)?;out.push(joined);
    }
    c.checkpoint()?;Ok(out)
}

fn marker_word(b:u8)->bool { b.is_ascii_alphanumeric() || b == b'_' }
pub fn marker_named_vars(body:&str)->Vec<String>{match marker_named_vars_admitted(body,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub fn marker_named_vars_admitted<C:crate::key_policy_control::Control>(body:&str,control:&mut C)->Result<Vec<String>,C::Error>{
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(at) = body[from..].find("nameof(") {
        control.checkpoint()?;
        let start = from + at;
        from = start + 7;
        if start > 0 && marker_word(body.as_bytes()[start - 1]) {
            continue;
        }
        let Some(close) = matching_paren(body, start + 6) else { continue };
        let name = body[start + 7..close].trim();
        if !name.is_empty() && name.bytes().all(marker_word) {
            crate::key_policy_control::row(control,&mut out)?;out.push(crate::key_policy_control::own(control,name)?);
        }
    }
    control.checkpoint()?;Ok(out)
}

#[cfg(test)]mod borrowed_argument_tests{fn original_split_args(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    let mut in_str = false;
    let mut prev = '\0';
    for c in s.chars() {
        if in_str {
            cur.push(c);
            if c == '"' && prev != '\\' {
                in_str = false;
            }
            prev = c;
            continue;
        }
        match c {
            '"' => {
                in_str = true;
                cur.push(c);
            }
            '(' | '[' | '{' => {
                depth += 1;
                cur.push(c);
            }
            ')' | ']' | '}' => {
                depth -= 1;
                cur.push(c);
            }
            ',' if depth == 0 => {
                out.push(cur.trim().to_string());
                cur.clear();
            }
            _ => cur.push(c),
        }
        prev = c;
    }
    let last = cur.trim().to_string();
    if !last.is_empty() || !out.is_empty() {
        out.push(last);
    }
    out
}

#[test]fn borrowed_argument_slices_preserve_exact_original_splitter(){for text in ["",",",",,","  ","a,","(a,b),[x,y],{z,q}","\"a,b\", c","α,\tβ,\"x\\\"y,z\"", ")a,b","a, "]{assert_eq!(super::split_args(text),original_split_args(text));}}}
