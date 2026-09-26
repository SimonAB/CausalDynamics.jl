"""Schema-level relational structures grounded to ordinary causal graphs.

The relational layer is deliberately small: it describes entity types, relation
instances, and attribute-to-attribute parent rules, then grounds those rules to
a `Graphs.jl` directed graph. Identification and temporal unrolling continue to
operate on the grounded graph.
"""

"""Describe entity types, relation types, and attributes in a relational model."""
struct RelationalSchema
    entity_types::Vector{Symbol}
    relation_types::Dict{Symbol, Tuple{Symbol, Symbol}}
    attributes::Dict{Symbol, Vector{Symbol}}
end

function RelationalSchema(
    entity_types,
    relation_types::AbstractDict,
    attributes::AbstractDict,
)
    entities = Symbol.(collect(entity_types))
    isempty(unique(entities)) || length(unique(entities)) == length(entities) ||
        throw(ArgumentError("entity types must be unique"))
    entity_set = Set(entities)
    relations = Dict{Symbol, Tuple{Symbol, Symbol}}()
    for (name, endpoints) in relation_types
        pair = Tuple(Symbol.(collect(endpoints)))
        length(pair) == 2 || throw(ArgumentError("relation $name must have two endpoints"))
        all(endpoint -> endpoint in entity_set, pair) ||
            throw(ArgumentError("relation $name refers to an unknown entity type"))
        relations[Symbol(name)] = (pair[1], pair[2])
    end
    attrs = Dict{Symbol, Vector{Symbol}}()
    for entity in entities
        values = Symbol.(collect(get(attributes, entity, Symbol[])))
        length(unique(values)) == length(values) ||
            throw(ArgumentError("attributes for $entity must be unique"))
        attrs[entity] = values
    end
    extra = setdiff(Set(Symbol.(collect(keys(attributes)))), entity_set)
    isempty(extra) || throw(ArgumentError("attributes contain unknown entity types: $extra"))
    return RelationalSchema(entities, relations, attrs)
end

"""Provide the entity and relation instances for one relational situation."""
struct RelationalSkeleton
    schema::RelationalSchema
    entities::Dict{Symbol, Vector{Symbol}}
    relations::Dict{Symbol, Vector{Tuple{Vararg{Symbol}}}}
end

function RelationalSkeleton(schema::RelationalSchema, entities::AbstractDict, relations::AbstractDict)
    entity_values = Dict{Symbol, Vector{Symbol}}()
    for entity_type in schema.entity_types
        values = Symbol.(collect(get(entities, entity_type, Symbol[])))
        length(unique(values)) == length(values) ||
            throw(ArgumentError("instances for $entity_type must be unique"))
        entity_values[entity_type] = values
    end
    extra_entities = setdiff(Set(Symbol.(collect(keys(entities)))), Set(schema.entity_types))
    isempty(extra_entities) || throw(ArgumentError("entities contain unknown types: $extra_entities"))
    relation_values = Dict{Symbol, Vector{Tuple{Vararg{Symbol}}}}()
    for (relation_name, endpoints) in schema.relation_types
        expected = length(endpoints)
        instances = Tuple{Vararg{Symbol}}[]
        for instance in get(relations, relation_name, Tuple[])
            values = Tuple(Symbol.(collect(instance)))
            length(values) == expected ||
                throw(ArgumentError("instances for $relation_name must have $expected endpoints"))
            for (endpoint_type, entity_id) in zip(endpoints, values)
                entity_id in entity_values[endpoint_type] ||
                    throw(ArgumentError("relation $relation_name refers to unknown $endpoint_type instance $entity_id"))
            end
            push!(instances, values)
        end
        relation_values[relation_name] = instances
    end
    extra = setdiff(Set(Symbol.(collect(keys(relations)))), Set(keys(schema.relation_types)))
    isempty(extra) || throw(ArgumentError("relations contain unknown names: $extra"))
    return RelationalSkeleton(schema, entity_values, relation_values)
end

"""Declare an attribute-level parent relation for a relational SCM."""
struct RelationalParent
    parent_type::Symbol
    parent_attribute::Symbol
    child_type::Symbol
    child_attribute::Symbol
    relation::Symbol
end

"""Return the entity identifiers present for `entity_type`."""
function relational_entities(skeleton::RelationalSkeleton, entity_type::Symbol)
    haskey(skeleton.entities, entity_type) || throw(ArgumentError("unknown entity type: $entity_type"))
    return copy(skeleton.entities[entity_type])
end

"""Return the declared attributes for `entity_type`."""
function relational_attributes(schema::RelationalSchema, entity_type::Symbol)
    haskey(schema.attributes, entity_type) || throw(ArgumentError("unknown entity type: $entity_type"))
    return copy(schema.attributes[entity_type])
end

"""Ground relational parent rules to a directed graph with tuple node labels.

Relation instances follow the schema endpoint order `(parent, child)`. The
returned `node_labels` vector maps graph vertices to `(entity_type, id,
attribute)` tuples, making the grounding auditable without introducing a new
graph representation for downstream algorithms.
"""
function ground_relational_graph(
    skeleton::RelationalSkeleton,
    parents::AbstractVector{<:RelationalParent},
)
    schema = skeleton.schema
    labels = Tuple{Symbol, Symbol, Symbol}[]
    for entity_type in schema.entity_types, entity_id in skeleton.entities[entity_type]
        for attribute in schema.attributes[entity_type]
            push!(labels, (entity_type, entity_id, attribute))
        end
    end
    graph = SimpleDiGraph(length(labels))
    index = Dict(label => i for (i, label) in enumerate(labels))
    for parent in parents
        haskey(schema.relation_types, parent.relation) ||
            throw(ArgumentError("unknown relation: $(parent.relation)"))
        endpoints = schema.relation_types[parent.relation]
        endpoints == (parent.parent_type, parent.child_type) ||
            throw(ArgumentError("relation $(parent.relation) must be ordered (parent, child)"))
        parent.parent_attribute in schema.attributes[parent.parent_type] ||
            throw(ArgumentError("unknown parent attribute: $(parent.parent_type).$(parent.parent_attribute)"))
        parent.child_attribute in schema.attributes[parent.child_type] ||
            throw(ArgumentError("unknown child attribute: $(parent.child_type).$(parent.child_attribute)"))
        for instance in skeleton.relations[parent.relation]
            source = (parent.parent_type, instance[1], parent.parent_attribute)
            target = (parent.child_type, instance[2], parent.child_attribute)
            add_edge!(graph, index[source], index[target])
        end
    end
    return (; graph, node_labels = labels)
end

export RelationalSchema, RelationalSkeleton, RelationalParent
export relational_entities, relational_attributes, ground_relational_graph
