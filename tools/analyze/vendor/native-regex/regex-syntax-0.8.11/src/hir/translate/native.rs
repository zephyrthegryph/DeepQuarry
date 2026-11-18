//! Same pinned AST visitor, with explicit native allocation ports.
use super::*;
use alloc::string::String;
use crate::native_admission::{Hook,Refused};
struct NativeTranslatorI<'t,'p>{trans:&'t Translator,pattern:&'p str,hook:&'t Hook<'p>}
impl<'t, 'p> Visitor for NativeTranslatorI<'t, 'p> {
    type Output = Hir;
    type Err = Error;

    fn finish(self) -> Result<Hir> {
        // ... otherwise, we should have exactly one HIR on the stack.
        assert_eq!(self.trans().stack.borrow().len(), 1);
        self.unwrap_expr(self.pop().unwrap())
    }

    fn visit_pre(&mut self, ast: &Ast) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        match *ast {
            Ast::ClassBracketed(_) => {
                if self.flags().unicode() {
                    let cls = hir::ClassUnicode::empty();
                    self.push(HirFrame::ClassUnicode(cls))?;
                } else {
                    let cls = hir::ClassBytes::empty();
                    self.push(HirFrame::ClassBytes(cls))?;
                }
            }
            Ast::Repetition(_) => self.push(HirFrame::Repetition)?,
            Ast::Group(ref x) => {
                let old_flags = x
                    .flags()
                    .map(|ast| self.set_flags(ast))
                    .unwrap_or_else(|| self.flags());
                self.push(HirFrame::Group { old_flags })?;
            }
            Ast::Concat(_) => {
                self.push(HirFrame::Concat)?;
            }
            Ast::Alternation(ref x) => {
                self.push(HirFrame::Alternation)?;
                if !x.asts.is_empty() {
                    self.push(HirFrame::AlternationBranch)?;
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn visit_post(&mut self, ast: &Ast) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        match *ast {
            Ast::Empty(_) => {
                self.push(HirFrame::Expr(self.resource(hir::native::empty(self.hook))?))?;
            }
            Ast::Flags(ref x) => {
                self.set_flags(&x.flags);
                // Flags in the AST are generally considered directives and
                // not actual sub-expressions. However, they can be used in
                // the concrete syntax like `((?i))`, and we need some kind of
                // indication of an expression there, and Empty is the correct
                // choice.
                //
                // There can also be things like `(?i)+`, but we rule those out
                // in the parser. In the future, we might allow them for
                // consistency sake.
                self.push(HirFrame::Expr(self.resource(hir::native::empty(self.hook))?))?;
            }
            Ast::Literal(ref x) => match self.ast_literal_to_scalar(x)? {
                Either::Right(byte) => self.push_byte(byte)?,
                Either::Left(ch) => match self.case_fold_char(x.span, ch)? {
                    None => self.push_char(ch)?,
                    Some(expr) => self.push(HirFrame::Expr(expr))?,
                },
            },
            Ast::Dot(ref span) => {
                self.push(HirFrame::Expr(self.hir_dot(**span)?))?;
            }
            Ast::Assertion(ref x) => {
                self.push(HirFrame::Expr(self.hir_assertion(x)?))?;
            }
            Ast::ClassPerl(ref x) => {
                if self.flags().unicode() {
                    let cls = self.hir_perl_unicode_class(x)?;
                    let hcls = hir::Class::Unicode(cls);
                    self.push(HirFrame::Expr(self.resource(hir::native::class(hcls,self.hook))?))?;
                } else {
                    let cls = self.hir_perl_byte_class(x)?;
                    let hcls = hir::Class::Bytes(cls);
                    self.push(HirFrame::Expr(self.resource(hir::native::class(hcls,self.hook))?))?;
                }
            }
            Ast::ClassUnicode(ref x) => {
                let cls = hir::Class::Unicode(self.hir_unicode_class(x)?);
                self.push(HirFrame::Expr(self.resource(hir::native::class(cls,self.hook))?))?;
            }
            Ast::ClassBracketed(ref ast) => {
                if self.flags().unicode() {
                    let mut cls = self.pop().unwrap().unwrap_class_unicode();
                    self.unicode_fold_and_negate(
                        &ast.span,
                        ast.negated,
                        &mut cls,
                    )?;
                    let expr = self.resource(hir::native::class(hir::Class::Unicode(cls),self.hook))?;
                    self.push(HirFrame::Expr(expr))?;
                } else {
                    let mut cls = self.pop().unwrap().unwrap_class_bytes();
                    self.bytes_fold_and_negate(
                        &ast.span,
                        ast.negated,
                        &mut cls,
                    )?;
                    let expr = self.resource(hir::native::class(hir::Class::Bytes(cls),self.hook))?;
                    self.push(HirFrame::Expr(expr))?;
                }
            }
            Ast::Repetition(ref x) => {
                let expr = self.unwrap_expr(self.pop().unwrap())?;
                self.pop().unwrap().unwrap_repetition();
                self.push(HirFrame::Expr(self.hir_repetition(x, expr)?))?;
            }
            Ast::Group(ref x) => {
                let expr = self.unwrap_expr(self.pop().unwrap())?;
                let old_flags = self.pop().unwrap().unwrap_group();
                self.trans().flags.set(old_flags);
                self.push(HirFrame::Expr(self.hir_capture(x, expr)?))?;
            }
            Ast::Concat(_) => {
                let mut exprs = vec![];
                while let Some(expr) = self.pop_concat_expr()? {
                    if !matches!(*expr.kind(), HirKind::Empty) {
                        self.resource(self.hook.push(&mut exprs,expr))?;
                    }
                }
                exprs.reverse();
                self.push(HirFrame::Expr(self.resource(hir::native::concat(exprs,self.hook))?))?;
            }
            Ast::Alternation(_) => {
                let mut exprs = vec![];
                while let Some(expr) = self.pop_alt_expr()? {
                    self.pop().unwrap().unwrap_alternation_pipe();
                    self.resource(self.hook.push(&mut exprs,expr))?;
                }
                exprs.reverse();
                self.push(HirFrame::Expr(self.resource(hir::native::alternation(exprs,self.hook))?))?;
            }
        }
        Ok(())
    }

    fn visit_alternation_in(&mut self) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        self.push(HirFrame::AlternationBranch)?;
        Ok(())
    }

    fn visit_class_set_item_pre(
        &mut self,
        ast: &ast::ClassSetItem,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        match *ast {
            ast::ClassSetItem::Bracketed(_) => {
                if self.flags().unicode() {
                    let cls = hir::ClassUnicode::empty();
                    self.push(HirFrame::ClassUnicode(cls))?;
                } else {
                    let cls = hir::ClassBytes::empty();
                    self.push(HirFrame::ClassBytes(cls))?;
                }
            }
            // We needn't handle the Union case here since the visitor will
            // do it for us.
            _ => {}
        }
        Ok(())
    }

    fn visit_class_set_item_post(
        &mut self,
        ast: &ast::ClassSetItem,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        match *ast {
            ast::ClassSetItem::Empty(_) => {}
            ast::ClassSetItem::Literal(ref x) => {
                if self.flags().unicode() {
                    let mut cls = self.pop().unwrap().unwrap_class_unicode();
                    self.resource(cls.push_admitted(hir::ClassUnicodeRange::new(x.c, x.c),self.hook))?;
                    self.push(HirFrame::ClassUnicode(cls))?;
                } else {
                    let mut cls = self.pop().unwrap().unwrap_class_bytes();
                    let byte = self.class_literal_byte(x)?;
                    self.resource(cls.push_admitted(hir::ClassBytesRange::new(byte, byte),self.hook))?;
                    self.push(HirFrame::ClassBytes(cls))?;
                }
            }
            ast::ClassSetItem::Range(ref x) => {
                if self.flags().unicode() {
                    let mut cls = self.pop().unwrap().unwrap_class_unicode();
                    self.resource(cls.push_admitted(hir::ClassUnicodeRange::new(x.start.c, x.end.c),self.hook))?;
                    self.push(HirFrame::ClassUnicode(cls))?;
                } else {
                    let mut cls = self.pop().unwrap().unwrap_class_bytes();
                    let start = self.class_literal_byte(&x.start)?;
                    let end = self.class_literal_byte(&x.end)?;
                    self.resource(cls.push_admitted(hir::ClassBytesRange::new(start, end),self.hook))?;
                    self.push(HirFrame::ClassBytes(cls))?;
                }
            }
            ast::ClassSetItem::Ascii(ref x) => {
                if self.flags().unicode() {
                    let xcls = self.hir_ascii_unicode_class(x)?;
                    let mut cls = self.pop().unwrap().unwrap_class_unicode();
                    self.resource(cls.union_admitted(&xcls,self.hook))?;
                    self.push(HirFrame::ClassUnicode(cls))?;
                } else {
                    let xcls = self.hir_ascii_byte_class(x)?;
                    let mut cls = self.pop().unwrap().unwrap_class_bytes();
                    self.resource(cls.union_admitted(&xcls,self.hook))?;
                    self.push(HirFrame::ClassBytes(cls))?;
                }
            }
            ast::ClassSetItem::Unicode(ref x) => {
                let xcls = self.hir_unicode_class(x)?;
                let mut cls = self.pop().unwrap().unwrap_class_unicode();
                self.resource(cls.union_admitted(&xcls,self.hook))?;
                self.push(HirFrame::ClassUnicode(cls))?;
            }
            ast::ClassSetItem::Perl(ref x) => {
                if self.flags().unicode() {
                    let xcls = self.hir_perl_unicode_class(x)?;
                    let mut cls = self.pop().unwrap().unwrap_class_unicode();
                    self.resource(cls.union_admitted(&xcls,self.hook))?;
                    self.push(HirFrame::ClassUnicode(cls))?;
                } else {
                    let xcls = self.hir_perl_byte_class(x)?;
                    let mut cls = self.pop().unwrap().unwrap_class_bytes();
                    self.resource(cls.union_admitted(&xcls,self.hook))?;
                    self.push(HirFrame::ClassBytes(cls))?;
                }
            }
            ast::ClassSetItem::Bracketed(ref ast) => {
                if self.flags().unicode() {
                    let mut cls1 = self.pop().unwrap().unwrap_class_unicode();
                    self.unicode_fold_and_negate(
                        &ast.span,
                        ast.negated,
                        &mut cls1,
                    )?;

                    let mut cls2 = self.pop().unwrap().unwrap_class_unicode();
                    self.resource(cls2.union_admitted(&cls1,self.hook))?;
                    self.push(HirFrame::ClassUnicode(cls2))?;
                } else {
                    let mut cls1 = self.pop().unwrap().unwrap_class_bytes();
                    self.bytes_fold_and_negate(
                        &ast.span,
                        ast.negated,
                        &mut cls1,
                    )?;

                    let mut cls2 = self.pop().unwrap().unwrap_class_bytes();
                    self.resource(cls2.union_admitted(&cls1,self.hook))?;
                    self.push(HirFrame::ClassBytes(cls2))?;
                }
            }
            // This is handled automatically by the visitor.
            ast::ClassSetItem::Union(_) => {}
        }
        Ok(())
    }

    fn visit_class_set_binary_op_pre(
        &mut self,
        _op: &ast::ClassSetBinaryOp,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        if self.flags().unicode() {
            let cls = hir::ClassUnicode::empty();
            self.push(HirFrame::ClassUnicode(cls))?;
        } else {
            let cls = hir::ClassBytes::empty();
            self.push(HirFrame::ClassBytes(cls))?;
        }
        Ok(())
    }

    fn visit_class_set_binary_op_in(
        &mut self,
        _op: &ast::ClassSetBinaryOp,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        if self.flags().unicode() {
            let cls = hir::ClassUnicode::empty();
            self.push(HirFrame::ClassUnicode(cls))?;
        } else {
            let cls = hir::ClassBytes::empty();
            self.push(HirFrame::ClassBytes(cls))?;
        }
        Ok(())
    }

    fn visit_class_set_binary_op_post(
        &mut self,
        op: &ast::ClassSetBinaryOp,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        use crate::ast::ClassSetBinaryOpKind::*;

        if self.flags().unicode() {
            let mut rhs = self.pop().unwrap().unwrap_class_unicode();
            let mut lhs = self.pop().unwrap().unwrap_class_unicode();
            let mut cls = self.pop().unwrap().unwrap_class_unicode();
            if self.flags().case_insensitive() {
                self.fold_unicode(&mut rhs)?.map_err(|_| {
                    self.error(
                        op.rhs.span().clone(),
                        ErrorKind::UnicodeCaseUnavailable,
                    )
                })?;
                self.fold_unicode(&mut lhs)?.map_err(|_| {
                    self.error(
                        op.lhs.span().clone(),
                        ErrorKind::UnicodeCaseUnavailable,
                    )
                })?;
            }
            match op.kind {
                Intersection => self.resource(lhs.intersect_admitted(&rhs,self.hook))?,
                Difference => self.resource(lhs.difference_admitted(&rhs,self.hook))?,
                SymmetricDifference => self.resource(lhs.symmetric_difference_admitted(&rhs,self.hook))?,
            }
            self.resource(cls.union_admitted(&lhs,self.hook))?;
            self.push(HirFrame::ClassUnicode(cls))?;
        } else {
            let mut rhs = self.pop().unwrap().unwrap_class_bytes();
            let mut lhs = self.pop().unwrap().unwrap_class_bytes();
            let mut cls = self.pop().unwrap().unwrap_class_bytes();
            if self.flags().case_insensitive() {
                self.fold_bytes(&mut rhs)?;
                self.fold_bytes(&mut lhs)?;
            }
            match op.kind {
                Intersection => self.resource(lhs.intersect_admitted(&rhs,self.hook))?,
                Difference => self.resource(lhs.difference_admitted(&rhs,self.hook))?,
                SymmetricDifference => self.resource(lhs.symmetric_difference_admitted(&rhs,self.hook))?,
            }
            self.resource(cls.union_admitted(&lhs,self.hook))?;
            self.push(HirFrame::ClassBytes(cls))?;
        }
        Ok(())
    }
}

impl<'t, 'p> NativeTranslatorI<'t, 'p> {
    /// Build a new internal translator.
    fn new(trans: &'t Translator, pattern: &'p str,hook:&'t Hook<'p>) -> NativeTranslatorI<'t, 'p> {
        NativeTranslatorI { trans, pattern,hook }
    }

