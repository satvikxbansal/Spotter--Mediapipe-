# Export chat history archive

- Thread ID: 019e5e09-a38f-7810-8727-c60dbda471fc
- Created: 2026-05-25 12:59:10 (Asia/Kolkata)
- Updated: 2026-05-25 13:07:58 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/25/rollout-2026-05-25T12-59-10-019e5e09-a38f-7810-8727-c60dbda471fc.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 4a0bd6f816723a8fef53a5f71628dcd160410915
- Exported visible messages: 5
- Extracted input images: 0

## Conversation

### User - 2026-05-25 12:59:12

hey i want to see all the chat conversations i have had abut the curent project with codex. currently i think only a fixed number of historical conversatins show in the chat panel on the left. is there a way i can view all of my past chats ? does codex store them somewhere? can you deeply research understand and help me with this please? there is a critical requriement to find an older chat 

can you create a folder in the current repo with md or pdf or json files each of the historical threads' conversations? one master folder that contains all of our conversation history - dated and with the chat title with contents containing our history. dont make this a hidden folder. i want it visible.

### Assistant - 2026-05-25 12:59:32

I’ll look for Codex’s local session storage first, then filter for threads tied to this repo path and export them into a visible folder here. I’ll keep the extraction read-only until I’ve mapped the format, then write the archive files into the repo.

### Assistant - 2026-05-25 13:03:01

I found the important pieces: Codex has local JSONL rollouts under `~/.codex/sessions/YYYY/MM/DD/` plus a `~/.codex/session_index.jsonl`, and there are also two files in `~/.codex/archived_sessions/`. Next I’m going to inspect the metadata and message shape so the export preserves useful roles, dates, titles, and source paths.

### Assistant - 2026-05-25 13:04:34

There is a proper local thread table too: `~/.codex/state_5.sqlite` has `threads` with `title`, `cwd`, archive flags, git info, and the rollout JSONL path. That’s better than guessing from filename alone, so I’m using the database as the source of truth and the JSONL files as the message bodies.

### Assistant - 2026-05-25 13:07:58

I’ve got enough confidence to export now. I’m going to create a visible `Codex_Conversation_History` folder in this repo with one Markdown transcript and one normalized JSON file per Codex thread, plus an index and README; screenshots embedded in prompts will be extracted into an `attachments` folder instead of leaving giant base64 blobs in the JSON.
