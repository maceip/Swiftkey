"""Synthetic offline tests. None of these labels or results are UI research evidence."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import research as r


def feature(name="coverage", kind="noul", question="Does the text document the callback?"):
    return r.Feature.create({"name": name, "kind": kind, "question": question,
                             "criteria": {"true": "The callback is documented", "false": "The callback is absent"}
                             if kind == "noul" else ["Absent", "Partial", "Complete"]})


def synthetic_dataset():
    """Arithmetic labels, deliberately bypassing the production human-label loader."""
    rows = []
    for group in range(8):
        for level in range(6):
            rows.append(r.Row(id=f"sparse-{1000 + group * 71 + level * 3}", component=f"synthetic-{group}",
                              group=f"group-{group}", split="dev" if group < 6 else "test",
                              description=f"SYNTHETIC TEST ONLY; documented_count={level}",
                              evidence=[{"source": "synthetic-test://arithmetic", "text": "Six possible counts"}],
                              label=float(level), label_record=f"synthetic-{group}-{level}"))
    return r.Dataset("synthetic-fixture-not-human-data", {"id": "synthetic-count", "definition": "Synthetic arithmetic only",
                     "minimum": 0, "maximum": 5}, {"kind": "synthetic_test", "records_ref": "test code"}, tuple(rows))


def dataset_document():
    source = synthetic_dataset()
    return {"schema_version": 1, "rubric": source.rubric, "provenance": source.provenance,
            "rows": [r.asdict(row) for row in source.rows]}


def schema_only_document():
    # A schema fixture; this declaration does not convert synthetic labels into research data.
    raw = dataset_document()
    raw["provenance"] = {"kind": "human_review", "records_ref": "SYNTHETIC SCHEMA TEST, NOT REAL REVIEWS"}
    for row in raw["rows"]:
        row["description"] += " " + row["id"]
    return raw


class Contracts(unittest.TestCase):
    def test_duplicate_keys_and_nonfinite_json_rejected(self):
        for value in ('{"a":1,"a":2}', '{"x":NaN}', '{"x":Infinity}'):
            with self.subTest(value=value), self.assertRaises(r.ResearchError):
                r.parse_json(value)

    def test_synthetic_labels_cannot_enter_production_loader(self):
        with self.assertRaisesRegex(r.ResearchError, "real human-reviewed"):
            r.dataset_from_json(dataset_document())

    def test_valid_schema_has_stable_hash_and_no_labels_in_state(self):
        data = r.dataset_from_json(schema_only_document())
        self.assertEqual(data.fingerprint, r.digest(schema_only_document()))
        state = data.rows[0].state(data.rubric)
        self.assertEqual(set(state), {"component", "description", "evidence", "rubric"})

    def test_fingerprints_ignore_row_order_and_holdout_identity_ignores_dev_changes(self):
        raw = schema_only_document()
        original = r.dataset_from_json(raw)
        raw["rows"].reverse()
        reordered = r.dataset_from_json(raw)
        self.assertEqual(original.fingerprint, reordered.fingerprint)
        self.assertEqual(original.holdout_fingerprint, reordered.holdout_fingerprint)
        next(row for row in raw["rows"] if row["split"] == "dev")["description"] += " revised"
        changed = r.dataset_from_json(raw)
        self.assertNotEqual(original.fingerprint, changed.fingerprint)
        self.assertEqual(original.holdout_fingerprint, changed.holdout_fingerprint)

    def test_unknown_fields_missing_labels_and_bad_targets_rejected(self):
        for mutation in (lambda x: x["rows"][0].update(extra="hidden"),
                         lambda x: x["rows"][0].pop("label"),
                         lambda x: x["rows"][0].update(label=True),
                         lambda x: x["rows"][0].update(label=float("nan")),
                         lambda x: x["rows"][0].update(label=6)):
            raw = schema_only_document()
            mutation(raw)
            with self.subTest(mutation=mutation), self.assertRaises(r.ResearchError):
                r.dataset_from_json(raw)

    def test_group_component_and_duplicate_state_leakage_rejected(self):
        for mutation in (lambda x: x["rows"][-1].update(group="group-0"),
                         lambda x: x["rows"][-1].update(component="synthetic-0"),
                         lambda x: x["rows"][-1].update(label_record=x["rows"][0]["label_record"]),
                         lambda x: x["rows"][-1].update(description=x["rows"][0]["description"])):
            raw = schema_only_document()
            # Original arithmetic descriptions repeat across groups: give each row a distinct context.
            for row in raw["rows"]:
                row["description"] += " " + row["id"]
            mutation(raw)
            with self.subTest(mutation=mutation), self.assertRaises(r.ResearchError):
                r.dataset_from_json(raw)

    def test_proposals_reject_conflicting_or_unknown_targets(self):
        old, new = feature(), feature(question="Does it identify disabled state?")
        config = r.Config("synthetic-proposer", "synthetic-answerer")
        revise = {"op": "revise", "target": old.id, "feature": {k: v for k, v in r.asdict(new).items() if k != "id"}}
        drop = {"op": "drop", "target": old.id, "feature": None}
        for actions in ([revise, drop], [{**drop, "target": "unknown"}],
                        [{"op": "add", "target": old.id, "feature": revise["feature"]}],
                        [{"op": "execute", "target": None, "feature": None}]):
            with self.subTest(actions=actions), self.assertRaises(r.ResearchError):
                r.validate_proposal({"actions": actions}, [old], config)

    def test_content_identity_changes_with_rubric_but_not_display_name(self):
        old, renamed = feature("a"), feature("a_sd")
        self.assertEqual(old.id, renamed.id)
        raw = {k: v for k, v in r.asdict(old).items() if k != "id"}
        raw["criteria"]["true"] = "The correct callback is fully documented"
        self.assertNotEqual(old.id, r.Feature.create(raw).id)

    def test_column_ownership_is_explicit_even_with_prefix_collisions(self):
        a = feature("state", "score")
        b = feature("state_sd", "score", "Are error states explained?")
        metadata = r.column_metadata([a, b])
        self.assertEqual([x["feature_id"] for x in metadata], [a.id, a.id, b.id, b.id])
        self.assertEqual(len({x["column_id"] for x in metadata}), 4)

    def test_probability_validation_and_mean_spread_arithmetic(self):
        f = feature(kind="score")
        good = {"type": "score", "probabilities": {"0": .25, "1": .5, "2": .25}}
        values = r.probabilities(f, good)
        mean, sd = r.encoded(f, values)
        self.assertEqual(mean, 1)
        self.assertAlmostEqual(sd, math.sqrt(.5))
        for probs in ({"0": 1}, {"0": .5, "1": .5, "2": .5}, {"0": -1, "1": 1, "2": 1},
                      {"0": float("nan"), "1": 0, "2": 1}, {"0": True, "1": 0, "2": 0}):
            with self.subTest(probs=probs), self.assertRaises(r.ResearchError):
                r.probabilities(f, {"type": "score", "probabilities": probs})

    def test_grouped_folds_never_split_families_and_cover_sparse_ids(self):
        rows = synthetic_dataset().dev
        folds = r.grouped_folds(rows, 3, 17)
        self.assertEqual(folds, r.grouped_folds(rows, 3, 17))
        self.assertEqual(set.union(*folds), {row.id for row in rows})
        self.assertEqual(sum(map(len, folds)), len(rows))
        for group in {row.group for row in rows}:
            containing = [fold for fold in folds if any(row.group == group and row.id in fold for row in rows)]
            self.assertEqual(len(containing), 1)

    def test_error_feedback_uses_ids_not_global_array_positions(self):
        rows = synthetic_dataset().dev
        predictions = {row.id: row.label for row in rows}
        predictions[rows[5].id] = -10
        result = r.feedback(rows, predictions, 6)
        self.assertEqual(result[0]["row_id"], rows[5].id)
        self.assertEqual(result[0]["oof_prediction"], -10)
        self.assertEqual(result[0]["absolute_error"], 15)
        self.assertEqual(len({row["row_id"] for row in result}), 6)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_cache_only_miss_never_calls_transport(self):
        cache = r.Cache(self.root, r.Budget())
        with self.assertRaises(r.CacheMiss):
            cache.get("answer", {"state": "example"}, lambda x: None,
                      lambda: self.fail("network must never execute"))
        self.assertEqual(cache.budget.used, 0)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_exact_cache_hit_costs_no_budget_and_validates(self):
        cache = r.Cache(self.root, r.Budget())
        payload, response = {"state": "example"}, {"p": .5}
        r.write_new(cache.path("answer", payload), {"request": cache.envelope("answer", payload), "response": response})
        self.assertEqual(cache.get("answer", payload, lambda x: r.fields(x, {"p"}, "response"),
                                  lambda: self.fail("no network")), response)
        self.assertEqual(cache.budget.used, 0)

    def test_failed_call_consumes_budget_without_retry_or_cache(self):
        cache = r.Cache(self.root, r.Budget(True, 1))
        calls = []
        def fail():
            calls.append(1)
            raise RuntimeError("sensitive-request-body")
        with self.assertRaisesRegex(r.ResearchError, "RuntimeError") as caught:
            cache.get("answer", {}, lambda x: None, fail)
        self.assertNotIn("sensitive-request-body", str(caught.exception))
        with self.assertRaisesRegex(r.ResearchError, "budget exhausted"):
            cache.get("answer", {}, lambda x: None, fail)
        self.assertEqual(calls, [1])
        self.assertEqual(cache.budget.used, 1)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_invalid_cached_payload_is_not_silently_used(self):
        cache = r.Cache(self.root, r.Budget())
        r.write_new(cache.path("answer", {}), {"request": cache.envelope("answer", {"different": True}), "response": {}})
        with self.assertRaisesRegex(r.ResearchError, "hash mismatch"):
            cache.get("answer", {}, lambda x: None, lambda: self.fail("no network"))

    def test_oversized_request_rejected_before_budget_or_transport(self):
        cache = r.Cache(self.root, r.Budget(True, 1))
        with self.assertRaisesRegex(r.ResearchError, "256 KiB"):
            cache.get("answer", {"state": "x" * r.MAX_REQUEST_BYTES}, lambda x: None, lambda: self.fail("no network"))
        self.assertEqual(cache.budget.used, 0)


class SyntheticReplayAdapters(r.ModelAdapters):
    """Populate explicit synthetic replay records, then exercise the real offline adapter."""
    def __init__(self, cache, config):
        super().__init__(cache, config)
        self.answered_splits = []
        self.contexts = []
        self.question = feature(question="SYNTHETIC TEST: Is the documented count high?")

    def save_fixture(self, kind, payload, response):
        path = self.cache.path(kind, payload)
        if not path.exists():
            r.write_new(path, {"request": self.cache.envelope(kind, payload), "response": response})

    def propose(self, context, accepted):
        self.contexts.append(context)
        proposal = {"actions": [] if context["round"] > 1 else [{"op": "add", "target": None,
                    "feature": {k: v for k, v in r.asdict(self.question).items() if k != "id"}}]}
        self.save_fixture("proposal", self.proposal_payload(context), proposal)
        return super().propose(context, accepted)

    def answer(self, row, rubric, features):
        self.answered_splits.append(row.split)
        self.seed_answer(row, rubric, features)
        return super().answer(row, rubric, features)

    def seed_answer(self, row, rubric, features):
        # Observable synthetic text, not a read of the row's supervised label.
        count = int(row.description.rsplit("=", 1)[1])
        response = {f.id: {"type": "noul", "noul": count / 5} for f in features}
        self.save_fixture("answer", self.answer_payload(row, rubric, features), response)


@unittest.skipUnless(importlib.util.find_spec("catboost"), "install local requirements for CatBoost integration")
class Integration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = synthetic_dataset()
        self.config = r.Config("synthetic-proposer", "synthetic-answerer", rounds=2, folds=3,
                               repeats=1, iterations=60, learning_rate=.15)
        self.adapters = SyntheticReplayAdapters(r.Cache(self.root / "cache", r.Budget()), self.config)

    def test_cached_discovery_and_once_only_frozen_holdout_with_real_catboost(self):
        frozen = r.discover(self.data, self.config, self.adapters, self.root / "run")
        self.assertEqual(set(self.adapters.answered_splits), {"dev"})
        self.assertEqual(frozen["status"], "features_selected")
        self.assertLess(frozen["dev_cv_rmse"], frozen["baseline_cv_rmse"])
        for context in self.adapters.contexts:
            self.assertTrue(all(example["row_id"] in {row.id for row in self.data.dev} for example in context["examples"]))
        dev_calls = len(self.adapters.answered_splits)
        # Preflight must fail without consuming the holdout if no replay responses exist yet.
        with self.assertRaisesRegex(r.ResearchError, "offline preflight"):
            r.evaluate_holdout(self.data, frozen, self.adapters, self.root / "test.json")
        self.assertFalse((self.adapters.cache.root / "evaluations").exists())
        selected = [r.Feature.from_json(value) for value in frozen["features"]]
        for row in self.data.test:
            self.adapters.seed_answer(row, self.data.rubric, selected)
        report = r.evaluate_holdout(self.data, frozen, self.adapters, self.root / "test.json")
        self.assertEqual(self.adapters.answered_splits[dev_calls:], ["test"] * len(self.data.test))
        self.assertLess(report["test_rmse"], report["mean_baseline_test_rmse"])
        self.assertEqual(self.adapters.cache.budget.used, 0)
        with self.assertRaisesRegex(r.ResearchError, "already consumed"):
            r.evaluate_holdout(self.data, frozen, self.adapters, self.root / "second.json")

    def test_frozen_tampering_and_changed_dataset_rejected(self):
        frozen = r.discover(self.data, self.config, self.adapters, self.root / "run")
        edited = copy.deepcopy(frozen)
        edited["features"][0]["question"] += " changed"
        with self.assertRaisesRegex(r.ResearchError, "hash mismatch"):
            r.validate_frozen(edited, self.data)
        with self.assertRaisesRegex(r.ResearchError, "dataset changed"):
            r.validate_frozen(frozen, r.Dataset("other", self.data.rubric, self.data.provenance, self.data.rows))

    def test_all_constant_training_fold_uses_mean(self):
        f = feature()
        rows = self.data.dev
        answers = {row.id: {f.id: [.5]} for row in rows}
        predicted, score = r.Learner(self.config).cv(rows, [f], answers)
        self.assertTrue(math.isfinite(score))
        self.assertEqual(set(predicted.values()), {2.5})

    def test_empty_proposal_freezes_evaluable_mean_baseline_without_answers(self):
        self.adapters.propose = lambda context, accepted: []
        frozen = r.discover(self.data, self.config, self.adapters, self.root / "run")
        self.assertEqual(frozen["features"], [])
        self.assertEqual(frozen["status"], "mean_baseline_selected")
        report = r.evaluate_holdout(self.data, frozen, self.adapters, self.root / "test.json")
        self.assertEqual(report["test_rmse"], report["mean_baseline_test_rmse"])
        self.assertEqual(self.adapters.answered_splits, [])

    def test_later_failure_preserves_complete_evaluable_best_checkpoint(self):
        original = self.adapters.propose
        def propose(context, accepted):
            if context["round"] == 2:
                raise r.ResearchError("synthetic exhausted budget")
            return original(context, accepted)
        self.adapters.propose = propose
        with self.assertRaisesRegex(r.ResearchError, "exhausted budget"):
            r.discover(self.data, self.config, self.adapters, self.root / "run")
        checkpoint = r.read_json(self.root / "run" / "round-1.frozen.json")
        _, selected = r.validate_frozen(checkpoint, self.data)
        self.assertTrue(selected)
        self.assertEqual(set(checkpoint["dev_answers"]), {row.id for row in self.data.dev})
        for row in self.data.test:
            self.adapters.seed_answer(row, self.data.rubric, selected)
        report = r.evaluate_holdout(self.data, checkpoint, self.adapters, self.root / "test.json")
        self.assertLess(report["test_rmse"], report["mean_baseline_test_rmse"])

    def test_impossible_additions_rejected_before_answer_requests(self):
        config = r.Config("synthetic-proposer", "synthetic-answerer", rounds=2, folds=3,
                          repeats=1, iterations=60, learning_rate=.15, max_features=1)
        adapters = SyntheticReplayAdapters(self.adapters.cache, config)
        original = adapters.propose
        def propose(context, accepted):
            if context["round"] == 2:
                return [("add", None, feature(question="Another synthetic feature that cannot fit"))]
            return original(context, accepted)
        adapters.propose = propose
        frozen = r.discover(self.data, config, adapters, self.root / "run")
        self.assertEqual(len(frozen["features"]), 1)
        self.assertEqual(len(adapters.answered_splits), len(self.data.dev))
        journal = r.read_json(self.root / "run" / "journal.json")
        self.assertIn("rejected before answer requests", journal[-1]["reason"])

    def test_started_holdout_failure_consumes_marker(self):
        frozen = r.discover(self.data, self.config, self.adapters, self.root / "run")
        selected = [r.Feature.from_json(value) for value in frozen["features"]]
        for row in self.data.test:
            self.adapters.seed_answer(row, self.data.rubric, selected)
        with patch.object(self.adapters, "answer", side_effect=r.ResearchError("synthetic response failure")):
            with self.assertRaisesRegex(r.ResearchError, "response failure"):
                r.evaluate_holdout(self.data, frozen, self.adapters, self.root / "test.json")
        with self.assertRaisesRegex(r.ResearchError, "already consumed"):
            r.evaluate_holdout(self.data, frozen, self.adapters, self.root / "retry.json")


@unittest.skipUnless(importlib.util.find_spec("typesafe_sdk"), "install pinned SDK for mocked transport test")
class SDKIntegration(unittest.TestCase):
    def test_real_typesafe_sdk_score_noul_and_no_retry_over_mock_transport(self):
        import httpx2
        import typesafe_sdk
        original = typesafe_sdk.TypeSafeClient
        requests = []
        noul, score = feature(), feature("score", "score")
        def handle(request):
            body = json.loads(request.content)
            requests.append(body)
            return httpx2.Response(200, json={"model": "synthetic-answerer", "usage": {"input_tokens": 1, "output_tokens": 1},
                "answers": {noul.id: {"type": "noul", "noul": .8}, score.id: {"type": "score", "score": 1.,
                "confidence": .5, "legend": {"0": "Absent", "1": "Partial", "2": "Complete"},
                "probabilities": {"0": .25, "1": .5, "2": .25}}}})
        def client(**kwargs):
            self.assertEqual(kwargs["retry"].max_retries, 0)
            return original(**kwargs, transport=httpx2.MockTransport(handle))
        with tempfile.TemporaryDirectory() as directory, patch.dict(r.os.environ, {"TYPESAFE_API_KEY": "synthetic-not-a-secret"}), \
                patch.object(typesafe_sdk, "TypeSafeClient", client):
            adapter = r.ModelAdapters(r.Cache(Path(directory), r.Budget(True, 1)), r.Config("synthetic", "synthetic-answerer"))
            row = synthetic_dataset().rows[0]
            result = adapter.answer(row, synthetic_dataset().rubric, [noul, score])
            self.assertEqual(result[noul.id], [.8])
            self.assertEqual(result[score.id], [.25, .5, .25])
            self.assertEqual(len(requests), 1)
            self.assertNotIn("label", requests[0]["state"])
            self.assertEqual({q["type"] for q in requests[0]["questions"].values()}, {"score", "noul"})

    def test_real_typesafe_sdk_500_does_not_retry(self):
        import httpx2
        import typesafe_sdk
        original, requests = typesafe_sdk.TypeSafeClient, []
        def handle(request):
            requests.append(request)
            return httpx2.Response(500, json={"error": "synthetic server error"})
        def client(**kwargs):
            return original(**kwargs, transport=httpx2.MockTransport(handle))
        with tempfile.TemporaryDirectory() as directory, patch.dict(r.os.environ, {"TYPESAFE_API_KEY": "synthetic-not-a-secret"}), \
                patch.object(typesafe_sdk, "TypeSafeClient", client):
            adapter = r.ModelAdapters(r.Cache(Path(directory), r.Budget(True, 1)), r.Config("synthetic", "synthetic-answerer"))
            with self.assertRaisesRegex(r.ResearchError, "model call failed"):
                adapter.answer(synthetic_dataset().rows[0], synthetic_dataset().rubric, [feature()])
            self.assertEqual(len(requests), 1)
            self.assertEqual(adapter.cache.budget.used, 1)

    @unittest.skipUnless(importlib.util.find_spec("anthropic"), "install pinned Anthropic SDK")
    def test_real_anthropic_sdk_structured_proposal_over_mock_transport(self):
        import anthropic
        import httpx2
        original, requests = anthropic.Anthropic, []
        def handle(request):
            requests.append(json.loads(request.content))
            return httpx2.Response(200, json={"id": "msg_synthetic", "type": "message", "role": "assistant",
                "model": "synthetic-proposer", "content": [{"type": "text", "text": '{"actions":[]}'}],
                "stop_reason": "end_turn", "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 1}})
        def client(**kwargs):
            self.assertEqual(kwargs["max_retries"], 0)
            return original(**kwargs, http_client=httpx2.Client(transport=httpx2.MockTransport(handle)))
        with tempfile.TemporaryDirectory() as directory, patch.dict(r.os.environ, {"ANTHROPIC_API_KEY": "synthetic-not-a-secret"}), \
                patch.object(anthropic, "Anthropic", client):
            adapter = r.ModelAdapters(r.Cache(Path(directory), r.Budget(True, 1)), r.Config("synthetic-proposer", "synthetic-answerer"))
            self.assertEqual(adapter.propose({"task": "SYNTHETIC OFFLINE TEST"}, []), [])
            self.assertEqual(len(requests), 1)
            self.assertEqual(requests[0]["output_config"]["format"]["type"], "json_schema")
            self.assertEqual(requests[0]["output_config"]["format"]["schema"], r.PROPOSAL_SCHEMA)


if __name__ == "__main__":
    unittest.main()
