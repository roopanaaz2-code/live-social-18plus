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

## Social connections, privacy and VIP

- New accounts receive a unique editable username. Members can search by username and send connection requests.
- Private text, voice and video calls require an accepted connection.
- Email addresses are not part of public profile data and are not shown on the home screen.
- The developer account receives lifetime VIP, no banner ads, and free gifts in battles.
- Voice calls use echo cancellation, noise suppression and earpiece routing by default; video calls prefer speaker output.

## AdMob setup

The release workflow supports two GitHub Actions repository secrets:

- `ADMOB_ANDROID_APP_ID`: the Android app ID from your own AdMob account.
- `ADMOB_BANNER_AD_UNIT_ID`: the banner ad unit ID from your own AdMob account.

Add the real IDs under **GitHub → Settings → Secrets and variables → Actions**. Without both values, the AdMob SDK is not initialized and no ads are requested. Do not use Google's sample/test IDs for earning revenue. Use test IDs or test devices while developing; Google requires test ads during testing to avoid invalid traffic.

## VIP payments

The developer account has lifetime VIP access. Paid VIP checkout for other members is intentionally not enabled until a real payment provider, merchant credentials and server-side payment verification are configured. No fake purchase buttons or unverified coin credits are used.

## Private Contact Us recipient

Set the GitHub Actions secret `NIGHTLINK_SUPPORT_EMAIL` to the support inbox address. The Contact Us button opens a pre-addressed email without displaying the recipient in the app UI. The compiled APK still contains the recipient needed by the mail app; a truly hidden recipient requires a server-side support form and email provider.


## NightLink AI setup (free-tier option)

The Android client calls the authenticated Supabase Edge Function `nightlink-ai-chat`; it does not contain a provider API key.

1. Create a Gemini API key in Google AI Studio: https://aistudio.google.com/apikey
2. In the Supabase project, add the Edge Function secret `GEMINI_API_KEY` with that key. Never add it to Flutter source, GitHub commits, or a public build variable.
3. Deploy `supabase/functions/nightlink-ai-chat/index.ts` as the `nightlink-ai-chat` Edge Function with JWT verification enabled.
4. The app uses the device speech-recognition service for microphone input and Android system text-to-speech for spoken replies. Availability and supported languages depend on the device's installed speech services.

Gemini's free tier has changing rate limits and availability. It is not unlimited or guaranteed to remain free. Google currently states that content on the free tier may be used to improve its products; do not send passwords, private messages, or sensitive personal information to the AI.

The Contact Us action first tries to open the Gmail app addressed to `roopanaaz2@gmail.com`; if Gmail is unavailable, it falls back to Android's registered `mailto:` handler.