    fn boxed_name(&self,value:&str)->Result<Box<str>>{
        let text=self.text(value)?;
        if text.len()!=text.capacity(){self.resource(self.hook.reserve(||text.len().checked_add(64)))?;}
        Ok(text.into_boxed_str())
    }
    fn fold_unicode(&self,value:&mut hir::ClassUnicode)->Result<core::result::Result<(),unicode::CaseFoldError>>{
        match value.case_fold_simple_admitted(self.hook){
            Ok(())=>Ok(Ok(())),Err(hir::interval::NativeCaseFoldError::Refused(_))=>Err(self.refused()),
            Err(hir::interval::NativeCaseFoldError::Unavailable(actual))=>Ok(Err(actual)),
        }
    }
    fn fold_bytes(&self,value:&mut hir::ClassBytes)->Result<()>{
        match value.case_fold_simple_admitted(self.hook){
            Ok(())=>Ok(()),Err(hir::interval::NativeCaseFoldError::Refused(_))=>Err(self.refused()),
            Err(hir::interval::NativeCaseFoldError::Unavailable(_))=>Err(self.error(Span::splat(ast::Position::new(0,0,0)),ErrorKind::UnicodeCaseUnavailable)),
        }
    }

    /// Return a reference to the underlying translator.
    fn trans(&self) -> &Translator {
        &self.trans
    }

