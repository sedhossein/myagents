# Project knowledge graph (graphify)

graphify keeps one knowledge graph per project in `graphify-out/` (`graph.json`, `GRAPH_REPORT.md`, `graph.html`). It maps code, docs, and configs and traces how they connect. Code is parsed locally with no model, so building and updating it is free.

When `graphify-out/graph.json` exists in the project:
- For questions about architecture, dependencies, "where is X", "what calls X", or "what breaks if I change X", query the graph first and read files only for the lines you then need:
  - `graphify query "<question>"` for a scoped subgraph
  - `graphify path "<A>" "<B>"` for how two things connect
  - `graphify explain "<X>"` for one concept and its neighbours
  - `graphify affected "<X>"` for what a change would impact
- Read `graphify-out/GRAPH_REPORT.md` only for a broad overview.
- After you change code files, run `graphify update .` to refresh the graph (no model, no cost).

When it does not exist:
- Work as usual. Do not build it unasked: a first build of a large repo can take a while and may call a model for docs.
- If the user asks to map or understand a whole codebase, suggest `/graphify .` once. A code-only graph needs no API key: `graphify extract . --code-only`.

Never commit `graphify-out/`.
