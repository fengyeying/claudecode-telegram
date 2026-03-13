"""Tests for bridge.py polling refactor."""
import json
import os
import sys
import time
import unittest
from io import BytesIO
from unittest.mock import MagicMock, patch, call

# bridge.py is at repo root; run pytest from repo root
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bridge


class TestTelegramPoll(unittest.TestCase):
    def setUp(self):
        # Ensure BOT_TOKEN is set for tests that need it
        self._orig_token = bridge.BOT_TOKEN
        bridge.BOT_TOKEN = "test-token"

    def tearDown(self):
        bridge.BOT_TOKEN = self._orig_token

    def test_returns_none_when_no_token(self):
        bridge.BOT_TOKEN = ""
        result = bridge.telegram_poll({"timeout": 30})
        self.assertIsNone(result)

    def test_returns_none_on_exception(self):
        with patch("urllib.request.urlopen", side_effect=OSError("network error")):
            result = bridge.telegram_poll({"timeout": 30})
        self.assertIsNone(result)

    def test_returns_parsed_response_on_success(self):
        payload = {"ok": True, "result": []}
        mock_resp = MagicMock()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_resp.read.return_value = json.dumps(payload).encode()
        with patch("urllib.request.urlopen", return_value=mock_resp):
            result = bridge.telegram_poll({"timeout": 30})
        self.assertEqual(result, payload)

    def test_uses_35s_client_timeout(self):
        """Client timeout must exceed the 30s server-side poll timeout."""
        payload = {"ok": True, "result": []}
        mock_resp = MagicMock()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_resp.read.return_value = json.dumps(payload).encode()
        captured = {}
        def fake_urlopen(req, timeout):
            captured["timeout"] = timeout
            return mock_resp
        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            bridge.telegram_poll({"timeout": 30})
        self.assertEqual(captured["timeout"], 35)


class TestPollUpdates(unittest.TestCase):
    def test_advances_offset_after_update(self):
        """offset must equal update_id + 1 after processing."""
        updates = [
            {"ok": True, "result": [{"update_id": 100, "message": {"text": "hi", "chat": {"id": 1}}}]},
            StopIteration,
        ]
        call_count = [0]

        def fake_poll(params):
            idx = call_count[0]
            call_count[0] += 1
            if idx == 0:
                assert params.get("offset") is None
                return updates[0]
            assert params.get("offset") == 101, f"expected 101, got {params.get('offset')}"
            raise StopIteration

        with patch.object(bridge, "telegram_poll", side_effect=fake_poll), \
             patch.object(bridge, "handle_message"), \
             patch("time.sleep"):
            try:
                bridge.poll_updates()
            except StopIteration:
                pass

        self.assertEqual(call_count[0], 2)

    def test_sleeps_on_none_result(self):
        """Sleeps 5s and continues when poll returns None."""
        call_count = [0]

        def fake_poll(params):
            call_count[0] += 1
            if call_count[0] == 1:
                return None
            raise StopIteration

        with patch.object(bridge, "telegram_poll", side_effect=fake_poll), \
             patch("time.sleep") as mock_sleep:
            try:
                bridge.poll_updates()
            except StopIteration:
                pass

        mock_sleep.assert_called_with(5)

    def test_routes_callback_query(self):
        """callback_query updates go to handle_callback."""
        cb = {"id": "1", "message": {"chat": {"id": 1}}, "data": "test"}
        updates = [{"ok": True, "result": [{"update_id": 50, "callback_query": cb}]}]
        call_count = [0]

        def fake_poll(params):
            call_count[0] += 1
            if call_count[0] == 1:
                return updates[0]
            raise StopIteration

        with patch.object(bridge, "telegram_poll", side_effect=fake_poll), \
             patch.object(bridge, "handle_callback") as mock_cb, \
             patch.object(bridge, "handle_message") as mock_msg, \
             patch("time.sleep"):
            try:
                bridge.poll_updates()
            except StopIteration:
                pass

        mock_cb.assert_called_once_with(cb)
        mock_msg.assert_not_called()

    def test_routes_message(self):
        """message updates go to handle_message."""
        msg_update = {"update_id": 60, "message": {"text": "hello", "chat": {"id": 1}}}
        call_count = [0]

        def fake_poll(params):
            call_count[0] += 1
            if call_count[0] == 1:
                return {"ok": True, "result": [msg_update]}
            raise StopIteration

        with patch.object(bridge, "telegram_poll", side_effect=fake_poll), \
             patch.object(bridge, "handle_message") as mock_msg, \
             patch("time.sleep"):
            try:
                bridge.poll_updates()
            except StopIteration:
                pass

        mock_msg.assert_called_once_with(msg_update)


class TestTelegramSend(unittest.TestCase):
    def test_calls_telegram_api_with_correct_args(self):
        with patch.object(bridge, "telegram_api") as mock_api:
            bridge.telegram_send(12345, "hello world")
        mock_api.assert_called_once_with(
            "sendMessage", {"chat_id": 12345, "text": "hello world"}
        )


class TestMain(unittest.TestCase):
    def test_calls_deleteWebhook_with_drop_pending_before_polling(self):
        """main() must call deleteWebhook(drop_pending_updates=True) before poll loop."""
        with patch.object(bridge, "BOT_TOKEN", "test-token"), \
             patch.object(bridge, "telegram_api") as mock_api, \
             patch.object(bridge, "setup_bot_commands"), \
             patch.object(bridge, "poll_updates", side_effect=KeyboardInterrupt):
            try:
                bridge.main()
            except (KeyboardInterrupt, SystemExit):
                pass
        self.assertTrue(mock_api.call_count >= 1)
        first_call = mock_api.call_args_list[0]
        self.assertEqual(first_call[0][0], "deleteWebhook")
        self.assertEqual(first_call[0][1].get("drop_pending_updates"), True)


if __name__ == "__main__":
    unittest.main()
