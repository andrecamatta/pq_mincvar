using StatsPlots, Plots
using DataFrames, Statistics

include("metrics.jl")

"""
Plot cumulative wealth curves for multiple strategies.
"""
function plot_wealth_curves(all_results::Dict; filename::String="wealth_curves.png")
    p = plot(
        xlabel="Date",
        ylabel="Cumulative Wealth",
        title="Portfolio Performance Comparison",
        legend=:topleft,
        size=(1200, 600)
    )

    colors = Dict(:LW => :blue, :HUBER => :green, :TYLER => :red, :EW => :black)
    linestyles = Dict(:MINCVAR => :solid, :MINVAR => :dash, :BUYHOLD => :dot)

    for (key, result) in all_results
        estimator, strategy, α, policy, band = key

        # Only plot monthly policy (and benchmark) for clarity
        if policy != :MONTHLY && policy != :ANNUAL
            continue
        end

        _, returns, wealth, dates = result

        # Validate vector sizes match
        if length(dates) != length(wealth)
            @warn "Skipping plot for $key: size mismatch (dates=$(length(dates)) vs wealth=$(length(wealth)))"
            continue
        end

        label = "$(estimator)-$(strategy)"
        if strategy == :MINCVAR
            label *= "-α$(Int(α*100))"
        elseif strategy == :MINVAR
            label *= "-α0"
        end

        plot!(p, dates, wealth,
            label=label,
            color=colors[estimator],
            linestyle=linestyles[strategy],
            linewidth=strategy == :BUYHOLD ? 3 : 2,
            alpha=strategy == :BUYHOLD ? 1.0 : 0.8)
    end

    savefig(p, "fig/$filename")
    return p
end

"""
Plot empirical efficient frontier in (σ, CVaR) space.
"""
function plot_frontier(
    all_results::Dict,
    α::Float64=0.95;
    filename::String="frontier_95.png"
)
    points = Dict(:LW => [], :HUBER => [], :TYLER => [], :EW => [])

    for (key, result) in all_results
        estimator, strategy, strat_α, policy, band = key

        # Only monthly policy (and benchmark), matching α
        if (policy != :MONTHLY && policy != :ANNUAL) || (strategy == :MINCVAR && strat_α != α)
            continue
        end

        _, returns, wealth, _ = result

        σ = std(returns) * sqrt(252)
        cvar = calculate_cvar(returns, α) * sqrt(252)

        push!(points[estimator], (σ, cvar, string(strategy)))
    end

    p = plot(
        xlabel="Annualized Volatility",
        ylabel="Annualized CVaR (α=$α)",
        title="Efficient Frontier (Risk-CVaR Space)",
        legend=:topright,
        size=(800, 600)
    )

    colors = Dict(:LW => :blue, :HUBER => :green, :TYLER => :red, :EW => :black)
    markers = Dict("MINCVAR" => :circle, "MINVAR" => :square, "BUYHOLD" => :star)

    for (estimator, pts) in points
        for (σ, cvar, strat) in pts
            scatter!(p, [σ], [cvar],
                label="$(estimator)-$(strat)",
                color=colors[estimator],
                marker=markers[strat],
                markersize=strat == "BUYHOLD" ? 12 : 8,
                alpha=0.7)
        end
    end

    savefig(p, "fig/$filename")
    return p
end

"""
Plot stacked area chart of portfolio weights over time.
"""
function plot_allocation_over_time(
    weights_df::DataFrame,
    dates::Vector{Date};
    filename::String="allocation.png"
)
    tickers = names(weights_df)[4:end]  # skip date, rebalanced, turnover
    n_tickers = length(tickers)

    # Prepare data for stacked area plot
    weight_matrix = Matrix(weights_df[:, tickers])  # T × p matrix

    # Use dates from weights_df, not the passed dates vector
    actual_dates = weights_df.date

    # Validate
    if size(weight_matrix, 1) != length(actual_dates)
        @warn "Skipping allocation plot: size mismatch (weights=$(size(weight_matrix, 1)) vs dates=$(length(actual_dates)))"
        return nothing
    end

    # areaplot expects: x-axis (dates), y-values as columns (each column = one series)
    # weight_matrix is T×p, which is correct orientation
    p = areaplot(
        actual_dates,
        weight_matrix,  # Do NOT transpose - already correct
        labels=permutedims(tickers),
        xlabel="Date",
        ylabel="Weight",
        title="Portfolio Allocation Over Time",
        legend=:outerright,
        size=(1200, 600),
        palette=:tab20
    )

    savefig(p, "fig/$filename")
    return p
