import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ error: "Authentication required" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publishableKeysRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
    const legacyAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    let publishableKey = legacyAnonKey;

    if (publishableKeysRaw) {
      try {
        const keys = JSON.parse(publishableKeysRaw);
        publishableKey = keys.default ?? legacyAnonKey;
      } catch {
        console.error("SUPABASE_PUBLISHABLE_KEYS is not valid JSON");
      }
    }

    if (!supabaseUrl || !publishableKey) {
      console.error("Supabase URL or publishable key environment variable is missing");
      return json({ error: "Supabase function configuration missing" }, 500);
    }

    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: "Invalid or expired session" }, 401);
    }

    let body: { roomName?: unknown; matchId?: unknown };
    try {
      body = await req.json();
    } catch {
      return json({ error: "Request body must be valid JSON" }, 400);
    }

    let roomName: string;
    let canPublish = true;
    const matchId = body.matchId;

    if (matchId !== undefined && matchId !== null) {
      if (typeof matchId !== "string" ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(matchId)) {
        return json({ error: "Invalid battle ID" }, 400);
      }

      const { data: accessRows, error: accessError } = await supabase.rpc(
        "get_battle_access",
        { p_match_id: matchId },
      );

      if (accessError || !Array.isArray(accessRows) || accessRows.length === 0) {
        return json({ error: "This battle is unavailable or has ended" }, 403);
      }

      const access = accessRows[0];
      if (typeof access.room_name !== "string") {
        return json({ error: "Battle room details are unavailable" }, 403);
      }

      roomName = access.room_name;
      const endsAt = access.battle_ends_at ? Date.parse(String(access.battle_ends_at)) : 0;
      canPublish = access.is_player === true && (endsAt === 0 || endsAt > Date.now());
    } else {
      if (typeof body.roomName !== "string" ||
          !/^[a-zA-Z0-9_-]{1,64}$/.test(body.roomName)) {
        return json({ error: "Invalid room name" }, 400);
      }
      roomName = body.roomName;
    }

    const livekitUrl = Deno.env.get("LIVEKIT_URL");
    const apiKey = Deno.env.get("LIVEKIT_API_KEY");
    const apiSecret = Deno.env.get("LIVEKIT_API_SECRET");

    if (!livekitUrl || !apiKey || !apiSecret) {
      console.error("Missing LIVEKIT_URL, LIVEKIT_API_KEY, or LIVEKIT_API_SECRET Edge Function secret");
      return json({ error: "LiveKit configuration missing" }, 500);
    }

    const token = new AccessToken(apiKey, apiSecret, {
      identity: userData.user.id,
      ttl: "1h",
    });

    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish,
      canSubscribe: true,
      canPublishData: canPublish,
    });

    return json({
      token: await token.toJwt(),
      serverUrl: livekitUrl,
      roomName,
      identity: userData.user.id,
      role: canPublish ? "host" : "viewer",
    });
  } catch (error) {
    console.error("LiveKit token generation failed:", error);
    return json({ error: "Unable to generate call token" }, 500);
  }
});