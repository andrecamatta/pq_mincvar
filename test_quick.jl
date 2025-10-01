#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using DataFrames, CSV, Dates, Statistics

# Load .env file if it exists
if isfile(".env")
    for line in eachline(".env")
        line = strip(line)
        if !isempty(line) && !startswith(line, "#")
            key, val = split(line, "=", limit=2)
            ENV[strip(key)] = strip(val)
        end
    end
end

# Load modules
include("src/data.jl")
include("src/estimators.jl")
include("src/optimization.jl")
include("src/backtest.jl")
include("src/metrics.jl")

"""
Quick test with reduced configuration
"""
function test_quick()
    println("="^80)
    println("QUICK TEST - Min-CVaR with Robust Estimators")
    println("="^80)

    # Reduced configuration for quick test
    @info "Loading data (small subset)..."

    returns_df, prices_df = load_data(
        tickers=["SPY", "IWD", "IWF", "VTV", "VUG",
                 "EFA", "EEM",
                 "TLT", "IEF", "LQD", "HYG",
                 "VNQ", "GLD"],  # 13 assets
        start_date=Date(2010, 1, 1),  # Start from 2010
        min_years=15,  # 15 years requirement
        qc_threshold=0.5,
        min_assets=8
    )

    final_tickers = names(returns_df)[2:end]
    @info "Assets: $final_tickers"
    @info "Observations: $(nrow(returns_df))"

    # Quick single backtest
    @info "\nRunning single backtest (LW, MINCVAR, α=0.95, MONTHLY)..."

    result = backtest_strategy(
        returns_df;
        strategy=:MINCVAR,
        estimator=:LW,
        α=0.95,
        window_size=504,  # 2 years
        policy=:MONTHLY,
        cost_bps=10.0,
        max_weight=0.50
    )

    weights_df, returns, wealth, dates = result

    # Compute metrics
    turnover = zeros(length(returns))
    metrics = compute_metrics(returns, wealth, turnover)

    @info "\n" * "="^80
    @info "RESULTS"
    @info "="^80
    @info "Annualized Return: $(round(metrics["ann_return"]*100, digits=2))%"
    @info "Annualized Volatility: $(round(metrics["ann_volatility"]*100, digits=2))%"
    @info "Sharpe Ratio: $(round(metrics["sharpe"], digits=3))"
    @info "Max Drawdown: $(round(metrics["max_drawdown"]*100, digits=2))%"
    @info "CVaR 95%: $(round(metrics["cvar_95"]*100, digits=2))%"
    @info "Final Wealth: $(round(metrics["final_wealth"], digits=3))"
    @info "="^80

    println("\n✓ Quick test completed successfully!")
    println("  To run full backtest, use: julia main.jl")
    println("  (Note: full backtest may take 10-30 minutes)")
end

# Run test
if abspath(PROGRAM_FILE) == @__FILE__
    test_quick()
end
