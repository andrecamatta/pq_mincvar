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
- **Rebalance policies:** Monthly, Bands (2%, 5%, 10%)
- **Transaction costs:** 6.0 bps per side
- **Position limit:** 30% per asset
- **CVaR confidence levels:** α = [0.95, 0.99]
- **Lambda (turnover penalty):** [0.0, 0.0003, 0.001] - Grid search hyperparameter

## Hiperparâmetros Testados

O grid search avaliou 60 configurações estratégicas testando três valores de penalização de turnover (lambda: 0,0, 0,0003, 0,001) combinados com dois métodos de otimização (MINVAR e MINCVAR), três estimadores robustos de covariância (Ledoit-Wolf, Huber, Tyler), dois níveis de confiança para CVaR (α=95%, 99%), e quatro políticas de rebalanceamento (mensal e bandas de 2%, 5%, 10%). MINCVAR, sendo não-paramétrico, utilizou apenas o estimador Ledoit-Wolf, resultando em 24 backtests. MINVAR, paramétrico e dependente da matriz de covariância, testou os três estimadores em 36 backtests, totalizando 60 estratégias avaliadas contra benchmark equal-weight.

## Resultados

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
- Lambda (turnover penalty) hyperparameter

### Best Strategies

**Melhor Sharpe Ratio:**
- **TYLER-MINVAR** (BANDS 10%, λ=0.0003)
- Sharpe: 0.576 | Retorno: 5.92% a.a. | Volatilidade: 7.11%
- Max Drawdown: 23.79% | Turnover: 7.26% a.a.
- Rebalanceamentos: 1 em 18.5 anos

**Melhor Drawdown (menor):**
- **LW-MINVAR** (BANDS 5%, λ=0.0)
- Sharpe: 0.523 | Retorno: 4.96% a.a. | Volatilidade: 6.01%
- Max Drawdown: 15.74% | Turnover: 25.88% a.a.
- Rebalanceamentos: 16

**Benchmark (Equal-Weight):**
- Sharpe: 0.218 | Max Drawdown: 44.60%

### Análise dos Resultados

O backtest com grid search de lambda demonstrou a superioridade das estratégias otimizadas sobre o benchmark passivo. A estratégia TYLER-MINVAR com política BANDS-2% e lambda 0,0003 dominou em termos de retorno ajustado ao risco, alcançando Sharpe de 0,576 (2,6× superior ao benchmark de 0,218). Esta configuração entregou retorno anualizado de 5,92% com volatilidade de apenas 7,11% e turnover extremamente baixo de 7,26% anual.

O sucesso do estimador Tyler decorre de sua robustez a outliers, capturando melhor a estrutura de covariância durante crises. A penalização de turnover (lambda) revelou-se hiperparâmetro crucial: MINVAR maximizou performance com lambda 0,0003 (equilíbrio entre adaptação e custos), enquanto MINCVAR preferiu lambda 0,001 (maior penalização). Sem penalização (lambda 0), estratégias sofreram overtrading severo com turnover de 25-57% anual, degradando Sharpe médio de 0,50 para 0,44-0,48.

Para investidores avessos a perdas extremas, a LW-MINVAR com política BANDS-5% e lambda 0,0 ofereceu proteção superior, limitando o drawdown máximo a apenas 15,74%, substancialmente inferior aos 23,79% da melhor estratégia Sharpe e drasticamente abaixo dos 44,60% do benchmark. Esta estratégia manteve Sharpe competitivo de 0,523 com CVaR-95% de apenas 0,91%, demonstrando que banda intermediária (5%) e livre adaptação (lambda 0) equilibram proteção e desempenho.

O benchmark equal-weight buy-and-hold foi sistematicamente superado: sofreu 2× mais volatilidade (13,3% vs 6-7%), produziu Sharpe 2,6× inferior, e experimentou drawdowns superiores a 44%. As políticas de rebalanceamento por bands (2-10%) provaram-se cruciais, reduzindo drasticamente turnover enquanto preservavam performance. A estratégia vencedora realizou apenas 1 rebalanceamento em 18,5 anos, evidência de que otimização robusta com penalização adequada maximiza eficiência.

### Comparação das Melhores Estratégias

As duas estratégias líderes (uma em Sharpe Ratio e outra em menor max drawdown) revelam filosofias distintas de gestão de risco.

A TYLER-MINVAR BANDS-2% (Sharpe 0,576, lambda 0,0003) demonstrou estabilidade excepcional com apenas um rebalanceamento em 18,5 anos, mantendo alocação constante de 78% em renda fixa (principalmente IEF 30%, LQD 22%, HYG 18%), 13% em ações (IWF, SPY) e 9% em diversificadores (ouro e commodities). Esta configuração quasi-estática atravessou três crises sem ajustes, beneficiando-se da penalização de turnover que impediu movimentações desnecessárias.

Já a LW-MINVAR BANDS-5% (drawdown 15,74%, lambda 0,0) adotou postura defensiva com livre adaptação, realizando 16 rebalanceamentos ao longo do período. Com lambda zero, a estratégia adaptou-se dinamicamente aos regimes de mercado, mantendo turnover de 25,88% anual. Reduziu drawdown em 34% comparado à melhor Sharpe (15,74% vs 23,79%), sacrificando 0,96 pontos de Sharpe (0,523 vs 0,576).

Surpreendentemente, MINCVAR não liderou em drawdown apesar de otimizar diretamente perdas extremas na cauda. A explicação reside na natureza retrospectiva do CVaR: MINCVAR usa cenários históricos da janela de estimação (756 dias), mas drawdowns máximos ocorrem em eventos extremos fora-da-amostra não capturados nessa janela. MINVAR, ao minimizar variância global com estimadores robustos, produz alocações mais conservadoras e estáveis que acidentalmente protegem melhor contra drawdowns futuros.

| Métrica | Melhor Sharpe (TYLER-MINVAR) | Melhor Drawdown (LW-MINVAR) |
|---------|------------------------------|------------------------------|
| **Sharpe** | **0.576** | 0.523 |
| **Lambda** | 0.0003 | 0.0 |
| **MDD** | 23.79% | **15.74%** |
| **Retorno** | **5.92%** | 4.96% |
| **Volatilidade** | 7.11% | **6.01%** |
| **CVaR 95%** | 1.09% | **0.91%** |
| **Turnover** | **7.26%** | 25.88% |
| **Drag (custos)** | **0.44%** | 1.55% |
| **Rebalanceamentos** | **1** | 16 |

## Interpretation

- **Lambda como hiperparâmetro** é crucial: MINVAR ótimo com λ=0.0003, MINCVAR com λ=0.001
- **Tyler estimator** domina em Sharpe Ratio, capturando melhor estrutura de covariância robusta
- **Band policies** eliminam overtrading: BANDS-2/5/10% >> MONTHLY
- **Grid search validou** que penalização diferenciada por estratégia maximiza performance
- **Trade-off Sharpe vs Drawdown**: Proteção adicional (15.74% vs 23.79%) custa 1.11% a.a. em drag
- **MINVAR surpreendentemente** lidera em drawdown (não MINCVAR), devido a generalização out-of-sample
- **Transaction costs** materialmente impactam: turnover 3.6× maior degrada performance mesmo com Sharpe similar

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

Generated on 2025-10-06T08:51:30.192
