using StatsPlots, Plots
using DataFrames, Statistics

include("metrics.jl")

"""
Plot cumulative wealth curves for multiple strategies.
"""
function plot_wealth_curves(all_results::Dict; filename::String="wealth_curves.png")
    # Colorblind-friendly palette (Wong 2011)
    colors = Dict(
        :LW => RGB(0/255, 114/255, 178/255),      # Blue
        :HUBER => RGB(230/255, 159/255, 0/255),   # Orange
        :TYLER => RGB(204/255, 121/255, 167/255), # Purple
        :EW => RGB(0/255, 0/255, 0/255)           # Black
    )
    linestyles = Dict(:MINCVAR => :solid, :MINVAR => :dash, :BUYHOLD => :dot)

    # Select top strategies only (reduce clutter)
    # Best performer from each estimator + benchmark
    selected_keys = []
    for estimator in [:LW, :HUBER, :TYLER]
        # Get best MINCVAR α95 for this estimator
        best_key = nothing
        best_sharpe = -Inf
        for (key, result) in all_results
            est, strat, α, policy, band = key
            if est == estimator && strat == :MINCVAR && α == 0.95 && policy == :MONTHLY
                _, returns, _, _ = result
                sharpe = mean(returns) / std(returns) * sqrt(252)
                if sharpe > best_sharpe
                    best_sharpe = sharpe
                    best_key = key
                end
            end
        end
        if !isnothing(best_key)
            push!(selected_keys, best_key)
        end
    end
    # Add benchmark
    for (key, result) in all_results
        est, strat, α, policy, band = key
        if strat == :BUYHOLD
            push!(selected_keys, key)
            break
        end
    end

    p = plot(
        xlabel="Data",
        ylabel="Riqueza Acumulada",
        title="Comparação de Desempenho dos Portfólios",
        legend=:outerbottom,
        size=(1200, 700),
        legendcolumns=2,
        bottom_margin=10Plots.mm
    )

    # Add crisis period shading (semi-transparent vertical bands)
    crisis_periods = [
        (Date(2007, 10, 1), Date(2009, 3, 31), "Crise 2008"),
        (Date(2020, 2, 1), Date(2020, 4, 30), "COVID-19"),
        (Date(2022, 1, 1), Date(2022, 10, 31), "Inflação 2022")
    ]

    for (key, result) in all_results
        estimator, strategy, α, policy, band = key

        if key ∉ selected_keys
            continue
        end

        _, returns, wealth, dates = result

        # Add crisis shading (only once, using first valid dates)
        if estimator == :LW && strategy == :MINCVAR
            for (start_date, end_date, label) in crisis_periods
                # Find indices within date range
                crisis_mask = (dates .>= start_date) .& (dates .<= end_date)
                if any(crisis_mask)
                    crisis_dates = dates[crisis_mask]
                    vspan!(p, [minimum(crisis_dates), maximum(crisis_dates)],
                        fillalpha=0.15, fillcolor=:red, label="")
                end
            end
        end

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
            alpha=strategy == :BUYHOLD ? 1.0 : 0.9)
    end

    savefig(p, "fig/$filename")
    return p
end

