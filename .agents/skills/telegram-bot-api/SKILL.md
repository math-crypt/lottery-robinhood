---
name: telegram-bot-api
description: Official Telegram Bot API documentation reference (core.telegram.org)
---

# Telegram Bot API Reference
This skill refers to the official Telegram Bot API: https://core.telegram.org/bots/api
Key features to consider for bot development:
- `sendMessage`: Sending text with `parse_mode` (MarkdownV2 or HTML).
- `InlineKeyboardMarkup`: Adding interactive buttons under messages.
- `setMyCommands`: Configuring the autocomplete menu for slash commands.
- `pinChatMessage`: Pinning important messages (like lottery winners) in groups/channels.
- `sendAnimation` / `sendSticker`: Sending rich media for celebrations.
