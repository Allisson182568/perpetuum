import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 1. Configuração de CORS (Permite o Flutter chamar a função)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 2. Identificar quem é o usuário logado no App
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('No authorization header passed')
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Usuário não autenticado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 3. Autenticar o Servidor na Pluggy (Pegar API Key)
    const clientId = Deno.env.get('PLUGGY_CLIENT_ID')
    const clientSecret = Deno.env.get('PLUGGY_CLIENT_SECRET')

    const authRes = await fetch('https://api.pluggy.ai/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    })
    const authData = await authRes.json()
    const apiKey = authData.apiKey

    // 4. Gerar o Connect Token ESPECÍFICO para este usuário
    // AQUI ESTÁ A MÁGICA: clientUserId = user.id
    const tokenRes = await fetch('https://api.pluggy.ai/connect_tokens', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-KEY': apiKey
      },
      body: JSON.stringify({
        clientUserId: user.id, // VINCULA AO SEU ID DO SUPABASE
        options: {
          clientUserId: user.id // Reforço para garantir
        }
      }),
    })

    const tokenData = await tokenRes.json()

    // 5. Devolve o token para o Flutter abrir o widget
    return new Response(JSON.stringify(tokenData), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})