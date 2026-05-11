#!/usr/bin/env python3
"""Claude Code status line script.

Usage: statusline.py [LABEL]   (LABEL defaults to WORK)
Outputs: LABEL | ctx% tok | 5h% (+/-pp) | 7d% | worktree | PR#NNNN | model
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

# ANSI color codes
RESET = "\033[0m"
BOLD = "\033[1m"
CYAN = "\033[36m"
BRIGHT_YELLOW = "\033[1;33m"
BRIGHT_GREEN = "\033[1;32m"
BRIGHT_BLUE = "\033[1;34m"
MAGENTA = "\033[35m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
DIM_GRAY = "\033[2;37m"

SAMPLE_PATH = Path("/tmp/claude_statusline_sample.json")
PR_CACHE_TTL_SECS = 60


def pct_color(pct: int) -> str:
    """ANSI color by threshold: <50 green, <80 yellow, else red."""
    if pct < 50:
        return GREEN
    if pct < 80:
        return YELLOW
    return RED


def fmt_tokens(n: int) -> str:
    """Xk for <1M; XM (whole) or X.YM (one decimal) for >=1M."""
    if n >= 1_000_000:
        v = n / 1_000_000
        if v == int(v):
            return f"{int(v)}M"
        return f"{v:.1f}M"
    return f"{n // 1000}k"


def fmt_count(n: int) -> str:
    """Like fmt_tokens but renders <1000 as a raw integer (avoid `0k` for small counts)."""
    if n < 1000:
        return str(n)
    return fmt_tokens(n)


def color_pct_field(val: str) -> str:
    """Color a percentage field like '45%' by threshold; dash stays dim."""
    if val == "-":
        return f"{DIM_GRAY}-{RESET}"
    num = int(val.rstrip("%"))
    return f"{pct_color(num)}{val}{RESET}"


def parse_resets_at(v: Any) -> int | None:
    """Parse resets_at (epoch int, numeric string, or ISO 8601 string) to epoch seconds."""
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return int(v)
    if isinstance(v, str):
        if v.isdigit():
            return int(v)
        try:
            if v.endswith("Z"):
                dt = datetime.fromisoformat(v[:-1] + "+00:00")
            else:
                dt = datetime.fromisoformat(v)
            return int(dt.timestamp())
        except ValueError:
            return None
    return None


def fmt_reset_time(resets_at: Any, include_day: bool = False) -> str:
    """Return colored ' 15:30' (or ' Mon 15:30' with include_day) suffix, or ''.

    Time is rendered in the local timezone, 24-hour format.
    """
    epoch = parse_resets_at(resets_at)
    if epoch is None:
        return ""
    dt = datetime.fromtimestamp(epoch)
    t = f"{dt.hour:02d}:{dt.minute:02d}"
    if include_day:
        t = f"{dt.strftime('%a')} {t}"
    return f" {DIM_GRAY}{t}{RESET}"


def pace_delta_suffix(used_pct: int, resets_at: Any, window_secs: int) -> str:
    """Compute pace delta (used% - elapsed%); return colored ' (+/-Dpp)' suffix or ''.

    <=-5pp green (under pace), -5..+5 dim (on pace), >=+5 red (over pace).
    """
    reset_epoch = parse_resets_at(resets_at)
    if reset_epoch is None:
        return ""
    now = int(time.time())
    window_start = reset_epoch - window_secs
    elapsed = now - window_start
    # Guard against negative elapsed or elapsed > window (clock skew / already-reset window).
    if elapsed <= 0 or elapsed > window_secs:
        return ""
    elapsed_pct = elapsed / window_secs * 100
    delta = round(used_pct - elapsed_pct)
    if delta <= -5:
        col = GREEN
    elif delta >= 5:
        col = RED
    else:
        col = DIM_GRAY
    sign = "+" if delta >= 0 else ""
    return f" {col}{sign}{delta}pp{RESET}"


def _have(cmd: str) -> bool:
    for p in os.environ.get("PATH", "").split(os.pathsep):
        if p and os.access(os.path.join(p, cmd), os.X_OK):
            return True
    return False


def lookup_pr(cwd: str) -> str:
    """Return PR field string (colored), or '' if no PR / unavailable. Caches per-branch (60s TTL)."""
    if not cwd or not _have("gh"):
        return ""
    try:
        branch = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        return ""
    if not branch or branch == "HEAD":
        return ""
    # Sanitize branch name for use as filename.
    branch_key = re.sub(r"[^A-Za-z0-9_.-]", "", branch.replace("/", "_"))
    cache_file = Path(f"/tmp/claude_pr_cache_{branch_key}")

    pr_json_text: str | None = None
    if cache_file.exists():
        try:
            age = time.time() - cache_file.stat().st_mtime
            if age < PR_CACHE_TTL_SECS:
                pr_json_text = cache_file.read_text()
        except OSError:
            pass

    if pr_json_text is None:
        try:
            res = subprocess.run(
                ["gh", "pr", "view", "--json", "number,state,isDraft"],
                cwd=cwd, capture_output=True, text=True, timeout=1,
            )
            pr_json_text = res.stdout if res.returncode == 0 else ""
        except (subprocess.SubprocessError, FileNotFoundError):
            pr_json_text = ""
        # Cache the result (empty = no PR or timeout — cache that too to avoid retry storms).
        try:
            cache_file.write_text(pr_json_text)
        except OSError:
            pass

    if not pr_json_text:
        return ""
    try:
        data = json.loads(pr_json_text)
    except json.JSONDecodeError:
        return ""
    num = data.get("number")
    if not num:
        return ""
    if data.get("isDraft", False):
        return f"{MAGENTA}PR#{num}{RESET} {DIM_GRAY}(draft){RESET}"
    return f"{MAGENTA}PR#{num}{RESET}"


def _find_usage(obj: Any) -> dict | None:
    """Recursively find a 'usage' object inside nested JSON."""
    if isinstance(obj, dict):
        u = obj.get("usage")
        if isinstance(u, dict):
            return u
        for v in obj.values():
            r = _find_usage(v)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = _find_usage(v)
            if r is not None:
                return r
    return None


def last_usage_from_transcript(path: str) -> tuple[int, int, int] | None:
    """Return (input_tokens, cache_creation_input_tokens, cache_read_input_tokens) from the last
    'usage' block in a JSONL transcript, or None if no usage was found.
    """
    if not path or not os.path.isfile(path):
        return None
    last_usage: dict | None = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                # Cheap prefilter to avoid JSON-parsing every line.
                if '"usage"' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                u = _find_usage(obj)
                if u is not None:
                    last_usage = u
    except OSError:
        return None
    if not last_usage:
        return None
    return (
        int(last_usage.get("input_tokens", 0) or 0),
        int(last_usage.get("cache_creation_input_tokens", 0) or 0),
        int(last_usage.get("cache_read_input_tokens", 0) or 0),
    )


def main() -> int:
    label = sys.argv[1] if len(sys.argv) > 1 else "WORK"
    label_color = {
        "WORK": BRIGHT_YELLOW,
        "PERSONAL": BRIGHT_GREEN,
    }.get(label, BOLD)

    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = {}

    # Write first-seen input to sample file for schema inspection.
    if not SAMPLE_PATH.exists():
        try:
            SAMPLE_PATH.write_text(raw if raw.endswith("\n") else raw + "\n")
        except OSError:
            pass
    # Always also write last-seen input for live diagnostics.
    try:
        Path("/tmp/claude_statusline_last.json").write_text(raw if raw.endswith("\n") else raw + "\n")
    except OSError:
        pass

    transcript_path = data.get("transcript_path") or ""
    model = data.get("model") or {}
    model_display = model.get("display_name") or "unknown"
    model_id = model.get("id") or ""
    workspace = data.get("workspace") or {}
    cwd = workspace.get("current_dir") or ""
    git_worktree = workspace.get("git_worktree") or ""
    context_window = data.get("context_window") or {}

    # Context window size: prefer authoritative JSON field, else infer from model_id substring.
    ctx_window = context_window.get("context_window_size")
    if not isinstance(ctx_window, int) or ctx_window <= 0:
        ctx_window = 1_000_000 if "[1m]" in model_id else 200_000

    # Token counts. Three input-side categories fill the context window:
    #   input_tokens                 — fresh, not in cache this turn
    #   cache_creation_input_tokens  — newly written to cache this turn
    #   cache_read_input_tokens      — read from cache
    # output_tokens is excluded (becomes part of context only on the next turn's input).
    # Sources, in priority order:
    #   1. JSON context_window.current_usage  (exact, full breakdown)
    #   2. JSON context_window.total_input_tokens  (exact, total only)
    #   3. transcript JSONL last usage block  (exact, full breakdown)
    #   4. JSON context_window.used_percentage  (approximate; marked with '~', no breakdown)
    tokens_exact = False
    total_tokens = 0
    breakdown: tuple[int, int, int] | None = None

    cu = context_window.get("current_usage")
    if isinstance(cu, dict):
        in_t = int(cu.get("input_tokens") or 0)
        cc_t = int(cu.get("cache_creation_input_tokens") or 0)
        cr_t = int(cu.get("cache_read_input_tokens") or 0)
        if in_t + cc_t + cr_t > 0:
            breakdown = (in_t, cc_t, cr_t)
            total_tokens = in_t + cc_t + cr_t
            tokens_exact = True

    if total_tokens == 0:
        json_total = context_window.get("total_input_tokens")
        if isinstance(json_total, (int, float)) and json_total > 0:
            total_tokens = int(json_total)
            tokens_exact = True

    if total_tokens == 0 and transcript_path:
        b = last_usage_from_transcript(transcript_path)
        if b is not None and sum(b) > 0:
            breakdown = b
            total_tokens = sum(b)
            tokens_exact = True

    ctx_pct = "-"
    if total_tokens > 0:
        ctx_pct = f"{round(total_tokens / ctx_window * 100)}%"
    else:
        used_pct_raw = context_window.get("used_percentage")
        if isinstance(used_pct_raw, (int, float)):
            ctx_pct = f"{round(used_pct_raw)}%"
            total_tokens = round(used_pct_raw / 100 * ctx_window)

    tokens_display = ""
    if total_tokens > 0:
        prefix = "" if tokens_exact else "~"
        # Highlight when usage has crossed the 200k threshold (extended-context billing tier).
        color = YELLOW if total_tokens > 200_000 else DIM_GRAY
        if breakdown is not None:
            in_t, cc_t, cr_t = breakdown
            parts_txt = f"({fmt_count(in_t)} + {fmt_count(cc_t)} + {fmt_count(cr_t)})"
            tokens_display = f" {color}{prefix}{parts_txt}/{fmt_tokens(ctx_window)}{RESET}"
        else:
            tokens_display = f" {color}{prefix}{fmt_tokens(total_tokens)}/{fmt_tokens(ctx_window)}{RESET}"

    # Rate limits. 5h has a fixed window; 7d is a rolling window — pace delta for 7d is shown but
    # the semantics are "% used vs % of rolling window elapsed since oldest tracked usage."
    rate_limits = data.get("rate_limits") or {}
    five = rate_limits.get("five_hour") or {}
    seven = rate_limits.get("seven_day") or {}
    five_raw = five.get("used_percentage")
    seven_raw = seven.get("used_percentage")
    five_pct = f"{round(five_raw)}%" if isinstance(five_raw, (int, float)) else "-"
    seven_pct = f"{round(seven_raw)}%" if isinstance(seven_raw, (int, float)) else "-"
    five_delta = ""
    five_reset = ""
    if isinstance(five_raw, (int, float)):
        five_delta = pace_delta_suffix(round(five_raw), five.get("resets_at"), 18_000)
        five_reset = fmt_reset_time(five.get("resets_at"), include_day=False)
    seven_delta = ""
    seven_reset = ""
    if isinstance(seven_raw, (int, float)):
        seven_delta = pace_delta_suffix(round(seven_raw), seven.get("resets_at"), 7 * 86_400)
        seven_reset = fmt_reset_time(seven.get("resets_at"), include_day=True)

    # Worktree label. Canonical schema is top-level `worktree.*` (only present during --worktree
    # sessions). For native worktrees both `branch` and `original_branch` are set; for hook-based
    # worktrees neither is set and we fall back to `name`. Outside worktree sessions, fall back to
    # the legacy `workspace.git_worktree` field, then basename(cwd).
    worktree_obj = data.get("worktree") if isinstance(data.get("worktree"), dict) else {}
    wt_branch = worktree_obj.get("branch")
    wt_original = worktree_obj.get("original_branch")
    wt_name = worktree_obj.get("name")
    if wt_branch and wt_original:
        worktree_name = f"{wt_original} <- {wt_branch}"
    elif wt_branch:
        worktree_name = wt_branch
    elif wt_name:
        worktree_name = wt_name
    elif git_worktree:
        worktree_name = git_worktree
    elif cwd:
        worktree_name = os.path.basename(cwd)
    else:
        worktree_name = "-"

    pr_field = lookup_pr(cwd)

    ctx_colored = color_pct_field(ctx_pct)
    five_colored = color_pct_field(five_pct)
    seven_colored = color_pct_field(seven_pct)

    sep = f"{DIM_GRAY} | {RESET}"
    parts = [
        f"{label_color}{label}{RESET}",
        sep,
        ctx_colored,
        tokens_display,
        sep,
        f"{CYAN}5h:{RESET}",
        five_colored,
        five_delta,
        five_reset,
        sep,
        f"{CYAN}7d:{RESET}",
        seven_colored,
        seven_delta,
        seven_reset,
        sep,
        f"{BRIGHT_BLUE}{worktree_name}{RESET}",
        sep,
    ]
    if pr_field:
        parts.extend([pr_field, sep])
    parts.append(f"{DIM_GRAY}{model_display}{RESET}")
    parts.append(RESET)

    sys.stdout.write("".join(parts))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        import traceback
        try:
            Path("/tmp/claude_statusline_err.log").write_text(traceback.format_exc())
        except OSError:
            pass
        # Print a marker so the bar is visibly broken rather than empty.
        sys.stdout.write(f"{RED}statusline error — see /tmp/claude_statusline_err.log{RESET}")
        sys.exit(1)
