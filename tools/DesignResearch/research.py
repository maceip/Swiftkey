#!/usr/bin/env python3
"""Optional, text-only supervised description research. No network without --live."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import random
import sys
from dataclasses import asdict, dataclass
from typing import Any, Callable


VERSION = 1
MAX_JSON_BYTES = 32 * 1024 * 1024
MAX_REQUEST_BYTES = 256 * 1024


class ResearchError(ValueError):
    pass


class CacheMiss(ResearchError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ResearchError(message)


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def _object(pairs: list[tuple[str, Any]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json(raw: str) -> Any:
    def invalid(value: str) -> None:
        raise ResearchError(f"non-finite JSON value: {value}")
    try:
        return json.loads(raw, object_pairs_hook=_object, parse_constant=invalid)
    except (json.JSONDecodeError, UnicodeError) as exc:
        raise ResearchError(f"invalid JSON: {exc}") from exc


def read_json(path: Path) -> Any:
    require(path.stat().st_size <= MAX_JSON_BYTES, f"JSON exceeds {MAX_JSON_BYTES} bytes")
    return parse_json(path.read_text(encoding="utf-8"))


def write_new(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation is intentional: neither caches nor run artifacts are overwritten.
    with path.open("x", encoding="utf-8") as stream:
        stream.write(canonical(value).decode("utf-8") + "\n")


def fields(value: Any, expected: set[str], where: str) -> dict:
    require(isinstance(value, dict), f"{where}: expected object")
    require(set(value) == expected, f"{where}: expected fields {sorted(expected)}")
    return value


def text_value(value: Any, where: str, maximum: int = 10000) -> str:
    require(isinstance(value, str) and bool(value.strip()) and len(value) <= maximum,
            f"{where}: expected nonempty string of at most {maximum} characters")
    return value


def number(value: Any, where: str, lower: float, upper: float) -> float:
    require(type(value) in (int, float) and math.isfinite(value) and lower <= value <= upper,
            f"{where}: expected finite number in [{lower}, {upper}]")
    return float(value)


def integer(value: Any, where: str, lower: int, upper: int) -> int:
    require(type(value) is int and lower <= value <= upper,
            f"{where}: expected integer in [{lower}, {upper}]")
    return value


@dataclass(frozen=True)
class Row:
    id: str
    component: str
    group: str
    split: str
    description: str
    evidence: list[dict]
    label: float
    label_record: str

    def state(self, rubric: dict) -> dict:
        # Ground-truth labels, reviewer rationales, group IDs and split are never sent.
        return {"component": self.component, "description": self.description,
                "evidence": self.evidence, "rubric": rubric["definition"]}


@dataclass(frozen=True)
class Dataset:
    fingerprint: str
    rubric: dict
    provenance: dict
    rows: tuple[Row, ...]

    @property
    def dev(self) -> tuple[Row, ...]:
        return tuple(row for row in self.rows if row.split == "dev")

    @property
    def test(self) -> tuple[Row, ...]:
        return tuple(row for row in self.rows if row.split == "test")

    @property
    def holdout_fingerprint(self) -> str:
        return digest({"schema_version": VERSION, "rubric": self.rubric, "provenance": self.provenance,
                       "rows": [asdict(row) for row in sorted(self.test, key=lambda row: row.id)]})


def dataset_from_json(raw: dict) -> Dataset:
    fields(raw, {"schema_version", "rubric", "provenance", "rows"}, "dataset")
    require(type(raw["schema_version"]) is int and raw["schema_version"] == VERSION,
            "unsupported dataset schema")
    rubric = fields(raw["rubric"], {"id", "definition", "minimum", "maximum"}, "rubric")
    text_value(rubric["id"], "rubric.id", 128)
    text_value(rubric["definition"], "rubric.definition")
    low = number(rubric["minimum"], "rubric.minimum", -10000, 10000)
    high = number(rubric["maximum"], "rubric.maximum", -10000, 10000)
    require(low < high, "rubric minimum must be below maximum")
    provenance = fields(raw["provenance"], {"kind", "records_ref"}, "provenance")
    require(provenance["kind"] == "human_review",
            "real human-reviewed labels are required; synthetic/model labels are not accepted")
    text_value(provenance["records_ref"], "provenance.records_ref")
    require(isinstance(raw["rows"], list) and 6 <= len(raw["rows"]) <= 10000,
            "dataset requires 6..10000 rows; row count alone does not establish statistical power")
    rows, ids, records, groups, components, duplicate_states = [], set(), set(), {}, {}, {}
    row_fields = {"id", "component", "group", "split", "description", "evidence", "label", "label_record"}
    for value in raw["rows"]:
        fields(value, row_fields, "row")
        for key in ("id", "component", "group", "label_record"):
            text_value(value[key], f"row.{key}", 256)
        text_value(value["description"], "row.description", 20000)
        require(value["split"] in ("dev", "test"), "split must be dev or test")
        require(value["id"] not in ids, "duplicate row ID")
        require(value["label_record"] not in records,
                "each description revision requires its own label record")
        ids.add(value["id"])
        records.add(value["label_record"])
        require(groups.setdefault(value["group"], value["split"]) == value["split"],
                "group leaks across dev/test")
        require(components.setdefault(value["component"], value["group"]) == value["group"],
                "a component and its revisions must share one group")
        evidence = value["evidence"]
        require(isinstance(evidence, list) and 1 <= len(evidence) <= 40,
                "row requires 1..40 authoritative evidence excerpts")
        for item in evidence:
            fields(item, {"source", "text"}, "evidence")
            text_value(item["source"], "evidence.source", 2000)
            text_value(item["text"], "evidence.text", 20000)
        normalized = digest({"description": " ".join(value["description"].lower().split()),
                             "evidence": evidence})
        require(duplicate_states.setdefault(normalized, value["split"]) == value["split"],
                "duplicate description/evidence leaks across dev/test")
        label = number(value["label"], "row.label", low, high)
        row = Row(**{**value, "label": label})
        require(len(canonical(row.state(rubric))) <= 64000, "row state exceeds 64000 bytes")
        rows.append(row)
    require(len({r.group for r in rows if r.split == "dev"}) >= 2,
            "at least two independent development groups are required")
    require(len({r.group for r in rows if r.split == "test"}) >= 2,
            "at least two independent held-out groups are required")
    ordered = tuple(sorted(rows, key=lambda row: row.id))
    normalized = {"schema_version": VERSION, "rubric": rubric, "provenance": provenance,
                  "rows": [asdict(row) for row in ordered]}
    return Dataset(digest(normalized), dict(rubric), dict(provenance), ordered)


@dataclass(frozen=True)
class Config:
    proposer_model: str
    answerer_model: str
    rounds: int = 3
    folds: int = 3
    repeats: int = 2
    max_actions: int = 6
    max_features: int = 24
    max_examples: int = 12
    min_gain: float = 0.001
    seed: int = 0
    iterations: int = 200
    depth: int = 4
    learning_rate: float = 0.05

    def validate(self) -> Config:
        text_value(self.proposer_model, "proposer_model", 128)
        text_value(self.answerer_model, "answerer_model", 128)
        for key, limits in {"rounds": (1, 10), "folds": (2, 10), "repeats": (1, 5),
                            "max_actions": (1, 12), "max_features": (1, 64),
                            "max_examples": (2, 40), "seed": (0, 2**31 - 1),
                            "iterations": (10, 1000), "depth": (1, 8)}.items():
            integer(getattr(self, key), key, *limits)
        number(self.min_gain, "min_gain", 0, 10000)
        number(self.learning_rate, "learning_rate", 0.001, 0.3)
        return self

    @classmethod
    def from_json(cls, raw: dict) -> Config:
        require(isinstance(raw, dict), "config must be an object")
        require(set(raw) <= set(cls.__dataclass_fields__), "unknown config field")
        require({"proposer_model", "answerer_model"} <= set(raw), "both model IDs are required")
        return cls(**raw).validate()


@dataclass(frozen=True)
class Feature:
    id: str
    name: str
    kind: str
    question: str
    criteria: Any

    @classmethod
    def create(cls, raw: dict) -> Feature:
        fields(raw, {"name", "kind", "question", "criteria"}, "feature")
        text_value(raw["name"], "feature.name", 128)
        text_value(raw["question"], "feature.question", 2000)
        require(raw["kind"] in ("score", "noul"), "feature.kind must be score or noul")
        criteria = raw["criteria"]
        if raw["kind"] == "score":
            require(isinstance(criteria, list) and 2 <= len(criteria) <= 7,
                    "score requires 2..7 ordered descriptive levels")
            for item in criteria:
                text_value(item, "score level", 1000)
            require(len(set(criteria)) == len(criteria), "score levels must be distinct")
        else:
            fields(criteria, {"true", "false"}, "noul criteria")
            for item in criteria.values():
                text_value(item, "noul criterion", 1000)
            require(criteria["true"] != criteria["false"], "noul criteria must differ")
        # Name is presentation only. Every change to question/kind/rubric changes identity.
        identity = digest({key: raw[key] for key in ("kind", "question", "criteria")})
        return cls(identity, **raw)

    @classmethod
    def from_json(cls, raw: dict) -> Feature:
        fields(raw, {"id", "name", "kind", "question", "criteria"}, "stored feature")
        feature = cls.create({k: v for k, v in raw.items() if k != "id"})
        require(feature.id == raw["id"], "feature content hash mismatch")
        return feature


FEATURE_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "required": ["name", "kind", "question", "criteria"],
    "properties": {"name": {"type": "string"}, "kind": {"type": "string", "enum": ["score", "noul"]},
                   "question": {"type": "string"}, "criteria": {"anyOf": [
                       {"type": "array", "items": {"type": "string"}},
                       {"type": "object", "additionalProperties": False,
                        "required": ["true", "false"],
                        "properties": {"true": {"type": "string"}, "false": {"type": "string"}}}]}}}
PROPOSAL_SCHEMA = {
    "type": "object", "additionalProperties": False, "required": ["actions"],
    "properties": {"actions": {"type": "array", "items": {
        "type": "object", "additionalProperties": False, "required": ["op", "target", "feature"],
        "properties": {"op": {"type": "string", "enum": ["add", "revise", "drop"]},
                       "target": {"type": ["string", "null"]},
                       "feature": {"anyOf": [FEATURE_SCHEMA, {"type": "null"}]}}}}}}


def validate_proposal(raw: dict, accepted: list[Feature], config: Config) -> list[tuple]:
    fields(raw, {"actions"}, "proposal")
    actions = raw["actions"]
    require(isinstance(actions, list) and len(actions) <= config.max_actions, "too many proposal actions")
    live, targets, proposed, result = {f.id for f in accepted}, set(), set(), []
    for action in actions:
        fields(action, {"op", "target", "feature"}, "action")
        op, target = action["op"], action["target"]
        require(op in ("add", "revise", "drop"), "unknown action")
        if op == "add":
            require(target is None, "add target must be null")
        else:
            require(isinstance(target, str) and target in live, "target must be an existing feature ID")
            require(target not in targets, "multiple actions target the same feature")
            targets.add(target)
        if op == "drop":
            require(action["feature"] is None, "drop feature must be null")
            feature = None
        else:
            feature = Feature.create(action["feature"])
            require(feature.id not in live | proposed, "duplicate or unchanged feature content")
            proposed.add(feature.id)
        result.append((op, target, feature))
    return result


def probabilities(feature: Feature, raw: Any) -> list[float]:
    if feature.kind == "noul":
        fields(raw, {"type", "noul"}, "noul answer")
        require(raw["type"] == "noul", "answer kind mismatch")
        return [number(raw["noul"], "noul probability", 0, 1)]
    fields(raw, {"type", "probabilities"}, "score answer")
    require(raw["type"] == "score", "answer kind mismatch")
    values = raw["probabilities"]
    expected = {str(i) for i in range(len(feature.criteria))}
    fields(values, expected, "score probability levels")
    result = [number(values[str(i)], "score probability", 0, 1) for i in range(len(expected))]
    require(abs(sum(result) - 1) <= 1e-6, "score probabilities must sum to 1")
    return result


def encoded(feature: Feature, values: list[float]) -> list[float]:
    if feature.kind == "noul":
        return values
    mean = sum(i * p for i, p in enumerate(values))
    variance = sum(i * i * p for i, p in enumerate(values)) - mean * mean
    return [mean, math.sqrt(max(0, variance))]


def validate_vector(feature: Feature, values: Any) -> None:
    expected = 1 if feature.kind == "noul" else len(feature.criteria)
    require(isinstance(values, list) and len(values) == expected, "invalid probability vector length")
    for value in values:
        number(value, "probability vector", 0, 1)
    require(feature.kind == "noul" or abs(sum(values) - 1) <= 1e-6,
            "probability vector must sum to 1")


def column_metadata(features: list[Feature]) -> list[dict]:
    return [{"column_id": f"{feature.id}:{stat}", "feature_id": feature.id, "statistic": stat}
            for feature in features for stat in (("mean", "sd") if feature.kind == "score" else ("probability",))]


@dataclass
class Budget:
    live: bool = False
    limit: int = 0
    used: int = 0

    def reserve(self) -> None:
        require(self.live, "live model calls are disabled")
        require(self.used < self.limit, "live request budget exhausted")
        self.used += 1  # Failed requests count. SDK retries are disabled.


class Cache:
    def __init__(self, root: Path, budget: Budget):
        self.root, self.budget = root, budget

    def envelope(self, kind: str, payload: dict) -> dict:
        return {"schema_version": VERSION, "kind": kind, "request": payload}

    def path(self, kind: str, payload: dict) -> Path:
        return self.root / "responses" / f"{digest(self.envelope(kind, payload))}.json"

    def get(self, kind: str, payload: dict, validator: Callable, call: Callable) -> Any:
        request = self.envelope(kind, payload)
        require(len(canonical(request)) <= MAX_REQUEST_BYTES, "model request exceeds 256 KiB")
        path = self.path(kind, payload)
        if path.exists():
            stored = fields(read_json(path), {"request", "response"}, "cache record")
            require(stored["request"] == request, "cache request hash mismatch")
            validator(stored["response"])
            return stored["response"]
        if not self.budget.live:
            raise CacheMiss(f"cache miss {path.name}; live calls disabled")
        self.budget.reserve()
        try:
            response = call()
        except ResearchError:
            raise
        except Exception as exc:
            raise ResearchError(f"model call failed ({type(exc).__name__}); request budget consumed; no retry") from None
        validator(response)
        write_new(path, {"request": request, "response": response})
        return response


class ModelAdapters:
    def __init__(self, cache: Cache, config: Config):
        self.cache, self.config = cache, config

    def proposal_payload(self, context: dict) -> dict:
        return {"model": self.config.proposer_model, "schema": PROPOSAL_SCHEMA,
                "adapter": "anthropic==1.7.0", "endpoint": "https://api.anthropic.com",
                "max_tokens": 8000, "context": context}

    def answer_payload(self, row: Row, rubric: dict, features: list[Feature]) -> dict:
        return {"model": self.config.answerer_model, "state": row.state(rubric),
                "adapter": "typesafe-sdk==0.7.0", "endpoint": "https://api.typesafe.ai",
                "questions": [asdict(feature) for feature in features]}

    def propose(self, context: dict, accepted: list[Feature]) -> list[tuple]:
        payload = self.proposal_payload(context)
        def validate(raw: dict) -> None:
            validate_proposal(raw, accepted, self.config)
        def call() -> dict:
            import anthropic
            require(importlib.metadata.version("anthropic") == "1.7.0", "install the pinned Anthropic SDK")
            key = os.environ.get("ANTHROPIC_API_KEY")
            require(bool(key), "--live requires ANTHROPIC_API_KEY")
            with anthropic.Anthropic(api_key=key, base_url=payload["endpoint"], max_retries=0, timeout=120) as client:
                response = client.messages.create(
                    model=payload["model"], max_tokens=payload["max_tokens"],
                    output_config={"format": {"type": "json_schema", "schema": PROPOSAL_SCHEMA}},
                    messages=[{"role": "user", "content": canonical(context).decode()}])
            require(response.stop_reason == "end_turn", "proposer did not finish a complete response")
            require(response.model == payload["model"], "proposer returned a different model ID; use a pinned ID")
            body = [block.text for block in response.content if block.type == "text"]
            require(len(body) == 1, "expected one structured proposal")
            return parse_json(body[0])
        raw = self.cache.get("proposal", payload, validate, call)
        return validate_proposal(raw, accepted, self.config)

    def answer(self, row: Row, rubric: dict, features: list[Feature]) -> dict[str, list[float]]:
        require(bool(features), "answer requires at least one question")
        payload = self.answer_payload(row, rubric, features)
        def validate(raw: dict) -> None:
            fields(raw, {feature.id for feature in features}, "answer set")
            for feature in features:
                probabilities(feature, raw[feature.id])
        def call() -> dict:
            from typesafe_sdk import Noul, RetryPolicy, Score, TypeSafeClient
            require(importlib.metadata.version("typesafe-sdk") == "0.7.0", "install the pinned TypeSafe SDK")
            key = os.environ.get("TYPESAFE_API_KEY")
            require(bool(key), "--live requires TYPESAFE_API_KEY")
            questions = {feature.id: (Score(instructions=feature.question, criteria=feature.criteria)
                         if feature.kind == "score" else
                         Noul(instructions=feature.question, criteria=feature.criteria)) for feature in features}
            # The SDK transport is checked in tests; no hidden retries exceed our request budget.
            with TypeSafeClient(api_key=key, base_url=payload["endpoint"], timeout=120,
                                retry=RetryPolicy(max_retries=0)) as client:
                response = client.system_one(state=payload["state"], questions=questions, model=payload["model"])
            require(response.model == payload["model"], "answerer returned a different model ID; use a pinned ID")
            raw = {}
            require(set(response.answers) == set(questions), "API returned unexpected question IDs")
            for feature in features:
                answer = response.answers[feature.id]
                raw[feature.id] = ({"type": "score", "probabilities": {
                    str(k): v for k, v in answer.probabilities.items()}} if feature.kind == "score"
                    else {"type": "noul", "noul": answer.noul})
            return raw
        raw = self.cache.get("answer", payload, validate, call)
        return {feature.id: probabilities(feature, raw[feature.id]) for feature in features}


def grouped_folds(rows: tuple[Row, ...], count: int, seed: int) -> list[set[str]]:
    groups: dict[str, set[str]] = {}
    for row in rows:
        groups.setdefault(row.group, set()).add(row.id)
    require(len(groups) >= count, "development group count must be at least folds")
    order = sorted(groups)
    random.Random(seed).shuffle(order)
    # Stable size sort preserves random tie-breaking, balancing whole groups only.
    order.sort(key=lambda key: -len(groups[key]))
    result = [set() for _ in range(count)]
    for group in order:
        index = min(range(count), key=lambda i: (len(result[i]), i))
        result[index].update(groups[group])
    return result


def rmse(rows: tuple[Row, ...], predictions: dict[str, float]) -> float:
    require(set(predictions) == {row.id for row in rows}, "prediction row IDs mismatch")
    require(all(math.isfinite(value) for value in predictions.values()), "non-finite prediction")
    return math.sqrt(sum((row.label - predictions[row.id]) ** 2 for row in rows) / len(rows))


class Learner:
    def __init__(self, config: Config):
        self.config = config

    def matrix(self, rows: tuple[Row, ...], features: list[Feature], answers: dict) -> list[list[float]]:
        return [[value for feature in features for value in encoded(feature, answers[row.id][feature.id])]
                for row in rows]

    def fit(self, rows: tuple[Row, ...], features: list[Feature], answers: dict):
        from catboost import CatBoostRegressor
        c = self.config
        return CatBoostRegressor(iterations=c.iterations, depth=c.depth, learning_rate=c.learning_rate,
                                 loss_function="RMSE", random_seed=c.seed, thread_count=1,
                                 allow_writing_files=False, allow_const_label=True, verbose=False).fit(
                                     self.matrix(rows, features, answers), [row.label for row in rows])

    def predict(self, train: tuple[Row, ...], test: tuple[Row, ...], features: list[Feature], answers: dict) -> dict:
        if not features or len({tuple(row) for row in self.matrix(train, features, answers)}) == 1:
            mean = sum(row.label for row in train) / len(train)
            return {row.id: mean for row in test}
        model = self.fit(train, features, answers)
        return dict(zip((row.id for row in test), map(float, model.predict(self.matrix(test, features, answers)))))

    def cv(self, rows: tuple[Row, ...], features: list[Feature], answers: dict) -> tuple[dict, float]:
        totals = {row.id: 0.0 for row in rows}
        for repeat in range(self.config.repeats):
            for ids in grouped_folds(rows, self.config.folds, self.config.seed + repeat):
                train, test = tuple(r for r in rows if r.id not in ids), tuple(r for r in rows if r.id in ids)
                for key, prediction in self.predict(train, test, features, answers).items():
                    totals[key] += prediction / self.config.repeats
        return totals, rmse(rows, totals)

    def importance(self, rows: tuple[Row, ...], features: list[Feature], answers: dict) -> dict:
        if not features:
            return {}
        values = self.fit(rows, features, answers).get_feature_importance()
        metadata = column_metadata(features)
        require(len(values) == len(metadata), "importance column count mismatch")
        result = {feature.id: 0.0 for feature in features}
        for column, value in zip(metadata, values):
            result[column["feature_id"]] += float(value)
        return result


def feedback(rows: tuple[Row, ...], predictions: dict, max_examples: int) -> list[dict]:
    ordered = sorted(rows, key=lambda row: (-abs(row.label - predictions[row.id]), row.id))
    count = min(len(rows), max_examples)
    worst = (count + 1) // 2
    chosen = ordered[:worst] + (ordered[-(count - worst):] if count > worst else [])
    return [{"row_id": row.id, "component": row.component, "description": row.description,
             "evidence": row.evidence, "human_label": row.label, "oof_prediction": predictions[row.id],
             "absolute_error": abs(row.label - predictions[row.id])} for row in chosen]


def versions() -> dict:
    result = {"python": sys.version.split()[0]}
    for package in ("catboost", "numpy", "typesafe-sdk", "anthropic"):
        try:
            result[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            result[package] = "not installed"
    return result


def frozen_snapshot(dataset: Dataset, config: Config, features: list[Feature], answers: dict,
                    best: float, baseline: float) -> dict:
    frozen = {"schema_version": VERSION, "dataset": dataset.fingerprint, "config": asdict(config),
              "features": [asdict(f) for f in features], "columns": column_metadata(features),
              "dev_answers": {row.id: {f.id: answers[row.id][f.id] for f in features} for row in dataset.dev},
              "dev_cv_rmse": best, "baseline_cv_rmse": baseline, "versions": versions(),
              "status": "features_selected" if features else "mean_baseline_selected"}
    frozen["freeze_id"] = digest(frozen)
    return frozen


def discover(dataset: Dataset, config: Config, adapters: ModelAdapters, output: Path) -> dict:
    require(not output.exists(), "output directory already exists; use a new run directory")
    grouped_folds(dataset.dev, config.folds, config.seed)
    require(len({row.label for row in dataset.dev}) > 1, "development labels must vary")
    output.mkdir(parents=True)
    write_new(output / "manifest.json", {"schema_version": VERSION, "dataset": dataset.fingerprint,
              "config": asdict(config), "versions": versions(), "scope": "text-description prediction only"})
    learner, accepted, answers = Learner(config), [], {row.id: {} for row in dataset.dev}
    predictions, best = learner.cv(dataset.dev, [], answers)
    baseline, history, journal = best, [], []
    write_new(output / "round-0.frozen.json", frozen_snapshot(dataset, config, accepted, answers, best, baseline))
    for round_index in range(1, config.rounds + 1):
        context = {"task": "Discover single, answerable text questions that help predict independent human "
                   "ratings of UI component descriptions against the provided source facts. Do not redesign UI, "
                   "invent source facts, ask for labels, or claim visual quality. Score levels must define "
                   "concrete ordered description properties; Noul criteria must distinguish true/false evidence. "
                   "Missing evidence is not proof of correctness. Add, revise, or drop questions by content ID. "
                   "Return an empty actions list when no defensible change remains.",
                   "round": round_index, "rubric": dataset.rubric, "limits": {"max_actions": config.max_actions,
                   "max_features": config.max_features}, "accepted": [asdict(f) for f in accepted],
                   "dev_cv_rmse": best, "baseline_cv_rmse": baseline, "history": history,
                   "importance": learner.importance(dataset.dev, accepted, answers),
                   "examples": feedback(dataset.dev, predictions, config.max_examples)}
        actions = adapters.propose(context, accepted)
        if not actions:
            journal.append({"round": round_index, "op": "stop", "reason": "empty proposal"})
            break
        possible_drop_count, viable = 0, []
        for action in actions:
            op, target, _ = action
            if op == "drop":
                possible_drop_count += 1
            if op == "add" and len(accepted) - possible_drop_count >= config.max_features:
                journal.append({"round": round_index, "op": op, "target": target, "accepted": False,
                                "reason": "feature limit, rejected before answer requests"})
            else:
                viable.append(action)
        actions = viable
        new_features = [feature for _, _, feature in actions if feature is not None]
        if new_features:
            for row in dataset.dev:
                answers[row.id].update(adapters.answer(row, dataset.rubric, new_features))
        for op, target, feature in actions:
            trial = [f for f in accepted if f.id != target]
            if feature is not None:
                trial.append(feature)
            if len(trial) > config.max_features:
                journal.append({"round": round_index, "op": op, "target": target,
                                "accepted": False, "reason": "feature limit"})
                continue
            # A constant new question cannot train CatBoost by itself. It provides no discrimination.
            matrix = learner.matrix(dataset.dev, trial, answers)
            flat = bool(trial) and len({tuple(row) for row in matrix}) == 1
            if flat:
                journal.append({"round": round_index, "op": op, "target": target,
                                "accepted": False, "reason": "all columns constant"})
                continue
            candidate_predictions, candidate = learner.cv(dataset.dev, trial, answers)
            took = candidate < best - config.min_gain
            journal.append({"round": round_index, "op": op, "target": target,
                            "feature": asdict(feature) if feature else None, "before": best,
                            "candidate": candidate, "accepted": took})
            if took:
                accepted, best, predictions = trial, candidate, candidate_predictions
        history.append({"round": round_index, "dev_cv_rmse": best, "feature_count": len(accepted)})
        write_new(output / f"round-{round_index}.json", {"history": history, "journal": journal,
                  "features": [asdict(f) for f in accepted], "oof": predictions})
        write_new(output / f"round-{round_index}.frozen.json",
                  frozen_snapshot(dataset, config, accepted, answers, best, baseline))
    frozen = frozen_snapshot(dataset, config, accepted, answers, best, baseline)
    write_new(output / "frozen.json", frozen)
    write_new(output / "journal.json", journal)
    return frozen


def validate_frozen(raw: dict, dataset: Dataset) -> tuple[Config, list[Feature]]:
    fields(raw, {"schema_version", "dataset", "config", "features", "columns", "dev_answers", "dev_cv_rmse",
                 "baseline_cv_rmse", "versions", "status", "freeze_id"}, "frozen run")
    require(raw["schema_version"] == VERSION, "unsupported frozen version")
    require(raw["dataset"] == dataset.fingerprint, "dataset changed after discovery")
    require(raw["freeze_id"] == digest({k: v for k, v in raw.items() if k != "freeze_id"}),
            "frozen manifest content hash mismatch")
    config = Config.from_json(raw["config"])
    require(isinstance(raw["features"], list) and len(raw["features"]) <= config.max_features,
            "invalid frozen feature count")
    features = [Feature.from_json(value) for value in raw["features"]]
    require(len({f.id for f in features}) == len(features), "duplicate frozen features")
    require(raw["columns"] == column_metadata(features), "frozen column metadata mismatch")
    require(raw["status"] == ("features_selected" if features else "mean_baseline_selected"),
            "frozen status disagrees with feature set")
    require(isinstance(raw["versions"], dict), "frozen versions must be an object")
    current = versions()
    for package in ("catboost", "numpy"):
        require(raw["versions"].get(package) == current[package],
                f"{package} version changed after discovery; restore frozen environment")
    fields(raw["dev_answers"], {row.id for row in dataset.dev}, "frozen development answers")
    for values in raw["dev_answers"].values():
        fields(values, {f.id for f in features}, "frozen row answers")
        for feature in features:
            validate_vector(feature, values[feature.id])
    for name in ("dev_cv_rmse", "baseline_cv_rmse"):
        number(raw[name], name, 0, 100000)
    return config, features


def evaluate_holdout(dataset: Dataset, frozen: dict, adapters: ModelAdapters, output: Path) -> dict:
    config, features = validate_frozen(frozen, dataset)
    require(asdict(adapters.config) == asdict(config), "adapter config differs from frozen config")
    require(not output.exists(), "evaluation output already exists")
    guard = adapters.cache.root / "evaluations" / f"{dataset.holdout_fingerprint}.started.json"
    require(not guard.exists(), "holdout already consumed for this dataset/cache, including failed attempts")
    # Discover missing cache entries before consuming the one-shot holdout guard. This permits
    # an offline cache miss to be resolved by an explicitly budgeted live invocation later.
    missing = sum(not adapters.cache.path("answer", adapters.answer_payload(row, dataset.rubric, features)).exists()
                  for row in dataset.test) if features else 0
    if missing:
        require(adapters.cache.budget.live,
                f"holdout requires {missing} uncached answers; offline preflight stopped before consuming holdout")
        require(adapters.cache.budget.limit - adapters.cache.budget.used >= missing,
                "remaining request budget cannot complete holdout; stopped before consuming holdout")
    # One-shot across run directories using the same cache and dataset; fail closed after a failed attempt.
    write_new(guard, {"dataset": dataset.fingerprint, "holdout": dataset.holdout_fingerprint,
                      "freeze_id": frozen["freeze_id"]})
    answers = {row.id: dict(frozen["dev_answers"][row.id]) for row in dataset.dev}
    if features:
        for row in dataset.test:
            answers[row.id] = adapters.answer(row, dataset.rubric, features)
    learner = Learner(config)
    predictions = learner.predict(dataset.dev, dataset.test, features, answers)
    baseline = learner.predict(dataset.dev, dataset.test, [], answers)
    report = {"schema_version": VERSION, "dataset": dataset.fingerprint, "freeze_id": frozen["freeze_id"],
              "test_rows": len(dataset.test), "test_groups": len({r.group for r in dataset.test}),
              "test_rmse": rmse(dataset.test, predictions), "mean_baseline_test_rmse": rmse(dataset.test, baseline),
              "predictions": predictions, "versions": versions(),
              "claim_scope": "Agreement with supplied human text-description labels on this split; "
              "not visual quality, usability, accessibility, or transfer to other components."}
    write_new(output, report)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "discover", "evaluate"))
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--frozen", type=Path)
    parser.add_argument("--cache", type=Path, default=Path("cache"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--request-budget", type=int, default=0)
    args = parser.parse_args(argv)
    budget = Budget(args.live, args.request_budget)
    try:
        integer(args.request_budget, "request budget", 0, 100000)
        if args.live:
            require(args.request_budget > 0, "--live requires a positive --request-budget")
            require(bool(os.environ.get("TYPESAFE_API_KEY")), "--live requires TYPESAFE_API_KEY")
            if args.command == "discover":
                require(bool(os.environ.get("ANTHROPIC_API_KEY")), "--live discovery requires ANTHROPIC_API_KEY")
        else:
            require(args.request_budget == 0, "offline mode requires request budget 0")
        dataset = dataset_from_json(read_json(args.dataset))
        if args.command == "validate":
            print(json.dumps({"dataset": dataset.fingerprint, "dev_rows": len(dataset.dev),
                              "test_rows": len(dataset.test), "status": "schema and provenance declaration valid"}))
            return 0
        require(args.output is not None, "--output is required")
        if args.command == "discover":
            require(args.config is not None and args.frozen is None, "discovery requires --config and no --frozen")
            config = Config.from_json(read_json(args.config))
            result = discover(dataset, config, ModelAdapters(Cache(args.cache, budget), config), args.output)
        else:
            require(args.frozen is not None and args.config is None, "evaluation requires --frozen and no --config")
            frozen = read_json(args.frozen)
            config, _ = validate_frozen(frozen, dataset)
            result = evaluate_holdout(dataset, frozen, ModelAdapters(Cache(args.cache, budget), config), args.output)
        print(json.dumps({"status": "completed", "output": str(args.output),
                          "model_requests": budget.used, "freeze_id": result["freeze_id"]}))
        return 0
    except (ResearchError, OSError, ImportError) as exc:
        # Never dump SDK exceptions containing requests, credentials or endpoint configuration.
        message = str(exc) if isinstance(exc, ResearchError) else f"{type(exc).__name__}: {getattr(exc, 'filename', '') or 'check local dependencies and paths'}"
        print(f"research stopped: {message}", file=sys.stderr)
        print(f"live requests attempted: {budget.used}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
