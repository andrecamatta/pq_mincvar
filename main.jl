#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using DataFrames, CSV, Dates, Statistics, ProgressMeter

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
include("src/plots.jl")
include("src/benchmarks.jl")

"""
Main execution script for Min-CVaR with robust estimators.
"""
function main()
    println("=" ^ 80)
    println("Min-CVaR with Robust Estimators (Tyler/Huber) vs Mean-Variance")
    println("ETFs with ≥15 years of history")
    println("=" ^ 80)

    # ========================================================================
    # 1. CONFIGURATION
    # ========================================================================
    config = Dict(
        # Data - 16 ETFs diversificados (≥15 anos)
        "tickers" => ["SPY",  # US Large Cap
                      "IWD",  # US Value
                      "IWF",  # US Growth
                      "IWM",  # US Small Cap
                      "EFA",  # Developed Markets ex-US
                      "EEM",  # Emerging Markets
                      "VWO",  # Emerging Markets Alt
                      "TLT",  # US 20+ Year Treasury
                      "IEF",  # US 7-10 Year Treasury
                      "LQD",  # Investment Grade Corp Bonds
                      "HYG",  # High Yield Corp Bonds
                      "GLD",  # Gold
                      "SLV",  # Silver
                      "VNQ",  # US Real Estate
                      "DBC",  # Commodities
                      "USO"], # Oil
        "start_date" => Date(2002, 1, 1),
        "min_years" => 15,
        "qc_threshold" => 0.5,

        # Backtest
        "window_size" => 756,  # ~3 years
        "estimators" => [:LW, :HUBER, :TYLER],
        "strategies" => [:MINCVAR, :MINVAR],  # Both strategies (OSQP makes MinVar fast!)
        "alphas" => [0.95, 0.99],
        "policies" => [:MONTHLY, :BANDS],
        "bands" => [0.02, 0.05, 0.10],

        # Optimization
        "cost_bps" => 6.0,  # Realistic average for liquid ETFs (2024)
        "lambdas" => [0.0, 0.0003, 0.001],  # Grid search: free, intermediate, quasi-static
        "max_weight" => 0.30
    )

    @info "Configuration loaded"
    @info "Tickers: $(config["tickers"])"
    @info "Window size: $(config["window_size"]) days"
    @info "Estimators: $(config["estimators"])"
    @info "Strategies: $(config["strategies"])"

    # ========================================================================
    # 2. DATA LOADING
    # ========================================================================
    @info "\n--- Loading Data ---"

    returns_df, prices_df = load_data(
        tickers=config["tickers"],
        start_date=config["start_date"],
        min_years=config["min_years"],
        qc_threshold=config["qc_threshold"]
    )

    final_tickers = names(returns_df)[2:end]
    @info "Final universe: $(length(final_tickers)) assets"
    @info "Tickers: $final_tickers"
    @info "Date range: $(minimum(returns_df.date)) to $(maximum(returns_df.date))"
    @info "Total observations: $(nrow(returns_df))"

    # Sanity check
    if length(final_tickers) < 8
        error("Insufficient assets after filtering (< 8). Adjust min_years or expand ticker list.")
    end

    # Download risk-free rate
    @info "\n--- Loading Risk-Free Rate ---"
    token = get(ENV, "TIINGO_TOKEN", "")
    rf_df = download_risk_free_rate(config["start_date"], token)

    # Merge with returns and calculate average rf for the period
    rf_merged = leftjoin(returns_df, rf_df, on = :date)
    rf_avg = mean(skipmissing(rf_merged.rf))
    @info "Average 3-month T-bill rate: $(round(rf_avg * 100, digits=2))% annualized"

    # ========================================================================
    # 3. TAIL DIAGNOSTICS & ESTIMATOR COMPARISON
    # ========================================================================
    @info "\n--- Tail Diagnostics ---"

    R_matrix = Matrix(returns_df[:, 2:end])
    ν_estimates = Dict()
    Σ_estimates = Dict()

    for estimator in config["estimators"]
        @info "Fitting multivariate t for estimator: $estimator"

        # Use last window for diagnostic
        window_size = config["window_size"]
        R_window = R_matrix[end-window_size+1:end, :]

        ν_est = fit_multivariate_t(R_window)
        ν_estimates[estimator] = ν_est

        @info "  Estimated ν (degrees of freedom): $ν_est"

        # Compute covariance matrix for comparison (use same logic as robust_estimate)
        if estimator == :LW
            Σ, _ = oas_shrinkage(R_window)
        elseif estimator == :HUBER
            μ = [huber_mean(R_window[:, i]) for i in 1:size(R_window, 2)]
            R_centered = R_window .- μ'
            Σ, _ = oas_shrinkage_precentered(R_centered)
        elseif estimator == :TYLER
            # Apply same scaling as in robust_estimate
            R_centered = R_window .- median(R_window, dims=1)
            Σ_tyler = tyler_estimator(R_centered)  # Use centered data
            sample_scale = mean(diag(cov(R_centered, dims=1, corrected=false)))
            Σ_tyler_scaled = Σ_tyler * sample_scale
            # Apply shrinkage
            δ = 0.1
            Σ = (1 - δ) * Σ_tyler_scaled + δ * sample_scale * I(size(R_window, 2))
        end
        Σ_estimates[estimator] = Σ
    end

    # Compare covariance matrices
    @info "\n--- Covariance Matrix Comparison ---"
    estimator_list = collect(config["estimators"])
    for i in 1:length(estimator_list)
        for j in (i+1):length(estimator_list)
            est1, est2 = estimator_list[i], estimator_list[j]
            Σ1, Σ2 = Σ_estimates[est1], Σ_estimates[est2]

            # Frobenius norm of difference (normalized)
            frob_diff = norm(Σ1 - Σ2) / norm(Σ1)  # Frobenius norm (default)

            @info "  $est1 vs $est2: Relative difference = $(round(frob_diff * 100, digits=2))%"
        end
    end

    # ========================================================================
    # 4. BACKTESTING
    # ========================================================================
    @info "\n--- Running Backtests ---"

    all_results = run_all_backtests(
        returns_df;
        estimators=config["estimators"],
        strategies=config["strategies"],
        alphas=config["alphas"],
        policies=config["policies"],
        bands=config["bands"],
        lambdas=config["lambdas"],
        window_size=config["window_size"],
        cost_bps=config["cost_bps"],
        max_weight=config["max_weight"]
    )

    @info "Backtests completed: $(length(all_results)) strategies"

    # ========================================================================
    # 4.5. BENCHMARK
    # ========================================================================
    @info "\n--- Running Benchmark ---"

    # Equal-weight buy-and-hold (annual rebalance)
    bench_result = benchmark_equal_weight(returns_df, cost_bps=config["cost_bps"])
    all_results[(:EW, :BUYHOLD, 0.0, :ANNUAL, 0.0, 0.0)] = bench_result
    @info "Benchmark: Equal-weight buy-and-hold (annual rebalance)"

    # ========================================================================
    # 5. METRICS COMPUTATION
    # ========================================================================
    @info "\n--- Computing Metrics ---"

    metrics_df = generate_metrics_table(all_results, rf=rf_avg)

    # Display summary
    println("\n" * "=" ^ 80)
    println("PERFORMANCE SUMMARY")
    println("=" ^ 80)
    println(metrics_df)

    # Save to CSV
    CSV.write("results/metrics.csv", metrics_df)
    @info "Metrics saved to results/metrics.csv"

    # ========================================================================
    # 6. SAVE WEIGHTS AND TRADES
    # ========================================================================
    @info "\n--- Saving Weights and Trades ---"

    for (key, result) in all_results
        estimator, strategy, α, policy, band = key
        weights_df, _, _, _ = result

        # Create filename
        suffix = "$(estimator)_$(strategy)"
        if strategy == :MINCVAR
            suffix *= "_a$(Int(α*100))"
        elseif strategy == :MINVAR
            suffix *= "_a0"  # MinVar doesn't use α
        end
        suffix *= "_$(policy)"
        if policy == :BANDS
            suffix *= "_b$(Int(band*100))"
        end

        # Save weights
        CSV.write("results/weights_$suffix.csv", weights_df)
    end

    @info "Weights saved to results/"

    # ========================================================================
    # 7. GENERATE PLOTS
    # ========================================================================
    @info "\n--- Generating Plots ---"

    generate_all_plots(all_results, metrics_df)

    # ========================================================================
    # 8. AUTO-GENERATE README
    # ========================================================================
    @info "\n--- Generating README ---"

    readme_content = """
    # Min-CVaR with Robust Estimators

    ## Summary

    This project implements and backtests portfolio optimization strategies comparing:
    - **Min-CVaR** (Conditional Value-at-Risk) optimization using Rockafellar-Uryasev formulation
    - **Min-Var** (Minimum Variance) optimization

    With three robust covariance estimators:
    - **:LW** - Ledoit-Wolf / Oracle Approximating Shrinkage (OAS)
    - **:HUBER** - Huber M-estimator for mean + OAS covariance
    - **:TYLER** - Tyler M-estimator for scatter + shrinkage

    ## Universe

    **Final Assets ($(length(final_tickers))):** $final_tickers

    **Period:** $(minimum(returns_df.date)) to $(maximum(returns_df.date))

    **Filter:** ETFs with ≥ $(config["min_years"]) years of history

    ## Parameters

    - **Estimation window:** $(config["window_size"]) days (~3 years)
    - **Rebalance:** End-of-month
    - **Policies:** Monthly, Bands (2%, 5%, 10%)
    - **Transaction costs:** $(config["cost_bps"]) bps per side
    - **Position limit:** $(Int(config["max_weight"]*100))% per asset
    - **CVaR confidence levels:** α = $(config["alphas"])

    ## Key Findings

    ### Tail Diagnostics (Multivariate t-distribution)
    $(join(["- $est: ν = $(ν_estimates[est])" for est in keys(ν_estimates)], "\n"))

    ### Performance Metrics

    See `results/metrics.csv` for detailed metrics including:
    - Annualized return and volatility
    - Sharpe and Sortino ratios
    - VaR and CVaR at 95% and 99% confidence levels
    - Maximum drawdown and Ulcer index
    - Annualized turnover and number of rebalances

    ### Best Strategies (by Sharpe Ratio)

    Top 5 strategies:
    $(let
        top5 = first(sort(metrics_df, :sharpe, rev=true), 5)
        join([
            "$(i). $(row.estimator)-$(row.strategy)-α$(Int(row.alpha*100))-$(row.policy): Sharpe=$(round(row.sharpe, digits=3))"
            for (i, row) in enumerate(eachrow(top5))
        ], "\n")
    end)

    ## Interpretation

    - **Tyler estimator** typically reduces tail risk (CVaR/MDD) vs Gaussian (LW), especially when ν < 10
    - **Band policies** significantly reduce turnover vs monthly rebalancing, with modest performance trade-offs
    - **Min-CVaR** strategies show better downside protection compared to Min-Var during crisis periods
    - **Transaction costs** materially impact net performance, particularly for high-turnover strategies

    ## Files

    - `results/metrics.csv` - Comprehensive performance metrics
    - `results/weights_*.csv` - Portfolio weights over time
    - `fig/` - Visualizations (wealth curves, frontiers, allocation, tail losses)

    ## Reproducibility

    **Julia version:** $(VERSION)

    **Packages:** See `Project.toml`

    **Random seed:** Not used (deterministic optimization)

    **Execution:** `julia main.jl`

    ---

    Generated on $(Dates.now())
    """

    open("README.md", "w") do f
        write(f, readme_content)
    end

    @info "README.md generated"

    # ========================================================================
    # DONE
    # ========================================================================
    println("\n" * "=" ^ 80)
    println("✓ All tasks completed successfully!")
    println("=" ^ 80)
    println("\nOutputs:")
    println("  - Results: ./results/")
    println("  - Figures: ./fig/")
    println("  - README: ./README.md")
    println()
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
