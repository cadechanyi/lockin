# Backlog

Not started or deliberately deferred. Roughly in priority order within each group.

## Quiz / validation (deferred, functional today but not hardened)

- **Prompt injection in short-answer grading.** The student's answer is pasted straight into the grading prompt. Delimit it, use structured output, and prefer deterministic checks for math answers.
- **Retry abuse.** Failing immediately regenerates a new question. Add a cooldown and a per-attempt cap.
- **Offline / API failure lockout.** No key or no network means no unlock until the 14-day cap. Pre-generate and cache a question bank when the session is created.
- **Wrong answer keys.** LLM-written math keys are sometimes wrong. Verify with a second independent solve; add "report bad question" that regenerates for free.
- **Material import.** Questions come from pasted text. Add PDF/notes import (PDFKit text extraction) as the source.
- **Math rendering/input.** No LaTeX rendering; plain-text answers are awkward.
- **Proof-friendly question types** that are exact to grade: fill the missing step, spot the error, order the steps.
- **Mistake notebook.** Store question, answer, and solution per attempt, not just pass/fail.
- Stale hardcoded model IDs in `ValidationService`.
- Shield button cannot open Lockin; post a local notification from the extension that deep-links instead.

## Progress tracker follow-ups

- Topics per course with lecture dates and a pace indicator (behind / on track / ahead).
- Syllabus import (LLM extraction of weights and dates) and Apple Calendar (EventKit) import for lectures.
- Daily agenda planner that proposes tomorrow's sessions from due dates and free time.
- Milestones on the calendar showing weight and score.
- Cumulative term GPA / multi-course view.

## Blocking hardening

- Websites are stored but not enforced. iOS: `ManagedSettings.webContent` with domains. Mac: needs a content filter or DNS-level approach (browsers are the biggest Mac leak).
- Allowlist mode ("block everything except Phone, Messages, Maps, class apps").
- Require automatic date & time while blocked, deny app installation.
- Screen Time passcode recovery via Apple ID is a known bypass; document using a friend's recovery Apple ID.
- Mac: relaunch via login item/launch agent if Lockin is force-quit; heartbeat so the iPhone can flag "Mac wasn't running during your block".
- Scheduled local notifications for block start/overrun (today they only fire while the app runs).
- Custom/repeating breaks shorter than 15 minutes cannot be scheduled by DeviceActivity.

## Polish / later

- Quick "Lock me for 45 min" button that skips the wizard.
- Widgets, Live Activity, Control Center toggle, App Intents / Shortcuts, Focus filter.
- Spaced-repetition daily quiz; exam-mode ramp-up.
- Weekly report / accountability partner; real usage trends via a DeviceActivityReport extension.
- Versioned SwiftData schema with a migration plan before the model changes again.
