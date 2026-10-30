let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\dim_source.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"source_key", type text}, {"project_id", type text},
            {"source_id", type text}, {"source_kind", type text},
            {"source_uri", type text}, {"source_locator", type text},
            {"source_sha256", type text}, {"source_version", type text},
            {"schema_version", Int64.Type}, {"evidence_class", type text},
            {"license_status", type text}, {"interpretation_limit", type text},
            {"is_unknown", type logical}
        },
        "en-US"
    )
in
    Typed
