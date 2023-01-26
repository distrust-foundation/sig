# sig #

The simple code signature toolchain for git repos.

## Features

  * Attach any number of signatures to any given git ref
  * Verify git history contains a minimum threshold of unique commit siguatures
  * Verify signatures belong to a defined GPG alias group
  * Verify code changes made since last time minimum valid signatures were present
  * Allow user to manually verify new keys and add to alias groups on the fly
  * Prompt user to install or upgrade any required tools as needed
  * Signs aginst git agnostic "tree hash" so signatures survive rebases
    * So long as the directory contents at a given ref do not change

## Install

  1. Clone

      ```
      git clone git@gitlab.com/pchq/sig.git sig
      ```

  2. Review source code and signatures manually

      Using `sig` to verify the signatures of `sig` itself is not recommended.

      Consider using the following one liner which is much faster to review:
      ```
      while read -r line; do \
        gpg --verify \
          <(printf "$line" | sed 's/.*pgp://g'| openssl base64 -d -A) \
          <(printf "$line" | sed 's/pgp:.*/pgp/g'); \
      done < <(git notes --ref=signatures show)
      ```

  3. Copy to `$PATH`

      ```
      cp sig ~/.local/bin/
      ```

## Usage

* sig verify [-g,--group=<group>] [-t,--threshold=<N>] [-r,--ref=<ref> ] [-d,--diff=<branch>]
  * Verify m-of-n signatures by given group are present for a given git ref.
* sig add
  * Add signature to this git ref
* sig fetch [-g,--group=<group>]
  * Fetch key by fingerprint. Optionally add to group.
* sig help
  * Show help text.
* sig version
  * Show version information.

## Methods

### Git

This method verifies the current HEAD was signed exactly as-is by one or more
keys.

This counts the commit signature, and any number of signed tags pointing at
this ref.

### Assumptions
  - Single sig mode: Repo contents controlled by signer
  - Multi-sig mode: Repo contents verified by multiple signers
  - Multi-sig group mode: Repo contents approved by specified individuals
  - Hashing scheme for respective backend is not broken: (sha256)

## Examples

#### Verify at least one signature is present with a known key

```
sig verify
```

#### Verify 2 unique signatures from known keys

```
sig verify --threshold 2
```

#### Verify 3 unique signatures from specified signing group

```
sig verify --threshold 3 --group myteam
```

#### Show diff between HEAD and last ref with 2 verified unique signatures

```
sig verify --threshold 2 --diff
```

#### Add signature

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
