# Src method-result ownership

Thirteen authored bodies compare completely with native output in both debug modes.
A captured Src method receiver now supports subsequent direct field operations,
including writes and compound expressions, until an owner-changing operation or
branch target invalidates it. Global helpers retain this specific captured context.
Another selected owner, derived receiver, safe other owner, and branch target
have paired controls requiring fresh selection. Getter-only code has an explicit
negative assertion and does not enable this method-context optimization.

Direct caller src assignment invalidates the receiver; a callee assigning its own src does not change the caller frame. Both controls compare completely.
