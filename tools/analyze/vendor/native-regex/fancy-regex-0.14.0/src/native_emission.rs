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

//! The original easy-expression serializer with actual checked String growth.
use crate::{Expr,Assertion,Result,is_special};
use alloc::string::String;
use regex_syntax::native_admission::Hook;
fn append_char(buf:&mut String,value:char,hook:&Hook<'_>)->Result<()>{let mut bytes=[0;4];hook.append(buf,value.encode_utf8(&mut bytes))?;Ok(())}
fn number(buf:&mut String,value:usize,hook:&Hook<'_>)->Result<()>{if value>=10{number(buf,value/10,hook)?}append_char(buf,(b'0'+(value%10)as u8)as char,hook)}
fn quoted(buf:&mut String,value:&str,hook:&Hook<'_>)->Result<()>{for ch in value.chars(){hook.checkpoint()?;if is_special(ch){append_char(buf,'\\',hook)?}append_char(buf,ch,hook)?}Ok(())}
pub(crate) fn emit(expr:&Expr,buf:&mut String,precedence:u8,hook:&Hook<'_>)->Result<()>{
 hook.checkpoint()?;
        match *expr {
            Expr::Empty => (),
            Expr::Any { newline } => hook.append(buf,if newline { "(?s:.)" } else { "." })?,
            Expr::Literal { ref val, casei } => {
                if casei {
                    hook.append(buf,"(?i:")?;
                }
                quoted(buf,val,hook)?;
                if casei {
                    hook.append(buf,")")?;
                }
            }
            Expr::Assertion(Assertion::StartText) => append_char(buf,'^',hook)?,
            Expr::Assertion(Assertion::EndText) => append_char(buf,'$',hook)?,
            Expr::Assertion(Assertion::StartLine { crlf: false }) => hook.append(buf,"(?m:^)")?,
            Expr::Assertion(Assertion::EndLine { crlf: false }) => hook.append(buf,"(?m:$)")?,
            Expr::Assertion(Assertion::StartLine { crlf: true }) => hook.append(buf,"(?Rm:^)")?,
            Expr::Assertion(Assertion::EndLine { crlf: true }) => hook.append(buf,"(?Rm:$)")?,
            Expr::Concat(ref children) => {
                if precedence > 1 {
                    hook.append(buf,"(?:")?;
                }
                for child in children {
                    emit(child,buf,2,hook)?;
                }
                if precedence > 1 {
                    append_char(buf,')',hook)?
                }
            }
            Expr::Alt(ref children) => {
                if precedence > 0 {
                    hook.append(buf,"(?:")?;
                }
                for (i, child) in children.iter().enumerate() {
                    if i != 0 {
                        append_char(buf,'|',hook)?;
                    }
                    emit(child,buf,1,hook)?;
                }
                if precedence > 0 {
                    append_char(buf,')',hook)?;
                }
            }
            Expr::Group(ref child) => {
                append_char(buf,'(',hook)?;
                emit(child,buf,0,hook)?;
                append_char(buf,')',hook)?;
            }
            Expr::Repeat {
                ref child,
                lo,
                hi,
                greedy,
            } => {
                if precedence > 2 {
                    hook.append(buf,"(?:")?;
                }
                emit(child,buf,3,hook)?;
                match (lo, hi) {
                    (0, 1) => append_char(buf,'?',hook)?,
                    (0, usize::MAX) => append_char(buf,'*',hook)?,
                    (1, usize::MAX) => append_char(buf,'+',hook)?,
                    (lo, hi) => {
                        append_char(buf,'{',hook)?;
                        number(buf,lo,hook)?;
                        if lo != hi {
                            append_char(buf,',',hook)?;
                            if hi != usize::MAX {
                                number(buf,hi,hook)?;
                            }
                        }
                        append_char(buf,'}',hook)?;
                    }
                }
                if !greedy {
                    append_char(buf,'?',hook)?;
                }
                if precedence > 2 {
                    append_char(buf,')',hook)?;
                }
            }
            Expr::Delegate {
                ref inner, casei, ..
            } => {
                // at the moment, delegate nodes are just atoms
                if casei {
                    hook.append(buf,"(?i:")?;
                }
                hook.append(buf,inner)?;
                if casei {
                    hook.append(buf,")")?;
                }
            }
            _ => panic!("attempting to format hard expr"),
        }
    Ok(())
}