    /// Push the given frame on to the call stack.
    fn push(&self,frame:HirFrame)->Result<()>{self.hook.push(&mut self.trans().stack.borrow_mut(),frame).map_err(|_|self.refused())}
    fn refused(&self)->Error{Error{kind:ErrorKind::NativeAdmissionRefused,pattern:String::new(),span:Span::splat(ast::Position::new(0,0,0))}}
    fn resource<T>(&self,result:core::result::Result<T,Refused>)->Result<T>{result.map_err(|_|self.refused())}
    fn text(&self,value:&str)->Result<String>{self.resource(self.hook.text(value))}
    fn literal(&self,value:Vec<u8>)->Result<Hir>{self.resource(hir::native::literal(value,self.hook))}
    fn unwrap_expr(&self,frame:HirFrame)->Result<Hir>{match frame{HirFrame::Expr(expr)=>Ok(expr),HirFrame::Literal(lit)=>self.literal(lit),_=>unreachable!("expected real expression frame")}}


    /// Push the given literal char on to the call stack.
    ///
    /// If the top-most element of the stack is a literal, then the char
    /// is appended to the end of that literal. Otherwise, a new literal
    /// containing just the given char is pushed to the top of the stack.
    fn push_char(&self,ch:char)->Result<()>{let mut buffer=[0;4];self.push_bytes(ch.encode_utf8(&mut buffer).as_bytes())}
    fn push_byte(&self,byte:u8)->Result<()>{self.push_bytes(&[byte])}
    fn push_bytes(&self,bytes:&[u8])->Result<()>{
        let mut stack=self.trans().stack.borrow_mut();
        if let Some(HirFrame::Literal(literal))=stack.last_mut(){self.resource(self.hook.room(literal,bytes.len()))?;literal.extend_from_slice(bytes);}
        else{let mut literal=Vec::new();self.resource(self.hook.room(&mut literal,bytes.len()))?;literal.extend_from_slice(bytes);self.resource(self.hook.push(&mut stack,HirFrame::Literal(literal)))?;}
        Ok(())
    }

