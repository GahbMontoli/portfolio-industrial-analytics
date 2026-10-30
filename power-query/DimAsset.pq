let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\dim_asset.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"project_id", type text}, {"asset_id", type text}, {"tag", type text},
            {"asset_name", type text}, {"category", type text}, {"model", type text},
            {"location", type text}, {"criticality", type text},
            {"evidence_class", type text}, {"quality_status", type text},
            {"schema_version", Int64.Type}
        },
        "en-US"
    )
in
    Typed
