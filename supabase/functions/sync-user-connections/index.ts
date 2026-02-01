import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Configuração de CORS para o Flutter não reclamar
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // Tentamos ler o corpo, mas vamos ignorar o clientUserId por enquanto
    // O catch é para garantir que não quebre se o corpo vier vazio
    await req.json().catch(() => ({}))

    const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
    const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')

    // 1. Autentica na Pluggy (Pega a API Key)
    const authRes = await fetch('https://api.pluggy.ai/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    })
    const authData = await authRes.json()

    if (!authData.apiKey) {
      throw new Error("Falha ao autenticar na Pluggy. Verifique suas chaves.")
    }

    // ---------------------------------------------------------
    // 🚨 MODO DEBUG ATIVADO 🚨
    // Estamos removendo o filtro "clientUserId" propositalmente.
    // Vamos buscar os últimos 5 itens (conexões) criados na sua conta Pluggy geral.
    // ---------------------------------------------------------
    const url = `https://api.pluggy.ai/items?size=5`

    console.log(`🔍 DEBUG RADICAL: Buscando em ${url}`)

    // 2. Busca os itens (conexões) SEM FILTRO
    const res = await fetch(url, {
      method: 'GET',
      headers: { 'X-API-KEY': authData.apiKey }
    })

    const data = await res.json()

    // Log para você ver no painel do Supabase o que está voltando
    console.log("📦 RETORNO DA PLUGGY (RAW):", JSON.stringify(data))

    // 🛡️ GARANTIA: Se não houver resultados, retorna array vazio
    const results = data.results || []

    return new Response(JSON.stringify(results), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })

  } catch (error) {
    console.error("❌ ERRO NA FUNCTION:", error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: corsHeaders
    })
  }
})