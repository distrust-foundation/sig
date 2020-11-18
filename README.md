# Sig #

The simple GPG signature toolchain for directories or git repos.

## Features

  * Generate sha256 manifest for all files in directory
    * Use git for listing if available
  * Add detached signatures to manifest
  * Verify manifest has a minimum threshold of unique detached signatures
  * Verify git history contains a minimum threshold of unique commit siguatures
  * Verify signatures belong to a defined GPG alias group
  * Allow user to manually verify new keys and add to alias groups on the fly
  * Prompt user to install or upgrade any required tools as needed

## Install

  1. Clone

      ```
      git clone git@gitlab.com/pchq/sig.git sig
      ```

  2. Manually generate manifest

      ```
      git ls-files \
      | grep -v .sig \
      | xargs openssl sha256 -r \
      | sed -e 's/ \*/ /g' -e 's/ \.\// /g'
      ```

  3. Manually verify manifest

      ```
      for file in .sig/*.asc; do gpg --verify $file .sig/manifest.txt; done
      git log --show-signature
      less sig
      ```

  4. Self verify

      ```
      ./sig verify --threshold 3
      ```

  5. Copy to $PATH

      ```
      cp sig ~/.local/bin/
      ```

## Usage

* sig verify [-g,--group=<group>] [-t,--threshold=<N>] [-m,--method=<git|detached> ]
  * Verify m-of-n signatures by given group are present for directory
* sig add
  * Add signature to manifest for this directory
* sig manifest
  * Generate hash manifest for this directory
* sig help
  * Show help text.
* sig version
  * Show version information.

## Methods

### Git

This method verifies a git repo contains signed commits by one or more authors.

If 'threshold' is specified, it searches history until enough unique signatures
are found to satisify the threshold, ensuring all commits between are signed.

If 'group' is specified, all signatures must be from keys that belong to a
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

## Examples

#### Verify 1 signature via Detached and Git methods

```
sig verify
```

#### Verify 2 unique signatures via Detached and Git methods

```
sig verify --threshold 2
```

#### Verify 3 unique signatures from specified signing group via Git method

```
sig verify --threshold 2 --group myteam --method git
```

#### Add Detached Signature

```
sig add
```

## Frequently Asked Questions

### Why Bash?

Because it is easy to quickly verify at any time, has wide OS compatibility and
the majority of the needed operations are calling other programs already on
most systems like gpg and openssl.

If this were in another language it would be harder to audit on the fly, would
require the user to have a specific language toolchain installed, and it would
still mostly just be a bunch of shell executions to call system binaries
anyway.

### Why PGP?

In spite of many popular claims to the contrary, PGP is still the most well
supported protocol for distribution, verification, and signing for keys held
by individual humans. It is also the only protocol with wide HSM support
allowing you to keep keys out of system memory and require physical approval
for each operation. E.G a trezor, ledger, yubikey, etc.

Admittedly the GnuPG codebase itself is a buggy dated mess, but PGP as a spec
is still Pretty Good for many use cases. A recent modern rewrite by a number
of former GnuPG team members is near complete and set to give PGP a long and
stable future.

See: https://sequoia-pgp.org/

### Why not "notary" ?

Notary is very well designed and well supports many HSMs.

It may be worth supporting as an alternate method in the future if m-of-n
multisig is ever implemented as a part of the TUF specification which has been
on their TODO list for a few years now.

It has the very desirable feature of conditionally expiring signatures which
no other solution has at the time of this writing, which comes from it being
purpose built for software signing concerns.

See: [The Update Framework](https://theupdateframework.io)

### Why not straight "openssl" ?

Openssl has HSM support via OpenSC that is fairly well supported via PKSC#11.

Contributions suggesting this an alterantive backend to OpenPGP are welcome,
however they would have to also come with methods for key discovery and pinned
key groups via configuration files of some kind.

PGP gives us these features almost for free.

### Why not "signify", "age", or "crev" ?

These alternatives have poor if any support for HSM workflows and thus put
private keys at too much risk of theft or loss to recommend for general use at
this time.

That said, verifying folders/repos that use these methods is certianly of value
and contributions to support doing this on systems where those tools are
available are welcome.
