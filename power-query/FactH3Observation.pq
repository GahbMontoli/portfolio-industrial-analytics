let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\fact_h3_observation.csv"),
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
            {"outdoor_temperature_c", type number}, {"outdoor_rh_percent", type number},
            {"indoor_temperature_c", type number}, {"indoor_rh_percent", type number},
            {"surface_temperature_c", type number}, {"dew_point_c", type number},
            {"dew_point_margin_c", type number}, {"risk_level", type text},
            {"door_open", type logical}, {"hvac_active", type logical},
            {"scenario_id", type text}, {"interval_minutes", Int64.Type}
        },
        "en-US"
    )
in
    Typed
