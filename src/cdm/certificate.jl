"""Versioned, machine-readable certificates for CDCS analyses."""

const CDCS_CERTIFICATE_SCHEMA = "cdcs.certificate.v2"

"""Return the current certificate schema identifier."""
certificate_schema_version() = CDCS_CERTIFICATE_SCHEMA

"""
    CertificateEnvelope(semantic; environment=NamedTuple())

Wrap semantic analysis identity and optional runtime metadata in a versioned
envelope.  Semantic fields are kept separate from environment fields so a
re-run on another Julia version does not silently change the identity of an
estimand or intervention.
"""
struct CertificateEnvelope{S,E}
    schema_version::String
    semantic::S
    environment::E
end

function CertificateEnvelope(semantic; environment = NamedTuple())
    return CertificateEnvelope(String(CDCS_CERTIFICATE_SCHEMA), semantic, environment)
end

"""Construct a certificate from provenance without conflating runtime metadata."""
function certificate_envelope(
    provenance::CDMProvenance;
    environment = NamedTuple(),
)
    return CertificateEnvelope(provenance_dict(provenance); environment)
end

"""Return a serialisable dictionary representation of a certificate."""
function certificate_dict(certificate::CertificateEnvelope)
    return Dict(
        "schema_version" => certificate.schema_version,
        "semantic" => certificate.semantic,
        "environment" => certificate.environment,
    )
end

export CDCS_CERTIFICATE_SCHEMA, certificate_schema_version, CertificateEnvelope,
    certificate_envelope, certificate_dict
