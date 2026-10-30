let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\fact_work_order.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"schema_version", Int64.Type}, {"project_id", type text},
            {"run_id", type text}, {"source_id", type text}, {"asset_id", type text},
            {"observed_at_utc", type datetimezone}, {"ingested_at_utc", type datetimezone},
            {"evidence_class", type text}, {"quality_status", type text},
            {"work_order_id", type text}, {"opened_at_utc", type datetimezone},
            {"closed_at_utc", type datetimezone}, {"is_closed", type logical},
            {"duration_hours", type number}, {"status", type text},
            {"priority", type text}, {"failure_code", type text}, {"title", type text},
            {"has_cause", type logical}, {"has_resolution", type logical},
            {"checks_count", Int64.Type}, {"parts_count", Int64.Type},
            {"evidence_key", type text}, {"source_key", type text},
            {"observed_date_key", Int64.Type}, {"observed_time_basis", type text},
            {"opened_date_key", Int64.Type}, {"closed_date_key", Int64.Type}
        },
        "en-US"
    )
in
    Typed
