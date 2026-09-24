# Luxir 0.1.0 — working notes for integrators

Compiled 2026-09-22 from https://luxir.org/docs/0.1.0/. Luxir is pre-1.0 and can change
without backward compatibility. When these notes and the running server disagree, the
server wins: update this file.

## Distribution and runtime

- Single static-ish executable. Linux x86-64 only, glibc ≥ 2.35 (Ubuntu 22.04+).
  No arm64 build and no official container image.
- Three builds per release, one per CPU tier: `x86-64-v2` (SSE4.2), `v3` (AVX2), `v4` (AVX-512).
  - URL pattern: `https://github.com/luxir-search/luxir/releases/download/v<VER>/luxir-<VER>-linux-x86_64-<tier>`
  - Checksums: `.../v<VER>/SHA256SUMS`
- A build for a tier the CPU lacks refuses to start with `CPU ISA level is lower than required`.
  `luxir --version` prints e.g. `Luxir 0.1.0 (x86-64-v3)`.
- Detect supported tiers with `/lib64/ld-linux-x86-64.so.2 --help | grep x86-64-v`.
  Lines marked `supported` are usable.
- Named time zones need the system zoneinfo database (install `tzdata`).
- Apache-2.0 licensed, so redistributing the binary inside an image is allowed.

## Server flags that matter

| Flag | Default | Notes |
|---|---|---|
| `--store.backend=fs --store.data-dir=DIR` | in-memory backend | **Default loses all data on exit.** Always use fs in DDEV/CI. |
| `--server.http.port` / `-p` | 9400 | Binds 0.0.0.0; there is no listen-address option |
| `--server.grpc.port` | HTTP port + 1 (9401) | gRPC always starts |
| `--max-ram-mb` | 25% of RAM or cgroup limit | Node-wide budget. Indexing gets half. |
| `--log-level` | | trace/debug/info/warn/error/critical |
| `--read-only` | | Serves an existing data dir without the write lock |
| `--no-indexing.auto-create-collection` | auto-create on | Otherwise any `_update` creates the collection |
| `--indexing.max-request-body` | 32MB | Caps buffered JSON bodies and atomic groups |

Operational limits:
- No TLS, authentication, authorization or CORS. Never expose the port publicly.
- No graceful shutdown on SIGTERM. Updates not yet committed are lost; the last commit survives.
- Single node. No replication and no snapshot API. Backup = stop writes, commit, stop the process, copy the data dir.
- `GET /health` returns `{"status":"ok"}`. It reports process liveness only.

## HTTP endpoints

| Method + path | Purpose |
|---|---|
| `GET /health` | liveness |
| `GET\|POST /collections/{c}/_search` | search; response is chunked NDJSON |
| `POST /collections/{c}/_update` | JSON update, or NDJSON stream (`Content-Type: application/x-ndjson`) |
| `GET /collections/{c}/_schema[?view=resolved]` | authored schema, or the resolved representations |
| `POST /collections/{c}/_schema[?mode=replace_all]` | set named definitions (default `mode=set`), or replace everything |
| `GET /collections` (`/collections/_list`) | list collection names |
| `POST /collections/_create` | body `{"name": "...", "schema": {...}}`; 409 if it exists |
| `POST /collections/_delete` | body `{"name": "..."}`; synchronous; deletes the data |
| `GET /_stats`, `GET /collections/{c}/_stats` | operational stats; a zero-valued field is omitted, so treat an absent count as 0 |

Collection names are one URL path component. Names starting with `_` are reserved.
**VERIFY** the allowed character set and maximum length empirically.

Every JSON body ends with a newline. `?pretty` formats output. `?explain=request` returns the
canonical request without executing it. `?explain=resolved` also shows which physical fields
each name resolved to.

## Errors — read this carefully

- Shape: `{"request_id": ..., "error": {"kind": ..., "code": ..., "message": ...}}`.
  `code` is the stable machine key.
- `kind` → HTTP status: `invalid_request` 400, `not_found` 404, `already_exists` 409,
  `failed_precondition` 403, `resource_exhausted` 429/413, `unavailable` 503, `internal` 500.
