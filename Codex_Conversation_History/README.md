# Codex Conversation History

Generated: 2026-05-25 13:08:00 (Asia/Kolkata)

This folder is an export of Codex Desktop conversations for this workspace. It was generated from local Codex storage, not from the left chat panel UI.

## What Was Exported

- Workspace filter: `/Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe`
- Source database: `/Users/satvik.bansal/.codex/state_5.sqlite`
- Source transcript files: `~/.codex/sessions/YYYY/MM/DD/*.jsonl` and `~/.codex/archived_sessions/*.jsonl`
- Included threads: 89
- Visible user/assistant messages: 2308
- Extracted prompt images/screenshots: 25
- Archived threads included: 1

## How To Use

- Start with `index.md` for a dated table of every exported thread.
- Readable transcripts live in `threads/`.
- Structured transcripts live in `json/`.
- Extracted images referenced by transcripts live in `attachments/`.

## Find An Older Chat Quickly

Search readable transcripts:

```sh
rg -n "keyword or phrase" Codex_Conversation_History/threads
```

Search structured JSON:

```sh
rg -n "keyword or phrase" Codex_Conversation_History/json
```

Codex stores the local thread list in `~/.codex/state_5.sqlite` and the underlying transcript rollouts in `~/.codex/sessions/YYYY/MM/DD/*.jsonl` plus `~/.codex/archived_sessions/*.jsonl`. This export used the SQLite `threads` table for titles/dates/workspace filtering, then read each rollout file for the visible conversation messages.

The Markdown and JSON exports intentionally keep only visible user/assistant conversation messages. Tool calls, hidden system/developer instructions, and raw tool output are not included in the readable transcript files. The source rollout path is listed in every transcript if a deeper forensic lookup is ever needed.
