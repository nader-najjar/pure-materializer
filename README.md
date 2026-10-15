# pure-materializer

Run **Materialization** manually from Actions to build the sources registered in [repositories.json](.github/repositories.json). Each entry specifies its build system and native runners. CI builds each repository on every listed runner using the same source pin.

Materialization calls a pinned workflow from [global-materialization-workflows](https://github.com/nader-najjar/global-materialization-workflows). Each source build must produce `build/release-artifact.tar.gz`, which CI uploads as `release-artifact-<owner>--<repository>-<SHA>-<runner>`.

With `bounce: false`, supply `source_repository` and `source_sha` to save one new source pin. With `bounce: true`, omit both source inputs to rebuild the saved pins unchanged.

Pins persist in `source-pins.json` on the automatically created `materialization-state` branch. The selection job serializes updates and saves pins before CI; a failed build keeps the attempted pins. Initialize each registered repository with a normal run before bouncing. Until every repository has a pin, runs save their input but stop before CI.

## Concepts

- [Build and OCI Image Packaging](https://app.notion.com/p/3f90a2b787558157a5c2cf7a9b7e92cc?pvs=204)
- [Product Release Pipelines Across Repositories](https://app.notion.com/p/3f90a2b7875581ef953bca201941e0dd?pvs=204)
- [Deployment Testing and Promotion](https://app.notion.com/p/3f90a2b7875581de812ffaddc1e44b83?pvs=204)
