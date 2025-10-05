# Julia Project: Min-CVaR with Robust Estimators

## Commands
- Run full analysis: `julia main.jl`
- Run quick test: `julia test_quick.jl`
- Activate environment: `julia --project -e "using Pkg; Pkg.activate(\".\")"`
- Install packages: `julia --project -e "using Pkg; Pkg.instantiate()"`

## Code Style

### Imports & Structure
- Use explicit imports at top of files
- Include modules with `include("src/module.jl")` in main scripts
- Organize code in src/ directory by functionality

### Naming Conventions
- Functions: `snake_case()` (e.g., `load_data`, `optimize_mincvar`)
- Variables: `snake_case` (e.g., `returns_df`, `window_size`)
- Constants: `UPPER_CASE` (e.g., `MAX_WEIGHT`)
- Types: `PascalCase` (e.g., `DataFrame`, `Matrix{Float64}`)

### Types & Performance
- Use explicit types for function parameters and returns
- Prefer `Matrix{Float64}` over generic `Matrix`
- Use `Vector{T}` instead of 1D arrays
- Leverage Julia's multiple dispatch for different estimator types

### Error Handling
- Use `try/catch` blocks for external API calls
- Use `@warn` for non-critical issues
- Use `error()` for critical failures
- Check data validity with assertions

### Optimization
- Use JuMP for mathematical optimization
- Set `set_silent(model)` for clean output
- Use HiGHS solver for LP problems
- Prefer OSQP for QP problems when available