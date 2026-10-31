#!/usr/bin/env python3
"""Checks a generated SwiftyChain DocC archive for the pages and curation the site needs.

Usage: scripts/check-docs.py <archive-or-site-directory>

Fails when articles, tutorials, curated topic groups, or key symbol pages are missing,
when package-internal symbols leak into the public docs, or when a cross-module
reference has no destination.
"""
import glob
import json
import os
import sys

REQUIRED_PAGES = [
    "swiftychain",
    "swiftychain/gettingstarted",
    "swiftychain/linux",
    "swiftychain/architecture",
    "swiftychain/testing",
    "swiftychain/usingmacros",
    "swiftychain/internetpasswords",
    "swiftychain/customstorabletypes",
    "swiftychain/keychain",
    "swiftychain/keychainkey",
    "swiftychain/keychainerror",
    "swiftychain/keychainstorage",
    "swiftychain/keychainaccessibility",
    "swiftychaintesting",
    "swiftychaintesting/inmemorykeychain",
    "swiftychaintesting/inmemorykeychainbackend",
]
REQUIRED_TUTORIALS = ["swiftychaintutorials"]
REQUIRED_TOPIC_GROUPS = ["Essentials", "Platforms", "Errors"]
INTERNAL_NAMES = [
    "securestoragebackend", "securestoragecapabilities", "keychainengine", "keychainquery",
    "platformdefaultbackend", "unsupportedplatformbackend", "inmemorystoragebackend",
    "secretservice", "applekeychainbackend", "swiftychainloggers",
]


def main() -> int:
    root = sys.argv[1]
    data = os.path.join(root, "data")
    problems = []

    for page in REQUIRED_PAGES:
        if not os.path.exists(os.path.join(data, "documentation", page + ".json")):
            problems.append(f"missing page: documentation/{page}")
    for page in REQUIRED_TUTORIALS:
        if not os.path.exists(os.path.join(data, "tutorials", page + ".json")):
            problems.append(f"missing tutorial: tutorials/{page}")

    landing = os.path.join(data, "documentation", "swiftychain.json")
    if os.path.exists(landing):
        groups = [s.get("title") for s in json.load(open(landing)).get("topicSections", [])]
        for group in REQUIRED_TOPIC_GROUPS:
            if group not in groups:
                problems.append(f"landing page is missing curated topic group '{group}' (found {groups})")

    for path in glob.glob(os.path.join(data, "**", "*.json"), recursive=True):
        relative = os.path.relpath(path, data).lower()
        if any(name in relative for name in INTERNAL_NAMES):
            problems.append(f"package-internal symbol documented: {relative}")
        for key, reference in json.load(open(path)).get("references", {}).items():
            if "SwiftyChain" in key and reference.get("type") == "topic" and not reference.get("url"):
                problems.append(f"reference without destination in {relative}: {key}")

    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1
    print(f"Documentation check passed: {len(REQUIRED_PAGES)} pages, "
          f"{len(REQUIRED_TUTORIALS)} tutorials, curated landing page, no internal symbols.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
