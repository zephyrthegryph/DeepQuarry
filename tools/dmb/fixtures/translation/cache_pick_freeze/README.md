# Pick receiver context fixture

Eighteen authored callers are compared against native DreamMaker 516.1687 output,
with and without debug markers. They cover unweighted/constant/dynamic weighted
picks, frozen child receivers, Initial/field candidates, different candidate
owners, global helper probabilities, receiver-changing field/method weights,
explicit global rebinding, conditional weights and nested weighted candidates.

Native candidate selectors are compiled from the context preceding probability
expressions. Actual probabilities execute first and can replace the VM cache:
`other.value; OWNER.child.read()` may invoke the bare native method selector on
`other`. These tests reproduce native encoding; they do not prove the originally
selected runtime object survives probability evaluation.
