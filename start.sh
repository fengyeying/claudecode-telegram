#!/usr/bin/env bash
# start.sh — launch Claude Code + Telegram bridge in one command
#
# Usage:
#   export TELEGRAM_BOT_TOKEN="your_token"
#   ./start.sh
#
# Exit strategy:
#   - Both processes run as tmux windows (not background jobs), so they
#     die cleanly when the session ends — no orphan/zombie risk.
#   - When Claude exits (Ctrl-C, /exit, etc.), the session is destroyed,
#     which sends SIGHUP to bridge.py and stops it automatically.
#   - To stop everything manually: tmux kill-session -t $SESSION
#
# Window layout:
#   Window 0 "claude" — Claude Code (you land here on attach)
#   Window 1 "bridge" — bridge.py output (switch with Ctrl-B 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="${TMUX_SESSION:-claude}"

# ── Validate token ────────────────────────────────────────────────────────────
if [ -z "${CC_4080_TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "Error: TELEGRAM_BOT_TOKEN is not set"
    echo "  export TELEGRAM_BOT_TOKEN=your_token"
    exit 1
fi

# ── If session already exists, just attach ────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already running — attaching..."
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "$SESSION"
    else
        tmux attach-session -t "$SESSION"
    fi
    exit 0
fi

echo "Starting '$SESSION'..."

# ── Window 0: Claude Code ─────────────────────────────────────────────────────
# After Claude exits, kill the whole session — this takes bridge with it.
tmux new-session -d -s "$SESSION" -n "claude" \
    "claude --dangerously-skip-permissions; tmux kill-session -t '$SESSION' 2>/dev/null"

# ── Window 1: Bridge ──────────────────────────────────────────────────────────
# Runs alongside Claude. Stays alive while the session exists.
tmux new-window -t "$SESSION:1" -n "bridge" \
    "cd '$SCRIPT_DIR' && CC_4080_TELEGRAM_BOT_TOKEN='$CC_4080_TELEGRAM_BOT_TOKEN' python bridge.py"

# Focus Claude window
tmux select-window -t "$SESSION:0"

echo "  Claude → window 0 (current)"
echo "  Bridge → window 1 (Ctrl-B 1 to inspect)"
echo "  Stop all → tmux kill-session -t $SESSION"
echo ""

# ── Attach ────────────────────────────────────────────────────────────────────
if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$SESSION"
else
    tmux attach-session -t "$SESSION"
fi
