# template-pure-pipeline

A central GitHub Actions pipeline connecting this repository with [legacy-nix-template-pure-java](https://github.com/nader-najjar/legacy-nix-template-pure-java).

## Flow

Java pull requests run Java CI; pipeline pull requests run the admission tests. Main-branch pushes start the central release flow:

```text
Java main push -> Start Pipeline -> Pipeline
Pipeline main push -------------> Pipeline
    -> Admit Inputs -> CI / Build -> CD / OCI Image Packaging -> OCI archive
```

The workflow definitions are [pipeline.yml](.github/workflows/pipeline.yml), [cd.yml](.github/workflows/cd.yml), and Java's [reusable CI](https://github.com/nader-najjar/legacy-nix-template-pure-java/blob/main/.github/workflows/ci.yml).

## Setup

1. Put both repositories' workflow changes on their respective `main` branches.
2. Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) owned by `nader-najjar`, selecting only `template-pure-pipeline` with **Actions: Read and Write**.
3. In the Java repository, set the Actions repository secret **`PIPELINE_DISPATCH_TOKEN`** to that token. Keep its value outside committed code and replace it before expiration.
4. Push to Java's `main`, or run **Pipeline** manually in this repository's Actions tab.

Additional personally owned source repositories can use the same notification secret. Organization-owned repositories can share a restricted organization secret. Provisioning can use GitHub's API or Terraform; initial PAT creation and renewal remain credential bootstrap tasks.

## Usage

Manual runs accept `java_commit`, a full Java commit SHA. Leave it empty to keep the last admitted Java selection, or select Java main during initial setup. To roll back, start a new run with the desired older commit.

Retries reuse the run's original input selection. Each stage allows retries of its latest admitted run and skips attempts from older runs. Ordering follows central workflow creation, rather than the original source push time. Preserve the admission records and central workflow counter identity; resetting either requires an explicit state migration.

Java's reusable CI orchestration is referenced at `main`; the application checkout uses the selected exact commit. A full rerun can resolve newer reusable orchestration, while a partial rerun retains its original definition.

## Outputs

The Linux/ARM64 release produces `release-artifact-<Java SHA>` and `oci-image-<Java SHA>` in the central run. The OCI artifact contains `oci-image.tar`. Runtime IaC must select the matching architecture and compatible native libraries. Keep the producing run and artifact IDs with published outputs; GitHub artifacts expire.

## Scope

The current example builds legacy Java and packages its OCI image. The IaC, Java/Bazel, Python/Bazel, and TypeScript/Bazel composition, registry publication, environment deployment, and runtime validation remain planned.

## Concepts

- [Build and OCI Image Packaging](https://app.notion.com/p/3f90a2b787558157a5c2cf7a9b7e92cc?pvs=204)
- [Product Release Pipelines Across Repositories](https://app.notion.com/p/3f90a2b7875581ef953bca201941e0dd?pvs=204)
- [Deployment Testing and Promotion](https://app.notion.com/p/3f90a2b7875581de812ffaddc1e44b83?pvs=204)

## Validation

Run `bash .github/scripts/admit-stage.test.sh`. Java's verification command is `./universal-build build`.
