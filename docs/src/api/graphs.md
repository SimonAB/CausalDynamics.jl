# Graph Operations

```@meta
CurrentModule = CausalDynamics
```

Names also exported by DAGMakie (`find_backdoor_paths`, `find_directed_paths`,
`is_dag`) are written fully qualified so the docs build resolves them
unambiguously when the plotting extension is loaded.

## Paths and ancestry

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
CausalDynamics.has_path
CausalDynamics.is_dag
validate_causal_graph
create_causal_graph
```

## CausalGraph metadata

Optional property bag and attached data on a causal graph wrapper.

```@docs
CausalGraph
attach_data!
get_data
has_data
get_node_names
get_node_name
get_prop
set_prop!
has_prop
delete_prop!
get_node_prop
set_node_prop!
has_node_prop
delete_node_prop!
get_edge_prop
set_edge_prop!
has_edge_prop
delete_edge_prop!
```

## Hypergraphs

Higher-order edges; not used by `identify` or CDM simulation (see [Scope](../scope.md)).

```@docs
Hypergraph
HyperedgeData
add_hyperedge!
rem_hyperedge!
hyperedges
hyperedge_vertices
incident_hyperedges
num_vertices
num_hyperedges
to_simple_graph
```
