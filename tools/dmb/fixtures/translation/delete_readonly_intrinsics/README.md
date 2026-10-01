# Deleting native intrinsic references

Fresh DreamMaker516.1687 fixture: twelve accepted procedures, zero errors/warnings. Compilation only; no DreamDaemon execution.

| Operand | Native storage clearing |
|---|---|
| world | None |
| caller / callee | None |
| global.vars | None |
| src.type / typed or dynamic receiver.type / safe receiver?.type | None |
| src | PushVal Null; SetVar Src; Del; End |
| usr | PushVal Null; SetVar Usr; Del |
| args | PushVal Null; SetVar Args; Del |
| ordinary global variable named type | PushVal Null; SetVar Global; Del |

Readonly forms still load the target and execute Del. Readonly receiver identity does not imply mutable fields are readonly: ordinary world/client/object fields retain their independently resolved mutability. Native rejects world.type as an undefined field.

The integration test compares each complete procedure against native in both source-debug modes, checks setter counts, and retains Src's immediate End. All twelve complete native procedure bodies pass the focused translated regression in both source-debug modes. The mutable global named type and readonly safe/dynamic member-type controls are retained.
