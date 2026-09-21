# Description research tool

This optional Python tool discovers text questions that predict independent human ratings of UI component descriptions. It implements a bounded **propose → TypeSafe probabilities → grouped CatBoost cross-validation → error feedback** loop. It does not modify the application, descriptions, component code, or design tokens.

**No real UI evaluation has been run.** No labeled UI dataset is supplied. The tests use clearly synthetic arithmetic fixtures and mocked HTTP transports. Their scores are test assertions, not evidence that a design improved.

TypeSafe's Jev currently accepts text and structured text JSON, with no image input. This tool can assess descriptions against supplied source facts. Visual fidelity, layout, interaction quality, accessibility, and usefulness on actual devices require separate rendered checks and human evaluation. Its predicted score and probability concentration do not establish those outcomes. See [TypeSafe state](https://docs.typesafe.ai/concepts/state) and [Score semantics](https://docs.typesafe.ai/primitives/score).

## Install and verify

From this directory, create a local environment; no global installation is needed:

```sh
uv venv --python python3.13 .venv
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m unittest discover -s tests -v
```

The direct dependencies are pinned. Runs record Python, NumPy, CatBoost, TypeSafe SDK, and Anthropic SDK versions. Holdout evaluation requires the same NumPy/CatBoost versions as discovery. The standard-library contract tests can also run with `python3 -m unittest discover -s tests -v`; integration tests explicitly skip when their dependencies are absent.

## Required data

Supply one JSON dataset containing a fixed rubric and independently reviewed description cases. The React library under `vendor/design-system` provides source facts and tests; it is not a labeled quality dataset.

Every row represents **one component description revision and its own human label**. It needs:

- A stable row ID, component ID, component-family group, and preassigned `dev` or `test` split.
- The exact candidate description and authoritative source excerpts for props, defaults, states, callbacks, slots, and platform support relevant to that description.
- A numeric human rating under the declared rubric, plus a unique review-record reference. Revisions cannot inherit the previous text's rating.
- Real review provenance. Prefer blinded reviewers, explicit scoring anchors, adjudication of disagreements, and retained review records. Automated source/compile checks can provide evidence but do not become human judgments by renaming them.

This structural example intentionally has `label: null` and is **not runnable**. Replace it with real labeled cases; the loader rejects missing labels, synthetic/model provenance, and insufficient groups.

```json
{
  "schema_version": 1,
  "rubric": {
    "id": "description-usefulness-v1",
    "definition": "Use independently defined anchors for factual support, coverage of required behavior, and usefulness to the intended implementer. Document exactly what each numeric level means.",
    "minimum": 0,
    "maximum": 4
  },
  "provenance": {
    "kind": "human_review",
    "records_ref": "reference-to-your-real-review-records"
  },
  "rows": [{
    "id": "actual-component-description-revision-id",
    "component": "actual-component-id",
    "group": "actual-component-family-id",
    "split": "dev",
    "description": "The actual description reviewed by the human reviewers.",
    "evidence": [{
      "source": "repository revision and path or another authoritative reference",
      "text": "The exact relevant source facts."
    }],
    "label": null,
    "label_record": "unique-record-for-this-description-revision"
  }]
}
```

The loader checks declarations and consistency; it cannot authenticate that a human actually reviewed the cases. Review provenance remains an investigator responsibility. Do not fabricate labels to make the command run.

The dataset must contain at least six rows, at least two groups in each split, and at least as many development groups as CV folds. These are execution minima, **not a sample-size justification**. A small catalog with many near-duplicate revisions still has few independent groups. Choose enough independent families and cases to support the intended claim before collecting a final test set.

Keep related component revisions, templated descriptions, variants, and near-duplicates together. The loader enforces one group per component, disjoint groups across splits, unique row/review IDs, and no exact normalized description/evidence duplicates across splits. Investigators must identify semantic duplicates and shared templates. Label records and scores never enter TypeSafe answer requests; only development examples and labels enter the proposer.

All dataset objects reject unknown fields and duplicate JSON keys. Numbers must be finite and within the rubric range. Inputs are bounded to 32 MiB per JSON file, 10,000 rows, 64,000 bytes per row state, and 256 KiB per model request. Oversized inputs stop with an error; they are not silently truncated.

## Run stages

Edit `config.example.json` with the model IDs you intend to use. Its IDs come from the published recipe; availability has not been checked through a model API. Use pinned IDs: live responses returning a different model ID are rejected.

```sh
.venv/bin/python research.py validate --dataset /path/to/reviewed-descriptions.json
.venv/bin/python research.py discover \
  --dataset /path/to/reviewed-descriptions.json \
  --config config.example.json --cache cache --output runs/research-001
```

**The default is cache-only, even if API keys exist.** A missing entry stops before any model request. Existing replay records must have the exact request envelope and valid answers. No canned production cache, synthetic dataset, or demonstration score is shipped.

To intentionally permit live calls, set `TYPESAFE_API_KEY` and `ANTHROPIC_API_KEY` in the process environment, then add both `--live` and a positive `--request-budget N`. Do not put keys in datasets, command arguments, caches, or this repository. The tool does not search credential files. It uses the official provider endpoints and ignores environment endpoint overrides.