- **Search:** once streaming has started, a failure arrives with **HTTP 200** as the final
  NDJSON line containing `error`. It invalidates every earlier line of that response.
  Clients must parse every line and check for `error`.
- **Update:** HTTP success does not mean the update succeeded. Check the body's `status`:
  - `ok`: everything applied
  - `partial`: some documents failed; see `errors[]` with `id`, `index` and `error`, plus `total_errors`
  - `error`: nothing applied, or a request-level failure (top-level `error`)
- Unknown JSON keys are errors. Unknown URL parameters are ignored.

## Indexing

```json
POST /collections/books/_update
{"docs": [{"id": "b1", "title_t": "Dune", "year_i": 1965}],
 "delete_ids": ["old"],
 "commit": {}}
```

- `id` is the reserved unique key. Writing an existing id replaces the **whole** document.
- Request fields: `request_id`, `docs`, `delete_ids`, `allow_dups`, `all_or_none`,
  `return_ids`, `commit`, `field_map`, `drop_unmapped`.
- `commit: {}` publishes immediately and waits. `{"commit_within_ms": N}` publishes within
  N ms and returns sooner. `?commit=true` on the URL forces an immediate commit.
  A body of just `{"commit": {}}` commits with no documents.
- Documents are only searchable after a commit.
- NDJSON streaming: one document per line; `{"_update_": {...}}` opens a group with options;
  `{"_end_": {"commit": {}}}` closes it. There is no limit on stream size.
- **Delete-by-query does not exist. Partial (field-level) updates do not exist.**
- Values: dates are ISO-8601 strings or epoch milliseconds. `geo_point` is `[lon, lat]`.
  A vector is a number array.

## Schema

- Field types: `text`, `string`, `int` (int64), `float`, `double`, `date` (millisecond
  precision), `vector`, `geo_point`, `id`.
- Field properties:
  - `type`, `index` (`match` | `range` | `none`), `column`, `multi`, `stored`
  - `analyzer` (text only), `normalizer` (string only)
  - `long_terms`, `variants`, `defaults`, `parent`
  - vector only: `dims`, `metric`, `normalized`, `normalize_on_write`
- Analyzer components:
  - tokenizers: `unicode_word`, `whitespace`, `keyword`
  - filters: `nfkc_cf`, `lowercase`, `fold`, `english_possessive`, `kstem`
  - **No stopwords, synonyms, or non-English stemmers.**
- Built-in suffix templates, used when a field has no explicit definition:
  - `_s` / `_ss`: string, single / multi
  - `_i`/`_is`, `_f`/`_fs`, `_d`/`_ds`, `_dt`/`_dts`: int, float, double, date (single / multi)
  - `_t`: English text — `unicode_word` + `nfkc_cf`, `fold`, `kstem`
  - `_un`: unstemmed text, case-folded
  - `_name` / `_names`: text plus a string `s` variant
  - `_v` / `_vs`: vector
  - There is no geo template.
- Explicit field definitions take precedence over templates. `POST ...?mode=replace_all` with
  only `fields` removes all templates. `id` and `_version_` are added automatically.
- **Variants:** a field `f` with `"variants": {"s": {"type": "string"}}` also indexes its value
  as `f__s`. A text field with exactly one string variant searches words on `f` but sorts and
  facets on `f__s`. `__` is reserved in authored field names.
  Physical names are limited to 127 bytes.
- Analyzed text has no column, so sorting text requires a string variant.
- Numeric fields are column-backed; add `"index": "range"` for a points index.
  Queries work without it, but slower.
- **Schema edits never rewrite existing documents and aren't checked for compatibility.**
  Changing a field's type or analysis means a new field name, or recreate the collection
  and reindex.

## Search

Shorthand body (a single `top_docs` named `q`):

```json
{"query": <string|object>, "filter": [...], "limit": 10, "offset": 0,
 "get_number": true, "get_scores": true, "fields": ["id", ...],
 "sort": ["score desc", "id"], "ops": {...}}
```

