"""Loader for `bazel aquery --output=jsonproto` dumps.

Turns the id-indexed wire format into objects with resolved paths.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field


@dataclass
class Action:
    mnemonic: str
    target_label: str
    rule_class: str
    argv: list[str]
    inputs: list[str]
    outputs: list[str]
    primary_output: str
    config_mnemonic: str
    is_tool_config: bool
    # TemplateExpand carries its work in these instead of a command line.
    template_content: str = ""
    substitutions: list[tuple[str, str]] = field(default_factory=list)


@dataclass
class Aquery:
    actions: list[Action]
    # Every artifact path the dump mentions, keyed by artifact id.
    artifact_paths: dict[int, str] = field(default_factory=dict)

    def by_mnemonic(self, mnemonic: str) -> list[Action]:
        return [a for a in self.actions if a.mnemonic == mnemonic]

    def target_labels(self) -> set[str]:
        return {a.target_label for a in self.actions}


def _resolve_fragments(fragments: list[dict]) -> dict[int, str]:
    """Walk each pathFragment's parent chain into a full path."""
    by_id = {f["id"]: f for f in fragments}
    resolved: dict[int, str] = {}

    for start in by_id:
        if start in resolved:
            continue
        # Collect the chain up to an already-resolved ancestor or the root.
        chain = []
        cur = start
        while cur is not None and cur not in resolved:
            frag = by_id[cur]
            chain.append(cur)
            cur = frag.get("parentId")
        prefix = resolved[cur] if cur is not None else ""
        for node in reversed(chain):
            label = by_id[node]["label"]
            prefix = f"{prefix}/{label}" if prefix else label
            resolved[node] = prefix

    return resolved


def _flatten_depsets(depsets: list[dict]) -> dict[int, set[int]]:
    """Flatten each depset into the full set of artifact ids it reaches."""
    by_id = {d["id"]: d for d in depsets}
    flat: dict[int, set[int]] = {}

    def resolve(dep_id: int) -> set[int]:
        if dep_id in flat:
            return flat[dep_id]
        # Iterative post-order so deep transitive chains cannot blow the stack.
        order: list[int] = []
        stack = [dep_id]
        seen = set()
        while stack:
            cur = stack.pop()
            if cur in flat or cur in seen:
                continue
            seen.add(cur)
            order.append(cur)
            for child in by_id[cur].get("transitiveDepSetIds", []):
                if child not in flat:
                    stack.append(child)
        for cur in reversed(order):
            acc = set(by_id[cur].get("directArtifactIds", []))
            for child in by_id[cur].get("transitiveDepSetIds", []):
                acc |= flat[child]
            flat[cur] = acc
        return flat[dep_id]

    for dep_id in by_id:
        resolve(dep_id)
    return flat


def load(path: str) -> Aquery:
    with open(path) as fh:
        raw = json.load(fh)

    frag_paths = _resolve_fragments(raw.get("pathFragments", []))
    artifact_paths = {
        a["id"]: frag_paths[a["pathFragmentId"]] for a in raw.get("artifacts", [])
    }
    rule_classes = {r["id"]: r["name"] for r in raw.get("ruleClasses", [])}
    targets = {
        t["id"]: (t["label"], rule_classes.get(t.get("ruleClassId"), ""))
        for t in raw.get("targets", [])
    }
    configs = {
        c["id"]: (c.get("mnemonic", ""), bool(c.get("isTool")))
        for c in raw.get("configuration", [])
    }
    depsets = _flatten_depsets(raw.get("depSetOfFiles", []))

    actions = []
    for a in raw.get("actions", []):
        label, rule_class = targets.get(a["targetId"], ("", ""))
        config_mnemonic, is_tool = configs.get(a.get("configurationId"), ("", False))

        input_ids: set[int] = set()
        for dep_id in a.get("inputDepSetIds", []):
            input_ids |= depsets.get(dep_id, set())

        actions.append(
            Action(
                mnemonic=a["mnemonic"],
                target_label=label,
                rule_class=rule_class,
                argv=a.get("arguments", []),
                inputs=sorted(artifact_paths[i] for i in input_ids if i in artifact_paths),
                outputs=[
                    artifact_paths[o] for o in a.get("outputIds", []) if o in artifact_paths
                ],
                primary_output=artifact_paths.get(a.get("primaryOutputId"), ""),
                config_mnemonic=config_mnemonic,
                is_tool_config=is_tool,
                template_content=a.get("templateContent", ""),
                substitutions=[
                    (s.get("key", ""), s.get("value", ""))
                    for s in a.get("substitutions", [])
                ],
            )
        )

    return Aquery(actions=actions, artifact_paths=artifact_paths)
