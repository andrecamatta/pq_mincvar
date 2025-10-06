#!/usr/bin/env julia

using CSV, DataFrames, Statistics

# Load metrics
metrics = CSV.read("results/metrics.csv", DataFrame)

# Exclude benchmark
metrics = filter(row -> row.strategy != "BUYHOLD", metrics)

println("=" ^ 80)
println("ANÁLISE DE LAMBDA COMO HIPERPARÂMETRO")
println("=" ^ 80)

# Group by strategy type
for strategy in [:MINVAR, :MINCVAR]
    println("\n" * "=" ^ 80)
    println("ESTRATÉGIA: $strategy")
    println("=" ^ 80)

    strat_data = filter(row -> row.strategy == string(strategy), metrics)

    # Summary by lambda
    println("\n### Resumo por Lambda:")
    println("-" ^ 80)

    for λ in [0.0, 0.0003, 0.001]
        lambda_data = filter(row -> row.lambda == λ, strat_data)

        avg_sharpe = mean(lambda_data.sharpe)
        max_sharpe = maximum(lambda_data.sharpe)
        avg_turnover = mean(lambda_data.ann_turnover)
        avg_rebalances = mean(lambda_data.n_rebalances)

        println("\nLambda = $λ:")
        println("  - Sharpe médio:      $(round(avg_sharpe, digits=3))")
        println("  - Sharpe máximo:     $(round(max_sharpe, digits=3))")
        println("  - Turnover médio:    $(round(avg_turnover * 100, digits=2))%")
        println("  - Rebal. médios:     $(round(Int, avg_rebalances))")
    end

    # Best strategies by lambda
    println("\n### Top 3 Estratégias por Lambda:")
    println("-" ^ 80)

    for λ in [0.0, 0.0003, 0.001]
        lambda_data = filter(row -> row.lambda == λ, strat_data)
        top3 = first(sort(lambda_data, :sharpe, rev=true), 3)

        println("\nLambda = $λ:")
        for (i, row) in enumerate(eachrow(top3))
            policy_str = row.policy == "MONTHLY" ? "MONTHLY" : "BANDS-$(Int(row.band*100))"
            est_str = strategy == :MINVAR ? row.estimator : ""
            alpha_str = strategy == :MINCVAR ? "α$(Int(row.alpha*100))" : ""

            desc = join(filter(!isempty, [est_str, alpha_str, policy_str]), "-")

            println("  $i. $desc")
            println("     Sharpe=$(round(row.sharpe, digits=3)), " *
                    "Turnover=$(round(row.ann_turnover*100, digits=1))%, " *
                    "MDD=$(round(row.max_drawdown*100, digits=1))%")
        end
    end
end

# Overall best strategy across all lambdas
println("\n" * "=" ^ 80)
println("MELHOR ESTRATÉGIA GLOBAL (TODOS OS LAMBDAS)")
println("=" ^ 80)

best_overall = first(sort(metrics, :sharpe, rev=true), 1)[1, :]
policy_str = best_overall.policy == "MONTHLY" ? "MONTHLY" : "BANDS-$(Int(best_overall.band*100))"
alpha_str = best_overall.strategy == "MINCVAR" ? "-α$(Int(best_overall.alpha*100))" : ""

println("\n$(best_overall.estimator)-$(best_overall.strategy)$alpha_str-$(policy_str)")
println("Lambda:           $(best_overall.lambda)")
println("Sharpe:           $(round(best_overall.sharpe, digits=3))")
println("Retorno anual:    $(round(best_overall.ann_return * 100, digits=2))%")
println("Volatilidade:     $(round(best_overall.ann_volatility * 100, digits=2))%")
println("Max Drawdown:     $(round(best_overall.max_drawdown * 100, digits=2))%")
println("CVaR 95%:         $(round(best_overall.cvar_95 * 100, digits=2))%")
println("Turnover anual:   $(round(best_overall.ann_turnover * 100, digits=2))%")
println("Rebalanceamentos: $(best_overall.n_rebalances)")

# Lambda recommendation
println("\n" * "=" ^ 80)
println("RECOMENDAÇÃO DE LAMBDA POR ESTRATÉGIA")
println("=" ^ 80)

for strategy in [:MINVAR, :MINCVAR]
    strat_data = filter(row -> row.strategy == string(strategy), metrics)

    # Find best lambda (highest average Sharpe)
    lambda_sharpes = []
    for λ in [0.0, 0.0003, 0.001]
        lambda_data = filter(row -> row.lambda == λ, strat_data)
        avg_sharpe = mean(lambda_data.sharpe)
        max_sharpe = maximum(lambda_data.sharpe)
        push!(lambda_sharpes, (λ=λ, avg=avg_sharpe, max=max_sharpe))
    end

    best_lambda = sort(lambda_sharpes, by=x -> x.max, rev=true)[1]

    println("\n$strategy:")
    println("  Lambda recomendado: $(best_lambda.λ)")
    println("  Sharpe médio:       $(round(best_lambda.avg, digits=3))")
    println("  Sharpe máximo:      $(round(best_lambda.max, digits=3))")

    if best_lambda.λ == 0.0
        println("  Interpretação: Livre adaptação (máximo desempenho, maior turnover)")
    elseif best_lambda.λ == 0.0003
        println("  Interpretação: Equilíbrio intermediário (bom desempenho, turnover moderado)")
    else
        println("  Interpretação: Quasi-estático (baixo turnover, pode travar em alocações subótimas)")
    end
end

println("\n" * "=" ^ 80)
