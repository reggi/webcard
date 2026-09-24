#!/usr/bin/env python3

import hashlib
import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = ROOT / "spec" / "1.0.0"
CAPTURE_PATH = re.compile(r"^captures/[0-9]{8}T[0-9]{6}\.[0-9]{3}Z(?:-[0-9]+)?\.json$")
DIGEST = re.compile(r"^[a-f0-9]{64}$")


def load_json(path):
    def reject_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key {key!r}")
            result[key] = value
        return result

    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=reject_duplicates)


def validate_schemas():
    for path in sorted((SPEC / "schemas").glob("*.schema.json")):
        schema = load_json(path)
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        assert schema["$id"] == f"https://webcard.app/spec/1.0.0/schemas/{path.name}"


def validate_example(directory):
    assert (directory / "mimetype").read_bytes().rstrip(b"\n") == b"application/vnd.everything.webcard+zip"
    root = load_json(directory / "webcard.json")
    assert root["formatVersion"] == "1.0.0"
    captures = root["captures"]
    assert captures and len(captures) == len(set(captures))
    assert root["currentCapture"] in captures

    referenced = {"mimetype", "webcard.json"}
    for relative_capture in captures:
        assert CAPTURE_PATH.fullmatch(relative_capture)
        capture_path = directory / relative_capture
        capture = load_json(capture_path)
        capture_id = pathlib.PurePosixPath(relative_capture).stem
        assert capture["id"] == capture_id
        referenced.add(relative_capture)
        for field in ("image", "icon"):
            asset = capture.get(field)
            if asset is None:
                continue
            digest = asset["sha256"]
            assert DIGEST.fullmatch(digest)
            assert asset["path"].startswith(f"assets/sha256/{digest}.")
            asset_path = directory / asset["path"]
            data = asset_path.read_bytes()
            assert len(data) == asset["byteLength"]
            assert hashlib.sha256(data).hexdigest() == digest
            referenced.add(asset["path"])

    actual = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file()
    }
    assert actual == referenced, f"unreferenced or missing entries: {sorted(actual ^ referenced)}"


def main():
    validate_schemas()
    examples = sorted(path for path in (SPEC / "examples").iterdir() if path.is_dir())
    assert examples
    for example in examples:
        validate_example(example)
    print(f"Validated Webcard Format 1.0.0 schemas and {len(examples)} example package(s).")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, OSError, ValueError) as error:
        print(f"Specification validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
