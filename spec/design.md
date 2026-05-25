# Camp Comics — Design Spec

A pipeline for generating personalized 12-panel D&D-style comic books for
summer camp participants, where each camper's face is rendered into a fantasy
hero in their chosen character class, performing a positive-themed quest.

This document is the source of truth for the design. Every other artifact in
this project (YAML templates, Python orchestration script, HTML/CSS render
template) is an implementation of decisions captured here.

---

## 1. Scope and constraints (first camp)

| | |
|---|---|
| Campers per week | 30–60 |
| Camper age range | 18–19 (deliberate first-run scope) |
| Staff running pipeline | 1–2 (camp staff + you) |
| Photo collection | Day 1, dedicated photo station |
| Generation window | Days 3–4 evenings |
| Delivery | Day 5 reveal ceremony |
| Output per camper | 5-page printed softcover comic, comic-standard 6.625×10.25" |

Future-camp items deferred from this scope (see §13):
- Campers under 18 (re-activates consent/retention stack)
- Cabin group-shot panel (multi-character likeness is too brittle in 2026)
- Lulu Print API for automated delivery (local print for first run)

---

## 2. Tool stack

| Layer | Tool | Notes |
|---|---|---|
| Image generation | **Gemini 2.5 Flash Image** ("Nano Banana") via **Vertex AI** | Vertex AI tier specifically — adult faces should not be used for model training. Same cost as default API (~$0.04/image). |
| Orchestration | **Python 3.11+** | Single script, runnable per-camper. |
| Image-gen SDK | `google-genai` with `vertexai=True` | Newer unified client. |
| Layout / PDF | **Jinja2** + **WeasyPrint** | HTML+CSS → print-ready PDF. |
| Storage | Local filesystem | Intake photos and intermediate images deleted 30 days post-camp (policy hygiene even with adult campers). |

Total API cost estimate: ~60 campers × 13 images × 1.3 avg-attempt-factor ≈
1,000 calls × $0.04 = **~$40 per camp**.

---

## 3. Class list and value mapping

Six classes, gender-neutral costuming by default, each carrying a distinct
positive value that lands at **Panel 9 (the class-specific solution)**:

| Class | Value (panel 9 payload) | Notes |
|---|---|---|
| Warrior | Courage in protecting others | Shielding, not conquering. |
| Wizard | Curiosity and the patience to learn | Setback in panel 8 = arrogance; payoff = humility-driven study. |
| Druid | Listening before acting | Solution from observation, not force. |
| Bard | The power of telling your own story | For kids who don't self-identify as "fighters." |
| Healer | Empathy as strength | Support class reframed as protagonist. |
| Trickster/Scout | Cleverness and the non-obvious path | Renamed Rogue to dodge "thief" baggage. |

Day-1 intake collects each camper's **top 3 ranked class choices** so cohorts
can be rebalanced if one class is over-picked.

---

## 4. Story structure (12-panel arc)

Hero's-journey compressed to 12 beats. Same skeleton for every class; only the
scene imagery and the panel-9 payload change. Personalization tokens slot into
panels **2, 7, and 11**.

### Act I — Ordinary World → Call (1–4)
1. **Everyday self** — camper as themselves, modern clothes, ordinary setting.
2. **The summons** — *[personalized: hometown landmark]* — something otherworldly intrudes in a place they recognize.
3. **Crossing the threshold** — mid-transformation.
4. **Transformation reveal** — full class regalia, hero shot. *The "wow, that's me" panel.*

### Act II — The Quest (5–9)
5. **The world** — establishing wide shot of the realm, camper small in frame.
6. **The guide** — meeting a mentor or companion figure.
7. **The challenge appears** — *[personalized: fear made manifest in fantasy form]*.
8. **First attempt fails** — the obvious approach doesn't work.
9. **The class-specific solution** — **values payload**, dramatized via the class's distinctive way of solving things.

### Act III — Return (10–12)
10. **Triumph** — quiet competence, not power fantasy.
11. **The reward** — *[personalized: quality they want to grow into, depicted symbolically]*.
12. **Return home, changed** — mirror of panel 1, same setting, but holding one small token from the quest.

The mirror between panels 1 and 12 is the emotional spine of the story. Do
not break it without intent.

---

## 5. Personalization tokens

Collected day 1 alongside the photo on a short index card. **You translate
the raw tokens into fantasy prompt fragments mid-week** (the highest-skill,
lowest-volume work in the pipeline — ~3 fragments × 60 campers × 30 sec each
≈ 90 min total).

