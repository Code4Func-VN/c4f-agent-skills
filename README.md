# c4f-agent-skills

A collection of Claude Code skills for software engineering workflows. Each skill lives in `skills/<name>/SKILL.md` and is loaded by Claude Code when the trigger conditions are met.

## How skills work

A skill is a markdown file with a YAML frontmatter block that tells Claude Code:
- **name** — the skill identifier
- **description** — when to activate it (Claude reads this to decide relevance)
- **allowed-tools** — which tools the skill is permitted to use
- **disable-model-invocation** — if `true`, the skill body is injected as a system prompt without consuming an LLM call

The body of the skill is instruction text that Claude follows when active. Skills can reference companion files in `references/`, `scripts/`, or `assets/` subdirectories.

To install a skill, copy its folder into `.claude/skills/<name>/` in your project (or `~/.claude/skills/<name>/` for global use), then reference it in your `claude.json`:

```json
{
  "skills": ["<name>"]
}
```

---

## Skills reference

### Git & version control

#### `git`
**When to use:** Any time code is written, modified, or deleted.

Auto-commits changes using conventional commits (`feat:`, `fix:`, `refactor:`…), runs a security scan before committing, and can open pull requests. Also invocable as `/git pr` or `/git scan`.

References: branch strategy, commit conventions, conflict resolution, PR workflow, security scanning.

---

#### `git-guardrails-claude-code`
**When to use:** When you want to prevent Claude from accidentally running destructive git commands.

Sets up a `PreToolUse` hook that intercepts and blocks: `git push`, `git reset --hard`, `git clean -f/fd`, `git branch -D`, `git checkout .`, `git restore .`. Supports project-scoped or global installation.

Includes: `scripts/block-dangerous-git.sh` — the hook script that gets installed.

---

### Go backend

#### `go-engineer`
**When to use:** Writing, reviewing, testing, or scaffolding Go code.

Enforces idiomatic Go style (clarity → simplicity → concision), error handling conventions (`fmt.Errorf("save user: %w", err)`), clean architecture with Echo + GORM + Docker, and test-first discipline. Blocks `feat`/`fix` commits without tests.

References: API design, blueprint structure/config, concurrency, database patterns, error handling, testing layers, linting, logging, performance, code review checklist.

Scripts: project scaffolding, lint setup, naming/error/interface checks, benchmark comparison, pre-review automation.

---

### Ant Design / React UI

#### `ant-design`
**When to use:** Making decisions about antd 6.x, Ant Design Pro, or Ant Design X — component selection, theming, SSR, a11y, performance, CRUD patterns, AI/chat UI.

Decision guide (not a tutorial). Follows the SPOT framework: Scope → Process → Output. Mandates querying `@ant-design/cli` before writing any component code. Enforces: one root `ConfigProvider`, tokens-first theming, no `.ant-*` selector coupling.

References: `antd-cli.md` — offline CLI workflow for API lookup, demos, migration, linting, bug reporting.

---

#### `antd`
**When to use:** Writing antd components, debugging antd issues, querying APIs/props/tokens/demos, migrating between versions, or analyzing antd usage.

CLI-focused skill. Requires `@ant-design/cli` (`which antd || npm install -g @ant-design/cli`). Covers 10 scenarios: writing components, full docs, debugging, migration, project analysis, changelogs, component discovery, bug reporting, CLI bug reporting, MCP server mode. Always uses `--format json`.

---

### Architecture & design

#### `improve-codebase-architecture`
**When to use:** Improving architecture, finding refactoring opportunities, making a codebase more testable or AI-navigable.

Surfaces **deepening opportunities** — refactors that turn shallow modules (large interface, thin implementation) into deep ones (small interface, large implementation). Uses Ousterhout's vocabulary: module, interface, depth, seam, adapter, leverage, locality. Three-phase process: Explore → Present candidates → Grilling loop. Reads `CONTEXT.md` and `docs/adr/` for domain language.

Companion files:
- `DEEPENING.md` — how to classify dependencies and test across seams
- `INTERFACE-DESIGN.md` — parallel sub-agent pattern for exploring alternative interfaces
- `LANGUAGE.md` — shared vocabulary (must use these terms exactly)

Pairs with: `domain-model`, `design-an-interface`.

---

#### `design-an-interface`
**When to use:** Designing an API, exploring interface options, comparing module shapes, or when someone says "design it twice".

Spawns 3+ sub-agents in parallel, each with a different design constraint (minimize methods / maximize flexibility / optimize for common case). Presents designs sequentially, then compares by depth, locality, and ease of correct use. Based on Ousterhout's "Design It Twice" principle.

---

#### `domain-model`
**When to use:** Stress-testing a plan against the project's domain language, sharpening terminology, managing `CONTEXT.md` and ADRs.

Conducts a relentless grilling session: challenges vague terms, cross-references code against stated behavior, updates `CONTEXT.md` inline as terms are resolved, and offers ADRs only when a decision is hard to reverse, surprising without context, and the result of a real trade-off.

Companion files:
- `CONTEXT-FORMAT.md` — format and rules for `CONTEXT.md` (single vs multi-context repos)
- `ADR-FORMAT.md` — minimal ADR format with criteria for when to write one

---

### Development process

#### `tdd`
**When to use:** Building features or fixing bugs using TDD, red-green-refactor, or test-first development.

Enforces vertical slices (one test → one implementation → repeat), not horizontal slices (all tests first, then all code). Tests must verify behavior through public interfaces only — no mocking internal collaborators, no testing private methods. Refactor only after GREEN.

Reference files:
- `deep-modules.md` — small interface + lots of implementation (Ousterhout)
- `interface-design.md` — accept dependencies, return results, small surface area
- `mocking.md` — mock only at system boundaries; prefer SDK-style interfaces
- `refactoring.md` — duplication, shallow modules, feature envy, primitive obsession
- `tests.md` — good vs bad test examples with red flags

---

#### `grill-me`
**When to use:** Stress-testing a plan, getting challenged on a design decision, or whenever you say "grill me".

Interviews you relentlessly about every aspect of a plan — one question at a time, walking down each branch of the decision tree. Provides a recommended answer for each question. Explores the codebase to answer questions it can resolve itself.

---

#### `zoom-out`
**When to use:** Unfamiliar with a section of code and need to understand how it fits into the bigger picture.

One-liner skill: instructs the agent to go up a layer of abstraction and produce a map of all relevant modules and callers. Zero LLM overhead (`disable-model-invocation: true`).

---

## Adding a new skill

1. Create `skills/<name>/SKILL.md` with the frontmatter schema above.
2. Add reference files under `skills/<name>/references/` or `skills/<name>/scripts/` as needed.
3. Keep the `description` field precise — Claude uses it to decide when to activate the skill.
4. Test with a real task before committing.