Each live request attempt consumes one budget unit, including failures. Cache hits consume none. Both SDKs have retries disabled. Calls are sequential with 120-second request timeouts. The proposer has an 8,000-output-token cap. The request budget bounds request attempts; it is not a dollar or total-token budget. Worst-case discovery answer traffic is `rounds × dev_rows`, plus at most one proposer request per round. Holdout uses at most one answer request per held-out row. CatBoost runs one CPU thread with bounded rounds, candidates, tree depth, and iterations.

Discovery writes a manifest, per-round decisions and OOF predictions, an action journal, and `frozen.json`. It never supplies test rows to the proposer or answerer. It starts from a fold-local mean baseline, tests every add/revise/drop, and keeps a change only when grouped development RMSE improves by more than `min_gain`. Ties and regressions are rejected. Empty proposals stop the run; empty/all-constant feature sets fall back to the mean predictor. Sequential screening can miss feature interactions; it is an intentionally bounded search, not a global optimizer.

Every completed round also writes a complete immutable `round-N.frozen.json` checkpoint; round zero is the mean baseline. If a later request exhausts the budget or fails, the command exits unsuccessfully but the latest completed checkpoint remains evaluable with `--frozen`. It contains all selected development answers. A new discovery attempt uses a new output directory and can replay the same cache. It does not resume a partially completed round.

OOF predictions are keyed by row ID. Whole groups remain together in every fold. Repeated CV predictions are averaged before computing the reported RMSE. The same split schedule is used for every candidate. These repeatedly optimized CV scores are **selection feedback**, not an unbiased generalization estimate.

Once the best set is frozen, evaluate the held-out data in a separate invocation:

```sh
.venv/bin/python research.py evaluate \
  --dataset /path/to/reviewed-descriptions.json \
  --frozen runs/research-001/frozen.json \
  --cache cache --output runs/research-001/holdout.json
```

This is also cache-only unless explicitly given `--live --request-budget N`; evaluation only needs the TypeSafe key. Offline cache/budget preflight failures do not consume the holdout. Once evaluation starts, an exclusive marker under `cache/evaluations/` prevents another attempt on that held-out set/cache, including after a transport failure. Its identity is independent of row ordering and development-row changes. This conservative guard prevents casual repeated peeking; deleting/copying caches or relabeling the test data can defeat it, so it is not a security boundary. Do not reset the marker to choose a better feature set on test results. Freeze the study plan, retain the report, and collect a new independent test set for a subsequent study.

The frozen manifest binds the dataset hash, configuration, selected questions, explicit columns, exact development probability vectors, and dependency versions. Holdout fitting reuses those saved development vectors; it does not ask the model to regenerate training answers. The report compares the final predictor with the training-mean baseline and records individual predictions. It does not select among rounds on test results, generate confidence intervals, or claim statistical significance. A serious comparison needs a prespecified metric, independent groups, and appropriate uncertainty estimates; ordinal labels also require a justified numeric-distance interpretation for RMSE.

## Cache and proposal contracts

`cache/responses/<sha256>.json` contains exactly `{"request": envelope, "response": value}`. The digest covers the schema version, operation, fixed provider endpoint, pinned SDK identifier, model ID, complete state, question content/rubrics, and proposer context/schema. No API key enters that envelope. Cache files are exclusively created and validated again on replay. A malformed/partial entry fails closed and is never silently treated as zero probabilities. Cached outputs make replay reproducible; a fresh stochastic provider run need not produce the same answers.

Proposals contain exactly `actions`. Each action has `op`, `target`, and `feature`. Adds have a null target; revisions/drops identify an existing feature content hash; drops have a null feature. Features contain `name`, `kind` (`score` or `noul`), `question`, and `criteria`. Score criteria contain 2–7 distinct ordered levels; Noul criteria contain exactly `true` and `false` descriptions. Duplicate content, unknown targets, multiple actions on one target, invalid types, and excess actions are rejected before answering.

Names are presentation only. Feature identity hashes the question, kind, and complete criteria. Column metadata explicitly stores `feature_id`, `column_id`, and `statistic`; ownership is never inferred from suffixes. Score probability support must exactly match rubric levels, all values must be finite in `[0,1]`, and their sum must be within `1e-6` of one. They become mean and standard-deviation columns. Noul yields one probability column. Importance is aggregated through explicit metadata and describes this fitted predictor, not causal importance or UI correctness.

## Adaptation boundaries

The [TypeSafe recipe](https://docs.typesafe.ai/cookbooks/autoresearch_feature_discovery) is a supervised wine-score experiment. Its accuracy figures do not transfer to UI descriptions. This tool replaces its domain assumptions and fixes its row-index coupling, permissive proposals, inferred column ownership, name/revision collisions, unvalidated probability defaults, unconditional additions, cache-only ambiguity, and empty-feature edge cases.

This loop discovers **questions**. A future description-refinement stage would need a separately bounded generator grounded in source facts, reviewable text diffs, and fresh human judgments of revised descriptions. Existing labels cannot be reused after editing their descriptions. Source checks and device/visual checks must remain independent acceptance requirements.

Primary references: [TypeSafe questions and responses](https://docs.typesafe.ai/sdk/python/api/types/responses), [confidence](https://docs.typesafe.ai/confidence), [Python client](https://docs.typesafe.ai/sdk/python/api/clients/sync). SDK adapter behavior is additionally tested against the locally installed pinned packages using mock transports, with no external model calls.
