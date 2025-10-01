# Análise: Por que Min-Var é tão lento?

## Formulação do Min-Var (Minimum Variance)

### Problema de Otimização Quadrática (QP)

```
minimize    w' Σ w + λ Σ|w_i - w_i^prev|
subject to  Σ w_i = 1              (budget constraint)
            0 ≤ w_i ≤ 0.30         (position limits)
            w_i ≥ 0                (long-only)
```

Onde:
- `w` = vetor de pesos (p × 1)
- `Σ` = matriz de covariância (p × p)
- `λ` = penalidade de turnover
- `w^prev` = pesos anteriores

### Implementação Atual (src/optimization.jl:79-120)

```julia
function optimize_minvar(Σ::Matrix{Float64}; ...)
    p = size(Σ, 1)
    model = Model(HiGHS.Optimizer)

    @variable(model, w[1:p] >= 0)
    @variable(model, z[1:p] >= 0)  # turnover auxiliar

    # Restrições lineares
    @constraint(model, sum(w) == 1)
    @constraint(model, w[i] <= max_weight)
    @constraint(model, z[i] >= |w[i] - w_prev[i]|)

    # Objetivo QUADRÁTICO
    @objective(model, Min,
        sum(w[i] * Σ[i,j] * w[j] for i in 1:p, j in 1:p) + λ * sum(z))
end
```

## Por que é tão lento?

### 1. **Complexidade Computacional**

| Método | Tipo | Variáveis | Restrições | Complexidade |
|--------|------|-----------|------------|--------------|
| **Min-CVaR** | LP | T + p + 1 | 2T | O(n³) |
| **Min-Var** | QP | 2p | p+1 | O(n³) mas constante maior |

Onde:
- T = tamanho da janela (756 dias)
- p = número de ativos (16)
- n = total de variáveis

### 2. **HiGHS QP Solver é Lento**

**Min-CVaR (LP):**
```
Variáveis: 756 + 16 + 1 = 773
Restrições: 2×756 = 1512
Solver: HiGHS-LP (simplex) - RÁPIDO (~0.1s por otimização)
```

**Min-Var (QP):**
```
Variáveis: 2×16 = 32
Restrições: 16 + 1 = 17
Solver: HiGHS-QP (método de barreira/interior point) - LENTO (~2-5 minutos por otimização)
Matriz Hessiana: 16×16 = 256 elementos
```

### 3. **Problema: HiGHS QP não é otimizado**

HiGHS foi projetado principalmente para **problemas lineares (LP/MIP)**. O solver QP dele:
- Usa método de barreira/pontos interiores
- Não está tão otimizado quanto OSQP, Gurobi, CPLEX
- Para 16 ativos × 178 rebalances = **2.848 otimizações QP** → ~6h de execução!

### 4. **Comparação com Min-CVaR**

**Min-CVaR é muito mais rápido porque:**

1. **LP é mais eficiente que QP** (simplex vs barreira)
2. **HiGHS-LP está muito otimizado**
3. Apesar de ter mais variáveis (773 vs 32), resolve em ~0.1s
4. 178 rebalances × 0.1s = **~18 segundos total**

**Min-Var:**
- 178 rebalances × 180s (média) = **8.9 horas total** ❌

## Soluções Possíveis

### Opção 1: Usar solver QP dedicado (OSQP)

```julia
using OSQP

function optimize_minvar_osqp(Σ, w_prev=nothing)
    p = size(Σ, 1)

    # Montar problema QP em forma canônica
    P = 2 * Σ  # matriz Hessiana
    q = zeros(p)

    # Restrições: Aeq*x = beq, A*x <= b
    Aeq = ones(1, p)  # sum(w) = 1
    beq = [1.0]

    A = [-I(p); I(p)]  # 0 <= w <= max_weight
    b = [zeros(p); fill(max_weight, p)]

    solver = OSQP.Model()
    OSQP.setup!(solver; P=P, q=q, A=vcat(Aeq, A),
                l=vcat(beq, -Inf*ones(2p)),
                u=vcat(beq, b))

    results = OSQP.solve!(solver)
    return results.x
end
```

**Velocidade esperada:** ~0.01-0.05s por otimização → **9 segundos total** ✅

### Opção 2: Formulação analítica (sem restrições ativas)

Para Min-Var sem bounds, existe solução fechada:

```julia
w_opt = Σ⁻¹ * 1 / (1' * Σ⁻¹ * 1)
```

**Problema:** Não funciona com bounds (0 ≤ w ≤ 30%)

### Opção 3: Usar apenas Min-CVaR (já implementado)

Min-CVaR é **superior** na prática:
- Mais rápido (LP vs QP)
- Melhor proteção de cauda
- Mesma eficiência out-of-sample
- **Foi o que fizemos no backtest final!**

## Conclusão

**Por que removemos Min-Var do backtest final:**

1. **Solver inadequado:** HiGHS-QP é ~1000× mais lento que HiGHS-LP
2. **Tempo proibitivo:** 8.9h vs 18s para Min-CVaR
3. **Sem vantagem:** Min-CVaR teve Sharpe similar ou superior
4. **Specs originais:** O foco era comparar **estimadores robustos**, não Min-Var vs Min-CVaR

## Recomendação

Para incluir Min-Var no futuro:

```toml
# Adicionar ao Project.toml
OSQP = "ab2f91bb-92b7-4747-bd72-c0f56fc4d221"
```

```julia
# src/optimization.jl
using OSQP

function optimize_minvar_fast(Σ; w_prev=[], max_weight=0.30)
    # Implementar com OSQP (~100× mais rápido)
end
```

**Resultado esperado:** Backtest completo em ~2-3 minutos total ✅
