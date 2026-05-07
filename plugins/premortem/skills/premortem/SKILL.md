---
name: premortem
description: Use when the user has a concrete plan, launch, hire, pricing change, strategy, partnership, or any commitment with significant downside and asks to stress-test it, expose blind spots, or anticipate failure modes. Triggers on phrases like "premortem this", "premortem my", "what could kill this", "stress test this plan", "what am I missing", "find the blind spots", "poke holes in this", "where will this break", "future-proof this", "devil's advocate this". Do NOT use for vague ideas without a plan, simple factual questions, routine feedback on a draft, or when the decision is already irreversible.
---

# Premortem

## Overview

A premortem is the inverse of a postmortem. Instead of explaining a failure after it happened, you assume the plan **already failed 6 months from now** and reason backward to find every reason why.

Method: Gary Klein, *Harvard Business Review*. Endorsed by Daniel Kahneman as his single most valuable decision-making technique. Used by Google, Goldman Sachs, P&G before major decisions.

**Why it works for AI-assisted decisions:** Asking "is this a good plan?" surfaces agreeable, optimistic answers. Asking "this is dead — explain how it died" forces narrative mode and produces honest, specific failure causes. Wharton/Cornell researchers call this *prospective hindsight*.

## When to Use

Good targets:
- Product/feature about to be built
- Launch with money or reputation on the line
- Pricing change or business-model shift
- Hire about to be made
- Strategy or positioning pivot
- Partnership or deal under evaluation
- Any commitment where being wrong is expensive

Bad targets (do something else instead):
- Vague ideas with no concrete plan → help plan first
- Questions with one right answer → just answer
- Creative feedback on a draft → that's editing
- Decisions already made and irreversible → premortem only helps when course can still change
- Request for multiple perspectives on a current decision → that's the LLM Council, not a premortem

## Workflow

### Step 1 — Gather minimum context

A premortem is only as good as the context. Vague input → vague failures → no value.

**1a. Scan first, ask second.** Look for context already available before asking the user:
- Earlier turns in this conversation
- `CLAUDE.md` / `claude.md` in the workspace
- Any `memory/` directory (audience profiles, past decisions, business details)
- Files the user attached or referenced
- Briefs or plan docs related to the thing being premortemed

Use `Glob` + targeted `Read`. Cap at ~30 seconds. The goal is grounding, not exhaustive search.

**1b. Check the minimum bar.** You need three things:
1. **What is it?** — Can you describe the plan in one sentence?
2. **Who is it for / who does it affect?** — Audience, stakeholders, team.
3. **What does success look like?** — Failure is the inversion of success. No success criteria → no failure definition.

**1c. Fill gaps conversationally.** If all three are present, proceed. Otherwise ask for the most important missing piece, one question at a time. Re-evaluate after each answer. Never ask more than required. Conversational, not interrogative.

### Step 2 — Set the frame explicitly

State the premortem premise out loud:

> "OK, I have enough context. Let's run the premortem. Here's the premise: it's 6 months from now. [The plan] has failed. It's done. We're looking back to understand what went wrong."

This shifts the mode from "evaluate this plan" (triggers agreement) to "explain why this died" (triggers honest failure identification). **Do not skip this.** It is the psychological mechanism that makes the technique work.

### Step 3 — Generate the raw failure list

Run a single comprehensive analysis. No prescribed categories. No lenses. No quotas.

> "This plan has failed 6 months from now. Generate every genuine reason it could have died. Be comprehensive. Be specific. Ground every reason in the actual details of the plan. Don't pad with weak reasons. Don't stop early if there are more."

Each failure reason must be:
- **Specific** to this plan (not generic advice)
- **Grounded** in details the user provided
- **Genuine** (a real threat, not an edge case or inconvenience)

Length: 1–2 sentences per reason. Count: whatever is real for this plan — could be 4, could be 9. Don't force a number.

### Step 4 — Deep-dive agents (parallel, one per failure reason)

**Spawn all agents in parallel in a single message.** Sequential spawning wastes time and lets earlier responses contaminate later ones.

Sub-agent prompt template:

```
You are an investigator in a premortem analysis. You've been assigned one specific failure reason to analyze in depth.

THE PLAN
---
[full context: what it is, who it's for, what success looks like, plus relevant workspace context]
---

PREMORTEM FRAME: It is 6 months from now. This plan has failed.

YOUR ASSIGNED FAILURE REASON: [one specific failure reason from step 3]

Your job: go deep on this one failure. Write the story of how it actually played out. Be specific. Use details from the plan. Make it feel like a case study of something that really happened.

Output:

1. THE FAILURE STORY — 2–3 paragraph narrative of how this failure played out. Use details from the plan. Name specific moments where things went wrong and why.

2. THE UNDERLYING ASSUMPTION — The one thing the user took for granted that made this failure possible. One sentence.

3. EARLY WARNING SIGNS — 1–2 concrete, observable signals indicating this failure mode is starting. Things you can see or measure, not vague feelings.

Total under 300 words. Be direct. Don't hedge. Don't sugarcoat.
```

