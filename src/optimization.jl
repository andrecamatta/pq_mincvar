using JuMP, HiGHS, OSQP, LinearAlgebra, SparseArrays

"""
Min-CVaR optimization using Rockafellar-Uryasev LP formulation.

α: confidence level (0.95 or 0.99)
R: matrix of scenario returns (T × p)
w_prev: previous weights (for turnover penalty)
λ: turnover penalty coefficient
max_weight: maximum weight per asset
"""
function optimize_mincvar(
    R::Matrix{Float64},
    α::Float64;
    w_prev::Vector{Float64} = Float64[],
    λ::Float64 = 0.0,
    max_weight::Float64 = 0.30
)
    T, p = size(R)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    # Variables
    @variable(model, w[1:p] >= 0)
    @variable(model, ζ)  # VaR
    @variable(model, u[1:T] >= 0)  # CVaR auxiliary variables

    # Turnover variables (if w_prev provided)
    if !isempty(w_prev)
        @variable(model, z[1:p] >= 0)
        for i in 1:p
            @constraint(model, z[i] >= w[i] - w_prev[i])
            @constraint(model, z[i] >= w_prev[i] - w[i])
        end
    end

    # CVaR constraints: u_t >= -r_t' * w - ζ
    for t in 1:T
        @constraint(model, u[t] >= -sum(R[t, i] * w[i] for i in 1:p) - ζ)
    end

    # Budget constraint
    @constraint(model, sum(w) == 1)

    # Position limits
    for i in 1:p
        @constraint(model, w[i] <= max_weight)
    end

    # Objective: minimize CVaR + turnover penalty
    if !isempty(w_prev)
        @objective(model, Min, ζ + (1 / ((1 - α) * T)) * sum(u) + λ * sum(z))
    else
        @objective(model, Min, ζ + (1 / ((1 - α) * T)) * sum(u))
    end

    optimize!(model)

    if termination_status(model) != MOI.OPTIMAL
        @warn "Min-CVaR optimization did not converge: $(termination_status(model))"
        return zeros(p), Inf
    end

    w_opt = value.(w)
    cvar_opt = objective_value(model)

    return w_opt, cvar_opt
end