    /// Pop the top of the call stack. If the call stack is empty, return None.
    fn pop(&self) -> Option<HirFrame> {
        self.trans().stack.borrow_mut().pop()
    }

    /// Pop an HIR expression from the top of the stack for a concatenation.
    ///
    /// This returns None if the stack is empty or when a concat frame is seen.
    /// Otherwise, it panics if it could not find an HIR expression.
    fn pop_concat_expr(&self) -> Result<Option<Hir>> {
        let Some(frame)=self.pop()else{return Ok(None)};
        match frame {
            HirFrame::Concat => Ok(None),
            HirFrame::Expr(expr) => Ok(Some(expr)),
            HirFrame::Literal(lit) => Ok(Some(self.literal(lit)?)),
            HirFrame::ClassUnicode(_) => {
                unreachable!("expected expr or concat, got Unicode class")
            }
            HirFrame::ClassBytes(_) => {
                unreachable!("expected expr or concat, got byte class")
            }
            HirFrame::Repetition => {
                unreachable!("expected expr or concat, got repetition")
            }
            HirFrame::Group { .. } => {
                unreachable!("expected expr or concat, got group")
            }
            HirFrame::Alternation => {
                unreachable!("expected expr or concat, got alt marker")
            }
            HirFrame::AlternationBranch => {
                unreachable!("expected expr or concat, got alt branch marker")
            }
        }
    }

