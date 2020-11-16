# Sig #

The simple GPG signature toolchain for directories or git repos.

## Features

  * Generate sha256 manifest for all files in directory
    * Use git for listing if available
  * Add detached signatures to manifest
  * Verify manifest has a minimum threshold of unique detached signatures
  * Verify git history contains a minimum threshold of unique commit siguatures
  * Verify signatures belong to a defined GPG alias group

## Install

  1. Clone

      ```
      git clone git@gitlab.com/pchq/sig.git sig
      ```

  2. Manually verify

      ```
      for file in .sig/*.asc; do gpg --verify $file .sig/manifest.txt; done
      gpg log --show-signature
      less sig
      ```

  3. Self verify

      ```
      ./sig verify --threshold 3
      ```

  4. Copy to $PATH

      ```
      cp sig ~/.local/bin/
      ```

## Methods

### Git

This method verifies a git repo contains signed commits by one or more authors.

If 'threshold' is specified, it searches history until enough unique signatures
are found to satisify the threshold, ensuring all commits between are signed.

If 'group' is specified, all signatures must be by keys that belong to a
defined gpg alias group.

Note: this only proves the history had multiple participants, but not that
the current HEAD was verified by all participants.

#### Assumptions
  - Single sig mode: Repo HEAD controlled by signer
  - Multi-sig mode: Repo has contributions from multiple individuals
  - Multi-sig group mode: Repo has contributions from specified individuals
  - Sha1 is not broken

### Detached

This method verifies the state of this folder was signed exactly as-is by one
or more authors.

If 'threshold' is specified, then that number of signatures must be present.

If 'group' is specified, all signatures must be by keys that belong to a
defined gpg alias group.

#### Assumptions
  - Single sig mode: Folder contents controlled by signer
  - Multi-sig mode: Folder contents verified by multiple signers
  - Multi-sig group mode: Folder contents approved by specified individuals
  - Sha256 is not broken

## Usage

### Verify 1 signature via Detached and Git methods

```
sig verify
```

### Verify 2 unique signatures via Detached and Git methods

```
sig verify --threshold 2
```

### Verify 3 unique signatures from specified signing group via Git method

```
sig verify --threshold 2 --group myteam --method git
```

### Add Detached Signature

```
sig add
```
