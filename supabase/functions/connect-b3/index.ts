import { serve } from "https://deno.land/std/http/server.ts";

serve(async (req) => {
  try {
    const { clientUserId } = await req.json();

    const res = await fetch("https://api.pluggy.ai/connect-token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-API-KEY": Deno.env.get("PLUGGY_CLIENT_ID")!,
        "X-API-SECRET": Deno.env.get("PLUGGY_CLIENT_SECRET")!,
      },
      body: JSON.stringify({
        clientUserId,
      }),
    });

    const data = await res.json();

    return new Response(JSON.stringify(data), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e.toString() }),
      { status: 500 }
    );
  }
});