    /// Pop an HIR expression from the top of the stack for an alternation.
    ///
    /// This returns None if the stack is empty or when an alternation frame is
    /// seen. Otherwise, it panics if it could not find an HIR expression.
    fn pop_alt_expr(&self) -> Result<Option<Hir>> {
        let Some(frame)=self.pop()else{return Ok(None)};
        match frame {
            HirFrame::Alternation => Ok(None),
            HirFrame::Expr(expr) => Ok(Some(expr)),
            HirFrame::Literal(lit) => Ok(Some(self.literal(lit)?)),
            HirFrame::ClassUnicode(_) => {
                unreachable!("expected expr or alt, got Unicode class")
            }
            HirFrame::ClassBytes(_) => {
                unreachable!("expected expr or alt, got byte class")
            }
            HirFrame::Repetition => {
                unreachable!("expected expr or alt, got repetition")
            }
            HirFrame::Group { .. } => {
                unreachable!("expected expr or alt, got group")
            }
            HirFrame::Concat => {
                unreachable!("expected expr or alt, got concat marker")
            }
            HirFrame::AlternationBranch => {
                unreachable!("expected expr or alt, got alt branch marker")
            }
        }
    }

    /// Create a new error with the given span and error type.
    fn error(&self, span: Span, kind: ErrorKind) -> Error {
        match self.text(self.pattern){Ok(pattern)=>Error{kind,pattern,span},Err(first)=>first}
    }

    /// Return a copy of the active flags.
    fn flags(&self) -> Flags {
        self.trans().flags.get()
    }

    /// Set the flags of this translator from the flags set in the given AST.
    /// Then, return the old flags.
    fn set_flags(&self, ast_flags: &ast::Flags) -> Flags {
        let old_flags = self.flags();
        let mut new_flags = Flags::from_ast(ast_flags);
        new_flags.merge(&old_flags);
        self.trans().flags.set(new_flags);
        old_flags
    }

    /// Convert an Ast literal to its scalar representation.
    ///
    /// When Unicode mode is enabled, then this always succeeds and returns a
    /// `char` (Unicode scalar value).
    ///
    /// When Unicode mode is disabled, then a `char` will still be returned
    /// whenever possible. A byte is returned only when invalid UTF-8 is
    /// allowed and when the byte is not ASCII. Otherwise, a non-ASCII byte
    /// will result in an error when invalid UTF-8 is not allowed.
    fn ast_literal_to_scalar(
        &self,
        lit: &ast::Literal,
    ) -> Result<Either<char, u8>> {
        if self.flags().unicode() {
            return Ok(Either::Left(lit.c));
        }
        let byte = match lit.byte() {
            None => return Ok(Either::Left(lit.c)),
            Some(byte) => byte,
        };
        if byte <= 0x7F {
            return Ok(Either::Left(char::try_from(byte).unwrap()));
        }
        if self.trans().utf8 {
            return Err(self.error(lit.span, ErrorKind::InvalidUtf8));
        }
        Ok(Either::Right(byte))
    }

