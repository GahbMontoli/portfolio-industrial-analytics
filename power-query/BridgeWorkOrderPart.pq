let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\bridge_work_order_part.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"schema_version", Int64.Type}, {"project_id", type text},
            {"run_id", type text}, {"source_id", type text},
            {"work_order_id", type text}, {"ordinal", Int64.Type},
            {"part_text", type text}, {"ingested_at_utc", type datetimezone},
            {"evidence_class", type text}, {"quality_status", type text}
        },
        "en-US"
    )
in
    Typed