### Step 5 — Synthesis

After all agents complete, read every deep-dive and produce:

1. **The Most Likely Failure** — Most probable scenario given what's known. Why? This is what the user should focus on first.
2. **The Most Dangerous Failure** — Worst-damage scenario, even if less likely. Worth insuring against.
3. **The Hidden Assumption** — Across all analyses, the single biggest thing the user is taking for granted. Often where the real value of a premortem lives.
4. **The Revised Plan** — Concrete changes mapped to specific failure scenarios. Not "consider your pricing." Instead: *"test pricing at $X with 20 people before committing publicly."* Each revision tied to a failure mode.
5. **The Pre-Launch Checklist** — 3–5 specific things to verify, test, or put in place before executing. Each item prevents or detects one identified failure.

### Step 6 — Generate the visual report

Save a single self-contained HTML file: `premortem-report-[timestamp].html`.

Design principles:
- Dark background (~`#0a0e1a`), clean typography, scannable
- Synthesis section (most likely / most dangerous / hidden assumption / revised plan / checklist) prominently at the top — most readers stop there
- One card per failure reason with: header (the reason), failure story, underlying assumption, early warning signs. Distinct accent colors per card so they're visually scannable
- Visual indicator of severity/likelihood per failure
- Grid/card layout for the agent findings so the full premortem scope is visible at a glance
- Footer: timestamp and what was premortemed

Open the file after generating it.

### Step 7 — Save the transcript

Save full transcript: `premortem-transcript-[timestamp].md` in the same directory.

Contents:
- Context gathered (what, who, success criteria)
- Raw failure reasons from step 3
- All agent deep-dives
- Full synthesis

## Output

Every premortem session produces two files in the user's workspace:

```
premortem-report-[timestamp].html    # visual report (primary)
premortem-transcript-[timestamp].md  # full transcript (reference)
```

In chat, also give a 3-sentences-max summary: most likely failure, hidden assumption, single most important revision. The report has the rest.

## Worked Example

**User:** *"premortem this: I'm about to launch a $297 live workshop on how to use Claude Cowork for marketing teams. 50 seats. Targeting marketing managers at companies with 10–50 employees."*

**Raw premortem identifies 6 failure reasons:**
1. Marketing managers at this company size need approval to spend $297 on professional development — friction not accounted for.
2. "Claude Cowork for marketing" is a tool-specific pitch in a market where most managers are still figuring out whether AI is relevant at all.
3. The audience that actually buys might be solopreneurs, not team managers — mismatch between content and attendees.
4. Building a workshop for marketing teams requires demo environments with realistic marketing data and multi-seat setups: 5 weeks of prep, not the 2 budgeted.
5. If 60% of attendees are solopreneurs, reviews and case studies won't resonate with the marketing-manager audience needed for future cohorts.
6. At $297 × 50 seats, max revenue is $14,850 — may not justify prep time vs. other revenue opportunities.

**6 agents go deep in parallel**, each producing a failure story, underlying assumption, and early warning signs.

**Synthesis:**
- *Most likely failure* — audience mismatch: targeting people who need approval to spend $297, friction not accounted for.
- *Most dangerous failure* — attracting solopreneurs instead of team managers means case studies won't resonate with the actual target buyer for future cohorts, compounding over time.
- *Hidden assumption* — "marketing managers at 10–50 person companies" is treated as a reachable audience, but these people don't self-identify that way and don't hang out in the same places.
- *Revised plan* — run a $47 pilot for 20 people first; use it to identify whether actual buyers are managers or solopreneurs; build the full workshop for whoever shows up.

## Critical Rules

- **Always set the premortem frame explicitly.** "This has already failed" is the mechanism. Without it, the analysis defaults to polite risk assessment.
- **Always spawn failure-deep-dive agents in parallel** in a single message.
- **Comprehensive, not padded.** Don't stop at 3 if there are 7. Don't force 7 if there are only 3.
- **The synthesis is the product.** Most readers will skim the failure cards. Make synthesis specific and actionable.
- **Don't sugarcoat.** Tell the user things they don't want to hear before reality does.
- **The revised plan must be concrete.** "Consider testing your pricing" is useless. "Run a $47 pilot with 20 people before committing to the $297 workshop" is useful.
- **Respect the minimum context bar.** One more question beats a generic premortem.
- **This is not the LLM Council.** Council = multiple perspectives on a current decision. Premortem = work backward from assumed failure. Different mechanism, different output. If the user wants perspectives rather than failure analysis, suggest the council instead.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Skipping "this has already failed" framing | Always state it out loud before generating failures |
| Running agents sequentially | Single message, parallel dispatch — every time |
| Generic failure reasons ("market risk", "execution risk") | Force specificity — name actual moments, prices, people, dates from the plan |
| Padding to a round number | If 4 real failures exist, list 4. Don't invent a 5th |
| Vague revisions ("review your strategy") | Every revision must be something the user can do this week |
| Premortem on insufficient context | Ask one more focused question instead of producing a generic report |
| Treating it like the LLM Council | Council ≠ premortem. If perspectives are wanted, route there |
