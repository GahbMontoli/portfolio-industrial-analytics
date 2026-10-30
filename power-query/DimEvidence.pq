let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\dim_evidence.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"evidence_key", type text}, {"evidence_class", type text},
            {"quality_status", type text}, {"class_label", type text},
            {"quality_label", type text}, {"interpretation_limit", type text},
            {"is_unknown", type logical}
        },
        "en-US"
    )
in
    Typed
