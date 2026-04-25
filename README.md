# SiliconSaga — Yggdrasil Realm

Community realm for the SiliconSaga ecosystem. Declares components,
build adapters, identity, and AI context pointers.

## Usage

```bash
cd yggdrasil
ws realm https://github.com/SiliconSaga/realm-siliconsaga.git
ws clone --all
```

## Structure

```
ecosystem.yaml      # Components, defaults, identity
adapters/            # Per-component build commands and AI context
  terasology.yaml
  nordri.yaml
```

## Creating Your Own

Fork this repo, edit `ecosystem.yaml` to point at your org's repos,
and update the adapter files for your build systems.
