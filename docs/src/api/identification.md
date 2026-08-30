# Identification Algorithms

```@meta
CurrentModule = CausalDynamics
```

Backdoor and frontdoor adjustment criteria delegate to
[CausalInference.jl](https://github.com/mschauer/CausalInference.jl) `gensearch`.
Backdoor listing follows the complete adjustment framework of van der Zander,
Liśkiewicz, and Textor (2019); frontdoor find/min/list builds on the linear-time
criterion of Wienöbst, van der Zander, and Liśkiewicz (2024). See
[References](../references.md#adjustment-set-algorithms-causalinference--gensearch).

For singleton mediators, prefer [`find_frontdoor_mediators`](@ref) over
[`list_frontdoor_adjustment_sets`](@ref): the latter can materialise exponentially
many sets on dense graphs.

## Queries and certificates

```@docs
CausalQuery
TotalEffectQuery
MediationQuery
TemporalEffectQuery
InterventionalPolicyQuery
TransportQuery
identify
IdentificationResult
IdentificationError
MissingnessSpec
MissingnessCertificate
certify_missingness
certificate_dict
graph_fingerprint
identification_report
temporal_adjustment_columns
adjustment_columns
query_panel_columns
OutcomeKind
NodeOutcomeSpec
EstimationPlan
plan_targeted_estimation
identification_support
```

## Adjustment and instruments

```@docs
backdoor_adjustment_set
is_backdoor_adjustable
frontdoor_adjustment_set
find_frontdoor_adjustment_set
find_min_frontdoor_adjustment_set
list_frontdoor_adjustment_sets
find_frontdoor_mediators
find_path_mediators
find_minimal_mediator_sets
MinimalMediatorSets
intercepts_all_directed_paths
find_instruments
is_valid_instrument
find_all_adjustment_sets
CausalDynamics.is_valid_adjustment_set
minimal_adjustment_set
```

## Column resolvers

Map graph node labels to data columns after identification.

```@docs
ColumnResolver
IdentityColumnResolver
DictColumnResolver
resolve_columns
resolve_identification_columns
```
