# Work Routing

How to decide who handles what.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| Architecture, scope, enterprise backup requirements | Ripley | Define backup scope, review trade-offs, approve demo architecture |
| Azure infrastructure and deployment | Dallas | Bicep modules, Azure resource layout, deployment parameters |
| Data workload and Cosmos DB app code | Parker | Data generator, Cosmos DB writes, sample document schema |
| Technical writing and documentation updates | Ash | README, architecture docs, runbooks, operator guidance, GitHub issue body drafting |
| Documentation strategy and demo narrative review | Lambert | Documentation structure, demo storyline, stakeholder narrative, technical-writing review |
| Code review | Ripley | Review architecture, quality, reliability, and maintainability |
| Testing and validation | Bishop | Write tests, find edge cases, verify backup/restore scenarios |
| Scope & priorities | Ripley | What to build next, trade-offs, decisions |
| Session logging | Scribe | Automatic — never needs routing |
| Work monitoring | Ralph | Backlog checks, issue pickup, keep-alive monitoring |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Lead |
| `squad:{name}` | Pick up issue and complete the work | Named member |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, the **Lead** triages it — analyzing content, assigning the right `squad:{member}` label, and commenting with triage notes.
2. When a `squad:{member}` label is applied, that member picks up the issue in their next session.
3. Members can reassign by removing their label and adding another member's label.
4. The `squad` label is the "inbox" — untriaged issues waiting for Lead review.

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work.
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.** Don't spawn an agent for "what port does the server run on?"
4. **When two agents could handle it**, pick the one whose domain is the primary concern.
5. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
6. **Anticipate downstream work.** If a feature is being built, spawn the tester to write test cases from requirements simultaneously.
7. **Issue-labeled work** — when a `squad:{member}` label is applied to an issue, route to that member. The Lead handles all `squad` (base label) triage.
8. **Technical writing** — all technical writing and issue-body drafting routes to Ash using `claude-opus-4.6`.
