# NightLink

18+ live social Android app with Supabase authentication and matchmaking for text, voice, and video room experiences.

## Matchmaking update

The first multiplayer foundation supports:

- **1v1**: two individual players
- **2v2**: two teams of two
- **1v1v1v1**: four individual players

The migration creates profiles, a transactional matchmaking queue, matches, participants, RLS policies, and RPCs for joining/leaving queues and matches.

### Apply the Supabase schema

Run [`supabase/migrations/001_matchmaking.sql`](supabase/migrations/001_matchmaking.sql) in the Supabase SQL Editor, or apply it with the Supabase CLI. The migration must be applied before opening the Match Lobby in the APK.

The Flutter lobby is in [`lib/matchmaking.dart`](lib/matchmaking.dart) and is opened from the **FIND A MATCH** button on the home screen.

### RPCs used by the app

- `join_matchmaking(p_mode)`
- `leave_matchmaking()`
- `get_my_active_match()`
- `set_match_ready(p_match_id)`
- `leave_match(p_match_id)`

Voice/video media rooms are intentionally not included in this migration. They require a media provider such as LiveKit or an SFU/TURN deployment; the match ID is ready to be used as the room identifier in the next update.
