using Statistics, StatsBase, LinearAlgebra

"""
Calculate Value-at-Risk (VaR) at level α.
"""
function calculate_var(returns::Vector{Float64}, α::Float64)
    return -quantile(returns, 1 - α)
end

"""
Calculate Conditional Value-at-Risk (CVaR/ES) at level α.
"""
function calculate_cvar(returns::Vector{Float64}, α::Float64)
    var_α = -quantile(returns, 1 - α)
    tail_losses = returns[returns .<= -var_α]
    return -mean(tail_losses)
end

"""
Calculate Sharpe ratio (annualized).
"""
function calculate_sharpe(returns::Vector{Float64}; rf::Float64=0.0, periods_per_year::Int=252)
    excess_returns = returns .- rf / periods_per_year
    return sqrt(periods_per_year) * mean(excess_returns) / std(excess_returns)
end

"""
Calculate Sortino ratio (annualized, downside deviation).
"""
function calculate_sortino(returns::Vector{Float64}; rf::Float64=0.0, periods_per_year::Int=252)
    excess_returns = returns .- rf / periods_per_year
    downside_returns = excess_returns[excess_returns .< 0]
    downside_std = isempty(downside_returns) ? 1e-10 : std(downside_returns)
    return sqrt(periods_per_year) * mean(excess_returns) / downside_std
end

"""
Calculate maximum drawdown.
"""
function calculate_max_drawdown(wealth::Vector{Float64})
    running_max = accumulate(max, wealth)
    drawdowns = (wealth .- running_max) ./ running_max
    return -minimum(drawdowns)
end

"""
Calculate Ulcer Index (measure of downside volatility).
"""
function calculate_ulcer_index(wealth::Vector{Float64})
    running_max = accumulate(max, wealth)
    drawdowns = (wealth .- running_max) ./ running_max
    return sqrt(mean(drawdowns .^ 2))
end

"""
Calculate annualized turnover.
"""
function calculate_annualized_turnover(
    turnover_series::Vector{Float64},
    n_periods::Int;
    periods_per_year::Int=252
)
    total_turnover = sum(turnover_series)
    return total_turnover * (periods_per_year / n_periods)
end

"""
Calculate weight stability (temporal standard deviation of weights).
"""
function calculate_weight_stability(weights_matrix::Matrix{Float64})
    # weights_matrix: T × p (time × assets)
    return vec(std(weights_matrix, dims=1))
end

"""
Compute comprehensive performance metrics for a strategy.
"""
function compute_metrics(
    returns::Vector{Float64},
    wealth::Vector{Float64},
    turnover_series::Vector{Float64};
    α_levels::Vector{Float64} = [0.95, 0.99],
    periods_per_year::Int = 252,
    rf::Float64 = 0.0
)
    metrics = Dict{String, Any}()

    # Basic stats
    metrics["mean_return"] = mean(returns)
    metrics["std_return"] = std(returns)
    metrics["ann_return"] = mean(returns) * periods_per_year
    metrics["ann_volatility"] = std(returns) * sqrt(periods_per_year)

    # Risk-adjusted returns (with risk-free rate)
    metrics["sharpe"] = calculate_sharpe(returns, rf=rf, periods_per_year=periods_per_year)
    metrics["sortino"] = calculate_sortino(returns, rf=rf, periods_per_year=periods_per_year)

    # Tail risk metrics
    for α in α_levels
        metrics["var_$(Int(α*100))"] = calculate_var(returns, α)
        metrics["cvar_$(Int(α*100))"] = calculate_cvar(returns, α)
    end

    # Drawdown metrics
    metrics["max_drawdown"] = calculate_max_drawdown(wealth)
    metrics["ulcer_index"] = calculate_ulcer_index(wealth)

    # Turnover
    n_periods = length(returns)
    metrics["ann_turnover"] = calculate_annualized_turnover(
        turnover_series, n_periods, periods_per_year=periods_per_year)
    metrics["n_rebalances"] = sum(turnover_series .> 0)

    # Final wealth
    metrics["final_wealth"] = wealth[end]
    metrics["total_return"] = wealth[end] - 1.0

    return metrics
end

"""
Compare ex-ante (model predicted) vs ex-post (realized) CVaR.
Computes bias and RMSE.
"""
function compare_exante_expost(
    predicted_cvar::Vector{Float64},
    realized_returns::Vector{Vector{Float64}},
    α::Float64
)
    n = length(predicted_cvar)
    realized_cvar = zeros(n)

    for i in 1:n
        if !isempty(realized_returns[i])
            realized_cvar[i] = calculate_cvar(realized_returns[i], α)
        end
    end

    bias = mean(predicted_cvar - realized_cvar)
    rmse = sqrt(mean((predicted_cvar - realized_cvar) .^ 2))

    return bias, rmse
end

"""
Generate metrics comparison table for all strategies.
"""
function generate_metrics_table(all_results::Dict; rf::Float64 = 0.0)
    rows = []

    for (key, result) in all_results
        estimator, strategy, α, policy, band, λ = key
        weights_df, returns, wealth, _ = result

        # Extract turnover series from weights DataFrame
        turnover = weights_df.turnover

        metrics = compute_metrics(returns, wealth, turnover, rf=rf)

        row = Dict(
            "estimator" => string(estimator),
            "strategy" => string(strategy),
            "alpha" => α,
            "policy" => string(policy),
            "band" => band,
            "lambda" => λ,
            "ann_return" => metrics["ann_return"],
            "ann_volatility" => metrics["ann_volatility"],
            "sharpe" => metrics["sharpe"],
            "sortino" => metrics["sortino"],
            "max_drawdown" => metrics["max_drawdown"],
            "var_95" => metrics["var_95"],
            "cvar_95" => metrics["cvar_95"],
            "var_99" => get(metrics, "var_99", NaN),
            "cvar_99" => get(metrics, "cvar_99", NaN),
            "ulcer_index" => metrics["ulcer_index"],
            "ann_turnover" => metrics["ann_turnover"],
            "n_rebalances" => metrics["n_rebalances"],
            "final_wealth" => metrics["final_wealth"]
        )

        push!(rows, row)
    end

    return DataFrame(rows)
end

"""
Extract tail losses (worst α% of returns).
"""
function get_tail_losses(returns::Vector{Float64}, α::Float64)
    threshold = quantile(returns, 1 - α)
    return returns[returns .<= threshold]
end
