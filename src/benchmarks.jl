using DataFrames, Dates, Statistics

"""
Run equal-weight buy-and-hold benchmark.
Rebalances annually to maintain equal weights.
"""
function benchmark_equal_weight(
    returns_df::DataFrame;
    cost_bps::Float64 = 6.0
)
    dates = returns_df.date
    tickers = names(returns_df)[2:end]
    p = length(tickers)

    R_full = Matrix(returns_df[:, 2:end])
    n_days = size(R_full, 1)

    # Initialize
    w_equal = ones(p) / p
    w_current = copy(w_equal)
    portfolio_value = 1.0
    wealth = Float64[]
    daily_returns = Float64[]

    # Rebalance annually (every 252 days)
    results = DataFrame(
        date = Date[],
        rebalanced = Bool[],
        turnover = Float64[]
    )
    for ticker in tickers
        results[!, ticker] = Float64[]
    end

    last_rebal_day = 0

    for t in 1:n_days
        current_date = dates[t]

        # Check if we should rebalance (annually)
        if t - last_rebal_day >= 252
            turnover = sum(abs.(w_equal - w_current))
            transaction_cost = (cost_bps / 10000) * turnover
            portfolio_value *= (1 - transaction_cost)

            w_current = w_equal
            last_rebal_day = t

            # Record weights
            push!(results, vcat([current_date, true, turnover], w_current))
        end

        # Record wealth BEFORE applying return
        push!(wealth, portfolio_value)

        # Daily return
        daily_ret = dot(w_current, R_full[t, :])
        portfolio_value *= (1 + daily_ret)
        push!(daily_returns, daily_ret)

        # Update weights by drift
        w_current = w_current .* (1 .+ R_full[t, :])
        w_current = w_current / sum(w_current)
    end

    return results, daily_returns, wealth, dates
end
