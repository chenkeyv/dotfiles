#!/usr/bin/env python3
"""Ensure the personal Codex marketplace exposes a Git-backed plugin."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def expected_entry(name: str, source_url: str) -> dict[str, Any]:
    return {
        "name": name,
        "source": {
            "source": "url",
            "url": source_url,
            "ref": "main",
        },
        "policy": {
            "installation": "AVAILABLE",
            "authentication": "ON_INSTALL",
        },
        "category": "Productivity",
    }


def load_marketplace(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "name": "personal",
            "interface": {"displayName": "Personal"},
            "plugins": [],
        }

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Invalid personal Codex marketplace JSON: {exc}") from exc

    if not isinstance(data, dict):
        raise SystemExit("Personal Codex marketplace must be a JSON object")
    if data.get("name") != "personal":
        raise SystemExit("Personal Codex marketplace must use the name 'personal'")
    if not isinstance(data.get("plugins"), list):
        raise SystemExit("Personal Codex marketplace field 'plugins' must be an array")
    return data


def entry_is_current(data: dict[str, Any], name: str, source_url: str) -> bool:
    expected = expected_entry(name, source_url)
    for entry in data["plugins"]:
        if isinstance(entry, dict) and entry.get("name") == name:
            return all(entry.get(key) == value for key, value in expected.items())
    return False


def update_marketplace(data: dict[str, Any], name: str, source_url: str) -> None:
    expected = expected_entry(name, source_url)
    for index, entry in enumerate(data["plugins"]):
        if isinstance(entry, dict) and entry.get("name") == name:
            data["plugins"][index] = {**entry, **expected}
            break
    else:
        data["plugins"].append(expected)

    data.setdefault("interface", {"displayName": "Personal"})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("marketplace", type=Path)
    parser.add_argument("source_url")
    parser.add_argument("--name", default="agent-toolbox")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    data = load_marketplace(args.marketplace)
    if args.check:
        return 0 if entry_is_current(data, args.name, args.source_url) else 1

    update_marketplace(data, args.name, args.source_url)
    args.marketplace.parent.mkdir(parents=True, exist_ok=True)
    args.marketplace.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
