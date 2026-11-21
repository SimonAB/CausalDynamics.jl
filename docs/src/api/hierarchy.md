# Hierarchy & relational grounding

Specifications and utilities for nested/hierarchical units and relational schemas
grounded to `Graphs.jl` DAGs. For worked guidance on clustered and multi-level
studies, see [Hierarchical & nested units](../hierarchy.md).

## Nested panels and random effects

```@docs
RandomEffectSpec
HIERARCHY_ASSUMPTIONS
assign_cluster_ids
draw_nested_effects
add_nested_effects!
simulate_hierarchical_panel
simulate_hierarchical_intercept_ate
```

## Hierarchical DAG unrolling

```@docs
HierarchicalNestingSpec
HierarchicalUnrolling
unroll_hierarchical_dag
hierarchical_node
hierarchical_node_names
attach_hierarchy_assumptions
```

## Relational grounding

```@docs
RelationalSchema
RelationalSkeleton
RelationalParent
relational_entities
relational_attributes
ground_relational_graph
```

`RelationalSchema` describes entity types, attributes, and binary relation
types. `RelationalSkeleton` supplies the entities and relation instances present
in one situation. A `RelationalParent` declares an attribute-level parent rule;
`ground_relational_graph` expands those rules into an ordinary `Graphs.jl`
directed graph with tuple labels. Identification and temporal unrolling remain
downstream operations on that grounded graph. The prototype does not claim
transportability to unseen skeletons without additional mechanism-invariance and
confounding assumptions.

```julia
schema = RelationalSchema(
    [:signal, :car],
    Dict(:controls => (:signal, :car)),
    Dict(:signal => [:walk], :car => [:brake]),
)
skeleton = RelationalSkeleton(
    schema,
    Dict(:signal => [:s1], :car => [:c1]),
    Dict(:controls => [(:s1, :c1)]),
)
ground_relational_graph(
    skeleton,
    [RelationalParent(:signal, :walk, :car, :brake, :controls)],
)
```