"""
Plot empirical efficient frontier in (σ, CVaR) space.
Shows all points individually with iso-Sharpe curves and Pareto frontier.
"""
function plot_frontier(
    all_results::Dict,
    α::Float64=0.95;
    filename::String="frontier_95.png"
)
    # Collect all points with metadata (NO clustering)
    all_points = []

    for (key, result) in all_results
        estimator, strategy, strat_α, policy, band = key

        # Only monthly policy (and benchmark), matching α
        if (policy != :MONTHLY && policy != :ANNUAL) || (strategy == :MINCVAR && strat_α != α)
            continue
        end

        _, returns, wealth, _ = result

        σ = std(returns) * sqrt(252)
        cvar = calculate_cvar(returns, α) * sqrt(252)
        μ = mean(returns) * 252  # Annualized return
        sharpe = μ / σ

        label = "$(estimator)-$(string(strategy))"
        if strategy == :MINCVAR
            label *= "-α$(Int(strat_α*100))"
        end

        push!(all_points, (
            σ=σ, cvar=cvar, μ=μ, sharpe=sharpe,
            estimator=estimator, strategy=string(strategy),
            label=label
        ))
    end

    p = plot(
        xlabel="Volatilidade Anualizada",
        ylabel="CVaR Anualizado (α=$α)",
        title="Fronteira Eficiente (Espaço Risco-CVaR)",
        legend=:topright,
        size=(1000, 700),
        legendfontsize=8
    )

    # Add iso-Sharpe curves (diagonal lines: CVaR = offset + Sharpe * σ)
    σ_range = [minimum(p.σ for p in all_points), maximum(p.σ for p in all_points)]
    sharpe_levels = [0.5, 1.0, 1.5, 2.0]

    for sr in sharpe_levels
        # Iso-Sharpe line: μ/σ = SR → μ = SR*σ
        # Approximate CVaR ≈ μ + k*σ (for visualization, use k≈1.5 for α=0.95)
        cvar_line = [sr * σ_val + 1.5 * σ_val for σ_val in σ_range]
        plot!(p, σ_range, cvar_line,
            label="Sharpe=$(sr)",
            linestyle=:dash,
            linewidth=1,
            color=:gray,
            alpha=0.4)
    end

    # Plot all points (color by estimator, shape by strategy)
    colors = Dict(:LW => RGB(0/255, 114/255, 178/255),      # Blue
                  :HUBER => RGB(230/255, 159/255, 0/255),   # Orange
                  :TYLER => RGB(204/255, 121/255, 167/255), # Purple
                  :EW => :black)
    markers = Dict("MINCVAR" => :circle, "MINVAR" => :square, "BUYHOLD" => :star)

    # Group by strategy for legend clarity
    for strat in ["MINCVAR", "MINVAR", "BUYHOLD"]
        strat_points = filter(p -> p.strategy == strat, all_points)
        if isempty(strat_points)
            continue
        end

        for point in strat_points
            scatter!(p, [point.σ], [point.cvar],
                label=point.label,
                color=colors[point.estimator],
                marker=markers[point.strategy],
                markersize=point.strategy == "BUYHOLD" ? 14 : 8,
                alpha=0.8,
                markerstrokewidth=2,
                markerstrokecolor=:black)
        end
    end

    # Highlight Pareto frontier (convex hull of MINCVAR points)
    mincvar_points = filter(p -> p.strategy == "MINCVAR", all_points)
    if length(mincvar_points) >= 2
        # Sort by σ
        sorted_pts = sort(mincvar_points, by=p -> p.σ)
        σ_frontier = [p.σ for p in sorted_pts]
        cvar_frontier = [p.cvar for p in sorted_pts]

        plot!(p, σ_frontier, cvar_frontier,
            label="Fronteira Pareto",
            linewidth=3,
            color=:green,
            alpha=0.5,
            linestyle=:solid)
    end

    savefig(p, "fig/$filename")
    return p
end

