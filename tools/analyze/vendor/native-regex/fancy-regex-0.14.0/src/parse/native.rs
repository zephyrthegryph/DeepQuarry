// Copyright 2016 The Fancy Regex Authors.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

//! Same pinned Fancy grammar with explicit resource-bearing containers.
use super::*;
use regex_syntax::native_admission::Hook;
#[derive(Debug)]
pub(crate) struct NativeExprTree{pub(crate) expr:Expr,pub(crate) backrefs:BitSet,pub(crate) named_groups:Vec<(String,usize)>}
struct NativeParser<'a>{re:&'a str,backrefs:BitSet,flags:u32,named_groups:Vec<(String,usize)>,numeric_backrefs:bool,curr_group:usize,hook:Hook<'a>}
impl<'a> NativeParser<'a>{

    fn boxed(&self,value:Expr)->Result<Box<Expr>>{self.hook.reserve(||core::mem::size_of::<Expr>().checked_add(64))?;Ok(Box::new(value))}
    fn append_char(&self,out:&mut String,value:char)->Result<()>{let mut buffer=[0;4];self.hook.append(out,value.encode_utf8(&mut buffer))?;Ok(())}
    fn escape_into(&self,value:&str,out:&mut String)->Result<()>{
        let need=value.len().checked_mul(2).ok_or_else(||self.hook.overflow())?;
        self.hook.string_room(out,need)?;regex_syntax::escape_into(value,out);Ok(())
    }
    fn make_literal(&self,value:&str)->Result<Expr>{Ok(Expr::Literal{val:self.hook.text(value)?,casei:false})}
    fn named_insert(names:&mut Vec<(String,usize)>,name:&str,value:usize,hook:&Hook<'_>)->Result<()>{
        hook.checkpoint()?;if let Some((_,prior))=names.iter_mut().find(|(prior,_)|prior==name){*prior=value;return Ok(())}
        let owned=hook.text(name)?;hook.push(names,(owned,value))?;Ok(())
    }
    fn backref_insert(backrefs:&mut BitSet,value:usize,hook:&Hook<'_>)->Result<()>{
        let bits=value.checked_add(1).ok_or_else(||hook.overflow())?;
        if bits>backrefs.capacity(){
            let words=bits.checked_add(31).ok_or_else(||hook.overflow())?/32;
            hook.reserve(||words.checked_mul(core::mem::size_of::<u32>())?.checked_add(64))?;
            backrefs.reserve_len_exact(bits);
            if backrefs.capacity()>words.checked_mul(32).ok_or_else(||hook.overflow())?{return Err(hook.allocation_failed().into())}
        }backrefs.insert(value);Ok(())
    }

    pub(crate) fn parse(re: &'a str,hook:&Hook<'a>) -> Result<NativeExprTree> {
        if !hook.active(){return Err(hook.allocation_failed().into())}hook.checkpoint()?;let mut p=NativeParser::new(re,hook);
        let (ix, expr) = p.parse_re(0, 0)?;
        if ix < re.len() {
            return Err(Error::ParseError(
                ix,
                ParseError::GeneralParseError(hook.text("end of string not reached")?),
            ));
        }
        hook.checkpoint()?;Ok(NativeExprTree {
            expr,
            backrefs: Default::default(),
            named_groups: p.named_groups,
        })
    }