"""
Minimum Variance optimization using OSQP (fast QP solver).

Σ: covariance matrix (p × p)
w_prev: previous weights (for turnover penalty)
λ: turnover penalty coefficient
max_weight: maximum weight per asset
"""
function optimize_minvar(
    Σ::Matrix{Float64};
    w_prev::Vector{Float64} = Float64[],
    λ::Float64 = 0.0,
    max_weight::Float64 = 0.30
)
    p = size(Σ, 1)

    # Setup QP problem with turnover penalty
    # Extended problem: min w'Σw + λΣz_i  s.t. z_i >= |w_i - w_prev[i]|
    # Variables: [w; z] where z_i are turnover auxiliary variables

    if !isempty(w_prev) && λ > 0
        # Extended QP: [w; z] where z_i >= |w_i - w_prev[i]|
        # P = [2Σ    0  ]  (2p × 2p)
        #     [0   λI  ]
        # Note: OSQP minimizes (1/2)x'Px + q'x, so we need P=2Σ for variance
        # and we add λz directly via q vector

        P_upper = sparse([2.0 * Σ spzeros(p, p)])
        P_lower = sparse([spzeros(p, p) spzeros(p, p)])  # No quadratic term for z
        P = sparse([P_upper; P_lower])

        # Linear term: add λ to z variables
        q = [zeros(p); fill(λ, p)]

        # Constraints on [w; z]:
        # 1. sum(w) = 1
        # 2. 0 <= w_i <= max_weight
        # 3. z_i >= w_i - w_prev[i]  (z >= Δw)
        # 4. z_i >= w_prev[i] - w_i  (z >= -Δw)
        # 5. z_i >= 0

        A_budget = sparse([ones(1, p) zeros(1, p)])  # sum(w) = 1
        A_w_bounds = sparse([I(p) spzeros(p, p); -I(p) spzeros(p, p)])  # w bounds
        A_z_pos = sparse([spzeros(p, p) I(p)])  # z >= 0
        A_z_turnover1 = sparse([-I(p) I(p)])  # z >= w - w_prev → -w + z >= -w_prev
        A_z_turnover2 = sparse([I(p) I(p)])   # z >= w_prev - w → w + z >= w_prev

        A = sparse([A_budget; A_w_bounds; A_z_pos; A_z_turnover1; A_z_turnover2])

        l = [1.0;                          # sum(w) = 1
             zeros(p);                      # w >= 0
             fill(-Inf, p);                 # -w unbounded below
             zeros(p);                      # z >= 0
             -w_prev;                       # -w + z >= -w_prev
             w_prev]                        # w + z >= w_prev

        u = [1.0;                          # sum(w) = 1
             fill(max_weight, p);           # w <= max_weight
             zeros(p);                      # -w <= 0
             fill(Inf, p);                  # z unbounded above
             fill(Inf, p);                  # -w + z unbounded above
             fill(Inf, p)]                  # w + z unbounded above
    else
        # Standard QP without turnover
        P = sparse(2.0 * Σ)
        q = zeros(p)

        A_eq = sparse(ones(1, p))  # sum(w) = 1
        A_ineq = sparse([I(p); -I(p)])  # w >= 0 and w <= max_weight
        A = sparse([A_eq; A_ineq])

        l = [1.0; zeros(p); fill(-Inf, p)]
        u = [1.0; fill(max_weight, p); zeros(p)]
    end

    # Solve with OSQP
    model = OSQP.Model()
    OSQP.setup!(model; P=P, q=q, A=A, l=l, u=u,
                verbose=false, eps_abs=1e-6, eps_rel=1e-6)
    results = OSQP.solve!(model)

    if results.info.status != :Solved
        @warn "Min-Var optimization did not converge: $(results.info.status)"
        return zeros(p), Inf
    end

    # Extract weights (first p elements)
    w_opt = results.x[1:p]
    var_opt = w_opt' * Σ * w_opt

    return w_opt, var_opt
end

"""
Maximum Sharpe ratio optimization (alternative to Min-Var).

μ: expected returns (p × 1)
Σ: covariance matrix (p × p)
rf: risk-free rate (default 0)
w_prev: previous weights (for turnover penalty)
λ: turnover penalty coefficient
max_weight: maximum weight per asset
"""
function optimize_maxsharpe(
    μ::Vector{Float64},
    Σ::Matrix{Float64};
    rf::Float64 = 0.0,
    w_prev::Vector{Float64} = Float64[],
    λ::Float64 = 0.0,
    max_weight::Float64 = 0.30
)
    p = length(μ)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    # Variables (rescaled problem)
    @variable(model, y[1:p] >= 0)
    @variable(model, κ >= 1e-6)  # auxiliary variable

    # Turnover variables (if w_prev provided)
    if !isempty(w_prev)
        @variable(model, z[1:p] >= 0)
        for i in 1:p
            @constraint(model, z[i] >= y[i]/κ - w_prev[i])
            @constraint(model, z[i] >= w_prev[i] - y[i]/κ)
        end
    end

    # Budget constraint (rescaled): μ' y = 1
    @constraint(model, sum((μ[i] - rf) * y[i] for i in 1:p) == 1)

    # Variance constraint (rescaled): y' Σ y = κ²
    @constraint(model, sum(y[i] * Σ[i, j] * y[j] for i in 1:p, j in 1:p) == κ^2)

    # Position limits (rescaled)
    for i in 1:p
        @constraint(model, y[i] <= max_weight * κ)
    end

    # Objective: minimize variance (κ²) + turnover penalty
    if !isempty(w_prev)
        @objective(model, Min, κ^2 + λ * sum(z))
    else
        @objective(model, Min, κ^2)
    end

    optimize!(model)

    if termination_status(model) != MOI.OPTIMAL
        @warn "Max-Sharpe optimization did not converge: $(termination_status(model))"
        return zeros(p), -Inf
    end

    κ_opt = value(κ)
    w_opt = value.(y) / κ_opt

    return w_opt, 1.0 / κ_opt  # Sharpe ratio
end