"""
Plot stacked area chart of portfolio weights over time.
Groups assets by class to reduce legend clutter.
"""
function plot_allocation_over_time(
    weights_df::DataFrame,
    dates::Vector{Date};
    filename::String="allocation.png",
    strategy_name::String=""
)
    tickers = names(weights_df)[4:end]  # skip date, rebalanced, turnover

    # Define asset classes
    asset_classes = Dict(
        "Ações US" => ["SPY", "IWD", "IWF", "IWM"],
        "Ações Intl" => ["EFA", "EEM", "VWO"],
        "Bonds Treas" => ["TLT", "IEF"],
        "Bonds Corp" => ["LQD", "HYG"],
        "Metais" => ["GLD", "SLV"],
        "Imóveis" => ["VNQ"],
        "Commodities" => ["DBC", "USO"]
    )

    # Use dates from weights_df, not the passed dates vector
    actual_dates = weights_df.date

    # Aggregate weights by asset class
    aggregated_weights = zeros(length(actual_dates), length(asset_classes))
    class_labels = collect(keys(asset_classes))

    for (i, class_name) in enumerate(class_labels)
        class_tickers = asset_classes[class_name]
        # Sum weights for all tickers in this class
        for ticker in class_tickers
            if ticker ∈ tickers
                aggregated_weights[:, i] .+= weights_df[:, ticker]
            end
        end
    end

    # Colorblind-friendly palette by asset class
    colors = [
        RGB(0/255, 114/255, 178/255),      # Blue - US Stocks
        RGB(86/255, 180/255, 233/255),     # Sky Blue - Intl Stocks
        RGB(0/255, 158/255, 115/255),      # Teal - Treasury Bonds
        RGB(0/255, 100/255, 80/255),       # Dark Teal - Corp Bonds
        RGB(240/255, 228/255, 66/255),     # Yellow - Metals
        RGB(213/255, 94/255, 0/255),       # Orange - Real Estate
        RGB(204/255, 121/255, 167/255)     # Purple - Commodities
    ]

    # Build title with strategy name if provided
    title_text = isempty(strategy_name) ?
        "Alocação do Portfólio por Classe de Ativo" :
        "Alocação do Portfólio por Classe de Ativo\n$(strategy_name)"

    p = areaplot(
        actual_dates,
        aggregated_weights,
        labels=permutedims(class_labels),
        xlabel="Data",
        ylabel="Peso",
        title=title_text,
        legend=:outerbottom,
        legendcolumns=4,
        size=(1200, 650),
        palette=colors,
        fillalpha=0.9
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
    strategies_meta = Dict()  # Store strategy type for coloring

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
        strategies_meta[label] = strategy
    end

    # Sort labels by median tail loss (best to worst)
    sorted_labels = sort(labels, by = l -> median(data[l]), rev=true)

    # Assign colors by strategy type
    colors_map = Dict(:MINCVAR => :steelblue, :MINVAR => :seagreen, :BUYHOLD => :gray60)
    colors = [colors_map[strategies_meta[l]] for l in sorted_labels]

    # Create violin plot with transparency and boxplot overlay
    p = violin(
        sorted_labels,
        [data[l] for l in sorted_labels],
        xlabel="Estratégia",
        ylabel="Retorno Diário",
        title="Distribuição das Perdas na Cauda (piores $(Int(α*100))%)",
        legend=false,
        size=(1200, 700),
        xrotation=45,
        bottom_margin=15Plots.mm,
        fillalpha=0.6,  # Transparency for overlaps
        linewidth=0,
        color=colors,
        grid=false  # Remove grid lines that create stripes
    )

    # Overlay boxplot for median/quartiles visibility (only show median line)
    boxplot!(p, sorted_labels, [data[l] for l in sorted_labels],
        fillalpha=0.0,  # Transparent boxes (only show lines)
        linewidth=0,    # No box outline
        whisker_width=0,  # No whiskers
        color=:white,   # Invisible
        outliers=false,  # Don't show outliers
        bar_width=0.8,
        marker=(4, :black, stroke(2, :black))  # Only show median as thick black line
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
        xlabel="Estratégia",
        ylabel="Estimador",
        title="Mapa de Calor: Turnover Anualizado",
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
        xlabel="Estratégia",
        ylabel="Número de Rebalanceamentos",
        title="Eventos de Rebalanceamento por Política",
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
        estimator, strategy, α, policy, band = best_key
        strategy_label = "$(estimator)-$(strategy)-α$(Int(α*100))-$(policy)"
        plot_allocation_over_time(weights_df, dates,
            filename="allocation_best.png",
            strategy_name=strategy_label)
    end

    @info "Plots saved to ./fig/"
end
