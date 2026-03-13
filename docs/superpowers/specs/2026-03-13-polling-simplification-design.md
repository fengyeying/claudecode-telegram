# Design: Replace Webhook with Long Polling

**Date:** 2026-03-13
**Status:** Approved

## Goal

Simplify the setup process by eliminating the cloudflared tunnel and manual webhook registration steps. Replace the HTTP server (webhook receiver) with Telegram long polling.

## Problem

Current setup requires 6 steps, 3 of which involve running separate processes and registering a public URL:

1. Create Telegram bot
2. Configure Stop hook
3. Start tmux + Claude
4. Run `python bridge.py` (HTTP server on :8080)
5. Run `cloudflared tunnel --url http://localhost:8080`
6. Run `curl .../setWebhook?url=...`

Steps 5 and 6 are pure infrastructure overhead with no functional value to the user.

## Solution

Replace the `HTTPServer` webhook receiver with a `getUpdates` long-polling loop. `bridge.py` actively polls Telegram instead of waiting for inbound HTTP requests.

**New setup (4 steps):**

1. Create Telegram bot
2. Configure Stop hook
3. Start tmux + Claude
4. `TELEGRAM_BOT_TOKEN=xxx python bridge.py`

## Architecture

```
Before: Telegram → cloudflared → HTTPServer(:8080) → handle_message()
After:  bridge.py → getUpdates(timeout=30) → handle_message()
```

## Code Changes

### Remove

- `Handler` class (`do_POST`, `do_GET`, `handle_callback`, `handle_message`, `reply`) — ~60 lines
- `PORT` environment variable and `HTTPServer` instantiation
- `do_GET` liveness endpoint (`GET /` → `"Claude-Telegram Bridge"`) is removed as a side effect; no external tooling relies on it in this project
- `log_message` suppression no longer needed; `print()` output will be visible in stdout (desired)

### Add

**`telegram_poll(params)`** — dedicated polling function with its own `urlopen` timeout of 35 seconds (must exceed the 30s server-side poll timeout to avoid spurious `socket.timeout` exceptions):

```python
def telegram_poll(params):
    if not BOT_TOKEN:
        return None
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{BOT_TOKEN}/getUpdates",
        data=json.dumps(params).encode(),
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=35) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"Poll error: {e}")
        return None
```

**`poll_updates()`** — main polling loop with error backoff. `telegram_poll` already swallows all exceptions and returns `None`, so no outer try/except is needed; the `if not result` branch handles errors:

```python
def poll_updates():
    offset = None
    while True:
        params = {"timeout": 30, "allowed_updates": ["message", "callback_query"]}
        if offset is not None:
            params["offset"] = offset
        result = telegram_poll(params)
        if not result or not result.get("ok"):
            time.sleep(5)
            continue
        for update in result.get("result", []):
            offset = update["update_id"] + 1
            if "callback_query" in update:
                handle_callback(update["callback_query"])
            elif "message" in update:
                handle_message(update)
```

**`telegram_send(chat_id, text)`** — thin wrapper replacing `self.reply()`:

```python
def telegram_send(chat_id, text):
    telegram_api("sendMessage", {"chat_id": chat_id, "text": text})
```

### Refactor

- `handle_callback` and `handle_message` extracted from `Handler` class into module-level functions
- `self.reply(chat_id, text)` → `telegram_send(chat_id, text)` (defined above)
- `main()`: call `deleteWebhook` first, then `setup_bot_commands()`, then `poll_updates()`

## Startup Sequence in `main()`

1. Validate `BOT_TOKEN`
2. Call `deleteWebhook` with `drop_pending_updates=True` — clears any updates queued while a webhook was active; prevents a burst of old messages on first poll
3. Call `setup_bot_commands()`
4. Print startup message
5. Enter `poll_updates()` loop

## Offset Mechanism

`offset = update_id + 1` tells Telegram not to re-send already-processed updates. On restart, `offset=None` causes Telegram to deliver any unacknowledged messages (those that arrived while the bridge was down). This is an **accepted risk**: if many messages accumulate during downtime, they will all be injected into tmux sequentially. This is acceptable for a single-user personal tool; no mitigation is added.

## Trade-offs

| | Webhook | Long Polling |
|---|---|---|
| Latency | ~instant | ~0–2s |
| Public URL required | Yes | No |
| Extra processes | cloudflared | None |
| Complexity | Higher | Lower |

Latency difference is imperceptible for this use case (Claude takes seconds to respond anyway).

## Out of Scope

- Hook script installation (remains manual)
- `~/.claude/settings.json` configuration (remains manual)
- tmux + Claude startup (remains manual)
