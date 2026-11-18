# Harbor RL Submission — <Your Name> (<@https://github.com/Abhay650>)

## 1. Loom Walkthrough Video
- **Video URL:** TODO — record yourself (unedited, <5 min, mic on) and paste the link.

## 2. Task & Calibration Summary
- **Bug 1 (Easy):** CLI arg check is `len(sys.argv) != 3`, so the script exits with a usage error on every valid invocation.
- **Bug 2 (Medium):** Status filter is `!= "FAILED"` in the wrong place, so `PENDING` rows are counted as `VALID` (count and amount).
- **Bug 3 (Hard):** Dedup by `tx_id` compares raw timestamp *strings*, not instants, so with mixed UTC offsets an earlier transaction can beat a later one.
- **Calibration Scores:** `nop` = `0.00` | `oracle` = `1.00` | Partial oracle (Bug 1+2 fixed, Bug 3 broken) = `0.50` | `hack.sh` = `0.00`
  *(verified locally with test.sh; re-confirm with `harbor run` on your machine)*

## 3. Ablation & RL Advantage Table (`terminus-2`, `k=3`)
TODO — fill from YOUR real runs. Do not invent numbers.
Reward per trial under Dense = 0.20*(bug1 check) + 0.30*(bug2 check) + 0.50*(bug3 check); Binary = 1 only if all three pass.
Advantage = trial reward − mean of the 3 trials.

| Run | Change Tested | Trial 1 (Bin / Dense) | Trial 2 | Trial 3 | Mean Bin | Mean Dense | Binary Adv | Dense Adv |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| Run 1: Baseline | Original 3-bug task | TODO | TODO | TODO | TODO | TODO | TODO | TODO |
| Run 2: Ablation | TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO |

## 4. Trajectory Forensics
- **Where the Agent Failed in Run 1:** TODO (name the exact command/step in trajectory.json).
- **Ablation Hypothesis & Result:** TODO.

## 5. Dense Reward & Anti-Cheat Design
- **Weights:** 0.20 clean-data base behaviour (fixes Bug 1), 0.30 status filtering (Bug 2), 0.50 duplicate/timezone/malformed handling (Bug 3). Bug 3 gets the most weight because it is the hardest and the one that should separate good agents from mediocre ones. Each check is 4 random datasets that must all pass.
- **How hack.sh cheats & how it's blocked:** hack.sh replaces `reconcile.py` with a stub printing hard-coded JSON. test.sh generates fresh random CSVs (seed from `os.urandom`) at verification time, runs the script from a random temp dir/filename, compares to an independent reference implementation, requires the no-argument call to fail, and rejects scripts that mention `/logs`, `/tests` or `reward.txt`. The stub scores 0.00.
- **Remaining Reward-Hacking Risk:** An agent could detect the verifier (e.g. a process/`/proc` watcher, a `sitecustomize.py`/`PYTHON*` hook, or a background process) and tamper with the Python environment or `reward.txt` outside `/app/reconcile.py`; or special-case the generator's recognisable patterns (e.g. `TX\d{6}` ids, trap-pair structure).

## 6. Local-optimum note (video Q2)
With 0.20/0.30/0.50 the agent can bank 0.50 from Bugs 1+2 and risk dropping to 0.00 by breaking the file while editing for Bug 3. If I saw RL stall there, I'd make syntax/crash-safety separate from correctness (e.g. 0.10 for "file still runs") and shrink Bug 3's weight to ~0.40 so a failed edit costs less, or add partial sub-credit inside Bug 3 (dedupe, tie-break, malformed rows scored separately).

## 7. AI Tool Workflow
- **AI Tool & Model Used:** TODO (add transcripts to `ai_transcripts/`).
- **How I Avoided Prompt Leakage:** instruction.md states only the business rules (incl. the offset-aware "latest moment" rule) and never names functions, lines or the string-comparison cause.
