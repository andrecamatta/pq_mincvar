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

**Final Assets (16):** ["SPY", "IWD", "IWF", "IWM", "EFA", "EEM", "VWO", "TLT", "IEF", "LQD", "HYG", "GLD", "SLV", "VNQ", "DBC", "USO"]

**Period:** 2007-04-12 to 2025-10-03

**Filter:** ETFs with ≥ 15 years of history

## Parameters

- **Estimation window:** 756 days (~3 years)
- **Rebalance:** End-of-month
- **Policies:** Monthly, Bands (2%, 5%, 10%)
- **Transaction costs:** 6.0 bps per side
- **Position limit:** 30% per asset
- **CVaR confidence levels:** α = [0.95, 0.99]

## Key Findings

### Tail Diagnostics (Multivariate t-distribution)
- LW: ν = 15
- TYLER: ν = 15
- HUBER: ν = 15

### Performance Metrics

See `results/metrics.csv` for detailed metrics including:
- Annualized return and volatility
- Sharpe and Sortino ratios
- VaR and CVaR at 95% and 99% confidence levels
- Maximum drawdown and Ulcer index
- Annualized turnover and number of rebalances

### Best Strategies (by Sharpe Ratio)

Top 5 strategies:
1. TYLER-MINVAR-α0-BANDS: Sharpe=0.576
2. TYLER-MINVAR-α0-BANDS: Sharpe=0.576
3. TYLER-MINVAR-α0-BANDS: Sharpe=0.576
4. LW-MINCVAR-α95-BANDS: Sharpe=0.564
5. LW-MINCVAR-α99-BANDS: Sharpe=0.521

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

**Julia version:** 1.11.7

**Packages:** See `Project.toml`

**Random seed:** Not used (deterministic optimization)

**Execution:** `julia main.jl`

---

Generated on 2025-10-05T21:46:47.731
