//! Calls general lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn named_call(
        &mut self,
        expr: &Expr,
        name: &str,
        args: &[Expr],
        statement: &str,
        named_arguments: bool,
        arglist_argument: Option<&Expr>,
    ) -> Result<(), LowerError> {
        if name == "input" {
            return self.input_call(args, &[], None, statement);
        }
        if name == "nameof" {
            let [arg] = args else {
                return Err(error(statement, "nameof() requires one reference"));
            };
            let leaf = nameof_reference(arg).ok_or_else(|| {
                error(
                    statement,
                    "nameof() requires a variable, procedure, or type reference",
                )
            })?;
            self.intern_string(leaf);
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::String(SymbolId::of(leaf)))],
            );
            return Ok(());
        }
        if name == "rgb" && args.len() == 4 {
            if let ExprKind::Binary { op, lhs, rhs } = &args[3].kind {
                if op == "=" && matches!(&lhs.kind, ExprKind::Ident(key) if key == "space") {
                    for arg in &args[..3] {
                        if let ExprKind::Binary { op, rhs, .. } = &arg.kind {
                            if op == "=" {
                                self.expression(rhs, statement)?;
                                continue;
                            }
                        }
                        self.expression(arg, statement)?;
                    }
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    self.expression(rhs, statement)?;
                    self.emit(0x161, vec![]);
                    return Ok(());
                }
            }
        }
        if named_arguments
            && name != "list"
            && name != "icon"
            && (crate::builtin_catalog::lookup(name).is_some()
                || matches!(
                    name,
                    "rand"
                        | "regex"
                        | "copytext"
                        | "findtext"
                        | "clamp"
                        | "min"
                        | "max"
                        | "isnull"
                        | "ceil"
                        | "floor"
                        | "round"
                        | "length"
                        | "text2num"
                        | "file"
                        | "sleep"
                ))
        {
            return Err(error(statement, "named built-in arguments are not lowered"));
        }
        if name == "." {
            if let [arg] = args {
                if let ExprKind::Call {
                    callee,
                    args: list_args,
                } = &arg.kind
                {
                    if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                        if list_args.len() != 1 {
                            return Err(error(statement, "arglist() requires one argument"));
                        }
                        self.expression(&list_args[0], statement)?;
                        self.emit(0xca, vec![]);
                        return Ok(());
                    }
                }
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x2f, vec![Word::Immediate(args.len() as u32)]);
            return Ok(());
        }
        if name == "rand" {
            if args.len() > 2 {
                return Err(error(statement, "rand() accepts at most two arguments"));
            }
            if args.is_empty() {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
            }
            self.emit(if args.len() == 2 { 0x23 } else { 0x22 }, vec![]);
            return Ok(());
        }
        if name == "isnull" {
            if args.len() != 1 {
                return Err(error(statement, "isnull() requires one argument"));
            }
            self.expression(&args[0], statement)?;
            self.emit(opcode::IS_NULL, vec![]);
            return Ok(());
        }
        if name == "ceil" {
            if args.len() != 1 {
                return Err(error(statement, "ceil() requires one argument"));
            }
            self.expression(&args[0], statement)?;
            self.emit(0x169, vec![]);
            return Ok(());
        }
        if name == "floor" {
            if args.len() != 1 {
                return Err(error(statement, "floor() requires one argument"));
            }
            self.expression(&args[0], statement)?;
            self.emit(0x43, vec![]);
            return Ok(());
        }
        if name == "round" {
            if !(1..=2).contains(&args.len()) {
                return Err(error(statement, "round() requires one or two arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(if args.len() == 1 { 0x43 } else { 0x44 }, vec![]);
            return Ok(());
        }
        if name == "regex" {
            if !(1..=2).contains(&args.len()) {
                return Err(error(statement, "regex() requires one or two arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x13a, vec![Word::Immediate(args.len() as u32)]);
            return Ok(());
        }
        if name == "length" {
            if args.len() != 1 {
                return Err(error(statement, "length() requires one argument"));
            }
            self.expression(&args[0], statement)?;
            self.emit(0x6d, vec![]);
            return Ok(());
        }
        if name == "copytext" {
            if !(2..=3).contains(&args.len()) {
                return Err(error(
                    statement,
                    "copytext() requires two or three arguments",
                ));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            if args.len() == 2 {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            self.emit(0x6e, vec![]);
            return Ok(());
        }
        if name == "text2num" {
            if !(1..=2).contains(&args.len()) {
                return Err(error(statement, "text2num() requires one or two arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(if args.len() == 1 { 0x76 } else { 0x158 }, vec![]);
            return Ok(());
        }
        if name == "findtext" {
            if !(2..=4).contains(&args.len()) {
                return Err(error(
                    statement,
                    "findtext() requires two to four arguments",
                ));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            if args.len() == 2 {
                self.emit(opcode::PUSH_INT, vec![Word::Immediate(1)]);
            }
            if args.len() < 4 {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            self.emit(0x6f, vec![]);
            return Ok(());
        }
        if name == "clamp" {
            if args.len() != 3 {
                return Err(error(statement, "clamp() requires three arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x14a, vec![]);
            return Ok(());
        }
        if name == "min" || name == "max" {
            if args.is_empty() {
                return Err(error(statement, "min/max require at least one argument"));
            }
            if let [arg] = args {
                if let ExprKind::Call {
                    callee,
                    args: list_args,
                } = &arg.kind
                {
                    if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                        if list_args.len() != 1 {
                            return Err(error(statement, "arglist() requires one argument"));
                        }
                        self.expression(&list_args[0], statement)?;
                        self.emit(if name == "min" { 0xd0 } else { 0xd1 }, vec![]);
                        return Ok(());
                    }
                }
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            if args.len() == 1 {
                self.emit(if name == "min" { 0xd0 } else { 0xd1 }, vec![]);
            } else {
                self.emit(
                    if name == "min" { 0xa5 } else { 0xa6 },
                    vec![Word::Immediate(args.len() as u32)],
                );
            }
            return Ok(());
        }
        if name == "file" {
            if args.len() != 1 {
                return Err(error(statement, "file() requires one positional argument"));
            }
            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::FileType)]);
            self.expression(&args[0], statement)?;
            self.emit(opcode::NEW, vec![Word::Immediate(1)]);
            return Ok(());
        }
        if name == "icon" || name == "sound" {
            if args.len() > 255 {
                return Err(error(statement, "constructor has too many arguments"));
            }
            let class_path = if name == "icon" { "/icon" } else { "/sound" };
            self.intern_string(class_path);
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::String(SymbolId::of(class_path)))],
            );
            let named = args
                .iter()
                .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
            if named {
                self.named_arguments(args, statement)?;
                self.emit(0xcf, vec![]);
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
            }
            return Ok(());
        }
        if name == "newlist" {
            if named_arguments {
                return Err(error(
                    statement,
                    "newlist() does not accept named arguments",
                ));
            }
            for arg in args {
                self.expression(arg, statement)?;
                self.emit(opcode::NEW, vec![Word::Immediate(0)]);
            }
            self.emit(opcode::NEW_LIST, vec![Word::Immediate(args.len() as u32)]);
            return Ok(());
        }
        if name == "list" {
            let associative = args
                .iter()
                .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
            if associative {
                self.named_arguments(args, statement)?;
                return Ok(());
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            // EMPTY_LIST consumes a dimension from the stack. A literal
            // list(), including arglist(list()), has zero operands.
            self.emit(opcode::NEW_LIST, vec![Word::Immediate(args.len() as u32)]);
            return Ok(());
        }
        if name == ".." {
            let source_ordinal = self.debug_current;
            let no_parent = self.bindings.procedure_identity.and_then(|identity| {
                self.lookup
                    .and_then(|lookup| lookup.parent_presence(identity))
            }) == Some(false);
            if named_arguments {
                self.named_arguments(args, statement)?;
                self.emit(0xc9, vec![]);
            } else if args.is_empty() {
                self.emit(0x2c, vec![]);
            } else if let [arg] = args {
                if let ExprKind::Call {
                    callee,
                    args: list_args,
                } = &arg.kind
                {
                    if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                        if list_args.len() != 1 {
                            return Err(error(statement, "arglist() requires one argument"));
                        }
                        self.expression(&list_args[0], statement)?;
                        self.emit(0xc9, vec![]);
                        if no_parent {
                            self.result.warnings.push(ProcedureWarning {
                                code: dm_ir::WarningCode::NoParent,
                                name: None,
                                source_ordinal,
                            });
                        }
                        return Ok(());
                    }
                }
                self.expression(arg, statement)?;
                self.emit(0x2d, vec![Word::Immediate(1)]);
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(0x2d, vec![Word::Immediate(args.len() as u32)]);
            }
            if no_parent {
                self.result.warnings.push(ProcedureWarning {
                    code: dm_ir::WarningCode::NoParent,
                    name: None,
                    source_ordinal,
                });
            }
            return Ok(());
        }
        if name == "sleep" {
            return Err(error(statement, "sleep requires statement lowering"));
        }
        if name == "alert" {
            if !(1..=6).contains(&args.len()) {
                return Err(error(statement, "alert() requires one to six arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            for _ in args.len()..6 {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            self.emit(0x18, vec![]);
            return Ok(());
        }
        if name == "time2text" && args.len() == 3 {
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x15d, vec![Word::Immediate(3)]);
            return Ok(());
        }
        if name == "json_encode" && args.len() == 2 {
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x167, vec![Word::Immediate(2)]);
            return Ok(());
        }
        let alternate_opcode = match (name, args.len()) {
            ("arctan", 2) => Some(0x146),
            ("log", 2) => Some(0x32),
            ("num2text", 2) => Some(0x56),
            ("num2text", 3) => Some(0x159),
            ("ispath", 2) => Some(0xf6),
            ("locate", 2) => Some(0x97),
            ("locate", 3) => Some(0x5a),
            ("rgb", 4) => Some(0x113),
            _ => None,
        };
        if let Some(opcode) = alternate_opcode {
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(opcode, vec![]);
            return Ok(());
        }
        if let Some(spec) = crate::builtin_catalog::lookup_with_arity(name, args.len()) {
            if !(spec.min_args..=spec.max_args).contains(&args.len()) {
                return Err(error(
                    statement,
                    &format!(
                        "invalid built-in argument count: {name} got {} expected {}..={}",
                        args.len(),
                        spec.min_args,
                        spec.max_args
                    ),
                ));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            let omitted = if spec.max_args == usize::MAX {
                0
            } else {
                spec.max_args - args.len()
            };
            if omitted > spec.trailing_defaults.len() {
                return Err(error(statement, "missing built-in default arguments"));
            }
            for default in &spec.trailing_defaults[spec.trailing_defaults.len() - omitted..] {
                if let ValueWord::Number(bits) = default {
                    let number = f32::from_bits(*bits);
                    if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                        self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
                        continue;
                    }
                }
                self.emit(opcode::PUSH_VAL, vec![Word::Value(default.clone())]);
            }
            let operands = match spec.count_operand {
                crate::builtin_catalog::OpcodeCountPolicy::None => vec![],
                crate::builtin_catalog::OpcodeCountPolicy::EmittedArgs => {
                    vec![Word::Immediate(args.len() as u32)]
                }
                crate::builtin_catalog::OpcodeCountPolicy::Fixed(value) => {
                    vec![Word::Immediate(value)]
                }
            };
            self.emit(spec.opcode, operands);
            if let Some(post_opcode) = spec.post_opcode {
                self.emit(post_opcode, vec![]);
            }
            if crate::builtin_catalog::is_void(name) {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            self.record_named_intrinsic(expr, name);
            return Ok(());
        }
        let has_member_proc = self.current_has_declared_member_proc(name)?
            || self.current_member_proc(name)?.is_some();
        if !has_member_proc && self.has_global_proc(name)? {
            if named_arguments || arglist_argument.is_some() {
                if named_arguments {
                    self.named_arguments(args, statement)?;
                } else if let Some(list) = arglist_argument {
                    self.expression(list, statement)?;
                }
                let reference = self.global_proc(name)?;
                self.record_named_call_selection(expr, name, &VariableWord::StaticProc(reference));
                self.emit(0xcd, vec![Word::Reference(reference)]);
                return Ok(());
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            let reference = self.global_proc(name)?;
            self.record_named_call_selection(expr, name, &VariableWord::StaticProc(reference));
            self.emit(
                opcode::CALL_GLOB,
                vec![
                    Word::Immediate(args.len() as u32),
                    Word::Reference(reference),
                ],
            );
            return Ok(());
        }
        if matches!(
            name,
            "sound"
                | "image"
                | "animate"
                | "locate"
                | "pick"
                | "issaved"
                | "typesof"
                | "istype"
                | "islist"
                | "istext"
                | "isnum"
                | "ispath"
                | "isfile"
                | "get_turf"
                | "hascall"
                | "call"
                | "filter"
                | "generator"
                | "alert"
                | "input"
                | "text2path"
                | "json_encode"
                | "json_decode"
        ) {
            return Err(error(statement, "unlowered built-in call"));
        }
        {
            let proc_selector = self
                .current_member_proc(name)?
                .map(member_proc_selector)
                .unwrap_or_else(|| {
                    VariableWord::DynamicProc(self.intern_string(&name.replace('_', " ")))
                });
            if (self.lookup.is_some() || self.bindings.shared.is_some())
                && matches!(proc_selector, VariableWord::DynamicProc(_))
                && !self.current_has_declared_member_proc(name)?
            {
                return Err(error(
                    statement,
                    &format!("unresolved unqualified procedure: {name}"),
                ));
            }
            self.record_named_call_selection(expr, name, &proc_selector);
            if named_arguments {
                self.named_arguments(args, statement)?;
            } else if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
            }
            self.emit(
                self.direct_call_opcode(expr),
                vec![
                    Word::Variable(VariableWord::SetCache(
                        Box::new(VariableWord::Src),
                        Box::new(proc_selector),
                    )),
                    Word::Immediate(if named_arguments || arglist_argument.is_some() {
                        u16::MAX as u32
                    } else {
                        args.len() as u32
                    }),
                ],
            );
        }
        Ok(())
    }
}
