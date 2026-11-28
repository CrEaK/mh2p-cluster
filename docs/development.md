# Building and testing

`CLAUDE.md` in the repository root has the full list of commands and the hard-won facts about the unit. The short version:

## What is built here and what is not

- **Built here:** the fork's Java classes (`modkit/build_aa_jar.sh`, ECJ at Java 1.4 level against the unit's stock classes), the CarPlay map hook (`src/altscreen/build.sh`), the navigation hook and its helper (`src/navhook/build.sh`), the stand-in class (`modkit/stub/build_stub.sh`). The two native builds use luka-dev's QNX 6.5 toolchain image in Docker.
- **Not built here:** the original project's programs (cluster daemon, Android Auto hook, CarPlay turn hook). They come from the release zip under `builds/`; the changes this fork needs are byte patches that are checked before and after (`modkit/patches/`).

The built results are tracked under `modkit/Mods/ClusterIntegration/Update/`, so a package can be put together without a toolchain.

## Package

```bash
modkit/build_sd_package.sh builds/ClusterIntegration_v0034_beta2_candidate_90d0b76.zip \
                           builds/ClusterIntegration_v0034_beta2_candidate_90d0b76_audi.zip
```

## Tests

```bash
# shell syntax, with the stand-in for the unit's shell
mksh -n modkit/Mods/ClusterIntegration/Update/install.sh

# every installer test under three simulated unit tool sets (needs root:
# the scripts write /mnt/app, /fs, /ifs; a container is the easy way)
sudo modkit/test/run_tests.sh
```

The tests assert on the installer's log lines, so a wording change in `install.sh` usually needs the matching change in `modkit/test/gate_*.sh`. Every change in the installer's behaviour gets a test.

## Rules of the house

- Stock classes and programs from a unit are untrusted input: keep them outside the repository, inspect them (`javap`, disassembly), never run them.
- Audi's files do not go into the repository or into a package.
- Nothing is called confirmed until it ran on a car; the notes say on which car and when.
