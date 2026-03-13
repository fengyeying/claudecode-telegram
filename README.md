# claudecode-telegram

![demo](demo.gif)

Telegram bot bridge for Claude Code. Send messages from Telegram, get responses back.

> **Based on** [hanxiao/claudecode-telegram](https://github.com/hanxiao/claudecode-telegram) — thanks to [@hanxiao](https://github.com/hanxiao) for the original project.

## How it works

```mermaid
flowchart LR
    A[Telegram] -->|getUpdates| B[Bridge]
    B -->|tmux send-keys| C[Claude Code]
    C -->|Stop Hook| D[Read Transcript]
    D -->|sendMessage| A
```

1. Bridge receives Telegram webhooks, injects messages into Claude Code via tmux
2. Claude Code's Stop hook reads the transcript and sends response back to Telegram
3. Forwards **all** Claude responses (not just Telegram-initiated ones)

## Install

```bash
# Prerequisites
brew install tmux

# Clone
git clone https://github.com/fengyeying/claudecode-telegram
cd claudecode-telegram

# Setup Python env
uv venv && source .venv/bin/activate
uv pip install -e .
```

## Setup

### 1. Create Telegram bot

Bot receives your messages and sends Claude's responses back.

```bash
# Message @BotFather on Telegram, create bot, get token
```

### 2. Configure Stop hook

Hook triggers when Claude finishes responding, reads transcript, sends to Telegram.

```bash
cp hooks/send-to-telegram.sh ~/.claude/hooks/
nano ~/.claude/hooks/send-to-telegram.sh  # set your bot token
chmod +x ~/.claude/hooks/send-to-telegram.sh
```

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/send-to-telegram.sh"}]}]
  }
}
```

### 3. Start tmux + Claude

tmux keeps Claude Code running persistently; bridge injects messages via `send-keys`.

```bash
tmux new -s claude
claude --dangerously-skip-permissions
```

### 4. Run bridge

Bridge polls Telegram for new messages and injects them into Claude Code.

```bash
export CC_4080_TELEGRAM_BOT_TOKEN="your_token"
python bridge.py
# No cloudflared or webhook setup needed — bridge polls Telegram directly
```

## Bot Commands

| Command | Description |
|---------|-------------|
| `/status` | Check tmux session |
| `/clear` | Clear conversation |
| `/resume` | Pick session to resume (inline keyboard) |
| `/continue_` | Auto-continue most recent |
| `/loop <prompt>` | Start Ralph Loop (5 iterations) |
| `/stop` | Interrupt Claude |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CC_4080_TELEGRAM_BOT_TOKEN` | required | Bot token from BotFather |
| `TMUX_SESSION` | `claude` | tmux session name |

## Changes from Original

This fork makes the following changes on top of [hanxiao/claudecode-telegram](https://github.com/hanxiao/claudecode-telegram):

### Long polling (no cloudflared)

Replaced the HTTP webhook server with Telegram long polling (`getUpdates`). The bridge now polls Telegram directly — no need to run `cloudflared` or register a webhook URL. Setup drops from 6 steps to 4.

### Forward all Claude responses

The original hook only forwarded responses to Telegram-initiated messages (via a pending-file gate). This fork forwards **all** Claude responses — whether the prompt came from Telegram or the local terminal. As long as a chat ID is known, every Claude reply goes to Telegram.

### Reaction emoji fix

Fixed a `400 Bad Request` error from `setMessageReaction`: replaced `✅` (not in Telegram's allowed reaction set) with `👌`.

### Unit tests

Added `tests/test_bridge.py` with 10 unit tests covering `telegram_poll`, `poll_updates`, `telegram_send`, and `main`.

## Credits

Original project: [hanxiao/claudecode-telegram](https://github.com/hanxiao/claudecode-telegram) by [@hanxiao](https://github.com/hanxiao).
