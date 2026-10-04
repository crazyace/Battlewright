#!/usr/bin/env python3
"""Summarise BattlewrightProbe recordings: what can an addon read in combat?

Input is either:
  * the SavedVariables file:  WTF/Account/<ACCOUNT>/SavedVariables/BattlewrightProbe.lua
  * a JSON file you pasted from /bwp export

Usage:
  python tools/probe_summary.py BattlewrightProbe.lua
  python tools/probe_summary.py export.json -o data/probe/2026-10-04-combat.json
"""
import argparse
import json
import re
import sys
from pathlib import Path


# --- Minimal Lua table parser (enough for WoW SavedVariables) ----------------

class LuaParser:
    TOKEN = re.compile(r"""
        (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*)
      | (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
      | (?P<num>-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+))
      | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
      | (?P<sym>[{}\[\]=,;])
    """, re.VERBOSE | re.DOTALL)

    ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}

    def __init__(self, text):
        self.tokens = []
        pos = 0
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m:
                raise ValueError(f"unexpected character at {pos}: {text[pos:pos+20]!r}")
            pos = m.end()
            kind = m.lastgroup
            if kind != "ws":
                self.tokens.append((kind, m.group()))
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError(f"expected {value!r}, got {tok[1]!r}")
        self.i += 1
        return tok

    def unquote(self, s):
        body = s[1:-1]
        out, k = [], 0
        while k < len(body):
            c = body[k]
            if c == "\\" and k + 1 < len(body):
                nxt = body[k + 1]
                if nxt.isdigit():
                    m = re.match(r"\d{1,3}", body[k + 1:])
                    out.append(chr(int(m.group())))
                    k += 1 + len(m.group())
                    continue
                out.append(self.ESCAPES.get(nxt, nxt))
                k += 2
                continue
            out.append(c)
            k += 1
        return "".join(out)

    def value(self):
        kind, tok = self.peek()
        if tok == "{":
            return self.table()
        self.take()
        if kind == "str":
            return self.unquote(tok)
        if kind == "num":
            n = int(tok, 16) if tok.lower().startswith(("0x", "-0x")) else float(tok)
            return int(n) if isinstance(n, float) and n.is_integer() else n
        if tok == "true":
            return True
        if tok == "false":
            return False
        if tok == "nil":
            return None
        raise ValueError(f"unexpected token {tok!r}")

    def table(self):
        self.take("{")
        items, arr, auto = {}, [], 1
        while self.peek()[1] != "}":
            kind, tok = self.peek()
            if tok == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                items[key] = self.value()
            elif kind == "name" and self.tokens[self.i + 1][1] == "=":
                self.take()
                self.take("=")
                items[tok] = self.value()
            else:
                items[auto] = self.value()
                auto += 1
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        # Convert 1..n integer-keyed tables to lists.
        keys = list(items)
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [items[k] for k in range(1, len(keys) + 1)]
        if not keys:
            return {}
        return {str(k): v for k, v in items.items()}

    def assignments(self):
        out = {}
        while self.peek()[0] is not None:
            _, name = self.take()
            self.take("=")
            out[name] = self.value()
        return out


def load(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    if text.lstrip().startswith("{"):
        return json.loads(text)
    return LuaParser(text).assignments().get("BattlewrightProbeDB", {})


def summarize(db):
    runs = db.get("runs") or []
    if isinstance(runs, dict):
        runs = [runs[k] for k in sorted(runs, key=lambda k: int(k))]
    if not runs:
        return "no combat recorded yet: /bwp combat, then fight something"
    lines = []
    for run in runs:
        lines.append(f"combat {run.get('at')}: {run.get('samples')} samples")
        secret = []
        for name, rec in sorted(run.items()):
            if isinstance(rec, dict) and "calls" in rec:
                # An error on most calls (e.g. "Auras cannot be accessed when secret
                # while tainted") means blocked in combat, even if a call before the
                # fight started worked.
                if rec.get("secret"):
                    state = "SECRET"
                elif rec.get("errors", 0) > rec.get("readable", 0):
                    state = "BLOCKED"
                elif rec.get("readable"):
                    state = "readable"
                else:
                    state = "missing" if rec.get("missing") else "error"
                if state in ("SECRET", "BLOCKED"):
                    secret.append(name)
                if rec.get("error") and state == "BLOCKED":
                    state += " - " + str(rec["error"]).split("\n")[0]
                lines.append(f"   {name}: {state} ({rec.get('readable', 0)} readable, {rec.get('secret', 0)} secret, "
                             f"{rec.get('missing', 0)} missing, {rec.get('errors', 0)} errors)")
        lines.append(f"   known spells: {', '.join(sorted((run.get('known') or {}).keys())) or '-'}")
        lines.append(f"   last buffs: {', '.join(map(str, run.get('buffs') or [])) or '-'}")
        lines.append(f"   last debuffs on target: {', '.join(map(str, run.get('debuffs') or [])) or '-'}")
        lines.append("   verdict: " + ("everything Battlewright reads was readable" if not secret
                                       else "hidden in combat: " + ", ".join(secret)))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="BattlewrightProbe.lua (SavedVariables) or exported .json")
    ap.add_argument("-o", "--out", help="write normalized JSON here")
    args = ap.parse_args()
    db = load(args.input)
    if args.out:
        Path(args.out).write_text(json.dumps(db, indent=1, sort_keys=True))
        print(f"wrote {args.out}")
    print(summarize(db))
    return 0


if __name__ == "__main__":
    sys.exit(main())
