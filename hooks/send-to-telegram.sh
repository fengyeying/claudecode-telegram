#!/bin/bash
# Claude Code Stop hook - sends response back to Telegram
# Install: copy to ~/.claude/hooks/ and add to ~/.claude/settings.json

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN_HERE}"
LOG=/tmp/tg-hook-debug.log
INPUT=$(cat)
echo "--- $(date) ---" >> "$LOG"
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
echo "TRANSCRIPT_PATH: $TRANSCRIPT_PATH" >> "$LOG"
CHAT_ID_FILE=~/.claude/telegram_chat_id

# Forward all responses if we have a known chat_id
if [ ! -f "$CHAT_ID_FILE" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    echo "EXIT: no chat_id or transcript" >> "$LOG"
    exit 0
fi

CHAT_ID=$(cat "$CHAT_ID_FILE")
echo "CHAT_ID: $CHAT_ID" >> "$LOG"
LAST_USER_LINE=$(grep -n '"type":"user"' "$TRANSCRIPT_PATH" | tail -1 | cut -d: -f1)
echo "LAST_USER_LINE: $LAST_USER_LINE" >> "$LOG"
if [ -z "$LAST_USER_LINE" ]; then echo "EXIT: no user line in transcript" >> "$LOG"; exit 0; fi

TMPFILE=$(mktemp)
tail -n "+$LAST_USER_LINE" "$TRANSCRIPT_PATH" | \
  grep '"type":"assistant"' | \
  jq -rs '[.[].message.content[] | select(.type == "text") | .text] | join("\n\n")' > "$TMPFILE" 2>/dev/null
echo "TMPFILE size: $(wc -c < "$TMPFILE")" >> "$LOG"
if [ ! -s "$TMPFILE" ]; then echo "EXIT: empty tmpfile" >> "$LOG"; rm -f "$TMPFILE"; exit 0; fi
echo "SENDING to Telegram" >> "$LOG"

python3 - "$TMPFILE" "$CHAT_ID" "$TELEGRAM_BOT_TOKEN" << 'PYEOF'
import sys, re, json, urllib.request

tmpfile, chat_id, token = sys.argv[1], sys.argv[2], sys.argv[3]
with open(tmpfile) as f:
    text = f.read().strip()

if not text or text == "null":
    sys.exit(0)

if len(text) > 4000:
    text = text[:4000] + "\n..."

def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

blocks, inlines = [], []
text = re.sub(r'```(\w*)\n?(.*?)```', lambda m: (blocks.append((m.group(1) or '', m.group(2))), f"\x00B{len(blocks)-1}\x00")[1], text, flags=re.DOTALL)
text = re.sub(r'`([^`\n]+)`', lambda m: (inlines.append(m.group(1)), f"\x00I{len(inlines)-1}\x00")[1], text)
text = esc(text)
text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
text = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', r'<i>\1</i>', text)

for i, (lang, code) in enumerate(blocks):
    text = text.replace(f"\x00B{i}\x00", f'<pre><code class="language-{lang}">{esc(code.strip())}</code></pre>' if lang else f'<pre>{esc(code.strip())}</pre>')
for i, code in enumerate(inlines):
    text = text.replace(f"\x00I{i}\x00", f'<code>{esc(code)}</code>')

def send(txt, mode=None):
    data = {"chat_id": chat_id, "text": txt}
    if mode:
        data["parse_mode"] = mode
    try:
        req = urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", json.dumps(data).encode(), {"Content-Type": "application/json"})
        return json.loads(urllib.request.urlopen(req, timeout=10).read()).get("ok")
    except:
        return False

if not send(text, "HTML"):
    with open(tmpfile) as f:
        send(f.read()[:4096])
PYEOF

rm -f "$TMPFILE"
exit 0
