# Native callback ABI controls

Pinned BYOND console compiler 516.1687 compiled control.dme with zero errors/warnings on 2026-10-06. This is compile-only evidence; no runtime was launched.

Every one of the 31 explicitly authored callback records was inspected individually. Each has its callback spelling as display name, absent description/category, flags 4, source kind 0, source parameter 255, and no extended flags. Parameters/signatures are not inferred from these zero-argument controls. Production source signatures remain authored metadata.

Finite owner/name pairs only: client Topic/Stat/AllowUpload/Move/Click/DblClick/MouseDown/MouseDrag/MouseDrop/MouseEntered/MouseExited/MouseUp; datum Topic; world Error/Reboot/Topic; atom Entered/Exited/Enter/Exit/Click/DblClick/MouseDrop/MouseEntered/MouseExited/MouseDown/MouseDrag/MouseUp/Stat; mob Login/Logout. New/Del retain separately captured existing controls. Unknown owners/names and formal declarations colliding with VM callbacks remain unsupported.

Raw receipts remain outside Git at D:/dmb-native-v2-phase0/callback-abi-controls/reference-compile.log and records.log. Source SHA256 D17D61691EC42D36DF081739491ABE2A54B1452B62A72B1CC00EEEAC222ABAD2; output DMB SHA256 4D742DDE4135E86A1B84C1AE6DE45176E173F14AC38BCD99EB146C03D4388650.