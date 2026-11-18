//! Native checked ports of the pinned HIR smart constructors.
use super::*;
use crate::native_admission::{Hook,Refused};
type Result<T>=core::result::Result<T,Refused>;

fn property(hook:&Hook<'_>)->Result<()>{hook.reserve(||core::mem::size_of::<PropertiesI>().checked_add(64))}
pub(super)fn retained_cleanup_bytes()->Option<usize>{core::mem::size_of::<Hir>().checked_mul(4)?.checked_add(core::mem::size_of::<PropertiesI>())?.checked_add(128)}
fn constructed(hook:&Hook<'_>)->Result<()>{
    // Existing Hir::drop uses a geometric Vec<Hir> plus one replacement
    // Properties box per capture/repetition. Every real constructed owner
    // prepays its share before publication, including after later failure.
    hook.reserve(retained_cleanup_bytes)
}
pub(crate) fn empty(hook:&Hook<'_>)->Result<Hir>{property(hook)?;constructed(hook)?;Ok(Hir::empty())}
pub(crate) fn fail(hook:&Hook<'_>)->Result<Hir>{property(hook)?;constructed(hook)?;Ok(Hir::fail())}
pub(crate) fn look(value:Look,hook:&Hook<'_>)->Result<Hir>{property(hook)?;constructed(hook)?;Ok(Hir::look(value))}
pub(crate) fn literal(bytes:Vec<u8>,hook:&Hook<'_>)->Result<Hir>{
    // Vec::into_boxed_slice can shrink into a new exact backing while the
    // already-owned Vec still exists. Fund that actual extent first.
    if bytes.len()!=bytes.capacity(){hook.reserve(||bytes.len().checked_add(64))?;}
    property(hook)?;constructed(hook)?;Ok(Hir::literal(bytes))
}
pub(crate) fn class(value:Class,hook:&Hook<'_>)->Result<Hir>{
    if value.is_empty(){return fail(hook)}
    // Class::literal only creates a Vec for one scalar/byte (at most UTF8's
    // four bytes); the non-singleton branch creates no backing.
    hook.reserve(||Some(4+64))?;
    if let Some(bytes)=value.literal(){return literal(bytes,hook)}
    property(hook)?;constructed(hook)?;
    let props=Properties::class(&value);Ok(Hir{kind:HirKind::Class(value),props})
}
pub(crate) fn repetition(rep:Repetition,hook:&Hook<'_>)->Result<Hir>{property(hook)?;constructed(hook)?;Ok(Hir::repetition(rep))}
pub(crate) fn capture(value:Capture,hook:&Hook<'_>)->Result<Hir>{property(hook)?;constructed(hook)?;Ok(Hir::capture(value))}
pub(crate) fn boxed(value:Hir,hook:&Hook<'_>)->Result<Box<Hir>>{hook.reserve(||core::mem::size_of::<Hir>().checked_add(64))?;Ok(Box::new(value))}
fn literal_copy(bytes:&[u8],hook:&Hook<'_>)->Result<Vec<u8>>{let mut out=Vec::new();hook.room(&mut out,bytes.len())?;out.extend_from_slice(bytes);Ok(out)}
fn literal_append(bytes:&mut Vec<u8>,extra:&[u8],hook:&Hook<'_>)->Result<()>{hook.room(bytes,extra.len())?;bytes.extend_from_slice(extra);Ok(())}
fn parts(value:Hir,hook:&Hook<'_>)->Result<(HirKind,Properties)>{
    // The original safe into_parts allocates exactly one Properties::empty
    // replacement. Preserve it, admitting its actual typed box first.
    property(hook)?;Ok(value.into_parts())
}
pub(crate) fn concat(subs:Vec<Hir>,hook:&Hook<'_>)->Result<Hir>{
    hook.checkpoint()?;
        // We rebuild the concatenation by simplifying it. Would be nice to do
        // it in place, but that seems a little tricky?
        let mut new = vec![];
        // This gobbles up any adjacent literals in a concatenation and smushes
        // them together. Basically, when we see a literal, we add its bytes
        // to 'prior_lit', and whenever we see anything else, we first take
        // any bytes in 'prior_lit' and add it to the 'new' concatenation.
        let mut prior_lit: Option<Vec<u8>> = None;
        for sub in subs {
            hook.checkpoint()?;
            let (kind, props) = parts(sub,hook)?;
            match kind {
                HirKind::Literal(Literal(bytes)) => {
                    if let Some(ref mut prior_bytes) = prior_lit {
                        literal_append(prior_bytes,&bytes,hook)?;
                    } else {
                        prior_lit = Some(literal_copy(&bytes,hook)?);
                    }
                }
                // We also flatten concats that are direct children of another
                // concat. We only need to do this one level deep since
                // Hir::concat is the only way to build concatenations, and so
                // flattening happens inductively.
                HirKind::Concat(subs2) => {
                    for sub2 in subs2 {
                        hook.checkpoint()?;
                        let (kind2, props2) = parts(sub2,hook)?;
                        match kind2 {
                            HirKind::Literal(Literal(bytes)) => {
                                if let Some(ref mut prior_bytes) = prior_lit {
                                    literal_append(prior_bytes,&bytes,hook)?;
                                } else {
                                    prior_lit = Some(literal_copy(&bytes,hook)?);
                                }
                            }
                            kind2 => {
                                if let Some(prior_bytes) = prior_lit.take() {
                                    hook.push(&mut new,literal(prior_bytes,hook)?)?;
                                }
                                hook.push(&mut new,Hir { kind: kind2, props: props2 })?;
                            }
                        }
                    }
                }
                // We can just skip empty HIRs.
                HirKind::Empty => {}
                kind => {
                    if let Some(prior_bytes) = prior_lit.take() {
                        hook.push(&mut new,literal(prior_bytes,hook)?)?;
                    }
                    hook.push(&mut new,Hir { kind, props })?;
                }
            }
        }
        if let Some(prior_bytes) = prior_lit.take() {
            hook.push(&mut new,literal(prior_bytes,hook)?)?;
        }
        if new.is_empty() {
            return empty(hook);
        } else if new.len() == 1 {
            return Ok(new.pop().unwrap());
        }
        property(hook)?;constructed(hook)?;
        let props = Properties::concat(&new);
        Ok(Hir { kind: HirKind::Concat(new), props })
    }
pub(crate) fn dot(dot:Dot,hook:&Hook<'_>)->Result<Hir>{
    hook.checkpoint()?;
        match dot {
            Dot::AnyChar => class(Class::Unicode(ClassUnicode::new_admitted([
                ClassUnicodeRange::new('\0', '\u{10FFFF}'),
            ],hook)?),hook),
            Dot::AnyByte => class(Class::Bytes(ClassBytes::new_admitted([
                ClassBytesRange::new(b'\0', b'\xFF'),
            ],hook)?),hook),
            Dot::AnyCharExcept(ch) => {
                let mut cls =
                    ClassUnicode::new_admitted([ClassUnicodeRange::new(ch, ch)],hook)?;
                cls.negate_admitted(hook)?;
                class(Class::Unicode(cls),hook)
            }
            Dot::AnyCharExceptLF => {
                class(Class::Unicode(ClassUnicode::new_admitted([
                    ClassUnicodeRange::new('\0', '\x09'),
                    ClassUnicodeRange::new('\x0B', '\u{10FFFF}'),
                ],hook)?),hook)
            }
            Dot::AnyCharExceptCRLF => {
                class(Class::Unicode(ClassUnicode::new_admitted([
                    ClassUnicodeRange::new('\0', '\x09'),
                    ClassUnicodeRange::new('\x0B', '\x0C'),
                    ClassUnicodeRange::new('\x0E', '\u{10FFFF}'),
                ],hook)?),hook)
            }
            Dot::AnyByteExcept(byte) => {
                let mut cls =
                    ClassBytes::new_admitted([ClassBytesRange::new(byte, byte)],hook)?;
                cls.negate_admitted(hook)?;
                class(Class::Bytes(cls),hook)
            }
            Dot::AnyByteExceptLF => {
                class(Class::Bytes(ClassBytes::new_admitted([
                    ClassBytesRange::new(b'\0', b'\x09'),
                    ClassBytesRange::new(b'\x0B', b'\xFF'),
                ],hook)?),hook)
            }
            Dot::AnyByteExceptCRLF => {
                class(Class::Bytes(ClassBytes::new_admitted([
                    ClassBytesRange::new(b'\0', b'\x09'),
                    ClassBytesRange::new(b'\x0B', b'\x0C'),
                    ClassBytesRange::new(b'\x0E', b'\xFF'),
                ],hook)?),hook)
            }
        }
    }

fn singleton_chars(hirs:&[Hir],hook:&Hook<'_>)->Result<Option<Vec<char>>>{
    let mut out=Vec::new();for h in hirs{hook.checkpoint()?;
        let HirKind::Literal(Literal(bytes))=h.kind()else{return Ok(None)};
        let Some(Ok(ch))=crate::debug::utf8_decode(bytes)else{return Ok(None)};
        if bytes.len()!=ch.len_utf8(){return Ok(None)}hook.push(&mut out,ch)?;
    }Ok(Some(out))
}
fn singleton_bytes(hirs:&[Hir],hook:&Hook<'_>)->Result<Option<Vec<u8>>>{
    let mut out=Vec::new();for h in hirs{hook.checkpoint()?;
        let HirKind::Literal(Literal(bytes))=h.kind()else{return Ok(None)};
        if bytes.len()!=1{return Ok(None)}hook.push(&mut out,bytes[0])?;
    }Ok(Some(out))
}
fn class_chars(hirs:&[Hir],hook:&Hook<'_>)->Result<Option<Class>>{
    let mut out=ClassUnicode::empty();for h in hirs{hook.checkpoint()?;match h.kind(){
        HirKind::Class(Class::Unicode(other))=>out.union_admitted(other,hook)?,
        HirKind::Class(Class::Bytes(other))=>{
            if !other.is_ascii(){return Ok(None)}
            let actual=ClassUnicode::new_admitted(other.ranges().iter().map(|r|ClassUnicodeRange::new(char::from(r.start),char::from(r.end))),hook)?;
            out.union_admitted(&actual,hook)?;
        },_=>return Ok(None),
    }}Ok(Some(Class::Unicode(out)))
}
fn class_bytes(hirs:&[Hir],hook:&Hook<'_>)->Result<Option<Class>>{
    let mut out=ClassBytes::empty();for h in hirs{hook.checkpoint()?;match h.kind(){
        HirKind::Class(Class::Bytes(other))=>out.union_admitted(other,hook)?,
        HirKind::Class(Class::Unicode(other))=>{
            if !other.is_ascii(){return Ok(None)}
            let actual=ClassBytes::new_admitted(other.ranges().iter().map(|r|ClassBytesRange::new(u8::try_from(r.start).unwrap(),u8::try_from(r.end).unwrap())),hook)?;
            out.union_admitted(&actual,hook)?;
        },_=>return Ok(None),
    }}Ok(Some(Class::Bytes(out)))
}
pub(crate) fn alternation(subs:Vec<Hir>,hook:&Hook<'_>)->Result<Hir>{
    hook.checkpoint()?;
        // We rebuild the alternation by simplifying it. We proceed similarly
        // as the concatenation case. But in this case, there's no literal
        // simplification happening. We're just flattening alternations.
        let mut new=Vec::new();hook.room(&mut new,subs.len())?;
        for sub in subs {
            hook.checkpoint()?;
            let (kind, props) = parts(sub,hook)?;
            match kind {
                HirKind::Alternation(subs2) => {
                    hook.room(&mut new,subs2.len())?;new.extend(subs2);
                }
                kind => {
                    hook.push(&mut new,Hir { kind, props })?;
                }
            }
        }
        if new.is_empty() {
            return fail(hook);
        } else if new.len() == 1 {
            return Ok(new.pop().unwrap());
        }
        // Now that it's completely flattened, look for the special case of
        // 'char1|char2|...|charN' and collapse that into a class. Note that
        // we look for 'char' first and then bytes. The issue here is that if
        // we find both non-ASCII codepoints and non-ASCII singleton bytes,
        // then it isn't actually possible to smush them into a single class.
        // (Because classes are either "all codepoints" or "all bytes." You
        // can have a class that both matches non-ASCII but valid UTF-8 and
        // invalid UTF-8.) So we look for all chars and then all bytes, and
        // don't handle anything else.
        if let Some(singletons) = singleton_chars(&new,hook)? {
            let it = singletons
                .into_iter()
                .map(|ch| ClassUnicodeRange { start: ch, end: ch });
            return class(Class::Unicode(ClassUnicode::new_admitted(it,hook)?),hook);
        }
        if let Some(singletons) = singleton_bytes(&new,hook)? {
            let it = singletons
                .into_iter()
                .map(|b| ClassBytesRange { start: b, end: b });
            return class(Class::Bytes(ClassBytes::new_admitted(it,hook)?),hook);
        }
        // Similar to singleton chars, we can also look for alternations of
        // classes. Those can be smushed into a single class.
        if let Some(cls) = class_chars(&new,hook)? {
            return class(cls,hook);
        }
        if let Some(cls) = class_bytes(&new,hook)? {
            return class(cls,hook);
        }
        // Factor out a common prefix if we can, which might potentially
        // simplify the expression and unlock other optimizations downstream.
        // It also might generally make NFA matching and DFA construction
        // faster by reducing the scope of branching in the regex.
        new = match lift_common_prefix(new,hook)? {
            Ok(hir) => return Ok(hir),
            Err(unchanged) => unchanged,
        };
        property(hook)?;constructed(hook)?;let props = Properties::alternation(&new);
        Ok(Hir { kind: HirKind::Alternation(new), props })
    }

fn lift_common_prefix(hirs:Vec<Hir>,hook:&Hook<'_>)->Result<core::result::Result<Hir,Vec<Hir>>>{
    if hirs.len()<=1{return Ok(Err(hirs))}
    let mut prefix=match hirs[0].kind(){HirKind::Concat(xs)=>&**xs,_=>return Ok(Err(hirs))};
    if prefix.is_empty(){return Ok(Err(hirs))}
    for h in hirs.iter().skip(1){hook.checkpoint()?;
        let HirKind::Concat(xs)=h.kind()else{return Ok(Err(hirs))};
        let common_len=prefix.iter().zip(xs.iter()).take_while(|(x,y)|x==y).count();
        prefix=&prefix[..common_len];if prefix.is_empty(){return Ok(Err(hirs))}
    }
    let len=prefix.len();assert_ne!(0,len);let mut prefix_concat=Vec::new();let mut suffix_alts=Vec::new();
    for h in hirs{hook.checkpoint()?;
        let HirKind::Concat(mut children)=h.into_kind()else{unreachable!()};
        // Vec::split_off owns this exact tail while the original backing
        // remains live. Admission precedes the pinned original split.
        hook.reserve(||children.len().checked_sub(len)?.checked_mul(core::mem::size_of::<Hir>())?.checked_add(64))?;
        let tail=children.split_off(len);hook.push(&mut suffix_alts,concat(tail,hook)?)?;
        if prefix_concat.is_empty(){prefix_concat=children}
    }
    let mut children=prefix_concat;hook.push(&mut children,alternation(suffix_alts,hook)?)?;
    Ok(Ok(concat(children,hook)?))
}
