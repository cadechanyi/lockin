# Lockin

Personal focus app for iPhone and Mac. Hard-blocks time-wasters during study sessions. The only way out is proof you actually learned the material — not a timer.

iPhone is the control surface. Mac follows the same session state.

## Why

Timer blockers (Freedom, Screen Time) help, but they are easy to wait out or disable. Lockin ties unlock to **validated knowledge** against milestones you set at the start of term, so procrastination cannot steal the week before an exam.

## Core model

```
Course
  └── Events (lecture, quiz, lab, midterm, final)
  └── Materials (textbook, notes, practice, syllabus scope)
  └── Milestones (content you must know, e.g. MATH 237 Ch 2.2–2.3)
        └── Sessions (multi-day study plan)
              └── Segments (time window + deliverable subset)
                    └── Block list + unlock rule (proof | time)
```

Example: Quiz Tuesday on Ch 2.1–2.3.

- Milestone covers 2.1–2.3.
- Session: Sat 12–3, Sun 4–7, Mon 5–8.
- Segments: Sat = 2.1, Sun = 2.2, Mon = 2.3.
- Passing Sat unlocks **that segment only**, not the whole session.
- Active segment = apps blocked. Calendar and app settings are frozen except adding to the block list.
- Leaving for hockey does not unlock anything; the segment can shift later (2–5 instead of 12–3) but stays locked until validation.
- Max block length: **7 days**.

## Unlock

Most segments unlock only after an LLM-graded validation against that segment’s materials (typed answers and/or photos of handwritten work). Time-based unlock is optional. Early finish escalates difficulty (mastery mode). After a pass, Lockin can offer to continue into the next segment or stop for the day.

## Blocking

Configurable block lists (apps + websites). Main list: Instagram, YouTube, Apple TV, related domains, Xbox (nudge-only). During an active segment you can add to a list, never remove. Breaks are configurable (one-shot or repeating); usage of blocked apps during breaks is logged, not prevented.

Xbox cannot be hard-blocked without hardware/account changes. During a session, presence checks drive repeating notifications (default 15 min, configurable).

## Safety

- 7-day maximum on any block.
- Phone, Messages, Maps stay unblocked.
- Emergency unlock exists as a delayed, heavily logged last resort — not instant, not silent.

## Status

Pre-implementation. Native SwiftUI iOS app + macOS companion, Screen Time APIs (FamilyControls / ManagedSettings / DeviceActivity), small backend for LLM grading, Xbox presence, and push.
