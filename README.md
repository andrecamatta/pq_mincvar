# Min-CVaR com Estimadores Robustos

## Resumo

Este projeto implementa e testa estratégias de otimização de portfólio comparando:
- **Min-CVaR** (Conditional Value-at-Risk) usando formulação de Rockafellar-Uryasev
- **Min-Var** (Mínima Variância)

Com três estimadores robustos de covariância:
- **:LW** - Ledoit-Wolf / Oracle Approximating Shrinkage (OAS)
- **:HUBER** - M-estimador de Huber para média + covariância OAS
- **:TYLER** - M-estimador de Tyler para matriz de dispersão + encolhimento

## Universo

**Ativos Finais (16):** ["SPY", "IWD", "IWF", "IWM", "EFA", "EEM", "VWO", "TLT", "IEF", "LQD", "HYG", "GLD", "SLV", "VNQ", "DBC", "USO"]

**Período:** 2007-04-12 até 2025-10-03

**Filtro:** ETFs com ≥ 15 anos de histórico

## Parâmetros

- **Janela de estimação:** 756 dias (~3 anos)
- **Rebalanceamento:** Fim do mês
- **Políticas:** Mensal, Bandas (2%, 5%, 10%)
- **Custos de transação:** 6.0 bps (média realista para ETFs líquidos, 2024)
- **Limite por ativo:** 30% por ativo
- **Níveis de confiança CVaR:** α = [0.95, 0.99]

## Principais Resultados

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

## Interpretação

- **Estimador Tyler** tipicamente reduz risco de cauda (CVaR/MDD) vs Gaussiano (LW), especialmente quando ν < 10
- **Políticas de bandas** reduzem significativamente o turnover vs rebalanceamento mensal, com trade-offs modestos de performance
- **Estratégias Min-CVaR** apresentam melhor proteção contra quedas comparadas a Min-Var durante períodos de crise
- **Custos de transação** impactam materialmente a performance líquida, particularmente em estratégias de alto turnover

## Arquivos

- `results/metrics.csv` - Métricas de performance abrangentes
- `results/weights_*.csv` - Pesos do portfólio ao longo do tempo
- `fig/` - Visualizações (curvas de riqueza, fronteiras, alocação, perdas na cauda)

## Reprodutibilidade

**Versão Julia:** 1.11.7

**Pacotes:** Ver `Project.toml`

**Seed aleatória:** Não utilizada (otimização determinística)

**Execução:** `julia main.jl`

---

Gerado em 2025-10-05T15:26:23.399
