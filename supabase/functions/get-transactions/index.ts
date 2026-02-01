import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { itemId } = await req.json()
    const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
    const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')

    // 1. Auth na Pluggy
    const authRes = await fetch('https://api.pluggy.ai/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    })
    const { apiKey } = await authRes.json()

    // 2. Busca Transações (Extrato)
    const transRes = await fetch(`https://api.pluggy.ai/transactions?itemId=${itemId}`, {
      method: 'GET',
      headers: { 'X-API-KEY': apiKey }
    })

    const data = await transRes.json()

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400, headers: corsHeaders })
  }
})