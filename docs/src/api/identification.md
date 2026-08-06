# Identification Algorithms

```@meta
CurrentModule = CausalDynamics
```

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
certificate_dict
graph_fingerprint
identification_report
```

## Adjustment and instruments

```@docs
backdoor_adjustment_set
is_backdoor_adjustable
frontdoor_adjustment_set
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