- Response: `{"found": N, "docs": [...], "ops": {...}}`. `found` only appears when
  `get_number: true`.
- `limit`: default 10; `0` for counts or facets only; `-1` for all matches.
- Paging is `offset` + `limit`. Deep pages get more expensive, and there is no cursor.
- `filter` entries don't score. A filter wrapper `{"query": Q, "except_ops": ["facetName"]}`
  hides the filter from the named sub-operations (used for OR facets).
- Full form: `{"ops": {"q": {"top_docs": {...}}}}`. Results then come back under `ops.q`.

Query node types:
- `all`, `match` (with `operator: "and"` / `min_match`), `phrase` (`slop`), `any_of`
  (exact values), `exists`, `range` (`gt`/`gte`/`lt`/`lte`)
- `prefix`, `wildcard`, `regex`, `fuzzy` (max_edits ≤ 2)
- `boolean` (`required`, `optional`, `prohibited`, `filter`, `min_match`)
- `constant_score`, `boost`, `rescore`
- `simple_query` (`{"q": ..., "fields": [...]}`; **never fails to parse**; for end-user text)
- `knn`, `geo_box`, `geo_distance` (`lat`, `lon`, `radius_meters`)
- A bare string is the strict query language. Use `$vars` for values; never concatenate user
  input into it.

Sorting:
- A clause is `"field"`, `"field desc"`, `"score"`, or an expression such as
  `"min(prices_fs)"`. The object form is `{"expr", "dir", "vars"}`.
- Default direction is desc for `score` and asc for everything else.
- Documents with no value sort last in both directions.
- A bare multi-valued string sorts by its min (asc) or max (desc). A bare multi-valued numeric
  sorts by its first value, so use `min(f)` / `max(f)` explicitly.

Field retrieval: `fields` lists names or wildcard patterns. Omitting it returns every
retrievable field. Row format is the HTTP default, and missing fields are left out of the row.

## Facets (as sub-ops of the query)

- `field_facet`: `field`, `limit` (default 5, `-1` = all), `mincount`, `missing`, `sort`
  (by a metric only), `selected`, `selection_mode` (`any` | `all`).
  Result: `{"buckets": [{"val", "count"}], "missing": N}`.
  - **No prefix option**, so it can't drive term autocomplete directly.
  - A text field facets on analyzed terms. Use a string field or variant for whole values.
- `range_facet`: `field`, `start`, `end`, `gap` or `calendar_gap` (`{"n", "unit"}`),
  `mincount` (default 0), `missing`, `time_zone`.
  Bucket `val` is `[lo, hi)`; range facets return zero-count buckets by default.
- `query_facet`: `{"buckets": {"name": query, ...}}`
- Metrics: `"avg(price_f)"`, `sum`, `min`, `max`.
- Facets can nest, and a facet can return a `top_docs` list per bucket.

## Not available in 0.1.0

- Server-side highlighting or snippets (not listed as a feature)
- Spellcheck
- Suggester / autocomplete endpoint
- More Like This
- Delete-by-query
- Partial updates
- Auth / TLS
- Replication
- Version endpoint — **VERIFY** whether `/_stats` reports the version
- arm64 builds
- Official Docker image

## Verified against the running server (0.1.0, added during implementation)

- Release assets: `luxir-0.1.0-linux-x86_64-{v2,v3,v4}` (bare executables) plus `SHA256SUMS` with standard `sha256sum` lines.
- `--version` prints `Luxir 0.1.0 (x86-64-v3)`. Under Rosetta on Apple Silicon `v3` starts, `v4` does not.
- Match syntax: `{"match":{"field":"f","val":"x"}}` or `{"match":{"f":"x"}}`. Bare `"type":"text"` uses a whitespace
  analyzer with no case folding, so `Dune` is not found by `dune`; always give an analyzer.
- A `main` collection exists in a fresh data dir. `/_stats` does not report the version.
- Facet `mincount` of 0 is not useful for the module; zero-count buckets are not returned.
- Search responses for the shorthand form carry `found`, `docs` and `ops` at top level.
