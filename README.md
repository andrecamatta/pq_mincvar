# Min-CVaR Portfolio Optimization with Robust Estimators

[![Julia](https://img.shields.io/badge/Julia-1.11+-9558B2?style=flat&logo=julia&logoColor=white)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Implementação e backtest de estratégias de otimização de portfólio comparando Min-CVaR (Conditional Value-at-Risk) vs Min-Variance com estimadores robustos de covariância.**

## 📊 Resumo

Este projeto implementa e compara estratégias de otimização de portfólio usando:

- **Min-CVaR**: Minimização de Conditional Value-at-Risk (Rockafellar-Uryasev)
- **Min-Var**: Minimização de Variância (QP via OSQP)

Com três estimadores robustos de covariância:
- **LW (Ledoit-Wolf)**: Oracle Approximating Shrinkage (OAS)
- **HUBER**: Huber M-estimator para média + OAS covariance
- **TYLER**: Tyler M-estimator para scatter matrix (robusto a caudas pesadas)

## 🎯 Principais Resultados

### Estratégia Vencedora: HUBER-MINCVAR-α95-BANDS-10%

| Métrica | Valor | vs Benchmark |
|---------|-------|--------------|
| **Sharpe Ratio** | 0.532 | +146% |
| **Retorno Anual** | 5.08% | +8% |
| **Volatilidade** | 6.14% | -54% |
| **Max Drawdown** | 16.0% | -64% |
| **CVaR 95%** | 0.92% | -56% |
| **Rebalances (15 anos)** | 5 | -72% |

**Composição média do portfólio:**
- 84% Renda Fixa (IEF 30%, HYG 26%, LQD 20%, TLT 8%)
- 12% Hedge (GLD 7%, DBC 5%)
- 3% Equity (SPY, IWF, IWM, IWD)

## 🚀 Quick Start

### Pré-requisitos

```bash
# Julia 1.11+
# Conta no Tiingo (API gratuita): https://www.tiingo.com/
```

### Instalação

```bash
git clone https://github.com/andrecamatta/pq_mincvar.git
cd pq_mincvar

# Criar arquivo .env com seu token do Tiingo
echo "TIINGO_TOKEN=seu_token_aqui" > .env

# Instalar dependências
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Execução

```bash
julia main.jl
```

Os resultados serão salvos em:
- `results/metrics.csv` - Métricas de performance
- `results/weights_*.csv` - Pesos dos portfólios ao longo do tempo
- `fig/` - Gráficos de análise

## 📁 Estrutura do Projeto

```
pq_mincvar/
├── main.jl                 # Script principal
├── src/
│   ├── data.jl            # Download e preparação de dados
│   ├── estimators.jl      # Estimadores robustos (LW, Huber, Tyler)
│   ├── optimization.jl    # Solvers Min-CVaR e Min-Var
│   ├── backtest.jl        # Engine de backtesting
│   ├── metrics.jl         # Cálculo de métricas de performance
│   ├── plots.jl           # Geração de gráficos
│   └── benchmarks.jl      # Estratégias de benchmark
├── results/               # Resultados dos backtests
├── fig/                   # Gráficos gerados
└── README.md
```

## 🔬 Metodologia

### Universo de Ativos

16 ETFs diversificados com ≥15 anos de histórico:
- **US Equity**: SPY, IWD, IWF, IWM
- **International**: EFA, EEM, VWO
- **Fixed Income**: TLT, IEF, LQD, HYG
- **Alternatives**: GLD, SLV, VNQ, DBC, USO

**Período**: Abril/2007 - Setembro/2025 (4,648 dias)

### Parâmetros de Backtesting

| Parâmetro | Valor |
|-----------|-------|
| Janela de estimação | 756 dias (~3 anos) |
| Políticas de rebalanceamento | MONTHLY, BANDS (2%, 5%, 10%) |
| Níveis de confiança CVaR | α = 95%, 99% |
| Custos de transação | 10 bps por lado |
| Penalidade de turnover | λ = 0.001 |
| Limite por ativo | 30% |

### Estratégias Implementadas

36 combinações testadas:
- 3 estimadores × 2 estratégias × 2 alphas × 4 políticas = 36 estratégias
- \+ 1 benchmark Equal-Weight Buy-and-Hold

## 📈 Análise de Resultados

### 1. Diagnóstico de Caudas (Multivariate t-distribution)

```
LW:    ν = 15 (caudas moderadamente pesadas)
HUBER: ν = 15
TYLER: ν = 15
```

### 2. Comparação de Matrizes de Covariância

```
LW vs HUBER:  0.0% diferença
LW vs TYLER:  20.84% diferença
HUBER vs TYLER: 20.84% diferença
```

Tyler captura estrutura de correlação diferente devido à robustez a outliers.

### 3. Top 5 Estratégias (por Sharpe Ratio)

1. **HUBER-MINCVAR-α95-BANDS-10%**: Sharpe 0.532
2. **TYLER-MINCVAR-α95-BANDS-10%**: Sharpe 0.532
3. **LW-MINCVAR-α95-BANDS-10%**: Sharpe 0.532
4. **HUBER-MINCVAR-α95-BANDS-2%**: Sharpe 0.517
5. **TYLER-MINCVAR-α95-BANDS-2%**: Sharpe 0.517

### 4. Comparação com Benchmarks

| Estratégia | Retorno | Sharpe | MDD | Rebalances |
|------------|---------|--------|-----|------------|
| **SHY (1-3Y Treasury)** | 1.81% | ~0.50 | ~2% | N/A |
| **Winner** | 5.08% | 0.532 | 16.0% | 5 |
| **Equal-Weight** | 4.69% | 0.216 | 44.6% | 18 |

**Winner vs SHY**: +3.27% ao ano (2.8× retorno) com Sharpe similar

## 🔑 Principais Insights

### 1. **Política de Bands é Superior**
- Bands de 10% reduzem turnover em 90% vs Monthly
- Performance similar com muito menos custos de transação
- Apenas 5 rebalances em 15 anos (Winner)

### 2. **Min-CVaR > Min-Var em Crises**
- Max drawdown 16% vs 27% (Min-Var)
- Melhor proteção de downside (Sortino 0.68 vs 0.45)
- CVaR 95% de 0.92% vs 1.87%

### 3. **Estimadores Robustos Funcionam**
- Tyler reduz tail risk quando ν < 10
- Diferença de 20% nas matrizes de covariância
- Performance similar entre LW/HUBER/TYLER neste dataset (ν=15)

### 4. **Concentração em Fixed Income**
- 84% alocação em bonds (Winner)
- Volatilidade de apenas 6% vs 13% (benchmark)
- Estratégia "enhanced cash" adequada para perfil conservador

## 🛠️ Tecnologias e Algoritmos

### Otimização
- **Min-CVaR**: Formulação LP de Rockafellar-Uryasev
- **Min-Var**: QP com [OSQP](https://osqp.org/) (3600× mais rápido que HiGHS)
- Restrições: sum(w)=1, w≥0, w≤0.30, turnover penalty

### Estimadores Robustos
- **OAS**: Oracle Approximating Shrinkage (Ledoit-Wolf)
- **Huber**: M-estimator iterativo (threshold c=1.345)
- **Tyler**: Fixed-point algorithm com scaling para variância amostral

### Performance Metrics
- Sharpe, Sortino, VaR, CVaR (95%, 99%)
- Max Drawdown, Ulcer Index
- Annualized Turnover, Rebalance Count

## 📊 Gráficos Gerados

- `wealth_curves.png` - Curvas de riqueza comparativas
- `frontier_95.png`, `frontier_99.png` - Fronteiras eficientes
- `tail_losses_*.png` - Distribuição de perdas na cauda
- `turnover_heatmap.png` - Heatmap de turnover
- `allocation_winner.png` - Alocação temporal do vencedor

## 🔧 Customização

Para modificar parâmetros, edite `main.jl`:

```julia
config = Dict(
    "tickers" => ["SPY", "TLT", ...],
    "window_size" => 756,           # Janela de estimação
    "estimators" => [:LW, :HUBER, :TYLER],
    "strategies" => [:MINCVAR, :MINVAR],
    "alphas" => [0.95, 0.99],
    "policies" => [:MONTHLY, :BANDS],
    "bands" => [0.02, 0.05, 0.10],
    "cost_bps" => 10.0,             # Custos de transação
    "lambda" => 0.001,              # Penalidade de turnover
    "max_weight" => 0.30            # Limite por ativo
)
```

## 📚 Referências

- Rockafellar, R. T., & Uryasev, S. (2000). Optimization of conditional value-at-risk. *Journal of Risk*, 2, 21-42.
- Ledoit, O., & Wolf, M. (2004). A well-conditioned estimator for large-dimensional covariance matrices. *Journal of Multivariate Analysis*, 88(2), 365-411.
- Tyler, D. E. (1987). A distribution-free M-estimator of multivariate scatter. *The Annals of Statistics*, 15(1), 234-251.
- Huber, P. J. (1964). Robust estimation of a location parameter. *The Annals of Mathematical Statistics*, 35(1), 73-101.

## 📄 Licença

MIT License - veja [LICENSE](LICENSE) para detalhes.

## 👤 Autor

**André Camatta**

- GitHub: [@andrecamatta](https://github.com/andrecamatta)

## 🙏 Agradecimentos

- [Tiingo](https://www.tiingo.com/) pela API de dados financeiros
- [OSQP](https://osqp.org/) pelo solver QP ultra-rápido
- Comunidade Julia pelo ecossistema excelente

---

**⭐ Se este projeto foi útil, considere dar uma estrela no GitHub!**
