# Min-CVaR com Estimadores Robustos

## Resumo

Este projeto implementa e testa estratégias de otimização de portfólio comparando:
- **Min-CVaR** (Conditional Value-at-Risk) usando formulação de Rockafellar-Uryasev
- **Min-Var** (Mínima Variância)

Com três estimadores robustos de covariância:
- **:LW** - Ledoit-Wolf / Oracle Approximating Shrinkage (OAS)
- **:HUBER** - M-estimador de Huber para média + covariância OAS
- **:TYLER** - M-estimador de Tyler para matriz de dispersão + encolhimento

## 📋 Pré-requisitos

- **Julia:** ≥ 1.11.0 (testado com 1.11.7)
- **Conta Tiingo:** API gratuita para dados históricos de ETFs
- **Sistema operacional:** Linux, macOS, ou Windows

## 🚀 Instalação e Configuração

### 1. Instalar Julia

Baixe Julia em: https://julialang.org/downloads/

Verifique a instalação:
```bash
julia --version
```

### 2. Clonar o Repositório

```bash
git clone https://github.com/andrecamatta/pq_mincvar.git
cd pq_mincvar
```

### 3. Instalar Dependências Julia

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Isso instalará automaticamente todos os pacotes listados em `Project.toml`:
- JuMP, HiGHS, OSQP (otimização)
- DataFrames, CSV, Dates (manipulação de dados)
- HTTP, JSON3 (API Tiingo)
- Plots, StatsPlots (visualizações)
- StatsBase, Distributions (estatísticas)

### 4. Configurar API Tiingo

#### 4.1. Obter Token Gratuito

1. Acesse https://www.tiingo.com/
2. Crie uma conta gratuita
3. Vá em **Account** → **API Token**
4. Copie seu token (ex: `7abc123...`)

#### 4.2. Configurar Variável de Ambiente

Crie um arquivo `.env` na raiz do projeto:

```bash
# Linux/macOS
cp .env.example .env
# Edite .env e substitua "your_token_here" pelo seu token

# Ou crie diretamente:
echo "TIINGO_TOKEN=seu_token_aqui" > .env
```

```powershell
# Windows (PowerShell)
Copy-Item .env.example .env
# Edite .env e substitua "your_token_here" pelo seu token
```

**⚠️ Importante:** O arquivo `.env` está no `.gitignore` e **NÃO** será commitado. Nunca compartilhe seu token publicamente.

**Alternativa:** Exportar como variável de ambiente da sessão:
```bash
export TIINGO_TOKEN="seu_token_aqui"  # Linux/macOS
$env:TIINGO_TOKEN="seu_token_aqui"    # Windows PowerShell
```

## 🧪 Execução

### Teste Rápido (Recomendado para Primeira Execução)

Execute um backtest reduzido para validar a instalação (~30 segundos):

```bash
julia test_quick.jl
```

Isso executa:
- 13 ativos (vs 16 no teste completo)
- 3 estimadores (LW, HUBER, TYLER)
- 1 estratégia (MINCVAR α=0.95)
- 1 política (MONTHLY)

**Saída esperada:**
- Métricas de performance no terminal
- Confirmação de download de dados da Tiingo

### Backtest Completo

Execute a análise completa (~3-5 minutos):

```bash
julia main.jl
```

Isso executa:
- **36 estratégias** (3 estimadores × 2 estratégias × 2 alphas × 4 políticas)
- **16 ETFs** com ≥15 anos de histórico
- **Período:** 2007-2025 (~18 anos)

**Saída gerada:**
- `results/metrics.csv` - Métricas de todas as estratégias
- `results/weights_*.csv` - Pesos por estratégia ao longo do tempo
- `fig/*.png` - Gráficos de análise

### Solução de Problemas

**Erro: "TIINGO_TOKEN not found"**
```
Solução: Verifique se o arquivo .env existe e contém o token correto
```

**Erro: "No data downloaded"**
```
Solução:
1. Verifique sua conexão com internet
2. Teste o token em: https://api.tiingo.com/tiingo/daily/spy/prices?token=SEU_TOKEN
3. Limite de requisições gratuitas: 500/hora (suficiente para o projeto)
```

