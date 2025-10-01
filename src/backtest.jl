using DataFrames, Dates, Statistics, LinearAlgebra

include("estimators.jl")
include("optimization.jl")

"""
Get rebalance dates (end-of-month) within the backtest period.
"""
function get_rebalance_dates(dates::Vector{Date}, window_size::Int)
    valid_start = dates[window_size]
    valid_dates = filter(d -> d >= valid_start, dates)

    # End-of-month dates
    rebal_dates = Date[]
    current_month = nothing

    for d in valid_dates
        month_key = (year(d), month(d))
        if month_key != current_month
            if !isnothing(current_month) && !isempty(rebal_dates)
                # Already added last date of previous month
            end
            current_month = month_key
        end
    end

    # Get last date of each month
    months = unique([(year(d), month(d)) for d in valid_dates])
    for (y, m) in months
        month_dates = filter(d -> year(d) == y && month(d) == m, valid_dates)
        if !isempty(month_dates)
            push!(rebal_dates, maximum(month_dates))
        end
    end

    return rebal_dates
end

"""
Check if rebalancing is needed based on band policy.
"""
function needs_rebalance(w_current::Vector{Float64}, w_target::Vector{Float64}, band::Float64)
    return any(abs.(w_current - w_target) .> band)
end

"""
Run backtest for a single strategy.

strategy: :MINCVAR or :MINVAR
estimator: :LW, :HUBER, or :TYLER
policy: :MONTHLY or :BANDS
"""
function backtest_strategy(
    returns_df::DataFrame;
    strategy::Symbol = :MINCVAR,
    estimator::Symbol = :LW,
    α::Float64 = 0.95,
    window_size::Int = 756,
    policy::Symbol = :MONTHLY,
    band::Float64 = 0.05,
    cost_bps::Float64 = 10.0,
    λ::Float64 = 0.0,
    max_weight::Float64 = 0.30
)
    dates = returns_df.date
    tickers = names(returns_df)[2:end]
    p = length(tickers)

    # Get returns matrix
    R_full = Matrix(returns_df[:, 2:end])
    n_days = size(R_full, 1)

    # Initialize storage
    results = DataFrame(
        date = Date[],
        rebalanced = Bool[],
        turnover = Float64[]
    )

    for ticker in tickers
        results[!, ticker] = Float64[]
    end

    # Initialize portfolio
    w_strategic = ones(p) / p  # Last rebalanced weights (fixed between rebalances)
    w_current = ones(p) / p    # Current weights with natural drift
    portfolio_value = 1.0
    wealth = Float64[]  # will be filled in loop to match dates
    daily_returns = Float64[]

    rebal_dates = get_rebalance_dates(dates, window_size)

    @info "Running backtest: strategy=$strategy, estimator=$estimator, α=$α, policy=$policy, band=$band"
    @info "Rebalance dates: $(length(rebal_dates))"

    for t in window_size:n_days
        current_date = dates[t]

        # Check if this is a rebalance date
        is_rebal_date = current_date ∈ rebal_dates

        if is_rebal_date
            # Get estimation window
            window_start = t - window_size + 1
            window_end = t
            R_window = R_full[window_start:window_end, :]

            # Estimate parameters
            μ, Σ = robust_estimate(R_window, estimator)

            # Optimize portfolio (use w_strategic as previous weights)
            if strategy == :MINCVAR
                w_target, _ = optimize_mincvar(R_window, α;
                    w_prev=w_strategic, λ=λ, max_weight=max_weight)
            elseif strategy == :MINVAR
                w_target, _ = optimize_minvar(Σ;
                    w_prev=w_strategic, λ=λ, max_weight=max_weight)
            else
                error("Unknown strategy: $strategy")
            end

            # Decide if we rebalance based on policy (compare strategic vs target)
            rebalance = false
            if policy == :MONTHLY
                rebalance = true
            elseif policy == :BANDS
                rebalance = needs_rebalance(w_strategic, w_target, band)
            end

            # Execute rebalance
            turnover = 0.0
            if rebalance
                # Turnover is based on strategic weights, not drifted weights
                turnover = sum(abs.(w_target - w_strategic))
                transaction_cost = (cost_bps / 10000) * turnover
                portfolio_value *= (1 - transaction_cost)

                # Update both strategic and current weights
                w_strategic = w_target
                w_current = w_target
            end

            # Record weights (always record on rebalance dates, even if no rebalance)
            push!(results, vcat([current_date, rebalance, turnover], w_strategic))
        end

        # Daily portfolio return (drift weights naturally with returns)
        if t <= n_days
            # Record wealth BEFORE applying return
            push!(wealth, portfolio_value)

            daily_ret = dot(w_current, R_full[t, :])
            portfolio_value *= (1 + daily_ret)
            push!(daily_returns, daily_ret)

            # Update current weights by drift (strategic stays fixed)
            w_current = w_current .* (1 .+ R_full[t, :])
            w_current = w_current / sum(w_current)
        end
    end

    return results, daily_returns, wealth, dates[window_size:end]
end

"""
Run comprehensive backtest for all combinations.
"""
function run_all_backtests(
    returns_df::DataFrame;
    estimators::Vector{Symbol} = [:LW, :HUBER, :TYLER],
    strategies::Vector{Symbol} = [:MINCVAR, :MINVAR],
    alphas::Vector{Float64} = [0.95, 0.99],
    policies::Vector{Symbol} = [:MONTHLY, :BANDS],
    bands::Vector{Float64} = [0.02, 0.05, 0.10],
    window_size::Int = 756,
    cost_bps::Float64 = 10.0,
    λ::Float64 = 0.0,
    max_weight::Float64 = 0.30
)
    all_results = Dict()

    for estimator in estimators
        for strategy in strategies
            if strategy == :MINCVAR
                for α in alphas
                    # Monthly policy
                    key = (estimator, strategy, α, :MONTHLY, 0.0)
                    @info "Backtesting: $key"
                    result = backtest_strategy(returns_df;
                        strategy=strategy, estimator=estimator, α=α,
                        window_size=window_size, policy=:MONTHLY,
                        cost_bps=cost_bps, λ=λ, max_weight=max_weight)
                    all_results[key] = result

                    # Band policies
                    for band in bands
                        key = (estimator, strategy, α, :BANDS, band)
                        @info "Backtesting: $key"
                        result = backtest_strategy(returns_df;
                            strategy=strategy, estimator=estimator, α=α,
                            window_size=window_size, policy=:BANDS, band=band,
                            cost_bps=cost_bps, λ=λ, max_weight=max_weight)
                        all_results[key] = result
                    end
                end
            else  # MINVAR
                # Monthly policy
                key = (estimator, strategy, 0.0, :MONTHLY, 0.0)
                @info "Backtesting: $key"
                result = backtest_strategy(returns_df;
                    strategy=strategy, estimator=estimator,
                    window_size=window_size, policy=:MONTHLY,
                    cost_bps=cost_bps, λ=λ, max_weight=max_weight)
                all_results[key] = result

                # Band policies
                for band in bands
                    key = (estimator, strategy, 0.0, :BANDS, band)
                    @info "Backtesting: $key"
                    result = backtest_strategy(returns_df;
                        strategy=strategy, estimator=estimator,
                        window_size=window_size, policy=:BANDS, band=band,
                        cost_bps=cost_bps, λ=λ, max_weight=max_weight)
                    all_results[key] = result
                end
            end
        end
    end

    return all_results
end
