using StatsPlots, Plots
using DataFrames, Statistics

include("metrics.jl")

"""
Plot cumulative wealth curves for multiple strategies.
"""
function plot_wealth_curves(all_results::Dict; filename::String="wealth_curves.png")
    p = plot(
        xlabel="Data",
        ylabel="Riqueza Acumulada",
        title="Comparação de Desempenho dos Portfólios",
        legend=:outerbottom,
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
Clusters nearby points to avoid visual clutter.
"""
function plot_frontier(
    all_results::Dict,
    α::Float64=0.95;
    filename::String="frontier_95.png",
    cluster_threshold::Float64=0.005  # 0.5% relative distance
)
    # Collect all points with metadata
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

        push!(all_points, (σ=σ, cvar=cvar, estimator=estimator, strategy=string(strategy)))
    end

    # Cluster nearby points
    clusters = []
    used = Set{Int}()

    for i in 1:length(all_points)
        if i ∈ used
            continue
        end

        p1 = all_points[i]
        cluster_points = [p1]
        cluster_estimators = Set([p1.estimator])
        push!(used, i)

        # Find nearby points (same strategy only)
        for j in (i+1):length(all_points)
            if j ∈ used
                continue
            end

            p2 = all_points[j]

            # Only cluster if same strategy
            if p1.strategy != p2.strategy
                continue
            end

            # Compute relative distance
            dist = sqrt(((p2.σ - p1.σ) / p1.σ)^2 + ((p2.cvar - p1.cvar) / p1.cvar)^2)

            if dist < cluster_threshold
                push!(cluster_points, p2)
                push!(cluster_estimators, p2.estimator)
                push!(used, j)
            end
        end

        # Compute cluster centroid
        σ_mean = mean([p.σ for p in cluster_points])
        cvar_mean = mean([p.cvar for p in cluster_points])

        # Create consolidated label
        estimators_sorted = sort(collect(cluster_estimators), by=string)
        if length(estimators_sorted) == 3
            label = "Robust-$(p1.strategy)"
        elseif length(estimators_sorted) == 2
            label = "$(estimators_sorted[1])/$(estimators_sorted[2])-$(p1.strategy)"
        else
            label = "$(estimators_sorted[1])-$(p1.strategy)"
        end

        push!(clusters, (
            σ=σ_mean,
            cvar=cvar_mean,
            strategy=p1.strategy,
            label=label,
            n_points=length(cluster_points)
        ))
    end

    # Plot clusters
    p = plot(
        xlabel="Volatilidade Anualizada",
        ylabel="CVaR Anualizado (α=$α)",
        title="Fronteira Eficiente (Espaço Risco-CVaR)",
        legend=:outerbottom,
        size=(800, 600)
    )

    colors = Dict("MINCVAR" => :blue, "MINVAR" => :red, "BUYHOLD" => :black)
    markers = Dict("MINCVAR" => :circle, "MINVAR" => :square, "BUYHOLD" => :star)

    for cluster in clusters
        scatter!(p, [cluster.σ], [cluster.cvar],
            label=cluster.label,
            color=colors[cluster.strategy],
            marker=markers[cluster.strategy],
            markersize=cluster.strategy == "BUYHOLD" ? 12 : (6 + 2 * cluster.n_points),
            alpha=0.7,
            markerstrokewidth=2)
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
        xlabel="Data",
        ylabel="Peso",
        title="Alocação do Portfólio ao Longo do Tempo",
        legend=:outerbottom,
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
        xlabel="Estratégia",
        ylabel="Retorno",
        title="Distribuição das Perdas na Cauda (piores $(Int(α*100))%)",
        legend=false,
        size=(1200, 700),
        xrotation=45,
        bottom_margin=15Plots.mm
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
        plot_allocation_over_time(weights_df, dates, filename="allocation_best.png")
    end

    @info "Plots saved to ./fig/"
end
