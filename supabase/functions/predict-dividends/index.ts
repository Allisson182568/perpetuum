// ARQUIVO: supabase/functions/predict-dividends/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 1. Pega todos os ativos únicos e seus donos
  const { data: assets } = await supabase.from('assets').select('ticker, user_id, type');

  if (!assets || assets.length === 0) {
    return new Response(JSON.stringify({ message: "Sem ativos para prever." }), { headers: { "Content-Type": "application/json" } });
  }

  const predictions = [];
  const now = new Date();

  // Agrupa por usuário para processar carteira a carteira
  const userAssets = {};
  assets.forEach(a => {
    if (!userAssets[a.user_id]) userAssets[a.user_id] = [];
    userAssets[a.user_id].push(a);
  });

  for (const userId in userAssets) {
    const portfolio = userAssets[userId];

    for (const asset of portfolio) {
      // Busca histórico de proventos desse ativo (últimos 24 lançamentos)
      // Ordenado do mais recente para o mais antigo
      const { data: history } = await supabase
        .from('earnings')
        .select('date, unit_value, total_value, ticker')
        .eq('user_id', userId)
        .eq('ticker', asset.ticker)
        .order('date', { ascending: false })
        .limit(24);

      if (!history || history.length < 2) continue; // Precisa de histórico mínimo para prever

      // === HEURÍSTICA DA IA ===

      // 1. Detecção de Frequência Mensal (FIIs ou Bonificações recorrentes)
      // Lógica: Verifica se os últimos 3 pagamentos têm diferença menor que 35 dias entre si
      const recentHistory = history.slice(0, 3);
      let isMonthly = false;

      if (recentHistory.length >= 3) {
        const d1 = new Date(recentHistory[0].date);
        const d2 = new Date(recentHistory[1].date);
        const d3 = new Date(recentHistory[2].date);

        const diff1 = Math.abs((d1.getTime() - d2.getTime()) / (1000 * 3600 * 24));
        const diff2 = Math.abs((d2.getTime() - d3.getTime()) / (1000 * 3600 * 24));

        if (diff1 < 35 && diff2 < 35) isMonthly = true;
      }

      if (isMonthly) {
        // --- CENÁRIO A: PAGAMENTO MENSAL (FIIs) ---
        // Projeta os próximos 6 meses baseado na média dos últimos 3
        const avgVal = recentHistory.reduce((sum, item) => sum + item.total_value, 0) / recentHistory.length;

        // Descobre o "dia padrão" de pagamento (ex: dia 15)
        // Pega a média dos dias do mês
        const daySum = recentHistory.reduce((sum, item) => sum + new Date(item.date).getDate() + 1, 0); // +1 ajuste fuso simples
        const avgDay = Math.round(daySum / recentHistory.length);

        for (let i = 1; i <= 12; i++) {
          // Cria data no futuro: Mês atual + i
          // Nota: JS Date month começa em 0.
          const predDate = new Date(now.getFullYear(), now.getMonth() + i, avgDay);

          predictions.push({
            user_id: userId,
            ticker: asset.ticker,
            predicted_date: predDate.toISOString().split('T')[0],
            predicted_amount: parseFloat(avgVal.toFixed(2)),
            confidence_score: 0.95- (i * 0.02), // Alta confiança para FIIs
            algorithm_version: 'monthly_avg_v1'
          });
        }
      } else {
        // --- CENÁRIO B: PAGAMENTO SAZONAL (AÇÕES) ---
        // Olha para os pagamentos de 1 ano atrás.
        // Se pagou em Maio/2024, projeta Maio/2025.

        const oneYearAgoStart = new Date();
        oneYearAgoStart.setFullYear(now.getFullYear() - 1);

        // Pega pagamentos que ocorreram entre hoje e 1 ano atrás
        // Ex: Se hoje é Jan/2026, pega tudo de Jan/2025 até hoje.
        // Mas queremos projetar o futuro.

        // Estratégia Melhorada: "Espelho de Calendário"
        // Itera sobre o histórico inteiro. Se a data + 1 ano > hoje, é uma previsão válida.

        for (const payment of history) {
            const oldDate = new Date(payment.date);
            // Projeta 1 ano pra frente
            const newDate = new Date(oldDate.getFullYear() + 1, oldDate.getMonth(), oldDate.getDate());

            // Só adiciona se for uma data futura (e não muito distante, limite 1 ano)
            const diffDaysFromNow = (newDate.getTime() - now.getTime()) / (1000 * 3600 * 24);

            if (diffDaysFromNow > 0 && diffDaysFromNow < 365) {
                // Verifica se já não adicionamos uma previsão para esse mês/ano (evita duplicatas se pagou jcp+div no mesmo dia)
                const alreadyExists = predictions.some(p =>
                    p.user_id === userId &&
                    p.ticker === asset.ticker &&
                    p.predicted_date === newDate.toISOString().split('T')[0]
                );

                if (!alreadyExists) {
                    predictions.push({
                        user_id: userId,
                        ticker: asset.ticker,
                        predicted_date: newDate.toISOString().split('T')[0],
                        predicted_amount: payment.total_value, // Assume valor nominal similar (conservador)
                        confidence_score: 0.60, // Confiança média (ações variam)
                        algorithm_version: 'seasonal_mirror_v1'
                    });
                }
            }
        }
      }
    }
  }

  // Salva no Banco (Upsert em lotes para performance)
  if (predictions.length > 0) {
      // Supabase limita o tamanho do body, vamos salvar em chunks de 100 se for muito grande
      const chunkSize = 100;
      for (let i = 0; i < predictions.length; i += chunkSize) {
        const chunk = predictions.slice(i, i + chunkSize);

        const { error } = await supabase
            .from('ai_predictions')
            .upsert(chunk, { onConflict: 'user_id, ticker, predicted_date' });

        if (error) {
            console.error('Erro ao salvar previsões:', error);
        }
      }
  }

  return new Response(
    JSON.stringify({
        message: "Processamento de IA concluído",
        generated_predictions: predictions.length
    }),
    { headers: { "Content-Type": "application/json" } }
  );
})