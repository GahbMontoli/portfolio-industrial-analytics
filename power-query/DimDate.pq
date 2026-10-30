let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\dim_date.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"date_key", Int64.Type}, {"date", type date},
            {"calendar_year", Int64.Type}, {"quarter_number", Int64.Type},
            {"quarter_label", type text}, {"month_number", Int64.Type},
            {"month_name", type text}, {"year_month_key", Int64.Type},
            {"year_month", type text}, {"iso_year", Int64.Type},
            {"iso_week_number", Int64.Type}, {"day_of_month", Int64.Type},
            {"day_of_week_number", Int64.Type}, {"day_name", type text},
            {"is_weekday", type logical}, {"is_weekend", type logical}
        },
        "en-US"
    )
in
    Typed
