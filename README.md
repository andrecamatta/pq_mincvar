# Min-CVaR Portfolio Optimization with Robust Estimators

[![Julia](https://img.shields.io/badge/Julia-1.11+-9558B2?style=flat&logo=julia&logoColor=white)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Implementação e backtest de estratégias de otimização de portfólio comparando Min-CVaR (Conditional Value-at-Risk) vs Min-Variance com estimadores robustos de covariância.**

## 📊 Descrição

Este projeto implementa um sistema completo de otimização e backtesting de portfólios utilizando:

### Estratégias de Otimização

- **Min-CVaR**: Minimização de Conditional Value-at-Risk usando formulação LP de Rockafellar-Uryasev
- **Min-Var**: Minimização de Variância usando QP com solver OSQP

### Estimadores de Covariância

- **LW (Ledoit-Wolf)**: Oracle Approximating Shrinkage (OAS)
- **HUBER**: Huber M-estimator para média + OAS covariance
- **TYLER**: Tyler M-estimator para scatter matrix (robusto a outliers e caudas pesadas)

## 🚀 Instalação

### Pré-requisitos

- **Julia 1.11+**: [Download aqui](https://julialang.org/downloads/)
- **Conta Tiingo**: API gratuita para dados financeiros - [Registre-se aqui](https://www.tiingo.com/)

### Setup do Projeto

1. Clone o repositório:
```bash
git clone https://github.com/andrecamatta/pq_mincvar.git
cd pq_mincvar
```

2. Crie o arquivo `.env` com seu token do Tiingo:
```bash
echo "TIINGO_TOKEN=seu_token_aqui" > .env
```

3. Instale as dependências Julia:
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## 📖 Como Executar

### Execução Básica

Para rodar o backtest completo com configuração padrão:

```bash
julia main.jl
```

O programa irá:
1. Baixar dados históricos de ETFs via API Tiingo
2. Filtrar ativos com ≥15 anos de histórico
3. Executar diagnóstico de caudas (multivariate t-distribution)
4. Rodar 36 backtests (3 estimadores × 2 estratégias × 2 alphas × 4 políticas)
5. Calcular métricas de performance
6. Gerar gráficos de análise
7. Salvar resultados em `results/` e `fig/`

### Saídas Geradas

Após a execução, você encontrará:

```
pq_mincvar/
├── results/
│   ├── metrics.csv              # Métricas de todas as estratégias
│   └── weights_*.csv            # Pesos dos portfólios ao longo do tempo
├── fig/
│   ├── wealth_curves.png        # Curvas de riqueza acumulada
│   ├── frontier_95.png          # Fronteira eficiente (α=95%)
│   ├── frontier_99.png          # Fronteira eficiente (α=99%)
│   ├── tail_losses_5pct.png     # Distribuição de perdas (5% cauda)
│   ├── tail_losses_1pct.png     # Distribuição de perdas (1% cauda)
│   ├── turnover_heatmap.png     # Heatmap de turnover
│   └── allocation_*.png         # Alocação temporal dos portfólios
└── README.md                    # Gerado automaticamente com resumo
```

## ⚙️ Configuração

### Parâmetros Principais

Edite o dicionário `config` em `main.jl` para customizar:

```julia
config = Dict(
    # Universo de ativos
    "tickers" => ["SPY", "IWD", "IWF", "IWM", "EFA", "EEM", "VWO",
                  "TLT", "IEF", "LQD", "HYG", "GLD", "SLV", "VNQ",
                  "DBC", "USO"],

    # Filtros de dados
    "start_date" => Date(2002, 1, 1),
    "min_years" => 15,              # Anos mínimos de histórico
    "qc_threshold" => 0.5,          # Threshold para quality control

    # Backtest
    "window_size" => 756,           # Janela de estimação (~3 anos)
    "estimators" => [:LW, :HUBER, :TYLER],
    "strategies" => [:MINCVAR, :MINVAR],
    "alphas" => [0.95, 0.99],       # Níveis de confiança CVaR
    "policies" => [:MONTHLY, :BANDS],
    "bands" => [0.02, 0.05, 0.10],  # Bandas de rebalanceamento

    # Custos e restrições
    "cost_bps" => 10.0,             # Custos de transação (bps)
    "lambda" => 0.001,              # Penalidade de turnover
    "max_weight" => 0.30            # Peso máximo por ativo
)
```

### Adicionar Novos Ativos

Para incluir outros ETFs, adicione os tickers ao vetor `"tickers"`:

```julia
"tickers" => ["SPY", "QQQ", "IWM", "AGG", ...]
```

**Nota**: Certifique-se que os ativos estão disponíveis no Tiingo e atendem ao critério de `min_years`.

### Modificar Políticas de Rebalanceamento

As políticas disponíveis são:

- **`:MONTHLY`**: Rebalanceia todo fim de mês
- **`:BANDS`**: Rebalanceia apenas quando deriva > banda especificada

Para alterar as bandas testadas:

```julia
"bands" => [0.05, 0.15, 0.20]  # Testa bands de 5%, 15%, 20%
```

### Ajustar Níveis de CVaR

```julia
"alphas" => [0.90, 0.95, 0.99]  # Testa CVaR a 90%, 95%, 99%
```

## 📁 Estrutura do Código

```
pq_mincvar/
├── main.jl                      # Script principal de execução
├── src/
│   ├── data.jl                  # Download e preparação de dados
│   ├── estimators.jl            # Implementação dos estimadores robustos
│   ├── optimization.jl          # Solvers Min-CVaR (LP) e Min-Var (QP)
│   ├── backtest.jl              # Engine de backtesting
│   ├── metrics.jl               # Cálculo de métricas de performance
│   ├── plots.jl                 # Geração de gráficos
│   └── benchmarks.jl            # Estratégias de benchmark
├── Project.toml                 # Dependências Julia
├── .env                         # Token Tiingo (não versionado)
└── README.md
```

### Módulos Principais

#### `src/data.jl`
- `download_tiingo_eod()`: Baixa preços ajustados via API
- `download_risk_free_rate()`: Baixa taxa livre de risco (SHY)
- `calculate_returns()`: Calcula log-returns com quality control
- `filter_by_history()`: Filtra ativos por histórico mínimo

#### `src/estimators.jl`
- `oas_shrinkage()`: Ledoit-Wolf/OAS shrinkage
- `huber_mean()`: Média robusta de Huber
- `tyler_estimator()`: Tyler M-estimator para scatter matrix
- `fit_multivariate_t()`: Estimação de ν (graus de liberdade)

#### `src/optimization.jl`
- `solve_mincvar()`: Min-CVaR via formulação LP (HiGHS)
- `solve_minvar_osqp()`: Min-Var via QP (OSQP - ultra-rápido)
- Ambos com suporte a turnover penalty e position limits

#### `src/backtest.jl`
- `run_backtest()`: Engine principal com rolling window
- Implementa políticas MONTHLY e BANDS
- Tracking de w_strategic vs w_current (drift natural)
- Cálculo de custos de transação

#### `src/metrics.jl`
- Sharpe Ratio, Sortino Ratio
- VaR e CVaR (múltiplos níveis)
- Max Drawdown, Ulcer Index
- Annualized Turnover

#### `src/benchmarks.jl`
- `benchmark_equal_weight()`: Equal-weight buy-and-hold com rebalanceamento anual

## 🔬 Metodologia

### Pipeline de Backtesting

1. **Download de Dados**
   - API Tiingo para preços ajustados
   - Filtro de ativos com ≥15 anos
   - Quality control (detecção de outliers)

2. **Rolling Window**
   - Janela de 756 dias (~3 anos)
   - Avanço diário
   - Rebalanceamento conforme política

3. **Otimização**
   - Estimação robusta da covariância
   - Solver apropriado (LP para CVaR, QP para Var)
   - Restrições: long-only, sum=1, max_weight

4. **Execução**
   - Aplicação de custos de transação
   - Tracking de deriva natural dos pesos
   - Cálculo de returns realizados

5. **Análise**
   - Métricas de risco/retorno
   - Comparação cross-sectional
   - Diagnóstico de caudas

### Formulações Matemáticas

#### Min-CVaR (Rockafellar-Uryasev)

```
min  CVaR_α(w) = VaR_α + (1/(1-α)) * E[max(0, -r'w - VaR_α)]

s.t. sum(w) = 1
     w >= 0
     w <= max_weight
     sum(|w - w_prev|) penalizado por λ
```

Implementado como LP com variáveis auxiliares.

#### Min-Var com Turnover Penalty

```
min  w' Σ w + λ * sum(|w - w_prev|)

s.t. sum(w) = 1
     w >= 0
     w <= max_weight
```

Implementado como QP estendido com variáveis z para valor absoluto.

### Estimadores Robustos

#### OAS (Oracle Approximating Shrinkage)
```
Σ_oas = (1 - δ) * Σ_sample + δ * tr(Σ_sample)/p * I
```
onde δ é otimizado analiticamente.

#### Huber M-estimator
```
μ_huber = argmin Σ ρ_c(x_i - μ)
ρ_c(r) = r²/2 se |r| ≤ c, c|r| - c²/2 caso contrário
```
Resolvido iterativamente com c=1.345 (95% eficiência).

#### Tyler M-estimator
```
Σ_tyler satisfaz: Σ = (p/n) Σ (x_i - μ)(x_i - μ)' / [(x_i - μ)' Σ^(-1) (x_i - μ)]
```
Resolvido por fixed-point iteration com scaling para variância amostral.

## 📊 Análise dos Resultados

### Interpretando `metrics.csv`

O arquivo contém as seguintes colunas:

| Coluna | Descrição |
|--------|-----------|
| `estimator` | LW, HUBER ou TYLER |
| `strategy` | MINCVAR ou MINVAR |
| `alpha` | Nível de confiança CVaR (0.95 ou 0.99) |
| `policy` | MONTHLY, BANDS ou ANNUAL |
| `band` | Tamanho da banda (se policy=BANDS) |
| `ann_return` | Retorno anualizado |
| `ann_volatility` | Volatilidade anualizada |
| `sharpe` | Sharpe Ratio (ajustado por rf) |
| `sortino` | Sortino Ratio |
| `max_drawdown` | Máximo drawdown |
| `var_95`, `cvar_95` | VaR/CVaR a 95% |
| `var_99`, `cvar_99` | VaR/CVaR a 99% |
| `ulcer_index` | Ulcer Index (downside volatility) |
| `ann_turnover` | Turnover anualizado |
| `n_rebalances` | Número de rebalanceamentos |
| `final_wealth` | Riqueza final ($1 inicial) |

### Analisando Pesos ao Longo do Tempo

Arquivos `weights_*.csv` contêm:
- `date`: Data da observação
- `rebalanced`: Boolean indicando rebalanceamento
- `turnover`: Turnover naquela data
- Colunas para cada ativo com pesos

### Visualizações

- **Wealth Curves**: Compare performance acumulada entre estratégias
- **Efficient Frontier**: Relação volatilidade × CVaR
- **Tail Losses**: Distribuição das piores perdas
- **Turnover Heatmap**: Frequência de rebalanceamento por estratégia
- **Allocation**: Evolução temporal dos pesos

## 🛠️ Tecnologias

- **[Julia](https://julialang.org/)**: Linguagem de alto desempenho
- **[JuMP](https://jump.dev/)**: Framework de otimização
- **[OSQP](https://osqp.org/)**: Solver QP (3600× mais rápido que HiGHS para Min-Var)
- **[HiGHS](https://highs.dev/)**: Solver LP para Min-CVaR
- **[Tiingo](https://www.tiingo.com/)**: API de dados financeiros

### Dependências Julia

Instaladas automaticamente via `Pkg.instantiate()`:
- JuMP, HiGHS, OSQP
- DataFrames, CSV, Dates
- HTTP, JSON3 (API calls)
- StatsBase, Statistics, LinearAlgebra
- StatsPlots, Plots (visualização)

## 📚 Referências

- Rockafellar, R. T., & Uryasev, S. (2000). *Optimization of conditional value-at-risk*. Journal of Risk, 2, 21-42.
- Ledoit, O., & Wolf, M. (2004). *A well-conditioned estimator for large-dimensional covariance matrices*. Journal of Multivariate Analysis, 88(2), 365-411.
- Tyler, D. E. (1987). *A distribution-free M-estimator of multivariate scatter*. The Annals of Statistics, 15(1), 234-251.
- Huber, P. J. (1964). *Robust estimation of a location parameter*. The Annals of Mathematical Statistics, 35(1), 73-101.

## 🐛 Troubleshooting

### Erro: "TIINGO_TOKEN not found"
Certifique-se que o arquivo `.env` existe e contém:
```
TIINGO_TOKEN=seu_token_aqui
```

### Erro: "HTTP 403 Forbidden"
Token Tiingo inválido ou expirado. Verifique em [tiingo.com](https://www.tiingo.com/).

### Erro: "Insufficient assets after filtering"
Reduza `min_years` ou adicione mais tickers ao universo.

### Performance Lenta
- Min-CVaR é mais lento que Min-Var (LP vs QP)
- Reduza `window_size` ou número de ativos para testes rápidos
- Use menos estratégias (comente linhas no config)

## 📄 Licença

MIT License - veja [LICENSE](LICENSE) para detalhes.

## 👤 Autor

**André Camatta**
- GitHub: [@andrecamatta](https://github.com/andrecamatta)

## 🙏 Contribuições

Contribuições são bem-vindas! Por favor:
1. Fork o repositório
2. Crie uma branch para sua feature (`git checkout -b feature/NovaFeature`)
3. Commit suas mudanças (`git commit -m 'Adiciona NovaFeature'`)
4. Push para a branch (`git push origin feature/NovaFeature`)
5. Abra um Pull Request

---

**⭐ Se este projeto foi útil, considere dar uma estrela no GitHub!**
