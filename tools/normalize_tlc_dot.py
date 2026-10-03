#!/usr/bin/env python3
import re
import sys
from pathlib import Path

NODE_RE = re.compile(
    r'^\s*(?P<id>"[^"]+"|[^\s\[]+)\s+\[(?P<attrs>.*)\]\s*;?\s*$'
)
EDGE_RE = re.compile(
    r'^\s*(?P<src>"[^"]+"|[^\s]+)\s*->\s*(?P<dst>"[^"]+"|[^\s\[]+)\s+\[(?P<attrs>.*)\]\s*;?\s*$'
)
LABEL_RE = re.compile(r'\blabel="(?P<label>(?:\\.|[^"])*)"')
STATE_RE = re.compile(r'\bstate\s*=\s*(?P<state>[A-Za-z_][A-Za-z0-9_]*)')
ACTION_RE = re.compile(r'<?(?P<action>[A-Za-z_][A-Za-z0-9_]*)')


def unquote_id(value: str) -> str:
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def unescape_dot_label(value: str) -> str:
    return (
        value.replace(r'\"', '"')
        .replace(r'\n', '\n')
        .replace(r'\\', '\')
    )


def label_from_attrs(attrs: str) -> str | None:
    match = LABEL_RE.search(attrs)
    if match is None:
        return None
    return unescape_dot_label(match.group("label"))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: normalize_tlc_dot.py STATE_GRAPH.dot", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    nodes: dict[str, str] = {}
    edges: list[tuple[str, str, str]] = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        edge_match = EDGE_RE.match(raw_line)
        if edge_match is not None:
            label = label_from_attrs(edge_match.group("attrs"))
            if label is None:
                continue
            action_match = ACTION_RE.search(label.strip())
            if action_match is None:
                raise SystemExit(f"could not parse action label: {label!r}")
            edges.append(
                (
                    unquote_id(edge_match.group("src")),
                    action_match.group("action").lower(),
                    unquote_id(edge_match.group("dst")),
                )
            )
            continue

        node_match = NODE_RE.match(raw_line)
        if node_match is None:
            continue
        label = label_from_attrs(node_match.group("attrs"))
        if label is None:
            continue
        state_match = STATE_RE.search(label)
        if state_match is None:
            continue
        nodes[unquote_id(node_match.group("id"))] = state_match.group("state").lower()

    normalized: set[tuple[str, str, str]] = set()
    for src, action, dst in edges:
        if src not in nodes or dst not in nodes:
            raise SystemExit(
                f"edge references an unparsed state node: {src!r} -> {dst!r}"
            )
        normalized.add((nodes[src], action, nodes[dst]))

    if not normalized:
        raise SystemExit("no TLC transitions found in DOT state graph")

    for before, action, after in sorted(normalized):
        print(f"{before}\t{action}\t{after}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
