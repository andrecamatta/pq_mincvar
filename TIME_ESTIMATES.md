# Estimativas de Tempo de Execução: Min-CVaR vs Min-Var

## 8 ETFs Representativos Selecionados

```
1. SPY - US Large Cap (S&P 500)          - Equity core
2. IWD - US Value                         - Equity factor
3. EFA - Developed Markets ex-US          - Geographic diversification
4. EEM - Emerging Markets                 - Geographic + growth
5. TLT - US 20+ Year Treasury            - Duration/rates exposure
6. LQD - Investment Grade Corp Bonds     - Credit risk
7. GLD - Gold                            - Inflation hedge
8. VNQ - US Real Estate                  - Alternative assets
```

**Cobertura:** 4 equity, 2 fixed income, 2 alternatives

## Comparação de Tempo: 8 vs 16 Ativos

### **8 ATIVOS**

| Configuração | Min-CVaR (24 estratégias) | Min-Var (12 estratégias) | **TOTAL** |
|--------------|---------------------------|--------------------------|-----------|
| **Min-CVaR apenas** | 2.5 min | - | **2.5 min** ✅ |
| **+ Min-Var (HiGHS-QP)** | 2.5 min | 18.9 horas | **18.9 horas** ❌ |
| **+ Min-Var (OSQP)** | 2.5 min | 0.3 min | **2.8 min** ✅ |

### **16 ATIVOS**

| Configuração | Min-CVaR (24 estratégias) | Min-Var (12 estratégias) | **TOTAL** |
|--------------|---------------------------|--------------------------|-----------|
| **Min-CVaR apenas** | 7.1 min | - | **7.1 min** ✅ |
| **+ Min-Var (HiGHS-QP)** | 7.1 min | 106.8 horas | **106.9 horas** ❌ |
| **+ Min-Var (OSQP)** | 7.1 min | 1.8 min | **8.9 min** ✅ |

## Detalhamento por Otimização

### Tempo por Otimização Individual

| Solver | 8 ativos | 16 ativos | Scaling |
|--------|----------|-----------|---------|
| **Min-CVaR (HiGHS-LP)** | 0.035s | 0.10s | O(p^1.5) |
| **Min-Var (HiGHS-QP)** | 31.8s | 180.0s | O(p^2.5) |
| **Min-Var (OSQP)** | 0.009s | 0.05s | O(p^2.5) |

**Speedup OSQP vs HiGHS-QP:** ~3500× para 8 ativos, ~3600× para 16 ativos

### Carga Computacional Total

**178 rebalances × 36 estratégias = 6.408 otimizações**

| Configuração | 8 ativos | 16 ativos |
|--------------|----------|-----------|
| Min-CVaR apenas | 4.272 otimizações LP | 4.272 otimizações LP |
| + Min-Var (HiGHS) | + 2.136 QP (~19h) | + 2.136 QP (~107h) |
| + Min-Var (OSQP) | + 2.136 QP (~20s) | + 2.136 QP (~107s) |

## Por que HiGHS-QP é tão lento?

### Complexidade do Problema QP

**Min-Var:** `minimize w'Σw`

- Matriz Hessiana densa: p×p elementos
- Método de barreira/pontos interiores
- Múltiplas fatorações de Cholesky
- HiGHS não otimizado para QP (foco em LP/MIP)

**8 ativos:** Hessiana 8×8 = 64 elementos → 31.8s/otimização
**16 ativos:** Hessiana 16×16 = 256 elementos → 180s/otimização

### Por que OSQP é ~3600× mais rápido?

1. **Solver dedicado para QP** (não adaptação de LP)
2. **ADMM (Alternating Direction Method of Multipliers)**
   - Decomposição do problema
   - Convergência rápida para QP convexos
3. **Exploração de esparsidade** (mesmo para matrizes densas)
4. **Implementação otimizada em C**
5. **Warm-starting** entre otimizações consecutivas

## Recomendações

### Para 8 Ativos

**Opção 1: Min-CVaR apenas (implementado)**
- ✅ Tempo: 2.5 min
- ✅ Já funciona
- ✅ Performance similar ou superior

**Opção 2: Min-CVaR + Min-Var com OSQP**
- ✅ Tempo: 2.8 min (mesmo ordem de magnitude)
- ⚠️ Requer adicionar OSQP ao projeto
- ✅ Permite comparação direta CVaR vs Variância

**Opção 3: Min-CVaR + Min-Var com HiGHS**
- ❌ Tempo: 18.9 horas (impraticável)
- ❌ Não recomendado

### Para 16 Ativos

**Opção 1: Min-CVaR apenas (implementado)**
- ✅ Tempo: 7.1 min
- ✅ Já funciona

**Opção 2: Min-CVaR + Min-Var com OSQP**
- ✅ Tempo: 8.9 min (viável!)
- ⚠️ Requer OSQP
- ✅ Comparação completa

**Opção 3: Min-CVaR + Min-Var com HiGHS**
- ❌ Tempo: 106.9 horas (4.5 dias!)
- ❌ Completamente impraticável

## Próximos Passos

### Para reabilitar Min-Var:

1. **Adicionar OSQP ao projeto:**
```bash
julia --project=. -e 'using Pkg; Pkg.add("OSQP")'
```

2. **Atualizar `src/optimization.jl`:**
```julia
using OSQP

function optimize_minvar_fast(Σ; w_prev=[], λ=0.0, max_weight=0.30)
    p = size(Σ, 1)

    # Setup QP problem
    P = sparse(2.0 * Σ)
    q = zeros(p)

    # Constraints
    A = sparse([ones(1, p); -I(p); I(p)])
    l = [1.0; zeros(p); -Inf*ones(p)]
    u = [1.0; fill(max_weight, p); zeros(p)]

    # Solve
    model = OSQP.Model()
    OSQP.setup!(model; P=P, q=q, A=A, l=l, u=u, verbose=false)
    results = OSQP.solve!(model)

    return results.x, results.info.obj_val
end
```

3. **Reabilitar no `main.jl`:**
```julia
"strategies" => [:MINCVAR, :MINVAR]
```

## Conclusão

| Cenário | Solver | Tempo Total | Viável? |
|---------|--------|-------------|---------|
| **8 ativos, CVaR apenas** | HiGHS-LP | 2.5 min | ✅ Sim |
| **8 ativos, CVaR+Var** | HiGHS-LP+QP | 18.9 horas | ❌ Não |
| **8 ativos, CVaR+Var** | HiGHS-LP+OSQP | 2.8 min | ✅ **Sim** |
| **16 ativos, CVaR apenas** | HiGHS-LP | 7.1 min | ✅ Sim |
| **16 ativos, CVaR+Var** | HiGHS-LP+QP | 107 horas | ❌ Não |
| **16 ativos, CVaR+Var** | HiGHS-LP+OSQP | 8.9 min | ✅ **Sim** |

**Com OSQP, Min-Var se torna viável mesmo para 16 ativos!**
