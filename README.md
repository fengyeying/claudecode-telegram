# claudecode-telegram

![demo](demo.gif)

Telegram bot bridge for Claude Code. Send messages from Telegram, get responses back.

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
3. Only responds to Telegram-initiated messages (uses pending file as flag)

## Install

```bash
# Prerequisites
brew install tmux

# Clone
git clone https://github.com/hanxiao/claudecode-telegram
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