**Erro: "UndefVarError: mad"**
```
Solução: Instale dependências novamente
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## 📊 Universo de Ativos

**Ativos Finais (16):** ["SPY", "IWD", "IWF", "IWM", "EFA", "EEM", "VWO", "TLT", "IEF", "LQD", "HYG", "GLD", "SLV", "VNQ", "DBC", "USO"]

**Período:** 2007-04-12 até 2025-10-03

**Filtro:** ETFs com ≥ 15 anos de histórico

## ⚙️ Parâmetros

- **Janela de estimação:** 756 dias (~3 anos)
- **Rebalanceamento:** Fim do mês
- **Políticas:** Mensal, Bandas (2%, 5%, 10%)
- **Custos de transação:** 6.0 bps (média realista para ETFs líquidos, 2024)
- **Limite por ativo:** 30% por ativo
- **Níveis de confiança CVaR:** α = [0.95, 0.99]

## 📈 Principais Resultados

### Diagnóstico de Caudas (distribuição t multivariada)
- LW: ν = 15
- TYLER: ν = 15
- HUBER: ν = 15

### Métricas de Performance

Ver `results/metrics.csv` para métricas detalhadas incluindo:
- Retorno e volatilidade anualizados
- Índices de Sharpe e Sortino
- VaR e CVaR nos níveis de confiança de 95% e 99%
- Drawdown máximo e índice Ulcer
- Turnover anualizado e número de rebalanceamentos

### Melhores Estratégias (por Índice de Sharpe)

Top 5 estratégias:
1. HUBER-MINCVAR-α95-BANDS: Sharpe=0.533
2. TYLER-MINCVAR-α95-BANDS: Sharpe=0.533
3. LW-MINCVAR-α95-BANDS: Sharpe=0.533
4. HUBER-MINCVAR-α95-BANDS: Sharpe=0.518
5. TYLER-MINCVAR-α95-BANDS: Sharpe=0.518

## 💡 Interpretação

- **Estimador Tyler** tipicamente reduz risco de cauda (CVaR/MDD) vs Gaussiano (LW), especialmente quando ν < 10
- **Políticas de bandas** reduzem significativamente o turnover vs rebalanceamento mensal, com trade-offs modestos de performance
- **Estratégias Min-CVaR** apresentam melhor proteção contra quedas comparadas a Min-Var durante períodos de crise
- **Custos de transação** impactam materialmente a performance líquida, particularmente em estratégias de alto turnover

## 📁 Estrutura de Arquivos

```
pq_mincvar/
├── main.jl              # Script principal (backtest completo)
├── test_quick.jl        # Teste rápido
├── src/
│   ├── data.jl          # Download e processamento de dados
│   ├── estimators.jl    # Estimadores robustos (LW, Huber, Tyler)
│   ├── optimization.jl  # Min-CVaR e Min-Var
│   ├── backtest.jl      # Engine de backtest
│   ├── metrics.jl       # Cálculo de métricas
│   ├── plots.jl         # Visualizações
│   └── benchmarks.jl    # Estratégias benchmark
├── results/             # CSVs de métricas e pesos
├── fig/                 # Gráficos PNG
├── .env                 # Token Tiingo (NÃO commitado)
├── .env.example         # Template para configuração
└── Project.toml         # Dependências Julia
```

## 🔬 Reprodutibilidade

**Versão Julia:** 1.11.7

**Seed aleatória:** Não utilizada (otimização determinística)

**Dados:** API Tiingo (dados EOD ajustados, consistentes para reprodução)

**Sistema testado:** Linux (Ubuntu 22.04), Julia 1.11.7

## 📚 Referências

**Formulação Min-CVaR:**
- Rockafellar, R.T., Uryasev, S. (2000). "Optimization of conditional value-at-risk"

**Estimadores Robustos:**
- Ledoit, O., Wolf, M. (2004). "A well-conditioned estimator for large-dimensional covariance matrices"
- Tyler, D.E. (1987). "A distribution-free M-estimator of multivariate scatter"
- Huber, P.J. (1964). "Robust estimation of a location parameter"

**Custos de Transação ETFs:**
- Frazzini, A., Israel, R., Moskowitz, T.J. (2018). "Trading Costs"
- Vanguard Research (2024). "Assessing ETF Trading Costs"

---

Gerado em 2025-10-05T15:26:23.399