    fn new(re:&'a str,hook:&Hook<'a>)->NativeParser<'a> {
        NativeParser {
            hook:hook.clone(),
            re,
            backrefs: Default::default(),
            named_groups: Default::default(),
            numeric_backrefs: false,
            flags: FLAG_UNICODE,
            curr_group: 0,
        }
    }

    fn parse_re(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        self.hook.checkpoint()?;
        let (ix, child) = self.parse_branch(ix, depth)?;
        let mut ix = self.optional_whitespace(ix)?;
        if self.re[ix..].starts_with('|') {
            let mut children=Vec::new();self.hook.push(&mut children,child)?;
            while self.re[ix..].starts_with('|') {
                ix += 1;
                let (next, child) = self.parse_branch(ix, depth)?;
                self.hook.push(&mut children,child)?;
                ix = self.optional_whitespace(next)?;
            }
            return Ok((ix, Expr::Alt(children)));
        }
        // can't have numeric backrefs and named backrefs
        if self.numeric_backrefs && !self.named_groups.is_empty() {
            return Err(Error::CompileError(CompileError::NamedBackrefOnly));
        }
        Ok((ix, child))
    }

    fn parse_branch(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        let mut children = Vec::new();
        let mut ix = ix;
        while ix < self.re.len() {
            self.hook.checkpoint()?;
            let (next, child) = self.parse_piece(ix, depth)?;
            if next == ix {
                break;
            }
            if child != Expr::Empty {
                self.hook.push(&mut children,child)?;
            }
            ix = next;
        }
        match children.len() {
            0 => Ok((ix, Expr::Empty)),
            1 => Ok((ix, children.pop().unwrap())),
            _ => Ok((ix, Expr::Concat(children))),
        }
    }

    fn parse_piece(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        let (ix, child) = self.parse_atom(ix, depth)?;
        let mut ix = self.optional_whitespace(ix)?;
        if ix < self.re.len() {
            // fail when child is empty?
            let (lo, hi) = match self.re.as_bytes()[ix] {
                b'?' => (0, 1),
                b'*' => (0, usize::MAX),
                b'+' => (1, usize::MAX),
                b'{' => {
                    match self.parse_repeat(ix) {
                        Ok((next, lo, hi)) => {
                            ix = next - 1;
                            (lo, hi)
                        }
                        Err(_) => {
                            // Invalid repeat syntax, which results in `{` being treated as a literal
                            return Ok((ix, child));
                        }
                    }
                }
                _ => return Ok((ix, child)),
            };
            if !self.is_repeatable(&child) {
                return Err(Error::ParseError(ix, ParseError::TargetNotRepeatable));
            }
            ix += 1;
            ix = self.optional_whitespace(ix)?;
            let mut greedy = true;
            if ix < self.re.len() && self.re.as_bytes()[ix] == b'?' {
                greedy = false;
                ix += 1;
            }
            greedy ^= self.flag(FLAG_SWAP_GREED);
            let mut node = Expr::Repeat {
                child: self.boxed(child)?,
                lo,
                hi,
                greedy,
            };
            if ix < self.re.len() && self.re.as_bytes()[ix] == b'+' {
                ix += 1;
                node = Expr::AtomicGroup(self.boxed(node)?);
            }
            return Ok((ix, node));
        }
        Ok((ix, child))
    }

    fn is_repeatable(&self, child: &Expr) -> bool {
        match child {
            Expr::LookAround(_, _) => false,
            Expr::Empty => false,
            Expr::Assertion(_) => false,
            _ => true,
        }
    }

    // ix, lo, hi
    fn parse_repeat(&self, ix: usize) -> Result<(usize, usize, usize)> {
        let ix = self.optional_whitespace(ix + 1)?; // skip opening '{'
        let bytes = self.re.as_bytes();
        if ix == self.re.len() {
            return Err(Error::ParseError(ix, ParseError::InvalidRepeat));
        }
        let mut end = ix;
        let lo = if bytes[ix] == b',' {
            0
        } else if let Some((next, lo)) = parse_decimal(self.re, ix) {
            end = next;
            lo
        } else {
            return Err(Error::ParseError(ix, ParseError::InvalidRepeat));
        };
        let ix = self.optional_whitespace(end)?; // past lo number
        if ix == self.re.len() {
            return Err(Error::ParseError(ix, ParseError::InvalidRepeat));
        }
        end = ix;
        let hi = match bytes[ix] {
            b'}' => lo,
            b',' => {
                end = self.optional_whitespace(ix + 1)?; // past ','
                if let Some((next, hi)) = parse_decimal(self.re, end) {
                    end = next;
                    hi
                } else {
                    usize::MAX
                }
            }
            _ => return Err(Error::ParseError(ix, ParseError::InvalidRepeat)),
        };
        let ix = self.optional_whitespace(end)?; // past hi number
        if ix == self.re.len() || bytes[ix] != b'}' {
            return Err(Error::ParseError(ix, ParseError::InvalidRepeat));
        }
        Ok((ix + 1, lo, hi))
    }

    fn parse_atom(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        let ix = self.optional_whitespace(ix)?;
        if ix == self.re.len() {
            return Ok((ix, Expr::Empty));
        }
        match self.re.as_bytes()[ix] {
            b'.' => Ok((
                ix + 1,
                Expr::Any {
                    newline: self.flag(FLAG_DOTNL),
                },
            )),
            b'^' => Ok((
                ix + 1,
                if self.flag(FLAG_MULTI) {
                    // TODO: support crlf flag
                    Expr::Assertion(Assertion::StartLine { crlf: false })
                } else {
                    Expr::Assertion(Assertion::StartText)
                },
            )),
            b'$' => Ok((
                ix + 1,
                if self.flag(FLAG_MULTI) {
                    // TODO: support crlf flag
                    Expr::Assertion(Assertion::EndLine { crlf: false })
                } else {
                    Expr::Assertion(Assertion::EndText)
                },
            )),
            b'(' => self.parse_group(ix, depth),
            b'\\' => {
                let (next, expr) = self.parse_escape(ix, false)?;
                if let Expr::Backref(group) = expr {
                    Self::backref_insert(&mut self.backrefs,group,&self.hook)?;
                }
                Ok((next, expr))
            }
            b'+' | b'*' | b'?' | b'|' | b')' => Ok((ix, Expr::Empty)),
            b'[' => self.parse_class(ix),
            b => {
                // TODO: maybe want to match multiple codepoints?
                let next = ix + codepoint_len(b);
                Ok((
                    next,
                    Expr::Literal {
                        val: self.hook.text(&self.re[ix..next])?,
                        casei: self.flag(FLAG_CASEI),
                    },
                ))
            }
        }
    }

    fn parse_named_backref(
        &self,
        ix: usize,
        open: &str,
        close: &str,
        allow_relative: bool,
    ) -> Result<(usize, Expr)> {
        if let Some((id, skip)) = parse_id(&self.re[ix..], open, close, allow_relative) {
            let group = if let Some(group) = self.named_groups.iter().find(|(name,_)|name==id).map(|(_,value)|value) {
                Some(*group)
            } else if let Ok(group) = id.parse::<isize>() {
                group.try_into().map_or_else(
                    |_| {
                        // relative backref
                        self.curr_group.checked_add_signed(group + 1)
                    },
                    |group| Some(group),
                )
            } else {
                None
            };
            if let Some(group) = group {
                return Ok((ix + skip, Expr::Backref(group)));
            }
            // here the name is parsed but it is invalid
            Err(Error::ParseError(
                ix,
                ParseError::InvalidGroupNameBackref(self.hook.text(id)?),
            ))
        } else {
            // in this case the name can't be parsed
            Err(Error::ParseError(ix, ParseError::InvalidGroupName))
        }
    }

    fn parse_numbered_backref(&mut self, ix: usize) -> Result<(usize, Expr)> {
        if let Some((end, group)) = parse_decimal(self.re, ix) {
            // protect BitSet against unreasonably large value
            if group < self.re.len() / 2 {
                self.numeric_backrefs = true;
                return Ok((end, Expr::Backref(group)));
            }
        }
        return Err(Error::ParseError(ix, ParseError::InvalidBackref));
    }

    // ix points to \ character
    fn parse_escape(&mut self, ix: usize, in_class: bool) -> Result<(usize, Expr)> {
        let bytes = self.re.as_bytes();
        let Some(b) = bytes.get(ix + 1).copied() else {
            return Err(Error::ParseError(ix, ParseError::TrailingBackslash));
        };
        let end = ix + 1 + codepoint_len(b);
        Ok(if is_digit(b) {
            return self.parse_numbered_backref(ix + 1);
        } else if matches!(b, b'k') && !in_class {
            // Named backref: \k<name>
            if bytes.get(end) == Some(&b'\'') {
                return self.parse_named_backref(end, "'", "'", true);
            } else {
                return self.parse_named_backref(end, "<", ">", true);
            }
        } else if b == b'A' && !in_class {
            (end, Expr::Assertion(Assertion::StartText))
        } else if b == b'z' && !in_class {
            (end, Expr::Assertion(Assertion::EndText))
        } else if b == b'b' && !in_class {
            if bytes.get(end) == Some(&b'{') {
                // Support for \b{...} is not implemented yet
                return Err(Error::ParseError(
                    ix,
                    ParseError::InvalidEscape(self.hook.format(format_args!("\\{}", &self.re[ix + 1..end]))?),
                ));
            }
            (end, Expr::Assertion(Assertion::WordBoundary))
        } else if b == b'B' && !in_class {
            if bytes.get(end) == Some(&b'{') {
                // Support for \b{...} is not implemented yet
                return Err(Error::ParseError(
                    ix,
                    ParseError::InvalidEscape(self.hook.format(format_args!("\\{}", &self.re[ix + 1..end]))?),
                ));
            }
            (end, Expr::Assertion(Assertion::NotWordBoundary))
        } else if b == b'<' && !in_class {
            (end, Expr::Assertion(Assertion::LeftWordBoundary))
        } else if b == b'>' && !in_class {
            (end, Expr::Assertion(Assertion::RightWordBoundary))
        } else if matches!(b | 32, b'd' | b's' | b'w') {
            (
                end,
                Expr::Delegate {
                    inner: self.hook.text(&self.re[ix..end])?,
                    size: 1,
                    casei: self.flag(FLAG_CASEI),
                },
            )
        } else if (b | 32) == b'h' {
            let s = if b == b'h' {
                "[0-9A-Fa-f]"
            } else {
                "[^0-9A-Fa-f]"
            };
            (
                end,
                Expr::Delegate {
                    inner: self.hook.text(s)?,
                    size: 1,
                    casei: false,
                },
            )
        } else if b == b'x' {
            return self.parse_hex(end, 2);
        } else if b == b'u' {
            return self.parse_hex(end, 4);
        } else if b == b'U' {
            return self.parse_hex(end, 8);
        } else if (b | 32) == b'p' && end != bytes.len() {
            let mut end = end;
            let b = bytes[end];
            end += codepoint_len(b);
            if b == b'{' {
                loop {
            self.hook.checkpoint()?;
                    if end == self.re.len() {
                        return Err(Error::ParseError(ix, ParseError::UnclosedUnicodeName));
                    }
                    let b = bytes[end];
                    if b == b'}' {
                        end += 1;
                        break;
                    }
                    end += codepoint_len(b);
                }
            }
            (
                end,
                Expr::Delegate {
                    inner: self.hook.text(&self.re[ix..end])?,
                    size: 1,
                    casei: self.flag(FLAG_CASEI),
                },
            )
        } else if b == b'K' && !in_class {
            (end, Expr::KeepOut)
        } else if b == b'G' && !in_class {
            (end, Expr::ContinueFromPreviousMatchEnd)
        } else {
            // printable ASCII (including space, see issue #29)
            (
                end,
                self.make_literal(match b {
                    b'a' => "\x07", // BEL
                    b'b' => "\x08", // BS
                    b'f' => "\x0c", // FF
                    b'n' => "\n",   // LF
                    b'r' => "\r",   // CR
                    b't' => "\t",   // TAB
                    b'v' => "\x0b", // VT
                    b'e' => "\x1b", // ESC
                    b' ' => " ",
                    b => {
                        let s = &self.re[ix + 1..end];
                        if b.is_ascii_alphabetic()
                            && !matches!(
                                b,
                                b'k' | b'A' | b'z' | b'b' | b'B' | b'<' | b'>' | b'K' | b'G'
                            )
                        {
                            return Err(Error::ParseError(
                                ix,
                                ParseError::InvalidEscape(self.hook.format(format_args!("\\{}", s))?),
                            ));
                        } else {
                            s
                        }
                    }
                })?,
            )
        })
    }

    // ix points after '\x', eg to 'A0' or '{12345}', or after `\u` or `\U`
    fn parse_hex(&self, ix: usize, digits: usize) -> Result<(usize, Expr)> {
        if ix >= self.re.len() {
            // Incomplete escape sequence
            return Err(Error::ParseError(ix, ParseError::InvalidHex));
        }
        let bytes = self.re.as_bytes();
        let b = bytes[ix];
        let (end, s) = if ix + digits <= self.re.len()
            && bytes[ix..ix + digits].iter().all(|&b| is_hex_digit(b))
        {
            let end = ix + digits;
            (end, &self.re[ix..end])
        } else if b == b'{' {
            let starthex = ix + 1;
            let mut endhex = starthex;
            loop {
            self.hook.checkpoint()?;
                if endhex == self.re.len() {
                    return Err(Error::ParseError(ix, ParseError::InvalidHex));
                }
                let b = bytes[endhex];
                if endhex > starthex && b == b'}' {
                    break;
                }
                if is_hex_digit(b) && endhex < starthex + 8 {
                    endhex += 1;
                } else {
                    return Err(Error::ParseError(ix, ParseError::InvalidHex));
                }
            }
            (endhex + 1, &self.re[starthex..endhex])
        } else {
            return Err(Error::ParseError(ix, ParseError::InvalidHex));
        };
        let codepoint = u32::from_str_radix(s, 16).unwrap();
        if let Some(c) = char::from_u32(codepoint) {
            let mut inner=String::new();
            self.append_char(&mut inner,c)?;
            Ok((
                end,
                Expr::Literal {
                    val: inner,
                    casei: self.flag(FLAG_CASEI),
                },
            ))
        } else {
            Err(Error::ParseError(ix, ParseError::InvalidCodepointValue))
        }
    }

    fn parse_class(&mut self, ix: usize) -> Result<(usize, Expr)> {
        let bytes = self.re.as_bytes();
        let mut ix = ix + 1; // skip opening '['
        let mut class = String::new();
        let mut nest = 1;
        self.append_char(&mut class,'[')?;

        // Negated character class
        if bytes.get(ix) == Some(&b'^') {
            self.append_char(&mut class,'^')?;
            ix += 1;
        }

        // `]` does not have to be escaped after opening `[` or `[^`
        if bytes.get(ix) == Some(&b']') {
            self.append_char(&mut class,']')?;
            ix += 1;
        }

        loop {
            self.hook.checkpoint()?;
            if ix == self.re.len() {
                return Err(Error::ParseError(ix, ParseError::InvalidClass));
            }
            let end = match bytes[ix] {
                b'\\' => {
                    // We support more escapes than regex, so parse it ourselves before delegating.
                    let (end, expr) = self.parse_escape(ix, true)?;
                    match expr {
                        Expr::Literal { val, .. } => {
                            debug_assert_eq!(val.chars().count(), 1);
                            self.escape_into(&val,&mut class)?;
                        }
                        Expr::Delegate { inner, .. } => {
                            self.hook.append(&mut class,&inner)?;
                        }
                        _ => {
                            return Err(Error::ParseError(ix, ParseError::InvalidClass));
                        }
                    }
                    end
                }
                b'[' => {
                    nest += 1;
                    self.append_char(&mut class,'[')?;
                    ix + 1
                }
                b']' => {
                    nest -= 1;
                    self.append_char(&mut class,']')?;
                    if nest == 0 {
                        break;
                    }
                    ix + 1
                }
                b => {
                    let end = ix + codepoint_len(b);
                    self.hook.append(&mut class,&self.re[ix..end])?;
                    end
                }
            };
            ix = end;
        }
        let class = Expr::Delegate {
            inner: class,
            size: 1,
            casei: self.flag(FLAG_CASEI),
        };
        let ix = ix + 1; // skip closing ']'
        Ok((ix, class))
    }

    fn parse_group(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        let depth = depth + 1;
        if depth >= MAX_RECURSION {
            return Err(Error::ParseError(ix, ParseError::RecursionExceeded));
        }
        let ix = self.optional_whitespace(ix + 1)?;
        let (la, skip) = if self.re[ix..].starts_with("?=") {
            (Some(LookAhead), 2)
        } else if self.re[ix..].starts_with("?!") {
            (Some(LookAheadNeg), 2)
        } else if self.re[ix..].starts_with("?<=") {
            (Some(LookBehind), 3)
        } else if self.re[ix..].starts_with("?<!") {
            (Some(LookBehindNeg), 3)
        } else if self.re[ix..].starts_with("?<") {
            // Named capture group using Oniguruma syntax: (?<name>...)
            self.curr_group += 1;
            if let Some((id, skip)) = parse_id(&self.re[ix + 1..], "<", ">", false) {
                Self::named_insert(&mut self.named_groups,id,self.curr_group,&self.hook)?;
                (None, skip + 1)
            } else {
                return Err(Error::ParseError(ix, ParseError::InvalidGroupName));
            }
        } else if self.re[ix..].starts_with("?P<") {
            // Named capture group using Python syntax: (?P<name>...)
            self.curr_group += 1; // this is a capture group
            if let Some((id, skip)) = parse_id(&self.re[ix + 2..], "<", ">", false) {
                Self::named_insert(&mut self.named_groups,id,self.curr_group,&self.hook)?;
                (None, skip + 2)
            } else {
                return Err(Error::ParseError(ix, ParseError::InvalidGroupName));
            }
        } else if self.re[ix..].starts_with("?P=") {
            // Backref using Python syntax: (?P=name)
            return self.parse_named_backref(ix + 3, "", ")", false);
        } else if self.re[ix..].starts_with("?>") {
            (None, 2)
        } else if self.re[ix..].starts_with("?(") {
            return self.parse_conditional(ix + 2, depth);
        } else if self.re[ix..].starts_with('?') {
            return self.parse_flags(ix, depth);
        } else {
            self.curr_group += 1; // this is a capture group
            (None, 0)
        };
        let ix = ix + skip;
        let (ix, child) = self.parse_re(ix, depth)?;
        let ix = self.check_for_close_paren(ix)?;
        let result = match (la, skip) {
            (Some(la), _) => Expr::LookAround(self.boxed(child)?, la),
            (None, 2) => Expr::AtomicGroup(self.boxed(child)?),
            _ => Expr::Group(self.boxed(child)?),
        };
        Ok((ix, result))
    }

    fn check_for_close_paren(&self, ix: usize) -> Result<usize> {
        let ix = self.optional_whitespace(ix)?;
        if ix == self.re.len() {
            return Err(Error::ParseError(ix, ParseError::UnclosedOpenParen));
        } else if self.re.as_bytes()[ix] != b')' {
            return Err(Error::ParseError(
                ix,
                ParseError::GeneralParseError(self.hook.text("expected close paren")?),
            ));
        }
        Ok(ix + 1)
    }

    // ix points to `?` in `(?`
    fn parse_flags(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        let start = ix + 1;

        fn unknown_flag(re: &str, start: usize, end: usize, hook: &Hook<'_>) -> Result<Error> {
            let after_end = end + codepoint_len(re.as_bytes()[end]);
            let s = hook.format(format_args!("(?{}", &re[start..after_end]))?;
            Ok(Error::ParseError(start, ParseError::UnknownFlag(s)))
        }

        let mut ix = start;
        let mut neg = false;
        let oldflags = self.flags;
        loop {
            self.hook.checkpoint()?;
            ix = self.optional_whitespace(ix)?;
            if ix == self.re.len() {
                return Err(Error::ParseError(ix, ParseError::UnclosedOpenParen));
            }
            let b = self.re.as_bytes()[ix];
            match b {
                b'i' => self.update_flag(FLAG_CASEI, neg),
                b'm' => self.update_flag(FLAG_MULTI, neg),
                b's' => self.update_flag(FLAG_DOTNL, neg),
                b'U' => self.update_flag(FLAG_SWAP_GREED, neg),
                b'x' => self.update_flag(FLAG_IGNORE_SPACE, neg),
                b'u' => {
                    if neg {
                        return Err(Error::ParseError(ix, ParseError::NonUnicodeUnsupported));
                    }
                }
                b'-' => {
                    if neg {
                        return Err(unknown_flag(self.re, start, ix, &self.hook)?);
                    }
                    neg = true;
                }
                b')' => {
                    if ix == start || neg && ix == start + 1 {
                        return Err(unknown_flag(self.re, start, ix, &self.hook)?);
                    }
                    return Ok((ix + 1, Expr::Empty));
                }
                b':' => {
                    if neg && ix == start + 1 {
                        return Err(unknown_flag(self.re, start, ix, &self.hook)?);
                    }
                    ix += 1;
                    let (ix, child) = self.parse_re(ix, depth)?;
                    if ix == self.re.len() {
                        return Err(Error::ParseError(ix, ParseError::UnclosedOpenParen));
                    } else if self.re.as_bytes()[ix] != b')' {
                        return Err(Error::ParseError(
                            ix,
                            ParseError::GeneralParseError(self.hook.text("expected close paren")?),
                        ));
                    };
                    self.flags = oldflags;
                    return Ok((ix + 1, child));
                }
                _ => return Err(unknown_flag(self.re, start, ix, &self.hook)?),
            }
            ix += 1;
        }
    }

    // ix points to after the last ( in (?(
    fn parse_conditional(&mut self, ix: usize, depth: usize) -> Result<(usize, Expr)> {
        if ix >= self.re.len() {
            return Err(Error::ParseError(ix, ParseError::UnclosedOpenParen));
        }
        let bytes = self.re.as_bytes();
        // get the character after the open paren
        let b = bytes[ix];
        let (mut next, condition) = if is_digit(b) {
            self.parse_numbered_backref(ix)?
        } else if b == b'\'' {
            self.parse_named_backref(ix, "'", "'", true)?
        } else if b == b'<' {
            self.parse_named_backref(ix, "<", ">", true)?
        } else {
            self.parse_re(ix, depth)?
        };
        next = self.check_for_close_paren(next)?;
        let (end, child) = self.parse_re(next, depth)?;
        if end == next {
            // Backreference validity checker
            if let Expr::Backref(group) = condition {
                let after = self.check_for_close_paren(end)?;
                return Ok((after, Expr::BackrefExistsCondition(group)));
            } else {
                return Err(Error::ParseError(
                    end,
                    ParseError::GeneralParseError(
                        self.hook.text("expected conditional to be a backreference or at least an expression for when the condition is true")?
                    )
                ));
            }
        }
        let if_true: Expr;
        let mut if_false: Expr = Expr::Empty;
        if let Expr::Alt(mut alternatives) = child {
            // the truth branch will be the first alternative
            if_true = alternatives.remove(0);
            // if there is only one alternative left, take it out the Expr::Alt
            if alternatives.len() == 1 {
                if_false = alternatives.pop().expect("expected 2 alternatives");
            } else {
                // otherwise the remaining branches become the false branch
                if_false = Expr::Alt(alternatives);
            }
        } else {
            // there is only one branch - the truth branch. i.e. "if" without "else"
            if_true = child;
        }
        let inner_condition = if let Expr::Backref(group) = condition {
            Expr::BackrefExistsCondition(group)
        } else {
            condition
        };

        let after = self.check_for_close_paren(end)?;
        Ok((
            after,
            if if_true == Expr::Empty && if_false == Expr::Empty {
                inner_condition
            } else {
                Expr::Conditional {
                    condition: self.boxed(inner_condition)?,
                    true_branch: self.boxed(if_true)?,
                    false_branch: self.boxed(if_false)?,
                }
            },
        ))
    }

    fn flag(&self, flag: u32) -> bool {
        (self.flags & flag) != 0
    }

    fn update_flag(&mut self, flag: u32, neg: bool) {
        if neg {
            self.flags &= !flag;
        } else {
            self.flags |= flag;
        }
    }

    fn optional_whitespace(&self, mut ix: usize) -> Result<usize> {
        let bytes = self.re.as_bytes();
        loop {
            self.hook.checkpoint()?;
            if ix == self.re.len() {
                return Ok(ix);
            }
            match bytes[ix] {
                b'#' if self.flag(FLAG_IGNORE_SPACE) => {
                    match bytes[ix..].iter().position(|&c| c == b'\n') {
                        Some(x) => ix += x + 1,
                        None => return Ok(self.re.len()),
                    }
                }
                b' ' | b'\r' | b'\n' | b'\t' if self.flag(FLAG_IGNORE_SPACE) => ix += 1,
                b'(' if bytes[ix..].starts_with(b"(?#") => {
                    ix += 3;
                    loop {
            self.hook.checkpoint()?;
                        if ix >= self.re.len() {
                            return Err(Error::ParseError(ix, ParseError::UnclosedOpenParen));
                        }
                        match bytes[ix] {
                            b')' => {
                                ix += 1;
                                break;
                            }
                            b'\\' => ix += 2,
                            _ => ix += 1,
                        }
                    }
                }
                _ => return Ok(ix),
            }
        }
    }
}

