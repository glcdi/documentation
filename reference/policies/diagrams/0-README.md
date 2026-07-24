# Policy Sequence Diagrams

PlantUML sequence diagrams showing how GLCDI policies affect end-users in concrete scenarios.

## Rendering

### Online (no install)

1. Open [PlantUML Web Server](https://www.plantuml.com/plantuml/uml)
2. Paste the contents of any `.puml` file
3. Click "Submit" to render

### VS Code

Install the [PlantUML extension](https://marketplace.visualstudio.com/items?itemName=jebbs.plantuml) by jebbs, then:
- `Alt+D` to preview the current `.puml` file
- `Ctrl+Shift+P` → "PlantUML: Export Current Diagram" to export as PNG/SVG

Requires a local renderer - the extension supports either:
- PlantUML server (default, uses the online server)
- Local JAR: set `plantuml.jar` path in settings
- Docker: set `plantuml.render` to `PlantUMLServer` with a local container

### Docker (batch render all diagrams)

```bash
cd management/policies/diagrams
docker run --rm -v "$PWD":/data plantuml/plantuml /data/*.puml
```

Outputs `.png` files next to each `.puml`. For SVG:

```bash
docker run --rm -v "$PWD":/data plantuml/plantuml -tsvg /data/*.puml
```

### Local JAR

```bash
# Requires Java 17+
java -jar plantuml.jar -tpng diagrams/*.puml
java -jar plantuml.jar -tsvg diagrams/*.puml
```

## Editing Tips

- Keep the same `skinparam` block across diagrams for visual consistency
- Use `#E8F5E9` (green) for producers, `#E3F2FD` (blue) for connectors/UI, `#F3E5F5` (purple) for Keycloak, `#FFF3E0` (orange) for corporate/external actors
- Use `#FFEBEE` / `#FFCDD2` (red tones) for rejected/blocked evaluation groups
- `note right of` for policy evaluation details, `note over` for user-facing summaries
- Preview frequently - long notes can overflow in narrow renders

## Diagram Index

| File | Scenario |
|------|----------|
| `01-researcher-accesses-soc-data.puml` | Full model calibration happy path |
| `02-producer-blocked-from-research-data.puml` | Access policy filtering (hidden offers) |
| `03-rancher-benchmarking.puml` | Peer-to-peer benchmarking with reciprocal sharing |
| `04-wrong-purpose-rejected.puml` | Contract rejected on purpose mismatch |
| `05-regenerative-producers-exclusive.puml` | Certification-based access (3 participants, 1 asset) |
| `06-time-limited-expiry.puml` | Temporal constraint expiry and renewal |
| `07-corporate-supply-chain-flow.puml` | Corporate ESG flow with payment and retention |
| `08-reciprocal-benchmarking-pool.puml` | Contribute-to-access reciprocity (observer blocked, contributor accesses + shares back) |
| `09-payment-gated-data-exchange.puml` | Payment-gated transfer (post-prototype): finalization → email → external payment → status update → transfer; with v2 deadline-termination via DSP. See [`../../../../../design/payment-gating.md`](../../../design/payment-gating.md). |
