import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

// 🛡️ CONFIGURAÇÃO DE CORS (PERMISSÃO TOTAL)
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 1. O NAVEGADOR PERGUNTA: "POSSO CONECTAR?" (OPTIONS)
  // Respondemos SIM imediatamente, antes de qualquer lógica.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 2. Tenta pegar o corpo da requisição
    // Se der erro aqui, assumimos que veio vazio (fallback)
    let body = {}
    try {
        body = await req.json()
    } catch {
        // Ignora erro de JSON vazio
    }

    const { clientUserId } = body

    // 3. Verifica as Chaves (Secrets)
    const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
    const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')

    if (!clientId || !clientSecret) {
      throw new Error("ERRO: Secrets PLUGGY_CLIENT_ID ou PLUGGY_CLIENT_SECRET não configuradas no Supabase.")
    }

    // 4. Autenticação na Pluggy (Pega a API Key)
    const authRes = await fetch('https://api.pluggy.ai/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    })

    if (!authRes.ok) {
        const errText = await authRes.text()
        throw new Error(`Erro Auth Pluggy (${authRes.status}): ${errText}`)
    }

    const authData = await authRes.json()
    const apiKey = authData.apiKey

    // 5. Gera o Connect Token
    // Se não veio clientUserId do Flutter, usa um genérico para não travar o teste
    const finalUserId = clientUserId || "usuario_debug_123"

    const tokenRes = await fetch('https://api.pluggy.ai/connect_token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-KEY': apiKey
      },
      body: JSON.stringify({
        options: { clientUserId: finalUserId }
      }),
    })

    if (!tokenRes.ok) {
        const errText = await tokenRes.text()
        throw new Error(`Erro Token Pluggy (${tokenRes.status}): ${errText}`)
    }

    const tokenData = await tokenRes.json()

    // 6. SUCESSO!
    return new Response(
      JSON.stringify({ accessToken: tokenData.accessToken }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200
      },
    )

  } catch (error) {
    // 7. EM CASO DE ERRO, RETORNA O MOTIVO + CORS HEADERS
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400
      }
    )
  }
})