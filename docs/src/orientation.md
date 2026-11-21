# Choosing an approach

```@meta
CurrentModule = CausalDynamics
```

This page maps common biological and scientific questions to the right causal
framework, package, and `CausalDynamics` API. It assumes familiarity with
experimental or observational data analysis (such as regression or mixed models),
not prior training in causal inference.

## Where this package fits

Causal analysis separates four jobs that are often conflated in standard
statistical modelling:

| Task | Typical question | Package |
|------|------------------|---------|
| **Draw assumptions** | How do variables in my system influence one another? | [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl/dev/) |
| **Identify & simulate** | Which covariates must I adjust for (or exclude)? Can this effect be identified at all? How does the system respond to an intervention? | **CausalDynamics.jl** (this package) |
| **Estimate effects** | Given data and an adjustment set, what is the effect of shifting an exposure or treatment? | [CausalTargeted.jl](https://simonab.github.io/CausalTargeted.jl/dev/) |
| **Decompose pathways** | How much of an effect acts directly versus through an intermediate mechanism? | [CausalMediation.jl](https://simonab.github.io/CausalMediation.jl/dev/) |

A standard workflow moves from left to right: state the causal graph, obtain an
identification certificate from `CausalDynamics`, and pass that certificate to an
estimator in `CausalTargeted` or `CausalMediation`.

## Why draw a causal graph before fitting a model?

Regression and machine-learning models estimate *associations* in observed data.
A causal question asks something different: how would an outcome ``Y`` change if we
*intervened* on an exposure ``A`` (for instance, reducing parasite load or altering
diet)?

Adding every measured variable to a regression does not fix bias. Whether a
covariate helps or harms depends on its causal position relative to exposure ``A``
and outcome ``Y`` (Pearl, 2009; Cinelli, Forney & Pearl, 2024; Hernán & Robins,
2020):

| Structure | Graph | Biological example | For the total effect of ``A`` on ``Y`` |
|-----------|-------|--------------------|------------------------------------|
| **Confounder** (fork) | ``A \leftarrow W \rightarrow Y`` | Age or season (``W``) affects both parasite load (``A``) and survival (``Y``). | **Adjust for ``W``.** Omitting it leaves a spurious non-causal association. |
| **Mediator** (chain) | ``A \rightarrow M \rightarrow Y`` | Infection (``A``) triggers an immune response (``M``) that affects survival (``Y``). | **Do not adjust for ``M``.** Conditioning on ``M`` blocks the pathway you want to measure. |
| **Collider** | ``A \rightarrow C \leftarrow Y`` | Both infection (``A``) and poor condition (``Y``) make an animal easier to trap (``C``). | **Do not condition on ``C``.** Restricting to or adjusting for ``C`` creates a spurious association between ``A`` and ``Y``. |

`CausalDynamics` encodes these graphical rules algorithmically (Shpitser,
VanderWeele & Robins, 2010; van der Zander, Liśkiewicz & Textor, 2019): you
supply the directed acyclic graph (DAG) representing your scientific
assumptions, and the package determines whether the target effect is
identifiable and which variables belong in the adjustment set. Full citations
and DOIs appear in [References](references.md).

## Match your question and data to an API

| Biological question or data structure | Causal estimand | Entry point in `CausalDynamics` | Basis / downstream |
|---------------------------------------|-----------------|--------------------------------|----------------------|
| **Observational study, single time point:** what must I adjust for to estimate the effect of ``A`` on ``Y``? | Total causal effect | `TotalEffectQuery`, [`identify`](@ref), [`backdoor_adjustment_set`](@ref) | Pearl (2009); van der Zander et al. (2019). Estimate in [CausalTargeted.jl](https://simonab.github.io/CausalTargeted.jl/dev/) |
| **Unmeasured confounder:** an important common cause of ``A`` and ``Y`` was not measured, but a complete intermediate mechanism ``M`` was. | Total effect via frontdoor | [`frontdoor_adjustment_set`](@ref), [`find_frontdoor_mediators`](@ref) | Pearl (2009); Wienöbst et al. (2024). [Identification API](api/identification.md) |
| **Unmeasured confounder with an instrument:** a randomised encouragement, genetic variant, or natural experiment shifts ``A`` without directly affecting ``Y``. | Instrumental-variable effect | [`find_instruments`](@ref), [`is_valid_instrument`](@ref), [`identify`](@ref) | Pearl (2009); Imbens & Rubin (2015). [Identification API](api/identification.md) |
| **Mechanism / pathway:** does ``A`` affect ``Y`` directly, or through an intermediate trait ``M``? | Direct and indirect (mediated) effects | `MediationQuery`, [`identify`](@ref) | Robins & Greenland (1992); Pearl (2001); VanderWeele (2015). Estimate in [CausalMediation.jl](https://simonab.github.io/CausalMediation.jl/dev/) |
| **Repeated measures or time series:** exposure, covariates, and outcomes evolve over time with feedback. | Longitudinal or time-indexed policy effect | `TemporalNodeSpec`, `TemporalDAGSpec`, `unroll_temporal_dag`, `TemporalEffectQuery` | Robins (1986); Hernán & Robins (2020); Díaz et al. (2023). Sequential LMTP in [CausalTargeted.jl](https://simonab.github.io/CausalTargeted.jl/dev/) |
| **Mechanistic or dynamical simulation:** simulate interventions or individual counterfactuals in a known model. | Interventional trajectory / counterfactual | `GraphSCM` (static), [`DiscreteTimeCDM`](@ref) + [`DoSequence`](@ref) / [`Policy`](@ref) / [`g_computation`](@ref) | Pearl (2009); Robins (1986). Continuous ODEs: [SciML recipes](SCIML_INTEGRATION.md) |
| **Nested or grouped units:** animals in cages, plots in sites, patients in clinics. | Population or cluster-level effect | [`RandomEffectSpec`](@ref), [`unroll_hierarchical_dag`](@ref) | [Hierarchical / nested units](hierarchy.md) |
| **Missing outcomes or attrition:** some individuals are not recaptured or drop out. | Complete-population causal effect | [`MissingnessSpec`](@ref), [`certify_missingness`](@ref) | [Missingness](missingness.md) and CausalTargeted |
| **Noisy observations of a latent state:** true abundance, physiological state, or infection intensity is observed with error. | Latent-state interventional effect | [`ObservationBridge`](@ref), [`panel_from_latent_series`](@ref) | [Exact linear Gaussian states](linear_bayesian_states.md), [Nonlinear states](nonlinear_states.md) |
| **Generalising across sites or populations:** does an effect identified in site 1 transport to site 2? | Transported causal effect | `TransportQuery`, [`identify`](@ref) | Bareinboim & Pearl (2016). [Identification API](api/identification.md) |

## A biological example: good and bad controls

Consider a field study of how parasite load (`A`) affects overwinter survival
(`Y`):

- Season and host age (`W`) influence parasite load, immune response, and
  survival (a confounder).
- Parasite load alters an immune marker (`M`), which in turn affects survival (a
  mediator).
- Both heavy parasite load and poor survival prospects affect whether an animal
  enters a live trap (`C`, a collider).

```@example orientation-bio
using CausalDynamics, Graphs

# Nodes: 1=W (age/season), 2=A (parasite load), 3=M (immune marker),
#        4=Y (survival),   5=C (trap capture)
g = DiGraph(5)
add_edge!(g, 1, 2); add_edge!(g, 1, 3); add_edge!(g, 1, 4)  # W → A, M, Y
add_edge!(g, 2, 3); add_edge!(g, 2, 4)                      # A → M, Y
add_edge!(g, 3, 4)                                          # M → Y
add_edge!(g, 2, 5); add_edge!(g, 4, 5)                      # A → C ← Y (collider)

names = Dict(1 => :W, 2 => :A, 3 => :M, 4 => :Y, 5 => :C)

# 1. Total effect of parasite load (A) on survival (Y)
id_total = identify(g, TotalEffectQuery(:A, :Y); node_names = names)
(identifiable = id_total.identifiable, strategy = id_total.strategy, adjust = id_total.adjustment)
```

`identify` selects `[:W]` and excludes both the mediator `:M` and the collider
`:C`. If the scientific question shifts to how much of the effect of parasite
load operates through the immune marker `:M`, switch the query to
`MediationQuery`:

```@example orientation-bio
# 2. Direct vs immune-mediated effect of A on Y
id_med = identify(
    g,
    MediationQuery(:A, :Y, [:M]; effect_kind = :interventional);
    node_names = names,
)
(identifiable = id_med.identifiable, adjust = id_med.adjustment, mediators = id_med.mediators, moc = id_med.moc)
```

The returned `IdentificationResult` is a structured certificate: it records the
graph fingerprint, the identification strategy, the adjustment set, and any
exposure-induced mediator–outcome confounders (`moc`). Passing this object to
`CausalTargeted` or `CausalMediation` keeps the assumptions explicit and prevents
accidental adjustment for mediators or colliders.

## What identification can and cannot tell you

- **Identification is prior to data.** It asks: *if the graph is structurally
  correct and we had unlimited data, could this causal effect be expressed from
  the observed distribution?* It does not test whether your data are large enough
  or whether a particular regression model is well specified.
- **Garbage in, garbage out.** A valid certificate guarantees only that the
  adjustment set is sound *under the assumed graph*. Omitting an unmeasured
  confounder from the graph will produce an overconfident adjustment set; use
  omitted-confounder sensitivity analysis in `CausalTargeted` (Cinelli &
  Hazlett, 2020) to quantify how strong an unmeasured confounder would need to
  be to overturn a conclusion.
- **Not identifiable is a useful answer.** When `id.identifiable == false`, the
  package is telling you that no statistical adjustment of the observed variables
  can isolate the causal effect under your graph (Shpitser & Pearl, 2006): you
  need an instrument, a frontdoor mechanism, longitudinal measurements, a
  randomised intervention, or a different estimand.

## Plain-language glossary

| Term | Plain meaning |
|------|---------------|
| **Estimand** | The exact causal quantity you want to know (for example, the difference in mean survival if parasite load were reduced by one unit across the population), stated before choosing a statistical estimator (Hernán & Robins, 2020). |
| **Identification vs estimation** | *Identification* decides whether the estimand can be recovered from observed variables under a causal graph; *estimation* computes a numerical estimate and uncertainty interval from finite data (Pearl, 2009). |
| **Backdoor path** | A non-causal path between exposure ``A`` and outcome ``Y`` that starts with an arrow pointing *into* ``A`` (such as ``A \leftarrow W \rightarrow Y``). Backdoor adjustment blocks all such paths without blocking causal paths or opening colliders (Pearl, 2009; Cinelli et al., 2024). |
| **d-separation** | The graphical rule that determines whether two variables are statistically independent once you condition on a given set of covariates (Pearl, 2009). |
| **Intervention `do(·)`** | Setting a variable to a value or rule externally, breaking the natural arrows that normally determine it (Pearl, 2009). |
| **Counterfactual** | What would have happened to the *same* individual or trajectory under a different intervention, holding its unobserved background factors (``U``) constant (Pearl, 2009). |
| **Intermediate confounder (`moc`)** | A variable affected by the exposure that then confounds the mediator and the outcome. Common in biology (for example, infection alters body condition, which affects both immunity and survival); it requires interventional rather than natural mediation estimands (Avin, Shpitser & Pearl, 2005; VanderWeele, 2015). |

## References

Key works cited on this page (complete list with BibTeX keys in
[References](references.md)):

- Bareinboim, E., & Pearl, J. (2016). Causal inference and the data-fusion problem. *PNAS*, *113*(27), 7345–7352.
- Cinelli, C., Forney, A., & Pearl, J. (2024). A crash course in good and bad controls. *Sociological Methods & Research*, *53*(3), 1071–1104. [doi:10.1177/00491241221099552](https://doi.org/10.1177/00491241221099552)
- Cinelli, C., & Hazlett, C. (2020). Making sense of sensitivity: Extending omitted variable bias. *JRSS-B*, *82*(1), 39–67. [doi:10.1111/rssb.12348](https://doi.org/10.1111/rssb.12348)
- Hernán, M. A., & Robins, J. M. (2020). *Causal Inference: What If*. Chapman & Hall/CRC.
- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference* (2nd ed.). Cambridge University Press.
- Robins, J. (1986). A new approach to causal inference in mortality studies with a sustained exposure period. *Mathematical Modelling*, *7*, 1393–1512.
- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions in recursive semi-Markovian causal models. In *AAAI*.
- van der Zander, B., Liśkiewicz, M., & Textor, J. (2019). Separators and adjustment sets in causal graphs. *Artificial Intelligence*, *270*, 1–40. [arXiv:1803.00116](https://arxiv.org/abs/1803.00116)
- VanderWeele, T. J. (2015). *Explanation in Causal Inference*. Oxford University Press.
- Wienöbst, M., van der Zander, B., & Liśkiewicz, M. (2024). Linear-time algorithms for front-door adjustment in causal graphs. In *AAAI*. [arXiv:2211.16468](https://arxiv.org/abs/2211.16468)

## Next steps

- Work through executable examples in [Getting Started](getting-started.md).
- Inspect what is in core versus optional extensions in [Scope](scope.md).
- For time-indexed graphs and temporal conventions, see [Terminology](terminology.md).
- Once you have an identification certificate, estimate effects with
  [CausalTargeted.jl](https://simonab.github.io/CausalTargeted.jl/dev/) or
  [CausalMediation.jl](https://simonab.github.io/CausalMediation.jl/dev/).
