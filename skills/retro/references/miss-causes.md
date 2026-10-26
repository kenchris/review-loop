# Why a review misses a finding

Name the first cause that applies. Each has a usual fix.

| Cause | How to recognise it | Usual fix |
|---|---|---|
| **No lens covers it** | The class appears in no lens, sweep or `REVIEW.md` line. | A pointer or a lens; if greppable, a sweep. |
| **A lens covers it, the reader skipped it** | The lens text names the class, and the reader's report shows no sign of having looked (no "fine" entry, nothing about that function). | Make the step checkable: a sweep whose hits must each be answered; a completion criterion on the lens; a narrower reader share. |
| **It was greppable and no sweep exists** | A one-line regex over the added lines would have pointed at it. | A sweep, marked high priority (`!`) if a miss costs more than reading extra lines. |
| **The sweep exists but the pattern missed it** | The code uses a helper or spelling the regex does not match. | Widen the pattern, or add a sweep for the helper. Do not tune a pattern on the case that will judge it. |
| **It was in code the change did not add** | The defect is in an existing function the new code starts to call or rely on, so a search over added lines cannot see it. | The "existing function the new code depends on" class: read the failure paths of every function the diff starts to call. |
| **It was outside every reader's share** | The files split between readers left a function, a caller or a test unread. | Adjust the split so each changed function has an owner; add the caller list to the prompt. |
| **The reader lacked context** | The finding needs a specification, a config value, a sibling repository or a platform the reader did not have. | Put it in the prompt or the registry (`Specs we implement`); say when the context is missing instead of guessing. |
| **Found, then dropped** | The reader reported it and the merge or verification step marked it disproved or "could not confirm". | Re-check the verification: was the disproof right? If not, tighten how a finding is disproved. |
| **A reviewer error** | The outside finding is wrong. | Record it as rejected with the reason, so the same comment is not fixed twice. |

A cause that explains several misses in the round is the one to fix first.