| Token | Where it's used | Translation example |
|---|---|---|
| `hometown_landmark` (universal) | Panel 2 background | "the old lighthouse" → "a lighthouse glowing on a windswept cliff" |
| `fear_image` (universal, *translated* from raw fear) | Panel 7 obstacle | "fear of letting my family down" → "a translucent ghostly figure of an elder looking on with sorrowful eyes" |
| `quality_symbol` (universal, *translated* from raw quality) | Panel 11 reward | "courage" → "a small lit torch handed to them" |
| `class_specific` (one per class) | Class-flavored beat | Druid: animal companion; Wizard: question to answer; Bard: art form; Healer: mentor figure; Warrior: someone to protect; Trickster: problem to solve. |

Also collected: `name`, optional `character_name` (appears on cover), `cabin`,
`top_3_class_choices`.

---

## 6. Art style anchor

**Painted fantasy illustration in the style of a D&D 5E sourcebook.**

Three layers of anchoring (all three are required — none are optional polish):

1. **Style suffix** appended verbatim to every prompt:
   > "painted digital fantasy illustration, in the style of a Dungeons & Dragons 5th Edition sourcebook, cinematic lighting, painterly brushwork, high detail on face. The character's face must match the reference photo exactly. No text or letters anywhere in the image."

2. **Per-class palette config** baked into the class YAML — lighting descriptor + color descriptor — concatenated into every prompt for that class.

3. **Pinned class hero-card reference image** — one painted full-body portrait per class, in full regalia, generic face, generated pre-camp and iterated to perfection. Passed as a reference image alongside the camper's photo on every API call for that class. Lives at `templates/refs/{class}_hero.png`.

The hero-card reference is the single most effective lever for cross-panel
visual consistency. It locks costume design, palette, and painted style for
all 12 panels of every camper in that class.

---

## 7. Reference inputs to Nano Banana

Every panel API call sends **two reference images** plus the prompt:
1. `intake/{camper_id}/photo.jpg` — the camper's one head-and-shoulders portrait.
2. `templates/refs/{class}_hero.png` — the class style anchor.

### Photo collection protocol (day 1)
- **One** photo per camper. One excellent reference beats multiple mediocre ones for identity preservation.
- Head-and-shoulders, front-facing, eyes to camera.
- Neutral background (white sheet or blank wall).
- Even soft lighting (window light or ring light, no harsh side shadow).
- Neutral or slight smile, mouth closed or barely open.
- Glasses-wearers photographed *with* glasses on (consistency).
- Minimum 1024×1024.
- Same setup all day: one tripod, one spot, one light.

### Day-1 photo QA gate
Before the camper leaves the photo station, run a single test generation
("this person as a generic fantasy hero in painted D&D style") and visually
verify the likeness transfers cleanly. If not, retake on the spot. Eliminates
Failure Mode 2 (unusable photo discovered mid-week with no recourse).

---

## 8. Prompt anatomy

A panel prompt is assembled at runtime from a 7-part skeleton:

```
{scene_with_tokens_filled}, {composition}.
Costume: {class_costume}.
Lighting and color: {class_palette_lighting}, {class_palette_colors}.
Style: {STYLE_SUFFIX}
Image aspect ratio: {aspect_ratio}.
```

| Part | Source | Variability |
|---|---|---|
| Scene | Class YAML, panel-specific, with `{token}` slots | Per panel, per camper for panels 2/7/11 |
| Composition | Class YAML, panel-specific | Per panel |
| Costume | Class YAML, class-level | Per class (constant across all 12 panels) |
| Palette | Class YAML, class-level | Per class |
| Style suffix | Constant | Identical for all generations |
| Aspect ratio | 4:3 panels, 3:4 cover | Per call type |

### Aspect ratios
- **Panels 1–12**: 4:3 landscape — fits the 2×2 grid on comic-standard pages with breathing room for painted detail.
- **Cover (panel 13)**: 3:4 portrait — fills the cover page with negative-space headroom at the top for the title overlay.

---

## 9. Captions

Every panel has **one third-person mythic-register narration caption**, ≤12
words, written into the class YAML alongside the prompt. Same narrator voice
across all 6 classes — only the words change.

Captions are:
- **Never** generated by Nano Banana (the prompt explicitly suppresses in-image text).
- **Always** rendered as CSS overlays at PDF generation time, on top of the panel image, in a fantasy serif typeface.

Hard 12-word cap per caption keeps the CSS layout uniform across all 60 books.

---

## 10. Pipeline stages

### Stage 0 — Pre-camp (one weekend, ~12 hrs)
1. Write 6 class YAML templates (`templates/{class}.yaml`).
2. Generate 6 hero-card reference images interactively in the Gemini UI; save to `templates/refs/{class}_hero.png`. Iterate until each looks like a sourcebook character.
3. Write fallback prompt library (one safe fallback per panel slot per class, for when generation persistently fails).
4. Build token translation cheat sheet (common fears → fantasy images, common qualities → symbols).