    fn case_fold_char(&self, span: Span, c: char) -> Result<Option<Hir>> {
        if !self.flags().case_insensitive() {
            return Ok(None);
        }
        if self.flags().unicode() {
            // If case folding won't do anything, then don't bother trying.
            let map = unicode::SimpleCaseFolder::new()
                .map(|f| f.overlaps(c, c))
                .map_err(|_| {
                    self.error(span, ErrorKind::UnicodeCaseUnavailable)
                })?;
            if !map {
                return Ok(None);
            }
            let mut cls =
                self.resource(hir::ClassUnicode::new_admitted([hir::ClassUnicodeRange::new(
                    c, c,
                )],self.hook))?;
            self.fold_unicode(&mut cls)?.map_err(|_| {
                self.error(span, ErrorKind::UnicodeCaseUnavailable)
            })?;
            Ok(Some(self.resource(hir::native::class(hir::Class::Unicode(cls),self.hook))?))
        } else {
            if !c.is_ascii() {
                return Ok(None);
            }
            // If case folding won't do anything, then don't bother trying.
            match c {
                'A'..='Z' | 'a'..='z' => {}
                _ => return Ok(None),
            }
            let mut cls =
                self.resource(hir::ClassBytes::new_admitted([hir::ClassBytesRange::new(
                    // OK because 'c.len_utf8() == 1' which in turn implies
                    // that 'c' is ASCII.
                    u8::try_from(c).unwrap(),
                    u8::try_from(c).unwrap(),
                )],self.hook))?;
            self.fold_bytes(&mut cls)?;
            Ok(Some(self.resource(hir::native::class(hir::Class::Bytes(cls),self.hook))?))
        }
    }

    fn hir_dot(&self, span: Span) -> Result<Hir> {
        let (utf8, lineterm, flags) =
            (self.trans().utf8, self.trans().line_terminator, self.flags());
        if utf8 && (!flags.unicode() || !lineterm.is_ascii()) {
            return Err(self.error(span, ErrorKind::InvalidUtf8));
        }
        let dot = if flags.dot_matches_new_line() {
            if flags.unicode() {
                hir::Dot::AnyChar
            } else {
                hir::Dot::AnyByte
            }
        } else {
            if flags.unicode() {
                if flags.crlf() {
                    hir::Dot::AnyCharExceptCRLF
                } else {
                    if !lineterm.is_ascii() {
                        return Err(
                            self.error(span, ErrorKind::InvalidLineTerminator)
                        );
                    }
                    hir::Dot::AnyCharExcept(char::from(lineterm))
                }
            } else {
                if flags.crlf() {
                    hir::Dot::AnyByteExceptCRLF
                } else {
                    hir::Dot::AnyByteExcept(lineterm)
                }
            }
        };
        self.resource(hir::native::dot(dot,self.hook))
    }

    fn hir_assertion(&self, asst: &ast::Assertion) -> Result<Hir> {
        let unicode = self.flags().unicode();
        let multi_line = self.flags().multi_line();
        let crlf = self.flags().crlf();
        Ok(match asst.kind {
            ast::AssertionKind::StartLine => self.resource(hir::native::look(if multi_line {
                if crlf {
                    hir::Look::StartCRLF
                } else {
                    hir::Look::StartLF
                }
            } else {
                hir::Look::Start
            },self.hook))?,
            ast::AssertionKind::EndLine => self.resource(hir::native::look(if multi_line {
                if crlf {
                    hir::Look::EndCRLF
                } else {
                    hir::Look::EndLF
                }
            } else {
                hir::Look::End
            },self.hook))?,
            ast::AssertionKind::StartText => self.resource(hir::native::look(hir::Look::Start,self.hook))?,
            ast::AssertionKind::EndText => self.resource(hir::native::look(hir::Look::End,self.hook))?,
            ast::AssertionKind::WordBoundary => self.resource(hir::native::look(if unicode {
                hir::Look::WordUnicode
            } else {
                hir::Look::WordAscii
            },self.hook))?,
            ast::AssertionKind::NotWordBoundary => self.resource(hir::native::look(if unicode {
                hir::Look::WordUnicodeNegate
            } else {
                hir::Look::WordAsciiNegate
            },self.hook))?,
            ast::AssertionKind::WordBoundaryStart
            | ast::AssertionKind::WordBoundaryStartAngle => {
                self.resource(hir::native::look(if unicode {
                    hir::Look::WordStartUnicode
                } else {
                    hir::Look::WordStartAscii
                },self.hook))?
            }
            ast::AssertionKind::WordBoundaryEnd
            | ast::AssertionKind::WordBoundaryEndAngle => {
                self.resource(hir::native::look(if unicode {
                    hir::Look::WordEndUnicode
                } else {
                    hir::Look::WordEndAscii
                },self.hook))?
            }
            ast::AssertionKind::WordBoundaryStartHalf => {
                self.resource(hir::native::look(if unicode {
                    hir::Look::WordStartHalfUnicode
                } else {
                    hir::Look::WordStartHalfAscii
                },self.hook))?
            }
            ast::AssertionKind::WordBoundaryEndHalf => self.resource(hir::native::look(if unicode {
                hir::Look::WordEndHalfUnicode
            } else {
                hir::Look::WordEndHalfAscii
            },self.hook))?,
        })
    }

