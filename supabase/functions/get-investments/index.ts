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
    const authData = await authRes.json()
    const apiKey = authData.apiKey

    // 2. Busca Investimentos
    const invRes = await fetch(`https://api.pluggy.ai/investments?itemId=${itemId}`, {
      headers: { 'X-API-KEY': apiKey }
    })
    const invData = await invRes.json()

    // 3. Busca Saldo de Conta (Para pegar o Caixa/Saldo disponível)
    const accRes = await fetch(`https://api.pluggy.ai/accounts?itemId=${itemId}`, {
      headers: { 'X-API-KEY': apiKey }
    })
    const accData = await accRes.json()

    return new Response(JSON.stringify({
      investments: invData.results || [],
      accounts: accData.results || []
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400, headers: corsHeaders
    })
  }
})