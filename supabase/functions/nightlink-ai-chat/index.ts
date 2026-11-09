import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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

const systemInstruction = `You are NightLink AI, the friendly, capable assistant built into the NightLink social app.
Help with NightLink accounts, profiles, connections, private text chat, voice/video calls, PK battles, gifts, coins, VIP, short videos, and troubleshooting. Also answer general knowledge, learning, writing, creativity, and everyday questions.
Speak naturally in the language the user uses, including English, Urdu, and Pashto when possible. Be clear, warm, concise, and practical. Use readable formatting. Never claim you can see private account data, send messages, make calls, issue coins, or change settings unless a connected tool explicitly confirms it. Do not invent app features or promise that a feature is working. For account-specific problems, give safe troubleshooting steps and direct users to Contact Us when needed. Never request passwords, one-time codes, or secret API keys.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Please sign in to use NightLink AI." }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publishableKeysRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
    const publishableKey =
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ||
      Deno.env.get("SUPABASE_ANON_KEY") ||
      (() => {
        if (!publishableKeysRaw) return null;
        try { return JSON.parse(publishableKeysRaw).default ?? null; } catch { return null; }
      })();

    if (!supabaseUrl || !publishableKey) {
      console.error("NightLink AI missing Supabase environment configuration");
      return json({ error: "NightLink AI is not configured yet. Please contact support." }, 503);
    }

    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return json({ error: "Your session has expired. Please sign in again." }, 401);

    const apiKey = Deno.env.get("GROQ_API_KEY");
    if (!apiKey) {
      return json({ error: "NightLink AI needs its free Groq API key. The app owner must add GROQ_API_KEY in Supabase Edge Function secrets." }, 503);
    }

    let body: { messages?: unknown };
    try { body = await req.json(); } catch { return json({ error: "Invalid request body." }, 400); }
    if (!Array.isArray(body.messages) || body.messages.length === 0 || body.messages.length > 12) {
      return json({ error: "Send between 1 and 12 recent chat messages." }, 400);
    }

    const messages = body.messages.map((item: unknown) => {
      if (!item || typeof item !== "object") throw new Error("Invalid message.");
      const message = item as { role?: unknown; content?: unknown };
      const role = message.role === "assistant" ? "assistant" : message.role === "user" ? "user" : null;
      if (!role || typeof message.content !== "string") throw new Error("Invalid message format.");
      const content = message.content.trim();
      if (!content || content.length > 4000) throw new Error("Each message must contain 1 to 4000 characters.");
      return { role, content };
    });

    if (messages[messages.length - 1].role !== "user") {
      return json({ error: "The latest message must be from you." }, 400);
    }

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "openai/gpt-oss-20b",
        messages: [
          { role: "system", content: systemInstruction },
          ...messages,
        ],
        max_completion_tokens: 1200,
      }),
    });

    const result = await response.json();
    if (!response.ok) {
      console.error("Groq request failed", response.status, JSON.stringify(result).slice(0, 1200));
      if (response.status === 429) return json({ error: "NightLink AI has reached Groq's free usage limit. Please wait and try again later." }, 429);
      if (response.status === 401 || response.status === 403) return json({ error: "The Groq API key was rejected. Please check the GROQ_API_KEY secret in Supabase." }, 502);
      if (response.status === 400) return json({ error: "Groq could not process this request. Please try a shorter message." }, 502);
      return json({ error: "The AI service is temporarily unavailable. Please try again shortly." }, 502);
    }

    const reply = result?.choices?.[0]?.message?.content?.trim();
    if (!reply) return json({ error: "The AI did not return a response. Please try again." }, 502);
    return json({ reply });
  } catch (error) {
    console.error("NightLink AI request failed", error);
    return json({ error: "NightLink AI could not process that message. Please try again." }, 500);
  }
});
