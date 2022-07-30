# PresentationServicePerformance

Run benchmark:
```shell
swift run -c release PresentationServicePerformance run \
    --cycles 1 \
    --disable-cutoff true \
    --min-size 2048 --max-size 2097152 --smoothness 1 \
    --label (Go|Scala|Swift|...) \
    out/run.json
```

Render chart:
```shell
swift run -c release PresentationServicePerformance render out/run.json out/report.svg
```
