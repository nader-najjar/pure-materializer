# pure-materializer

> Materialize software from its components.

The current workflows call placeholder implementations and deliberately fail until materialization is rebuilt. The inputs below describe the reserved interface.

Run **Ignition** manually from Actions with mode `materialize` or `bounce`.

For materialize, supply `source_repository` + `source_sha`, including for the materializer itself. Bounce takes no overrides. Only materialize changes saved pins.

First materialize the materializer’s own commit to initialize. Pins are stored in `source-pins.json` on `materialization-state`.

## Concepts

- [Build and OCI Image Packaging](https://app.notion.com/p/3f90a2b787558157a5c2cf7a9b7e92cc?pvs=204)
- [Product Release Pipelines Across Repositories](https://app.notion.com/p/3f90a2b7875581ef953bca201941e0dd?pvs=204)
- [Deployment Testing and Promotion](https://app.notion.com/p/3f90a2b7875581de812ffaddc1e44b83?pvs=204)

## License

All rights reserved. See [LICENSE](LICENSE).
