let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\fact_h3_experiment.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"schema_version", Int64.Type}, {"project_id", type text},
            {"run_id", type text}, {"source_id", type text},
            {"observed_at_utc", type datetimezone}, {"ingested_at_utc", type datetimezone},
            {"evidence_class", type text}, {"quality_status", type text},
            {"replication", Int64.Type}, {"seed", Int64.Type},
            {"intervention_id", type text}, {"baseline_exposure_hours", type number},
            {"intervention_exposure_hours", type number},
            {"exposure_hours_avoided", type number},
            {"baseline_high_risk_events", Int64.Type},
            {"intervention_high_risk_events", Int64.Type},
            {"high_risk_events_avoided", Int64.Type},
            {"baseline_minimum_margin_c", type number},
            {"intervention_minimum_margin_c", type number},
            {"minimum_margin_gain_c", type number}
        },
        "en-US"
    )
in
    Typed
