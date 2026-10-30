let
    Source = Csv.Document(
        File.Contents(pDataRoot & "\\dim_project.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed = Table.TransformColumnTypes(
        Headers,
        {
            {"project_id", type text},
            {"project_name", type text},
            {"domain", type text}
        },
        "en-US"
    )
in
    Typed
