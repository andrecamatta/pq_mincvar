#!/usr/bin/env julia

using CSV, DataFrames

metrics = CSV.read("results/metrics.csv", DataFrame)
metrics = filter(row -> row.strategy != "BUYHOLD", metrics)

# Best by drawdown
best_dd = first(sort(metrics, :max_drawdown), 1)[1, :]

policy_str = best_dd.policy == "MONTHLY" ? "MONTHLY" : "BANDS-$(Int(best_dd.band*100))%"
alpha_str = best_dd.strategy == "MINCVAR" ? "-α$(Int(best_dd.alpha*100))" : ""

println("\n" * "="^80)
println("MELHOR ESTRATÉGIA POR DRAWDOWN (MENOR)")
println("="^80)
println("\n$(best_dd.estimator)-$(best_dd.strategy)$alpha_str-$(policy_str)")
println("Lambda:           $(best_dd.lambda)")
println("Max Drawdown:     $(round(best_dd.max_drawdown * 100, digits=2))%")
println("Sharpe:           $(round(best_dd.sharpe, digits=3))")
println("Retorno anual:    $(round(best_dd.ann_return * 100, digits=2))%")
println("Volatilidade:     $(round(best_dd.ann_volatility * 100, digits=2))%")
println("CVaR 95%:         $(round(best_dd.cvar_95 * 100, digits=2))%")
println("CVaR 99%:         $(round(best_dd.cvar_99 * 100, digits=2))%")
println("Ulcer Index:      $(round(best_dd.ulcer_index * 100, digits=2))%")
println("Sortino:          $(round(best_dd.sortino, digits=3))")
println("Turnover anual:   $(round(best_dd.ann_turnover * 100, digits=2))%")
println("Rebalanceamentos: $(best_dd.n_rebalances)")
println("\n" * "="^80)

# Top 5 by drawdown
println("\nTOP 5 ESTRATÉGIAS POR DRAWDOWN:")
println("="^80)

top5 = first(sort(metrics, :max_drawdown), 5)

for (i, row) in enumerate(eachrow(top5))
    policy_str = row.policy == "MONTHLY" ? "MONTHLY" : "BANDS-$(Int(row.band*100))%"
    alpha_str = row.strategy == "MINCVAR" ? "-α$(Int(row.alpha*100))" : ""

    println("\n$i. $(row.estimator)-$(row.strategy)$alpha_str-$(policy_str)")
    println("   Lambda=$(row.lambda), MDD=$(round(row.max_drawdown*100, digits=2))%, " *
            "Sharpe=$(round(row.sharpe, digits=3)), " *
            "Turnover=$(round(row.ann_turnover*100, digits=1))%")
end

println("\n" * "="^80)