pub(crate) fn parse<'a>(pattern:&'a str,hook:&Hook<'a>)->Result<NativeExprTree>{NativeParser::parse(pattern,hook)}

#[cfg(test)]mod unknown_flag_admission_controls{
 use super::*;
 struct Lender{deny:bool,reserves:core::sync::atomic::AtomicUsize}
 impl regex_syntax::native_admission::Admission for Lender{
  fn checkpoint(&self)->core::result::Result<(),regex_syntax::native_admission::Refused>{Ok(())}
  fn reserve(&self,_:usize)->core::result::Result<(),regex_syntax::native_admission::Refused>{self.reserves.fetch_add(1,core::sync::atomic::Ordering::Relaxed);if self.deny{Err(regex_syntax::native_admission::Refused)}else{Ok(())}}
  fn overflow(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
  fn allocation_failed(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
 }
 #[test]fn native_unknown_flag_preserves_original_error_text_and_position_at_every_branch(){
  let lender=alloc::sync::Arc::new(Lender{deny:false,reserves:core::sync::atomic::AtomicUsize::new(0)});let hook=Hook(Some(lender));
  for pattern in ["(?q)","(?--)","(?)","(?-:)"]{
   let old=super::super::Parser::new(pattern).parse_flags(1,0).unwrap_err();
   let actual=NativeParser::new(pattern,&hook).parse_flags(1,0).unwrap_err();
   assert_eq!(alloc::format!("{actual:?}"),alloc::format!("{old:?}"),"{pattern}");
  }
 }
 #[test]fn unknown_flag_format_denial_stays_operational_without_constructing_parse_error(){
  let lender=alloc::sync::Arc::new(Lender{deny:true,reserves:core::sync::atomic::AtomicUsize::new(0)});let hook=Hook(Some(lender.clone()));
  let actual=NativeParser::new("(?q)",&hook).parse_flags(1,0).unwrap_err();
  assert!(matches!(actual,Error::RuntimeError(crate::RuntimeError::NativeAdmissionRefused)));
  assert_eq!(lender.reserves.load(core::sync::atomic::Ordering::Relaxed),1,"first formatting admission refusal must escape without retry/fallback");
 }
}
