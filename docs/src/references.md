# References

Literature underpinning CausalDynamics.jl. BibTeX keys match the CDCS book
[`references.bib`](https://github.com/SimonAB/causal-dynamics-book/blob/main/references.bib)
where possible. For estimation (LMTP, mediation TMLE, Super Learner), see also
[CausalTargeted.jl references](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/references.md).

## Structural causality and identification

- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference* (2nd ed.). Cambridge University Press. — key `pearl2009causality`

- Pearl, J. (2018). *The Book of Why*. Basic Books. — key `pearl2018bookofwhy`

- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions in recursive semi-Markovian causal models. In *AAAI*. — key `shpitser2006identification`

- Spirtes, P., Glymour, C., & Scheines, R. (2000). *Causation, Prediction, and Search* (2nd ed.). MIT Press. — key `spirtes2000causation`

- Peters, J., Janzing, D., & Schölkopf, B. (2017). *Elements of Causal Inference*. MIT Press. — key `peters2017elements`

- Bareinboim, E., & Pearl, J. (2016). Causal inference and the data-fusion problem. *Proceedings of the National Academy of Sciences*, *113*(27), 7345–7352. — key `bareinboim2016causal`

- Imbens, G. W., & Rubin, D. B. (2015). *Causal Inference for Statistics, Social, and Biomedical Sciences*. Cambridge University Press. — key `imbens2015causal`

## g-methods and longitudinal confounding

- Robins, J. (1986). A new approach to causal inference in mortality studies with a sustained exposure period. *Mathematical Modelling*, *7*, 1393–1512. — key `robins1986new`

- Robins, J. M., Hernán, M. A., & Brumback, B. (2000). Marginal structural models and causal inference in epidemiology. *Epidemiology*, *11*(5), 550–560. — key `robins2000marginal`

- Hernán, M. A., & Robins, J. M. (2020). *Causal Inference: What If*. Chapman & Hall/CRC. — key `hernan2020causal`

## Time-indexed / dynamical graphs

Unrolled lag DAGs (`TemporalDAGSpec`, `unroll_temporal_dag`, `TemporalEffectQuery`) apply
standard backdoor criteria on an expanded static graph. Conceptual links:

- Pearl (2009), Ch. on dynamic models / time-indexed SCMs
- Discrete-time CDMs in the [CDCS book](https://simonab.github.io/causal-dynamics-book/) (Ch. 28)
- Estimation of time-indexed MTP effects: Díaz et al. (2023), *JASA* — key `diaz2023lmtp` (implemented in CausalTargeted)

## Mediation identification (structural)

- Pearl, J. (2001). Direct and indirect effects. In *UAI*. — key `pearl2001direct`

- Robins, J. M., & Greenland, S. (1992). Identifiability and exchangeability for direct and indirect effects. *Epidemiology*. — key `robins1992estimation`

- Avin, C., Shpitser, I., & Pearl, J. (2005). Identifiability of path-specific effects. In *IJCAI*. — key `avin2005identifiability`

- VanderWeele, T. J. (2015). *Explanation in Causal Inference*. Oxford University Press. — key `vanderweele2015explanation`

## Discovery (optional Associations.jl bridge)

- Spirtes et al. (2000) — PC and constraint-based search
- Chickering, D. M. (2002). Optimal structure identification with greedy search. *JMLR*. — key `chickering2002optimal`
- Runge, J., et al. (2019). Detecting and quantifying causal associations in large nonlinear time series datasets. *Science Advances*. — key `runge2019detecting`

Discovery outputs feed **sensitivity** comparisons in CausalTargeted
(`discovery_adjustment_sensitivity`); they must not silently replace a user DAG.

## Related packages

- **Graphs.jl** — graph data structures
- **CausalInference.jl** — d-separation / backdoor façades used internally
- **CausalTargeted.jl** — LMTP / mediation estimation consuming `IdentificationResult`
- **DAGMakie.jl** — DAG visualisation
- **Associations.jl** — optional discovery bridge
- **ModelingToolkit.jl / Symbolics.jl** — symbolic modelling (SciML integration docs)

## Further reading

For narrative treatment with Quarto `[@citekey]` citations into the shared bibliography, see
the [CDCS Book](https://simonab.github.io/causal-dynamics-book/).
