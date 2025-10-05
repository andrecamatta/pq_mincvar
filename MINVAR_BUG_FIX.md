# MINVAR Turnover Bug - Root Cause and Solution

## Problem Summary

MINVAR strategies were showing **near-zero turnover** (~0.003% annualized) despite:
- 187 monthly rebalances
- Band policies never triggering rebalances
- Weights stuck at equal-weight (1/16 for all assets)

Meanwhile, MINCVAR strategies showed **realistic turnover** (16-35% annualized).

## Root Cause Analysis

### Investigation Steps

1. **Initial Observation**: Debug logging revealed MINVAR weights were always `[0.0625, 0.0625, ...]` (equal-weight)

2. **Hypothesis Testing**: Created synthetic data to test if:
   - Optimization was broken → ❌ (worked fine with synthetic Σ)
   - Constraints were too restrictive → ❌ (worked fine without constraints)
   - Real covariance matrix was problematic → ❌ (manual test showed 88% variance reduction was possible)

3. **Critical Discovery**: Testing λ (turnover penalty) sensitivity revealed:
   ```julia
   λ = 0.0:    Var = 2.377e-5  (optimal, 88% reduction)
   λ = 0.001:  Var = 0.00020082 (equal-weight, NO reduction!)
   λ = 0.01:   Var = 0.00020082 (equal-weight, NO reduction!)
   ```

### Root Cause

The **turnover penalty coefficient λ=0.001 was too large** relative to the variance improvement for MINVAR:

- **Variance improvement**: ~0.0002 (from equal-weight to optimal)
- **Turnover cost**: λ × turnover = 0.001 × 1.16 = **0.00116**
- **Economic trade-off**: Cost (0.00116) > Benefit (0.0002) → **Optimal to stay at equal-weight!**

The solver was **correctly** minimizing the objective:
```
min  w'Σw + λ·turnover
```

By choosing `turnover = 0` (staying at 1/16), it avoided paying the penalty.

### Why MINCVAR Wasn't Affected

MINCVAR has much larger CVaR improvements (~0.01 for CVaR vs ~0.0002 for variance), so the same λ=0.001 didn't cause the same lock-in problem.

## Solution

Modified [src/backtest.jl](src/backtest.jl) to **disable turnover penalty on first rebalance**:

```julia
# Determine effective lambda (zero on first rebalance to avoid getting stuck at equal-weight)
is_first_rebalance = all(w_strategic .≈ ones(p)/p)
λ_eff = is_first_rebalance ? 0.0 : λ
```

**Rationale:**
- First rebalance (from equal-weight) needs to find the optimal portfolio **without** penalty
- Subsequent rebalances use λ to penalize excessive trading
- This mirrors real-world behavior: initial allocation is "free" of turnover concerns

## Results After Fix

**Before:**
- MINVAR turnover: ~0.003% annually
- Weights: Always [0.0625, 0.0625, ...] (equal-weight)
- Variance reduction: 0%

**After:**
- LW MINVAR (MONTHLY): 1.05% turnover ✅
- HUBER MINVAR (BANDS): 1.13% turnover ✅
- TYLER MINVAR (MONTHLY): 0.95% turnover ✅
- Weights: Diverse, non-equal (e.g., [0, 0, 0.097, 0.013, ...])
- Variance reduction: Up to 88%

## Lessons Learned

1. **Scale-dependent parameters**: A penalty coefficient (λ) must be calibrated to the **scale of the objective function**. MINVAR (variance ~1e-4) and MINCVAR (CVaR ~1e-2) operate at different scales.

2. **First-rebalance problem**: Starting from equal-weight with turnover penalties can create a **local minimum trap**. Disabling the penalty initially allows finding the global optimum.

3. **Economic interpretation**: The solver's "bug" was actually **economically rational** given the objective function. The fix ensures we get the intended behavior.

## Alternative Solutions Considered

1. **Lower λ for MINVAR** (e.g., 0.0001): Would work, but requires strategy-specific tuning
2. **Scale-invariant penalty**: Normalize by objective value, but adds complexity
3. **Initial optimization without penalty**: ✅ **Chosen** - Simple, interpretable, and works for all strategies

---

**Fixed in:** 2025-10-05
**Commit:** (pending)
