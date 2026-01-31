// supabase/functions/update-dividends-yahoo/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const logs: string[] = [];

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    logs.push("Iniciando varredura inteligente...");

    // 1. Busca ativos da carteira
    const { data: assets, error } = await supabase
      .from('assets')
      .select('ticker')
      .not('ticker', 'is', null);

    if (error) throw error;
    if (!assets || assets.length === 0) {
      return new Response(JSON.stringify({ message: "Sem ativos." }), { headers: { "Content-Type": "application/json" } });
    }

    const distinctTickers = [...new Set(assets.map(a => a.ticker))];

    // Datas: 5 anos atrás até 1 ano no futuro
    const now = Math.floor(Date.now() / 1000);
    const startDate = now - (5 * 365 * 24 * 60 * 60);
    const endDate = now + (365 * 24 * 60 * 60);

    let processedCount = 0;

    for (let rawTicker of distinctTickers) {
      let yahooTicker = rawTicker;

      // === REGRA 1: Limpeza do Fracionário (F) ===
      // Remove 'F' final (ex: PETR4F -> PETR4)
      if (yahooTicker.endsWith('F') && yahooTicker.length > 5) {
        yahooTicker = yahooTicker.slice(0, -1);
      }

      // === REGRA 2: Auto-Correção de Subscrição (12/13/14 -> 11) ===
      // Se termina em 12, 13 ou 14, tenta buscar o ticker 11 (ex: KNRI12 -> KNRI11)
      // Isso evita sujar o log com recibos temporários
      if (/(12|13|14)$/.test(yahooTicker)) {
         const original = yahooTicker;
         yahooTicker = yahooTicker.replace(/(12|13|14)$/, '11');
         logs.push(`ℹ️ Auto-ajuste: ${original} tratado como ${yahooTicker}`);
      }

      // Adiciona sufixo .SA se for numérico
      if (/\d$/.test(yahooTicker) && !yahooTicker.includes('.SA')) {
        yahooTicker = yahooTicker + '.SA';
      }

      const url = `https://query1.finance.yahoo.com/v8/finance/chart/${yahooTicker}?symbol=${yahooTicker}&period1=${startDate}&period2=${endDate}&interval=1d&events=div`;

      try {
        const response = await fetch(url, {
          headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0 Safari/537.36" }
        });

        if (!response.ok) {
            // Se der 404, verificamos se é uma migração conhecida
            if (response.status === 404) {
                const { data: migration } = await supabase
                    .from('ticker_migrations')
                    .select('new_ticker')
                    .eq('old_ticker', rawTicker) // Checa o ticker ORIGINAL da carteira
                    .single();

                if (migration) {
                    logs.push(`⚠️ Migração já cadastrada: ${rawTicker} -> ${migration.new_ticker}`);
                } else {
                    // === REGRA 3: Salva no Log de Erros para o Easter Egg ===
                    await supabase.rpc('log_missing_ticker', { p_ticker: rawTicker });
                    logs.push(`❌ ERRO NOVO: ${rawTicker} (Yahoo 404). Salvo no log de gestão.`);
                }
            } else {
                logs.push(`Erro Yahoo genérico [${response.status}] para ${yahooTicker}`);
            }
            continue;
        }

        const json = await response.json();
        const result = json.chart?.result?.[0];

        if (!result || !result.events || !result.events.dividends) continue;

        const dividendsMap = result.events.dividends;

        // Busca donos pelo ticker ORIGINAL (rawTicker)
        const { data: owners } = await supabase
          .from('assets')
          .select('user_id, quantity')
          .eq('ticker', rawTicker);

        if (!owners) continue;

        const earningsToInsert = [];

        for (const key in dividendsMap) {
          const divInfo = dividendsMap[key];
          const dateObj = new Date(divInfo.date * 1000);
          const dateStr = dateObj.toISOString().split('T')[0];

          for (const owner of owners) {
            if (owner.quantity > 0) {
               earningsToInsert.push({
                user_id: owner.user_id,
                ticker: rawTicker,
                type: 'PROVENTO',
                date: dateStr,
                unit_value: divInfo.amount,
                total_value: (owner.quantity * divInfo.amount).toFixed(2)
              });
            }
          }
        }

        if (earningsToInsert.length > 0) {
          await supabase
            .from('earnings')
            .upsert(earningsToInsert, { onConflict: 'user_id, ticker, date, total_value' });

          processedCount += earningsToInsert.length;
        }

      } catch (err) {
        logs.push(`Exceção ${rawTicker}: ${err.message}`);
      }

      await new Promise(r => setTimeout(r, 100));
    }

    return new Response(
      JSON.stringify({ message: `Sucesso! ${processedCount} proventos processados.`, logs }),
      { headers: { "Content-Type": "application/json" } },
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message, logs }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    )
  }
})