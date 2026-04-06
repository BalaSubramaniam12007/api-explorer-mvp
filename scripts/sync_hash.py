"""Sync one batch of specs and update content hashes."""

from __future__ import annotations

import hashlib
import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "registry"


def read_json(path: Path) -> dict:
    """Read a JSON file into a dictionary."""
    return json.loads(path.read_text(encoding="utf-8") or "{}")


def write_json(path: Path, data: dict) -> None:
    """Write a dictionary to JSON with stable formatting."""
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def fetch_hash(url: str) -> str:
    """Fetch URL bytes and return a sha256 hash string."""
    with urllib.request.urlopen(url, timeout=15) as response:
        return "sha256:" + hashlib.sha256(response.read()).hexdigest()


def main() -> None:
    """Process current batch, update hashes, and rotate batch index."""
    registry = read_json(REGISTRY / "registry.json")
    hashes = read_json(REGISTRY / "hashes.json")
    batch_state = read_json(REGISTRY / "batch.json")
    batches: list[list[str]] = batch_state.get("batches", [])
    if not batches:
        # Safety fallback: reconstruct from registry if batch.json is empty
        batches = [sorted(registry.keys())] if registry else [[]]

    index = batch_state.get("current_batch_index", 0) % len(batches)
    current_batch = list(batches[index])
    next_index = (index + 1) % len(batches)
    updated: list[str] = []
    errors: dict[str, str] = {}

    for api_id in current_batch:
        url = registry.get(api_id, {}).get("openapi_url")
        if not url:
            continue
        try:
            new_hash = fetch_hash(url)
            if hashes.get(api_id) != new_hash:
                hashes[api_id] = new_hash
                updated.append(api_id)
        except Exception as exc:  # noqa: BLE001
            errors[api_id] = str(exc)

    batch_state["batches"] = batches
    batch_state["current_batch_index"] = next_index

    write_json(REGISTRY / "hashes.json", hashes)
    write_json(REGISTRY / "batch.json", batch_state)
    write_json(
        REGISTRY / "updates.json",
        {
            "errors": errors,
            "last_run_at": datetime.now(timezone.utc).isoformat(),
            "processed_batch_index": index,
            "next_batch_index": next_index,
            "processed_ids": current_batch,
            "updated_ids": updated,
        },
    )


if __name__ == "__main__":
    """Run sync script."""
    main()