    fn hir_capture(&self, group: &ast::Group, expr: Hir) -> Result<Hir> {
        let (index, name) = match group.kind {
            ast::GroupKind::CaptureIndex(index) => (index, None),
            ast::GroupKind::CaptureName { ref name, .. } => {
                (name.index, Some(self.boxed_name(&name.name)?))
            }
            // The HIR doesn't need to use non-capturing groups, since the way
            // in which the data type is defined handles this automatically.
            ast::GroupKind::NonCapturing(_) => return Ok(expr),
        };
        self.resource(hir::native::capture(hir::Capture { index, name, sub: self.resource(hir::native::boxed(expr,self.hook))? },self.hook))
    }

    fn hir_repetition(&self, rep: &ast::Repetition, expr: Hir) -> Result<Hir> {
        let (min, max) = match rep.op.kind {
            ast::RepetitionKind::ZeroOrOne => (0, Some(1)),
            ast::RepetitionKind::ZeroOrMore => (0, None),
            ast::RepetitionKind::OneOrMore => (1, None),
            ast::RepetitionKind::Range(ast::RepetitionRange::Exactly(m)) => {
                (m, Some(m))
            }
            ast::RepetitionKind::Range(ast::RepetitionRange::AtLeast(m)) => {
                (m, None)
            }
            ast::RepetitionKind::Range(ast::RepetitionRange::Bounded(
                m,
                n,
            )) => (m, Some(n)),
        };
        let greedy =
            if self.flags().swap_greed() { !rep.greedy } else { rep.greedy };
        self.resource(hir::native::repetition(hir::Repetition {
            min,
            max,
            greedy,
            sub: self.resource(hir::native::boxed(expr,self.hook))?,
        },self.hook))
    }

    fn hir_unicode_class(
        &self,
        ast_class: &ast::ClassUnicode,
    ) -> Result<hir::ClassUnicode> {
        use crate::ast::ClassUnicodeKind::*;

        if !self.flags().unicode() {
            return Err(
                self.error(ast_class.span, ErrorKind::UnicodeNotAllowed)
            );
        }
        let query = match ast_class.kind {
            OneLetter(name) => ClassQuery::OneLetter(name),
            Named(ref name) => ClassQuery::Binary(name),
            NamedValue { ref name, ref value, .. } => ClassQuery::ByValue {
                property_name: name,
                property_value: value,
            },
        };
        let mut result = self.convert_unicode_class_error(
            &ast_class.span,
            unicode::native::class(query,self.hook),
        );
        if let Ok(ref mut class) = result {
            self.unicode_fold_and_negate(
                &ast_class.span,
                ast_class.is_negated(),
                class,
            )?;
        }
        result
    }

    fn hir_ascii_unicode_class(
        &self,
        ast: &ast::ClassAscii,
    ) -> Result<hir::ClassUnicode> {
        let mut cls = self.resource(hir::ClassUnicode::new_admitted(
            ascii_class_as_chars(&ast.kind)
                .map(|(s, e)| hir::ClassUnicodeRange::new(s, e)),self.hook))?;
        self.unicode_fold_and_negate(&ast.span, ast.negated, &mut cls)?;
        Ok(cls)
    }

    fn hir_ascii_byte_class(
        &self,
        ast: &ast::ClassAscii,
    ) -> Result<hir::ClassBytes> {
        let mut cls = self.resource(hir::ClassBytes::new_admitted(
            ascii_class(&ast.kind)
                .map(|(s, e)| hir::ClassBytesRange::new(s, e)),self.hook))?;
        self.bytes_fold_and_negate(&ast.span, ast.negated, &mut cls)?;
        Ok(cls)
    }

    fn hir_perl_unicode_class(
        &self,
        ast_class: &ast::ClassPerl,
    ) -> Result<hir::ClassUnicode> {
        use crate::ast::ClassPerlKind::*;

        assert!(self.flags().unicode());
        let result = match ast_class.kind {
            Digit => unicode::native::perl_digit(self.hook),
            Space => unicode::native::perl_space(self.hook),
            Word => unicode::native::perl_word(self.hook),
        };
        let mut class =
            self.convert_unicode_class_error(&ast_class.span, result)?;
        // We needn't apply case folding here because the Perl Unicode classes
        // are already closed under Unicode simple case folding.
        if ast_class.negated {
            self.resource(class.negate_admitted(self.hook))?;
        }
        Ok(class)
    }

