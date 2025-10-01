Min-CVaR com estimadores robustos (Tyler/Huber) vs. Média-Variância — somente ETFs com ≥15 anos de histórico

Requisitos gerais

Pacotes: HTTP, JSON3, CSV, DataFrames, Dates, Random, Statistics, StatsBase, LinearAlgebra, RollingFunctions, Distributions, JuMP, HiGHS, StatsPlots (ou Plots).

Se disponível: CovarianceEstimation (Ledoit–Wolf/OAS) e RobustStats. Se não houver, implemente OAS e Huber conforme instruções abaixo.

Ler token da Tiingo em ENV["TIINGO_TOKEN"]. Se ausente, abortar com mensagem clara.

Sem dados simulados. Tudo vem da Tiingo.

Universo de ativos (lista candidata; filtrar por ≥15 anos)

Use a lista candidata abaixo e mantenha apenas os ETFs com ≥15 anos de histórico até a data mais recente baixada:

SPY, IWD, IWF, VTV, VUG,
EFA, EEM,
TLT, IEF, LQD, HYG, EMB,
VNQ, GLD, DBC, TIP


Regras de filtragem (parametrizáveis):

min_history_years = 15

Calcular cutoff_date = last_available_date - Year(min_history_years).

Para cada ticker, verificar:

existe série EOD “adjusted close” contínua o suficiente;

first_available_date <= cutoff_date;

pelo menos min_history_years*252 retornos diários após limpeza.

Se falhar, excluir o ticker e registrar no log (ex.: “USMV removido: <15y”).

Não fazer forward-fill de preços; alinhar por interseção de dias úteis.

Se após o filtro restarem <8 ativos, abortar com instrução de reduzir min_history_years ou ampliar a lista candidata.

Observação: ETFs “factor recentes” (USMV, SPLV, MTUM, QUAL, EEMV) não atendem os 15 anos; deixe claro no README.

Download e limpeza

Baixar EOD “adjusted close” diário (2002-01-01 até hoje, ou máximo disponível).

Unificar colunas, alinhar por interseção de datas.

Calcular retornos log diários.

QC: remover erros óbvios (ex.: |r|>50% seguido de reversão simétrica no dia seguinte); logar quantos pontos foram removidos.

Janelas e rebalance

Janela de estimação: 756 dias úteis (~3 anos) (testar 504 e 1260 como sensibilidade).

Datas de rebalance: fim-de-mês.

Políticas:

Mensal (sempre rebalanceia).

Bandas: só rebalancear se 
∣
𝑤
𝑖
−
𝑤
𝑖
𝑡
𝑎
𝑟
𝑔
𝑒
𝑡
∣
>
𝑏
∣w
i
	​

−w
i
target
	​

∣>b para 
𝑏
∈
{
2
%
,
5
%
,
10
%
}
b∈{2%,5%,10%}.

Custos lineares: 10 bps por lado (parametrizável).

Estimadores de média/covariância (três modos alternáveis)

Definir estimator ∈ {:LW, :HUBER, :TYLER}:

A) :LW (benchmark “gaussiano + shrink”)

Média amostral.

Covariância com Ledoit–Wolf ou OAS. Se CovarianceEstimation não existir, implementar OAS para alvo escalar 
𝜏
𝐼
τI, com 
𝜏
=
t
r
(
𝑆
)
/
𝑝
τ=tr(S)/p. Documentar fórmulas e colocar função oas_shrinkage(S).

B) :HUBER (média robusta + shrink)

Média Huber por ativo (k = 1.345·σ; implementar se não houver RobustStats).

Centralizar pelos 
𝜇
^
Huber
μ
^
	​

Huber
	​

; aplicar LW/OAS na covariância.

C) :TYLER (covariância M-estimador + shrink)

Centralizar por mediana por ativo.

Iterar Tyler: 
Σ
𝑘
+
1
=
𝑝
𝑛
∑
𝑖
𝑥
𝑖
𝑥
𝑖
′
𝑥
𝑖
′
Σ
𝑘
−
1
𝑥
𝑖
Σ
k+1
	​

=
n
p
	​

∑
i
	​

x
i
′
	​

Σ
k
−1
	​

x
i
	​

x
i
	​

x
i
′
	​

	​

, reescalando 
t
r
(
Σ
)
=
𝑝
tr(Σ)=p; parar em 
∥
Σ
𝑘
+
1
−
Σ
𝑘
∥
𝐹
<
10
−
6
∥Σ
k+1
	​

−Σ
k
	​

∥
F
	​

<10
−6
 ou 500 iterações.

