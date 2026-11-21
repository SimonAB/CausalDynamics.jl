# References

Literature underpinning CausalDynamics.jl. BibTeX keys match the CDCS book
[`references.bib`](https://github.com/SimonAB/causal-dynamics-book/blob/main/references.bib)
where possible. For estimation (LMTP, mediation TMLE, Super Learner), see also
[CausalTargeted.jl references](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/references.md).

## Adjustment-set algorithms (CausalInference / gensearch)

CausalDynamics delegates backdoor and frontdoor adjustment to
[CausalInference.jl](https://github.com/mschauer/CausalInference.jl) `gensearch`.
Literature underpinning those algorithms:

- Shpitser, I., VanderWeele, T., & Robins, J. M. (2010). On the validity of covariate adjustment for estimating causal effects. In *Proceedings of the Twenty-Sixth Conference on Uncertainty in Artificial Intelligence (UAI)*. — key `shpitser2010validity` ([arXiv:1203.3515](https://arxiv.org/abs/1203.3515))

- van der Zander, B., Liśkiewicz, M., & Textor, J. (2019). Separators and adjustment sets in causal graphs: complete criteria and an algorithmic framework. *Artificial Intelligence*, *270*, 1–40. [doi:10.1016/j.artint.2018.12.006](https://doi.org/10.1016/j.artint.2018.12.006) — key `vanderzander2019separators` ([arXiv:1803.00116](https://arxiv.org/abs/1803.00116))

- Wienöbst, M., van der Zander, B., & Liśkiewicz, M. (2024). Linear-time algorithms for front-door adjustment in causal graphs. In *Proceedings of the AAAI Conference on Artificial Intelligence*. [doi:10.1609/aaai.v38i18.30043](https://doi.org/10.1609/aaai.v38i18.30043) — key `wienoebst2024lineartimefrontdoor` ([arXiv:2211.16468](https://arxiv.org/abs/2211.16468))

Shared BibTeX keys also appear in the [CDCS book `references.bib`](https://github.com/SimonAB/causal-dynamics-book/blob/main/references.bib).

## Structural causality and identification

- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference* (2nd ed.). Cambridge University Press, Cambridge. — key `pearl2009causality`

- Cinelli, C., Forney, A., & Pearl, J. (2024). A crash course in good and bad controls. *Sociological Methods & Research*, *53*(3), 1071–1104. [doi:10.1177/00491241221099552](https://doi.org/10.1177/00491241221099552) — key `cinelli2024goodbadcontrols`

- Cinelli, C., & Hazlett, C. (2020). Making sense of sensitivity: extending omitted variable bias. *Journal of the Royal Statistical Society: Series B (Statistical Methodology)*, *82*(1), 39–67. [doi:10.1111/rssb.12348](https://doi.org/10.1111/rssb.12348) — key `cinelli2020sensitivity`

- Pearl, J., & Mackenzie, D. (2018). *The Book of Why: The New Science of Cause and Effect*. Basic Books, New York. — key `pearl2018bookofwhy`

- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions in recursive semi-Markovian causal models. In *Proceedings of the 21st National Conference on Artificial Intelligence (AAAI)*, Vol. 2, pp. 1219–1226. — key `shpitser2006identification`

- Spirtes, P., Glymour, C., & Scheines, R. (2000). *Causation, Prediction, and Search* (2nd ed.). MIT Press, Cambridge, MA. — key `spirtes2000causation`

- Peters, J., Janzing, D., & Schölkopf, B. (2017). *Elements of Causal Inference: Foundations and Learning Algorithms*. MIT Press, Cambridge, MA. — key `peters2017elements`

- Bareinboim, E., & Pearl, J. (2016). Causal inference and the data-fusion problem. *Proceedings of the National Academy of Sciences*, *113*(27), 7345–7352. — key `bareinboim2016causal`

- Imbens, G. W., & Rubin, D. B. (2015). *Causal Inference for Statistics, Social, and Biomedical Sciences*. Cambridge University Press, Cambridge. — key `imbens2015causal`

- Gnecco, N., Peters, J., Engelke, S., & Pfister, N. (2026). Boosted control functions: distribution generalization and invariance in confounded models. *Journal of Machine Learning Research*, *27*(46), 1–57. [https://jmlr.org/papers/v27/24-2207.html](https://jmlr.org/papers/v27/24-2207.html) — key `gnecco2026bcf`

## g-methods and longitudinal confounding

- Robins, J. M. (1986). A new approach to causal inference in mortality studies with a sustained exposure period—application to control of the healthy worker survivor effect. *Mathematical Modelling*, *7*(9–12), 1393–1512. — key `robins1986new`

- Robins, J. M., Hernán, M. A., & Brumback, B. (2000). Marginal structural models and causal inference in epidemiology. *Epidemiology*, *11*(5), 550–560. — key `robins2000marginal`

- Hernán, M. A., & Robins, J. M. (2020). *Causal Inference: What If*. Chapman & Hall/CRC, Boca Raton, FL. — key `hernan2020causal`

## Time-indexed and dynamical models

Unrolled lag DAGs (`TemporalDAGSpec`, `unroll_temporal_dag`, `TemporalEffectQuery`) apply
standard backdoor criteria on an expanded static graph, while continuous-time
and kinetic extensions build on dynamical SCMs and interventional embedding
entropy:

- Pearl (2009), Ch. on dynamic models / time-indexed SCMs
- Discrete-time CDMs in the [CDCS book](https://simonab.github.io/causal-dynamics-book/) (Ch. 28)
- Díaz, I., Williams, N., Hoffman, K. L., & Schenck, E. J. (2023). Nonparametric causal effects based on longitudinal modified treatment policies. *Journal of the American Statistical Association*, *118*(542), 846–857. [doi:10.1080/01621459.2021.1955691](https://doi.org/10.1080/01621459.2021.1955691) — key `diaz2023lmtp` (implemented in CausalTargeted)
- Peters, J., Bauer, S., & Pfister, N. (2022). Causal models for dynamical systems. In H. Geffner, R. Dechter, & J. Y. Halpern (Eds.), *Probabilistic and Causal Inference: The Works of Judea Pearl* (pp. 671–690). Association for Computing Machinery. [doi:10.1145/3501714.3501752](https://doi.org/10.1145/3501714.3501752) ([arXiv:2001.06208](https://arxiv.org/abs/2001.06208)) — key `peters2022causal`
- Pfister, N., Bauer, S., & Peters, J. (2019). Learning stable and predictive structures in kinetic systems. *Proceedings of the National Academy of Sciences*, *116*(51), 25405–25411. [doi:10.1073/pnas.1905688116](https://doi.org/10.1073/pnas.1905688116) ([arXiv:1810.11776](https://arxiv.org/abs/1810.11776)) — key `pfister2019causalkinetix`
- Shi, J., Li, Y., Zhao, J., Leng, S., Bao, R., Aihara, K., Chen, L., & Lin, W. (2026). Deciphering interventional dynamical causality from non-intervention complex systems. *The Innovation*, *7*(10), 101358. [doi:10.1016/j.xinn.2026.101358](https://doi.org/10.1016/j.xinn.2026.101358) ([arXiv:2407.01621](https://arxiv.org/abs/2407.01621)) — key `shi2026interventional`
- Shi, J., Chen, L., & Aihara, K. (2022). Embedding entropy: a nonlinear measure of dynamical causality. *Journal of the Royal Society Interface*, *19*(188), 20210766. [doi:10.1098/rsif.2021.0766](https://doi.org/10.1098/rsif.2021.0766) — key `shi2022embedding`

## Mediation identification (structural)

- Pearl, J. (2001). Direct and indirect effects. In *Proceedings of the Seventeenth Conference on Uncertainty in Artificial Intelligence (UAI)*, pp. 411–420. Morgan Kaufmann. — key `pearl2001direct`

- Robins, J. M., & Greenland, S. (1992). Identifiability and exchangeability for direct and indirect effects. *Epidemiology*, *3*(2), 143–155.

- Avin, C., Shpitser, I., & Pearl, J. (2005). Identifiability of path-specific effects. In *Proceedings of the 19th International Joint Conference on Artificial Intelligence (IJCAI)*, pp. 357–363. — key `avin2005identifiability`

- VanderWeele, T. J. (2015). *Explanation in Causal Inference: Methods for Mediation and Interaction*. Oxford University Press, Oxford. — key `vanderweele2015explanation`

## Discovery (optional Associations.jl bridge)

- Spirtes et al. (2000) — PC and constraint-based search
- Chickering, D. M. (2002). Optimal structure identification with greedy search. *Journal of Machine Learning Research*, *3*, 507–554. — key `chickering2002optimal`
- Runge, J., Bathiany, S., Bollt, E., et al. (2019). Detecting and quantifying causal associations in large nonlinear time series datasets. *Science Advances*, *5*(11), eaau4996. [doi:10.1126/sciadv.aau4996](https://doi.org/10.1126/sciadv.aau4996) — key `runge2019detecting`

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