### Stage 1 — Day 1 (~5 hrs staff time, parallel)
1. Photo station: each camper photographed per §7 protocol.
2. Intake card filled out per §5.
3. Photo QA gate per §7.
4. Files saved as `intake/{camper_id}/photo.jpg` + `intake/{camper_id}/tokens.json`.
5. Evening: cohort balancing (resolve class conflicts using top-3 rankings).

### Stage 2 — Days 3–4 evenings (~12 hrs total)
For each camper:
1. Manually translate raw tokens (fear, quality) into fantasy fragments. Write back to `tokens.json` as `_translated` fields.
2. Run `python scripts/generate.py --camper {id} --class {class}`.
3. For each of 13 images (12 panels + cover): script calls Vertex AI, displays image, prompts terminal review (accept / re-roll / tweak / skip). Max 4 attempts per panel; attempt 4 is the prompt-tweak attempt.
4. Save approved images to `outputs/{camper_id}/`; write `manifest.json` for the layout step.

### Stage 3 — Day 5 morning (~3 hrs)
1. Run layout renderer: Jinja2 fills `comic.html.j2` per camper from manifest; WeasyPrint renders to `outputs/{camper_id}/comic.pdf`.
2. Render cabin roster page using each cabin's panel-4 hero shots.
3. Local print + saddle-stitch bind. Done in time for afternoon reveal.

---

## 11. Quality rubric and re-roll budget

### Pass criteria — three hard rules, in order
A panel passes if and only if all three hold:
1. **Likeness**: would a cabinmate recognize the camper from this image without prompting?
2. **Hands and weapons**: no melted hands, six fingers, weapons fused to wrists.
3. **Tone-appropriate**: not scary, gory, sexualized, or unsettling.

Composition, exact pose, perfect background are bonus, not pass/fail.
Holding "good enough" over "perfect" is the single biggest schedule lever.

### Re-roll budget
- Hard cap: **4 attempts per panel**.
- Attempts 1–3: re-roll with same prompt (fixes random wobble; pass rate cumulative ~85%).
- Attempt 4: prompt-tweak attempt. Operator edits the prompt in the terminal before the final call.
- If attempt 4 fails → escalate per §12 Mode 1.

---

## 12. Failure-mode escalation ladder

### Mode 1 — Panel-level persistent failure
Substitute from the pre-built fallback prompt library (one safe fallback per
panel slot per class, written in Stage 0). Less personalized, guaranteed to
render. Mark in manifest so post-hoc audit is possible.

### Mode 2 — Unusable source photo
Prevented by the day-1 photo QA gate (§7). If discovered mid-week anyway:
re-shoot the camper at the photo station during a free period. Keep photo
station operational through day 3 for this reason.

### Mode 3 — Whole-camper persistent drift
Diagnostic stop-rule: if 4 of the first 6 panels fail likeness, halt generation
for this camper. Don't burn 13 calls.

Recovery options in priority order:
1. Re-shoot photo with different lighting; retry.
2. Add identity-hardening fragments to the prompt: "expressive distinct facial features, specific to the reference photo."
3. Last resort: switch to a **6-panel emergency template** (cover + Act I + Act III only, skipping Act II). Pre-built alternate `comic_short.html.j2` layout for this case. Better than no book.

---

## 13. Parked for future-camp redesign

| Item | Why deferred | Re-activation trigger |
|---|---|---|
| Cabin group-shot panel | Multi-character reference is too brittle in 2026 (≤60% likeness pass rate at 2 faces, lower at 3+). Would force HITL back into Stage 3. | When Nano Banana or a successor reliably handles 5+ reference faces in one image. |
| Lulu Print API integration | First camp uses local print to avoid coupling pipeline to print fulfillment debugging. | After local-print run validates the PDFs render correctly. |
| Minors handling (under-18 campers) | First camp scoped to 18–19 deliberately to focus on process. | Any future camp with minors. Re-activates: parental consent form, AI-disclosure language, opt-out fallback book pipeline, accelerated photo retention/deletion. |
| Opt-out fallback book | Not needed with 18+ campers (opt-out = not participating). | Same as above. |

---

## 14. Open risks and watch items

- **Two-evening generation window** is load-bearing. If days 3–4 evenings get consumed by camp duties, generation collapses. Fallback: shift to post-camp generation with mailed/emailed delivery instead of reveal ceremony.
- **Google Fonts in WeasyPrint** needs internet at render time, or fonts must be downloaded locally beforehand. Worth caching `Cinzel` and `EB Garamond` locally pre-camp.
- **Cohort balance** — if 30 of 60 campers all pick wizard, you have one bottleneck class. The top-3 ranking system handles this but staff need to actually do the reshuffling on day 1 evening.
- **Caption length variance** — if any caption exceeds the 12-word cap, the CSS grid will look uneven across books. Hold the line on the cap.
- **API rate limits** — Vertex AI image-gen has per-minute quotas. At 60 campers × 13 images, a serial script will be fine; parallelization isn't needed and may hit limits.
