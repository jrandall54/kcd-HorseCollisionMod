# Documentation style

Rules for everything in this repository except `TESTING_DIARY.md`, which is a
log and follows its own conventions.

`python tools/lint_docs.py` enforces the checkable parts and runs as part of
`build.ps1`. The rest is judgement.

## Know which of the four things you are writing

From [Diátaxis](https://diataxis.fr/), which separates documentation by what the
reader needs. Mixing two types in one document is what produces a junk drawer.

| Type | Serves | In this repository |
| --- | --- | --- |
| Tutorial | Learning by doing | none |
| How-to | Completing a task | `RELEASING.md`, `DEV_LOOP.md` |
| Reference | Looking up a fact | `TECHNICAL_DETAILS.md`, `docs/api/` |
| Explanation | Understanding why | `HOW_IT_WORKS.md` |

A how-to is numbered steps in the order performed. Reference is looked up, not
read through, so it is organised for scanning. Explanation may argue a case.
None of them is a story about how the work went.

## Person

Follow the [Google developer documentation style guide](https://developers.google.com/style/person):
second person for the reader, third person for the software.

- **No first person.** Not `we`, `our`, `us`, `I`, `my`. Documentation has no
  narrator and no authors visible in the text.
- **Second person for the reader.** `your game install`, `the settings you can
  change`. This is correct and should not be avoided.
- **Imperative for instructions.** `Bump the version`, not `You should bump the
  version`.
- **Third person for the software.** `The build refuses a mismatched manifest`,
  not `we refuse`.

## No narrative

Documentation describes the system as it is now. It is not a record of how it
came to be, and carries no dates relative to when it was written.

| Rejected | Instead |
| --- | --- |
| `the one that cost the most` | `the least obvious requirement` |
| `four cold-start test cycles proved` | *(cut entirely)* |
| `this session`, `earlier today` | *(cut entirely)* |
| `it turned out that X` | `X` |
| `build 2.1.0-dev.1 did that and broke` | `an earlier layout did that and broke` |

Findings, dead ends and the order things were discovered in belong in
`TESTING_DIARY.md`. That is what it is for.

## Cut

- **Marketing words.** `seamlessly`, `robust`, `powerful`, `leverage`,
  `delve`, `unlock`, `elevate`, `cutting-edge`.
- **Intensifiers.** `very`, `really`, `quite`, `extremely`. If the claim
  needs propping up, the claim is weak.
- **Filler.** `basically`, `essentially`, `simply`.
- **Throat-clearing.** `It is worth noting that`, `Please note`. State the
  thing.
- **Telling the reader what they think.** `obviously`, `clearly`,
  `of course`.
- **Em dashes.** Use a comma, a colon or a full stop.
- **Emoji.**

Sentences over 40 words are flagged. Long is not automatically wrong, but it is
worth a second look.

## Comments

Comments explain **why**, not what. Code already says what it does; a comment
that restates it goes stale and earns nothing.

Worth a comment:

- Why a value is what it is, especially if it was measured.
- What breaks if this changes, especially silently.
- A constraint imposed from outside: an engine behaviour, an API rule, a
  failure mode found by testing.

Not worth a comment:

- What the next line does.
- Anything the function name already says.

The test: if the comment would still be true after the code is rewritten, it
is probably about intent and worth keeping.

## Before committing documentation

```
python tools/lint_docs.py --warnings
```

Zero errors is required. Warnings are advisory, and each one should be looked
at rather than dismissed as a batch.
