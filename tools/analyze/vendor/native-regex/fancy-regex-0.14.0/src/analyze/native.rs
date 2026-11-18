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

//! Same pinned analyzer, with each actual child row admitted before growth.
use super::*;
use regex_syntax::native_admission::Hook;
struct NativeAnalyzer<'a,'h>{backrefs:&'a BitSet,group_ix:usize,hook:&'h Hook<'h>}
impl<'a,'h> NativeAnalyzer<'a,'h> {
    fn visit(&mut self, expr: &'a Expr) -> Result<Info<'a>> {
        self.hook.checkpoint()?;
        let start_group = self.group_ix;
        let mut children = Vec::new();
        let mut min_size = 0;
        let mut const_size = false;
        let mut hard = false;
        match *expr {
            Expr::Assertion(assertion) if assertion.is_hard() => {
                const_size = true;
                hard = true;
            }
            Expr::Empty | Expr::Assertion(_) => {
                const_size = true;
            }
            Expr::Any { .. } => {
                min_size = 1;
                const_size = true;
            }
            Expr::Literal { ref val, casei } => {
                // right now each character in a literal gets its own node, that might change
                min_size = 1;
                const_size = literal_const_size(val, casei);
            }
            Expr::Concat(ref v) => {
                const_size = true;
                for child in v {
                    let child_info = self.visit(child)?;
                    min_size += child_info.min_size;
                    const_size &= child_info.const_size;
                    hard |= child_info.hard;
                    self.hook.push(&mut children,child_info)?;
                }
            }
            Expr::Alt(ref v) => {
                let child_info = self.visit(&v[0])?;
                min_size = child_info.min_size;
                const_size = child_info.const_size;
                hard = child_info.hard;
                self.hook.push(&mut children,child_info)?;
                for child in &v[1..] {
                    let child_info = self.visit(child)?;
                    const_size &= child_info.const_size && min_size == child_info.min_size;
                    min_size = min(min_size, child_info.min_size);
                    hard |= child_info.hard;
                    self.hook.push(&mut children,child_info)?;
                }
            }
            Expr::Group(ref child) => {
                let group = self.group_ix;
                self.group_ix += 1;
                let child_info = self.visit(child)?;
                min_size = child_info.min_size;
                const_size = child_info.const_size;
                // If there's a backref to this group, we potentially have to backtrack within the
                // group. E.g. with `(x|xy)\1` and input `xyxy`, `x` matches but then the backref
                // doesn't, so we have to backtrack and try `xy`.
                hard = child_info.hard | self.backrefs.contains(group);
                self.hook.push(&mut children,child_info)?;
            }
            Expr::LookAround(ref child, _) => {
                let child_info = self.visit(child)?;
                // min_size = 0
                const_size = true;
                hard = true;
                self.hook.push(&mut children,child_info)?;
            }
            Expr::Repeat {
                ref child, lo, hi, ..
            } => {
                let child_info = self.visit(child)?;
                min_size = child_info.min_size * lo;
                const_size = child_info.const_size && lo == hi;
                hard = child_info.hard;
                self.hook.push(&mut children,child_info)?;
            }
            Expr::Delegate { size, .. } => {
                // currently only used for empty and single-char matches
                min_size = size;
                const_size = true;
            }
            Expr::Backref(group) => {
                if group >= self.group_ix {
                    return Err(Error::CompileError(CompileError::InvalidBackref));
                }
                hard = true;
            }
            Expr::AtomicGroup(ref child) => {
                let child_info = self.visit(child)?;
                min_size = child_info.min_size;
                const_size = child_info.const_size;
                hard = true; // TODO: possibly could weaken
                self.hook.push(&mut children,child_info)?;
            }
            Expr::KeepOut => {
                hard = true;
                const_size = true;
            }
            Expr::ContinueFromPreviousMatchEnd => {
                hard = true;
                const_size = true;
            }
            Expr::BackrefExistsCondition(group) => {
                if group >= self.group_ix {
                    return Err(Error::CompileError(CompileError::InvalidBackref));
                }
                hard = true;
                const_size = true;
            }
            Expr::Conditional {
                ref condition,
                ref true_branch,
                ref false_branch,
            } => {
                hard = true;

                let child_info_condition = self.visit(condition)?;
                let child_info_truth = self.visit(true_branch)?;
                let child_info_false = self.visit(false_branch)?;

                min_size = child_info_condition.min_size
                    + min(child_info_truth.min_size, child_info_false.min_size);
                const_size = child_info_condition.const_size
                    && child_info_truth.const_size
                    && child_info_false.const_size
                    // if the condition's size plus the truth branch's size is equal to the false branch's size then it's const size
                    && child_info_condition.min_size + child_info_truth.min_size == child_info_false.min_size;

                self.hook.push(&mut children,child_info_condition)?;
                self.hook.push(&mut children,child_info_truth)?;
                self.hook.push(&mut children,child_info_false)?;
            }
        };

        Ok(Info {
            expr,
            children,
            start_group,
            end_group: self.group_ix,
            min_size,
            const_size,
            hard,
        })
    }
}

pub(crate) fn analyze<'a,'h>(tree:&'a crate::parse::native::NativeExprTree,hook:&'h Hook<'h>)->Result<Info<'a>>{
 hook.require_active()?;NativeAnalyzer{backrefs:&tree.backrefs,group_ix:0,hook}.visit(&tree.expr)
}
pub(crate) fn push_literal(info:&Info<'_>,buf:&mut String,hook:&Hook<'_>)->Result<()>{
 hook.checkpoint()?;match info.expr{
 Expr::Literal{val,..}=>hook.append(buf,val)?,
 Expr::Concat(_)=>for child in &info.children{push_literal(child,buf,hook)?},
 _=>panic!("push_literal called on non-literal"),
 }Ok(())
}
