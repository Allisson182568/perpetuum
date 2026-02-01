import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 1. CORS: Permite o Flutter conectar
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 2. Recebe o ID da conexão (itemId) vindo do Flutter
    const { itemId } = await req.json().catch(() => ({}))

    if (!itemId) {
      throw new Error("itemId é obrigatório para buscar investimentos")
    }

    const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
    const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')

    // 3. Autentica na Pluggy (Pega a API Key)
    const authRes = await fetch('https://api.pluggy.ai/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    })

    const authData = await authRes.json()
    const apiKey = authData.apiKey

    // 4. BUSCA OS INVESTIMENTOS (O Grande Momento)
    // Buscamos apenas dessa conexão específica (itemId)
    const investRes = await fetch(`https://api.pluggy.ai/investments?itemId=${itemId}`, {
      method: 'GET',
      headers: {
        'X-API-KEY': apiKey,
        'Accept': 'application/json'
      }
    })

    const investData = await investRes.json()

    // 5. Retorna a lista de ativos para o Flutter
    return new Response(
      JSON.stringify(investData),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200
      },
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400
      }
    )
  }
})