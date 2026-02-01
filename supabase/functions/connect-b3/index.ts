import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  // 1. Pega as chaves seguras do ambiente
  const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
  const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')

  if (!clientId || !clientSecret) {
    return new Response(JSON.stringify({ error: "Chaves não configuradas" }), { status: 500 })
  }

  try {
    // 🔴 NOVO: Ler o corpo da requisição para pegar o ID do usuário enviado pelo Flutter
    const { clientUserId } = await req.json().catch(() => ({ clientUserId: null }))

    if (!clientUserId) {
        throw new Error("clientUserId é obrigatório")
    }

    // 2. Primeiro: Autentica sua empresa na Pluggy (Pega a API Key)
    const authResponse = await fetch('https://api.pluggy.ai/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    })

    const authData = await authResponse.json()
    const apiKey = authData.apiKey

    // 3. Segundo: Gera o Connect Token específico para o usuário final
    const tokenResponse = await fetch('https://api.pluggy.ai/connect_token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-KEY': apiKey
      },
      body: JSON.stringify({
        options: {
            clientUserId: clientUserId // ✅ CORRIGIDO: Usa o ID dinâmico do usuário
        }
      }),
    })

    const tokenData = await tokenResponse.json()

    // 4. Devolve o token para o seu App Flutter
    return new Response(
      JSON.stringify({ accessToken: tokenData.accessToken }),
      { headers: { "Content-Type": "application/json" } },
    )

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})