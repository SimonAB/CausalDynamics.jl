"""Stable semantic provenance for causal-dynamical analyses."""

"""
    CDMProvenance(; graph, mechanisms, observation, policy, exogenous,
        intervention, scale_map="", numerical="", coupling="", estimand="",
        identification="", estimator="", positivity="", sensitivity="")

Versioned identifiers for the semantic components of one CDM analysis. Identifiers
are supplied by the caller because executable Julia functions cannot be reliably
fingerprinted from source alone.
"""
struct CDMProvenance
    graph::String
    mechanisms::String
    observation::String
    policy::String
    exogenous::String
    intervention::String
    scale_map::String
    numerical::String
    coupling::String
    estimand::String
    identification::String
    estimator::String
    positivity::String
    sensitivity::String
end

"""Backward-compatible positional constructor for the original provenance fields."""
function CDMProvenance(
    graph::String, mechanisms::String, observation::String, policy::String,
    exogenous::String, intervention::String, scale_map::String, numerical::String,
    coupling::String,
)
    return CDMProvenance(
        graph, mechanisms, observation, policy, exogenous, intervention,
        scale_map, numerical, coupling, "", "", "", "", "",
    )
end

function CDMProvenance(
    ; graph,
    mechanisms,
    observation,
    policy,
    exogenous,
    intervention,
    scale_map = "",
    numerical = "",
    coupling = "",
    estimand = "",
    identification = "",
    estimator = "",
    positivity = "",
    sensitivity = "",
)
    return CDMProvenance(
        string(graph), string(mechanisms), string(observation), string(policy),
        string(exogenous), _provenance_intervention_id(intervention), string(scale_map), string(numerical),
        string(coupling), string(estimand), string(identification), string(estimator),
        string(positivity), string(sensitivity),
    )
end

_provenance_intervention_id(intervention::AbstractTypedIntervention) =
    canonical_intervention(intervention)

_provenance_intervention_id(intervention) = string(intervention)

"""Return canonical serialisable provenance metadata."""
function provenance_dict(provenance::CDMProvenance)
    return Dict(
        "graph" => provenance.graph,
        "mechanisms" => provenance.mechanisms,
        "observation" => provenance.observation,
        "policy" => provenance.policy,
        "exogenous" => provenance.exogenous,
        "intervention" => provenance.intervention,
        "scale_map" => provenance.scale_map,
        "numerical" => provenance.numerical,
        "coupling" => provenance.coupling,
        "estimand" => provenance.estimand,
        "identification" => provenance.identification,
        "estimator" => provenance.estimator,
        "positivity" => provenance.positivity,
        "sensitivity" => provenance.sensitivity,
    )
end

"""Return a stable SHA-256 fingerprint for semantic provenance metadata."""
function provenance_fingerprint(provenance::CDMProvenance)
    fields = provenance_dict(provenance)
    canonical = join([
        "$(ncodeunits(key)):$(key)$(ncodeunits(fields[key])):$(fields[key])"
        for key in sort!(collect(keys(fields)))
    ], "|")
    return bytes2hex(sha256(canonical))
end

export CDMProvenance, provenance_dict, provenance_fingerprint
