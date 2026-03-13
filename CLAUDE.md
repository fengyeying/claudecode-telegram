# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests
python -m pytest tests/test_bridge.py -v

# Run a single test
python -m pytest tests/test_bridge.py::TestTelegramPoll::test_uses_35s_client_timeout -v

# Run bridge directly (requires token)
export CC_4080_TELEGRAM_BOT_TOKEN="your_token"
python bridge.py

# One-command start (tmux + bridge together)
./start.sh
```

No build step — zero external Python dependencies (stdlib only).

## Architecture

Two independent components communicate through the filesystem and the Telegram Bot API:

```
Telegram ──getUpdates──► bridge.py ──tmux send-keys──► Claude Code
                                                              │
Telegram ◄──sendMessage── send-to-telegram.sh ◄──Stop hook──┘
```

### `bridge.py` — inbound path

Long-polls `getUpdates` (30s server timeout, 35s client timeout — the client must exceed the server to avoid spurious socket.timeout). On each message it:

1. Writes the sender's chat ID to `~/.claude/telegram_chat_id`
2. Writes a timestamp to `~/.claude/telegram_pending` (used by the typing indicator loop)
3. Injects the text into the active tmux session via `send-keys -l` (literal, avoids shell interpretation)
4. Runs `send_typing_loop` in a daemon thread until `telegram_pending` is removed

`telegram_api()` is the general-purpose wrapper (10s timeout). `telegram_poll()` is a separate function with 35s timeout — do not merge them.

`main()` must call `deleteWebhook(drop_pending_updates=True)` first; otherwise stale webhook updates flood the first poll.

### `hooks/send-to-telegram.sh` — outbound path

Installed as a Claude Code **Stop hook** (`~/.claude/hooks/send-to-telegram.sh`), configured in `~/.claude/settings.json`. Fires after every Claude response. It:

1. Reads `~/.claude/telegram_chat_id` — exits if absent (no known recipient)
2. Finds the last user message line in the JSONL transcript
3. Extracts all assistant text blocks after that line
4. Formats markdown → Telegram HTML (bold, italic, inline code, code blocks)
5. Sends via `sendMessage` with `parse_mode=HTML`; falls back to plain text on failure

The hook intentionally forwards **all** Claude responses (local terminal or Telegram-initiated), not just responses to Telegram messages. This is by design.

Debug log: `/tmp/tg-hook-debug.log`

### `start.sh` — lifecycle management

Creates a tmux session with two windows:
- Window 0 `claude`: `claude --dangerously-skip-permissions`; on exit runs `tmux kill-session`
- Window 1 `bridge`: `python bridge.py`

The kill-session cascade is the exit strategy — bridge is never a background job outside tmux.

### Runtime files (not in repo)

| Path | Purpose |
|------|---------|
| `~/.claude/telegram_chat_id` | Last known Telegram chat ID; presence enables outbound forwarding |
| `~/.claude/telegram_pending` | Timestamp written on inbound message; deletion signals response complete |
| `/tmp/tg-hook-debug.log` | Hook debug log |

## Key constraints

- **Telegram `setMessageReaction` emoji**: only a fixed whitelist is accepted. `✅` (`\u2705`) causes a 400 error — use `👌` (`\U0001f44c`) or another whitelisted emoji.
- **`telegram_poll` timeout must be > 30**: the server holds the connection for up to 30s; client timeout of 35s prevents spurious exceptions.
- **Hook token**: `hooks/send-to-telegram.sh` in the repo uses `YOUR_BOT_TOKEN_HERE` as placeholder. The installed copy at `~/.claude/hooks/send-to-telegram.sh` has the real token and must never be committed.
- **Bot token env var**: `CC_4080_TELEGRAM_BOT_TOKEN` (not `TELEGRAM_BOT_TOKEN`).