Aplicar shrink 
Σ
shr
=
(
1
−
𝛿
)
Σ
+
𝛿
𝜏
𝐼
Σ
shr
	​

=(1−δ)Σ+δτI (δ via OAS ou hiperparâmetro).

Diagnóstico de caudas (não obrigatório na otimização)

Ajustar t-Student multivariado na janela de estimação para diagnóstico (likelihood por grid de 
𝜈
∈
[
3
,
15
]
ν∈[3,15]).

Reportar estatísticas de 
𝜈
^
ν
^
 (mediana e IQR) por estimador.

Otimizações por data de rebalance

Gerar duas carteiras alvo por estimador:

Min-CVaR (Rockafellar–Uryasev)

Nível 
𝛼
∈
{
0.95
,
0.99
}
α∈{0.95,0.99} (ambos).

Variáveis: 
𝑤
w, 
𝜁
ζ (VaR), 
𝑢
𝑡
u
t
	​

 por cenário t (retornos diários da janela).

Minimizar 
𝜁
+
1
(
1
−
𝛼
)
𝑇
∑
𝑡
𝑢
𝑡
+
𝜆
∑
𝑖
𝑧
𝑖
ζ+
(1−α)T
1
	​

∑
t
	​

u
t
	​

+λ∑
i
	​

z
i
	​


com 
𝑢
𝑡
≥
0
u
t
	​

≥0, 
𝑢
𝑡
≥
−
𝑟
𝑡
′
𝑤
−
𝜁
u
t
	​

≥−r
t
′
	​

w−ζ; turnover por 
𝑧
𝑖
≥
∣
𝑤
𝑖
−
𝑤
𝑖
𝑝
𝑟
𝑒
𝑣
∣
z
i
	​

≥∣w
i
	​

−w
i
prev
	​

∣ (variáveis auxiliares de LP).

Restrições: 
∑
𝑖
𝑤
𝑖
=
1
∑
i
	​

w
i
	​

=1, 
0
≤
𝑤
𝑖
≤
30
%
0≤w
i
	​

≤30% (parametrizável).

Solver: HiGHS (LP).

Mínima Variância (gaussiano)

Minimizar 
𝑤
′
Σ
𝑤
w
′
Σw com as mesmas restrições e penalidade de turnover 
𝜆
λ.

Alternativa opcional: Máx. Sharpe com 
𝑟
𝑓
=
0
r
f
	​

=0.

Execução e registro

Backtest de ambas as políticas (mensal vs bandas) para cada estimador (:LW, :HUBER, :TYLER) e ambas as carteiras (Min-CVaR 95/99 e Min-Var).

Salvar séries: pesos realizados, retorno diário pós-custo, patrimônio.

Métricas

ES/CVaR realizado (95/99), VaR, Sharpe, Sortino, max drawdown, Ulcer index (opcional), turnover anualizado, # rebalanceamentos, estabilidade de pesos (desvio-padrão temporal).

Comparar ex-ante vs ex-post: ES previsto pelo modelo vs ES realizado (viés e RMSE).

Tabela bruto vs líquido (impacto de custos).

Gráficos (salvar em ./fig/)

Curvas de capital: Min-CVaR vs Min-Var (por estimador).

Fronteira empírica em 
(
𝜎
,
ES
95
)
(σ,ES
95
	​

) e 
(
𝜎
,
ES
99
)
(σ,ES
99
	​

).

Alocação no tempo (stacked area) da melhor combinação por família.

Violino das perdas de cauda (piores 5% e 1%).

Heatmap de turnover e histograma de rebalanceamentos (bandas).

Saídas e reprodutibilidade

CSVs em ./results/:

metrics.csv (todas as estratégias),

weights_YYYYMM.csv,

trades_YYYYMM.csv.

README.md auto-gerado com: universo final após filtro de 15 anos, parâmetros, versões, período efetivo e resumo dos achados.

Logging via @info para: exclusões por histórico insuficiente, eventos de rebalance, custos, violações de banda, falhas em fit t-multivariado.

Testes rápidos (sanity checks)

Conferir 
∑
𝑤
=
1
∑w=1, 
𝑤
∈
[
0
,
1
]
w∈[0,1], turnover ≥ 0, custos ≥ 0.

Se menos de 8 ativos passarem no filtro de 15 anos, abortar com mensagem: “Poucos ativos após filtro ≥15y; ajuste a lista ou reduza min_history_years.”

Interpretação esperada

Discutir quando :TYLER reduz ES/MDD vs :LW, custo em turnover e como bandas mitigam custos mantendo proteção de cauda.

Comentar distribuição de 
𝜈
^
ν
^
: caudas mais pesadas → maior benefício do Min-CVaR.
