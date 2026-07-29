# Graph Operations

```@meta
CurrentModule = CausalDynamics
```

Names also exported by DAGMakie (`find_backdoor_paths`, `find_directed_paths`,
`is_dag`) are written fully qualified so the docs build resolves them
unambiguously when the plotting extension is loaded.

```@docs
d_separated
get_ancestors
get_descendants
get_parents
get_children
markov_boundary
CausalDynamics.find_backdoor_paths
CausalDynamics.find_directed_paths
nodes_on_directed_paths
has_path
CausalDynamics.is_dag
validate_causal_graph
create_causal_graph
```
