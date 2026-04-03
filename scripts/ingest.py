"""Ingest new API sources into registry and batches."""

from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "registry"


def read_json(path: Path) -> dict:
    """Read a JSON file into a dictionary."""
    return json.loads(path.read_text(encoding="utf-8") or "{}")


def write_json(path: Path, data: dict) -> None:
    """Write a dictionary to JSON with stable formatting."""
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def pick_batch(batches: list[list[str]], size: int) -> list[str]:
    """Return a batch with free slots, or create a new batch."""
    for batch in batches:
        if len(batch) < size:
            return batch
    batches.append([])
    return batches[-1]


def main() -> None:
    """Merge intake into registry, assign batches, and clear intake."""
    batch_size = max(1, int(os.getenv("BATCH_SIZE", "3")))
    intake = read_json(REGISTRY / "input.json")
    registry = read_json(REGISTRY / "registry.json")
    batch_state = read_json(REGISTRY / "batch.json")
    batches: list[list[str]] = batch_state.get("batches", [])

    if not batches:
        batches = [[]]

    existing = set(registry)
    registry.update(intake)
    assigned = {sid for batch in batches for sid in batch}

    for sid in registry:
        if sid in assigned:
            continue
        pick_batch(batches, batch_size).append(sid)

    batch_state["batches"] = batches
    batch_state["current_batch_index"] = min(batch_state.get("current_batch_index", 0), len(batches) - 1)

    write_json(REGISTRY / "registry.json", registry)
    write_json(REGISTRY / "batch.json", batch_state)
    write_json(REGISTRY / "input.json", {})


if __name__ == "__main__":
    """Run ingestion script."""
    main()