    fn hir_perl_byte_class(
        &self,
        ast_class: &ast::ClassPerl,
    ) -> Result<hir::ClassBytes> {
        use crate::ast::ClassPerlKind::*;

        assert!(!self.flags().unicode());
        let mut class = match ast_class.kind {
            Digit => self.resource(hir::ClassBytes::new_admitted(ascii_class(&ast::ClassAsciiKind::Digit).map(|(start,end)|hir::ClassBytesRange::new(start,end)),self.hook))?,
            Space => self.resource(hir::ClassBytes::new_admitted(ascii_class(&ast::ClassAsciiKind::Space).map(|(start,end)|hir::ClassBytesRange::new(start,end)),self.hook))?,
            Word => self.resource(hir::ClassBytes::new_admitted(ascii_class(&ast::ClassAsciiKind::Word).map(|(start,end)|hir::ClassBytesRange::new(start,end)),self.hook))?,
        };
        // We needn't apply case folding here because the Perl ASCII classes
        // are already closed (under ASCII case folding).
        if ast_class.negated {
            self.resource(class.negate_admitted(self.hook))?;
        }
        // Negating a Perl byte class is likely to cause it to match invalid
        // UTF-8. That's only OK if the translator is configured to allow such
        // things.
        if self.trans().utf8 && !class.is_ascii() {
            return Err(self.error(ast_class.span, ErrorKind::InvalidUtf8));
        }
        Ok(class)
    }

    /// Converts the given Unicode specific error to an HIR translation error.
    ///
    /// The span given should approximate the position at which an error would
    /// occur.
    fn convert_unicode_class_error(
        &self,
        span: &Span,
        result: core::result::Result<hir::ClassUnicode, unicode::native::Failure>,
    ) -> Result<hir::ClassUnicode> {
        result.map_err(|err| {
            let sp = span.clone();
            let err=match err{unicode::native::Failure::Refused(_)=>return self.refused(),unicode::native::Failure::Semantic(err)=>err};
            match err {
                unicode::Error::PropertyNotFound => {
                    self.error(sp, ErrorKind::UnicodePropertyNotFound)
                }
                unicode::Error::PropertyValueNotFound => {
                    self.error(sp, ErrorKind::UnicodePropertyValueNotFound)
                }
                unicode::Error::PerlClassNotFound => {
                    self.error(sp, ErrorKind::UnicodePerlClassNotFound)
                }
            }
        })
    }

    fn unicode_fold_and_negate(
        &self,
        span: &Span,
        negated: bool,
        class: &mut hir::ClassUnicode,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        // Note that we must apply case folding before negation!
        // Consider `(?i)[^x]`. If we applied negation first, then
        // the result would be the character class that matched any
        // Unicode scalar value.
        if self.flags().case_insensitive() {
            self.fold_unicode(&mut *class)?.map_err(|_| {
                self.error(span.clone(), ErrorKind::UnicodeCaseUnavailable)
            })?;
        }
        if negated {
            self.resource(class.negate_admitted(self.hook))?;
        }
        Ok(())
    }

    fn bytes_fold_and_negate(
        &self,
        span: &Span,
        negated: bool,
        class: &mut hir::ClassBytes,
    ) -> Result<()> {
        self.resource(self.hook.checkpoint())?;
        // Note that we must apply case folding before negation!
        // Consider `(?i)[^x]`. If we applied negation first, then
        // the result would be the character class that matched any
        // Unicode scalar value.
        if self.flags().case_insensitive() {
            self.fold_bytes(&mut *class)?;
        }
        if negated {
            self.resource(class.negate_admitted(self.hook))?;
        }
        if self.trans().utf8 && !class.is_ascii() {
            return Err(self.error(span.clone(), ErrorKind::InvalidUtf8));
        }
        Ok(())
    }

    /// Return a scalar byte value suitable for use as a literal in a byte
    /// character class.
    fn class_literal_byte(&self, ast: &ast::Literal) -> Result<u8> {
        match self.ast_literal_to_scalar(ast)? {
            Either::Right(byte) => Ok(byte),
            Either::Left(ch) => {
                if ch.is_ascii() {
                    Ok(u8::try_from(ch).unwrap())
                } else {
                    // We can't feasibly support Unicode in
                    // byte oriented classes. Byte classes don't
                    // do Unicode case folding.
                    Err(self.error(ast.span, ErrorKind::UnicodeNotAllowed))
                }
            }
        }
    }
}


pub(super) fn translate<'p>(builder:&TranslatorBuilder,pattern:&'p str,ast:&Ast,hook:&Hook<'p>)->core::result::Result<Result<Hir>,Refused>{
    if !hook.active(){return Err(hook.allocation_failed())}
    hook.checkpoint()?;let actual=builder.build();
    let result=ast::visit(ast,NativeTranslatorI::new(&actual,pattern,hook));
    // The original first resource/IO error wins before exposing a semantic
    // error or HIR. No work hook survives in the returned value.
    hook.checkpoint()?;Ok(result)
}
