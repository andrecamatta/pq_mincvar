using LinearAlgebra, Statistics, StatsBase

"""
Oracle Approximating Shrinkage (OAS) estimator for covariance matrix.
Shrinks sample covariance towards τ*I where τ = tr(S)/p.

Reference: Chen et al. (2010) "Shrinkage Algorithms for MMSE Covariance Estimation"
"""
function oas_shrinkage(X::Matrix{Float64})
    n, p = size(X)

    # Sample covariance
    S = cov(X, dims=1, corrected=true)

    # Target: scaled identity
    τ = tr(S) / p

    # OAS shrinkage intensity (simplified formula)
    tr_S2 = sum(S .^ 2)
    tr_S_sq = tr(S)^2 / p

    num = (1 - 2/p) * tr_S2 + tr_S_sq
    den = (n + 1 - 2/p) * (tr_S2 - tr_S_sq / p)

    ρ = min(1.0, max(0.0, num / den))

    # Shrunk covariance
    Σ_shrunk = (1 - ρ) * S + ρ * τ * I(p)

    return Σ_shrunk, ρ
end

"""
OAS shrinkage for pre-centered data (does NOT re-center).
Use this when data has already been centered by a robust estimator.
"""
function oas_shrinkage_precentered(X_centered::Matrix{Float64})
    n, p = size(X_centered)

    # Compute covariance matrix manually (without re-centering)
    S = (X_centered' * X_centered) / (n - 1)

    # Target: scaled identity
    τ = tr(S) / p

    # OAS shrinkage intensity (simplified formula)
    tr_S2 = sum(S .^ 2)
    tr_S_sq = tr(S)^2 / p

    num = (1 - 2/p) * tr_S2 + tr_S_sq
    den = (n + 1 - 2/p) * (tr_S2 - tr_S_sq / p)

    ρ = min(1.0, max(0.0, num / den))

    # Shrunk covariance
    Σ_shrunk = (1 - ρ) * S + ρ * τ * I(p)

    return Σ_shrunk, ρ
end

"""
Huber M-estimator for robust mean estimation.

k: tuning constant (typically 1.345 for 95% efficiency under normality)
"""
function huber_mean(x::Vector{Float64}; k::Float64=1.345, max_iter::Int=100, tol::Float64=1e-6)
    μ = median(x)
    σ = mad(x, normalize=true)  # MAD as robust scale estimate

    if σ < 1e-10
        return μ
    end

    for iter in 1:max_iter
        residuals = (x .- μ) / σ
        weights = min.(1.0, k ./ abs.(residuals))
        weights[isnan.(weights)] .= 1.0

        μ_new = sum(weights .* x) / sum(weights)

        if abs(μ_new - μ) < tol
            return μ_new
        end

        μ = μ_new
    end

    return μ
end

"""
Tyler's M-estimator for robust covariance (shape matrix).

Returns a covariance matrix with trace normalized to p.
Iterative fixed-point algorithm.

Reference: Tyler (1987) "A distribution-free M-estimator of multivariate scatter"
"""
function tyler_estimator(X::Matrix{Float64}; max_iter::Int=500, tol::Float64=1e-6)
    n, p = size(X)

    # Center by column medians
    X_centered = X .- median(X, dims=1)

    # Initialize with sample covariance
    Σ = cov(X_centered, dims=1, corrected=false)
    Σ = p * Σ / tr(Σ)  # normalize trace to p

    for iter in 1:max_iter
        # Compute Mahalanobis distances
        Σ_inv = inv(Σ)
        d2 = zeros(n)
        for i in 1:n
            xi = X_centered[i, :]
            d2[i] = dot(xi, Σ_inv * xi)
        end

        # Update scatter matrix
        Σ_new = zeros(p, p)
        for i in 1:n
            xi = X_centered[i, :]
            Σ_new += (xi * xi') / d2[i]
        end
        Σ_new = (p / n) * Σ_new

        # Normalize trace
        Σ_new = p * Σ_new / tr(Σ_new)

        # Check convergence
        if norm(Σ_new - Σ, 2) / norm(Σ, 2) < tol
            @debug "Tyler estimator converged in $iter iterations"
            return Σ_new
        end

        Σ = Σ_new
    end

    @warn "Tyler estimator did not converge after $max_iter iterations"
    return Σ
end

"""
Estimate mean and covariance using specified robust estimator.

estimator: :LW (Ledoit-Wolf/OAS), :HUBER (Huber mean + OAS), :TYLER (Tyler scatter + shrink)
"""
function robust_estimate(X::Matrix{Float64}, estimator::Symbol)
    n, p = size(X)

    if estimator == :LW
        # Standard: sample mean + OAS shrinkage
        μ = vec(mean(X, dims=1))
        Σ, ρ = oas_shrinkage(X)
        @debug "OAS: shrinkage intensity ρ = $(round(ρ, digits=4))"

    elseif estimator == :HUBER
        # Huber robust mean + OAS covariance
        μ = [huber_mean(X[:, j]) for j in 1:p]
        X_centered = X .- μ'
        Σ, ρ = oas_shrinkage_precentered(X_centered)
        @debug "HUBER: shrinkage intensity ρ = $(round(ρ, digits=4))"

    elseif estimator == :TYLER
        # Median centering + Tyler M-estimator + shrinkage
        μ = vec(median(X, dims=1))
        X_centered = X .- μ'

        # Get Tyler shape matrix (normalized to tr(Σ) = p) - use CENTERED data
        Σ_tyler = tyler_estimator(X_centered)

        # Rescale to match data scale
        # Tyler gives shape (correlation structure), need to add scale back
        sample_scale = mean(diag(cov(X_centered, dims=1, corrected=false)))
        Σ_tyler_scaled = Σ_tyler * sample_scale

        # Apply light shrinkage with correct scale
        τ = sample_scale  # Shrink towards scaled identity
        δ = 0.1
        Σ = (1 - δ) * Σ_tyler_scaled + δ * τ * I(p)
        @debug "TYLER: rescaled by $(round(sample_scale, digits=6)), shrinkage δ = $δ"

    else
        error("Unknown estimator: $estimator. Use :LW, :HUBER, or :TYLER")
    end

    return μ, Σ
end

"""
Fit multivariate t-distribution for tail diagnostics (grid search over ν).
Returns estimated degrees of freedom.
"""
function fit_multivariate_t(X::Matrix{Float64}; ν_grid=3:15)
    n, p = size(X)

    μ = vec(mean(X, dims=1))
    Σ = cov(X, dims=1)

    best_ν = 0
    best_loglik = -Inf

    for ν in ν_grid
        # Simplified log-likelihood for MVT (not exact, for diagnostic purposes)
        Σ_inv = inv(Σ)
        loglik = 0.0

        for i in 1:n
            xi = X[i, :]
            d2 = dot(xi - μ, Σ_inv * (xi - μ))
            loglik += log((1 + d2 / ν)^(-(ν + p) / 2))
        end

        if loglik > best_loglik
            best_loglik = loglik
            best_ν = ν
        end
    end

    return best_ν
end