end

"""
Plot violin plot of tail losses (worst α% returns).
"""
function plot_tail_losses(
    all_results::Dict,
    α::Float64=0.05;
    filename::String="tail_losses.png"
)
    data = Dict()
    labels = String[]

    for (key, result) in all_results
        estimator, strategy, strat_α, policy, band = key

        # Only monthly policy and benchmark
        if policy != :MONTHLY && policy != :ANNUAL
            continue
        end

        _, returns, wealth, _ = result

        tail = get_tail_losses(returns, α)

        label = "$(estimator)-$(strategy)"
        if strategy == :MINCVAR
            label *= "-α$(Int(strat_α*100))"
        end

        data[label] = tail
        push!(labels, label)
    end

    # Create violin plot
    p = violin(
        labels,
        [data[l] for l in labels],
        xlabel="Strategy",
        ylabel="Return",
        title="Distribution of Tail Losses (worst $(Int(α*100))%)",
        legend=false,
        size=(1200, 600),
        xrotation=45
    )

    savefig(p, "fig/$filename")
    return p
end

"""
Plot heatmap of turnover by strategy.
"""
function plot_turnover_heatmap(metrics_df::DataFrame; filename::String="turnover_heatmap.png")
    # Pivot table: estimator × strategy
    estimators = unique(metrics_df.estimator)
    strategies = unique(metrics_df.strategy)

    turnover_matrix = zeros(length(estimators), length(strategies))

    for (i, est) in enumerate(estimators)
        for (j, strat) in enumerate(strategies)
            subset = filter(row -> row.estimator == est && row.strategy == strat, metrics_df)
            if !isempty(subset)
                turnover_matrix[i, j] = mean(subset.ann_turnover)
            end
        end
    end

    p = heatmap(
        strategies,
        estimators,
        turnover_matrix,
        xlabel="Strategy",
        ylabel="Estimator",
        title="Annualized Turnover Heatmap",
        color=:viridis,
        size=(800, 600)
    )

    savefig(p, "fig/$filename")
    return p
end

"""
Plot histogram of rebalancing events (for band policies).
"""
function plot_rebalance_histogram(all_results::Dict; filename::String="rebalance_hist.png")
    rebal_counts = Dict()

    for (key, result) in all_results
        estimator, strategy, α, policy, band = key

        # Only band policies
        if policy != :BANDS
            continue
        end

        weights_df, _, _, _ = result
        n_rebals = sum(weights_df.rebalanced)

        label = "$(estimator)-$(strategy)-band$(Int(band*100))"
        rebal_counts[label] = n_rebals
    end

    labels = collect(keys(rebal_counts))
    counts = [rebal_counts[l] for l in labels]

    p = bar(
        labels,
        counts,
        xlabel="Strategy",
        ylabel="Number of Rebalances",
        title="Rebalancing Events by Policy",
        legend=false,
        size=(1200, 600),
        xrotation=45
    )

    savefig(p, "fig/$filename")
    return p
end

"""
Generate all plots.
"""
function generate_all_plots(all_results::Dict, metrics_df::DataFrame)
    @info "Generating plots..."

    plot_wealth_curves(all_results)
    plot_frontier(all_results, 0.95, filename="frontier_95.png")
    plot_frontier(all_results, 0.99, filename="frontier_99.png")
    plot_tail_losses(all_results, 0.05, filename="tail_losses_5pct.png")
    plot_tail_losses(all_results, 0.01, filename="tail_losses_1pct.png")
    plot_turnover_heatmap(metrics_df)

    # Plot allocation for best strategy (example: TYLER-MINCVAR-95-MONTHLY)
    best_key = (:TYLER, :MINCVAR, 0.95, :MONTHLY, 0.0)
    if haskey(all_results, best_key)
        weights_df, _, _, dates = all_results[best_key]
        plot_allocation_over_time(weights_df, dates, filename="allocation_best.png")
    end

    @info "Plots saved to ./fig/"
end
