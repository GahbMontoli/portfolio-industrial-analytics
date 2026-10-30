let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\fact_fault_study.csv"),
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
            {"scenario_id", type text}, {"expectation_met", type logical},
            {"simulated_seconds", type number}, {"target_reached_at_seconds", type number},
            {"final_physical_volume_liters", type number},
            {"final_reported_volume_liters", type number},
            {"maximum_sensor_deviation_liters", type number},
            {"valve_open_at_capacity_steps", Int64.Type},
            {"valve_command_divergence_steps", Int64.Type},
            {"final_valve_command", type logical},
            {"final_valve_effective_state", type logical}, {"observation", type text}
        },
        "en-US"
    )
in
    Typed
