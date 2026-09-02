# API collections — the organization pattern

Every folder and every file in this tree starts with a **two-digit index**:

```
00-dop-core-grpc/
  00-identity/
    00-ensure-user.bru
    01-list-accounts.bru
    02-create-invite.bru
  01-hierarchy/   02-resource/   03-demand/    04-workflow/
  05-cost/        06-delivery/   07-knowledge/ 08-execution/
  09-event/       10-attention/  11-agent/
01-dop-api-grpc/
02-dop-api-rest/
```

**No space in a name, and no `folder.bru`.** The first version used `00 - identity` and a
`folder.bru` per folder; Bruno started reporting an error on every request. With no CLI to
reproduce it here, both things went — the space because it travels badly through tooling and
scripts, and `folder.bru` because it is a recent feature: a version that does not know it reads
it as a REQUEST with no method and no URL. The index, which is what matters, stayed where it
was.

## Why an index in the NAME, and not only Bruno's `seq`

Bruno's `seq` orders things inside the tool and is invisible everywhere else. The index in the
name orders things in `ls`, in `git diff`, in the editor's file browser and in a PR review —
which is where most people meet these files.

The two coexist: each `.bru`'s `seq` **follows** the name's index, and each folder has a
`folder.bru` with the same number. One place decides the order; the others repeat it. If they
diverge, the name is the truth — it is what shows up in the review.

## The order is not alphabetical: it is the execution order

Inside a folder, the index follows **the sequence in which somebody actually walks** the flow.
In `identity`, `ensure-user` comes before `list-accounts` because there is no account to list
before the first sign-in. In `resource`, `create-integration` comes before `set-credential`
because there is nowhere to keep the credential before the resource exists.

Ordering alphabetically would put `create-invite` ahead of `ensure-user`, and the collection's
first request would fail — teaching whoever arrives that the collection is broken, when what is
broken is the order.

## The collections' order

`00` is the **core**, because it is the source of truth: its contract is what the edges
translate. Then come the edge's two surfaces, gRPC (`01`) and REST (`02`) — both call the same
code in the BFF, and there is a parity test proving it.

## The domain names are the CODE's

`identity`, `hierarchy`, `resource`, `demand` — the same as the protos' and the domain
packages', even where the documentation around them was in another language. A numbered index
with a label that does not match the code is half a pattern: whoever looks for
`hierarchy.proto` needs to find the matching folder without translating.

## When adding

- **A new request in the middle of the flow:** renumber the following ones. An index with a
  gap or a repeat is worse than renumbering — it suggests something is missing.
- **A body copied from a call that really ran**, never invented. This collection has already
  had a request the server refused while the example looked correct.
- **`docs {}` explains the WHY**, not what the route does — the name already says that.

## What this collection does NOT cover yet

The **core is complete**: the 12 domains, with each request's body validated against the
running server — none was invented.

The **edge** exposes 12 gRPC services and 63 REST routes; the collection covers 3 of them
(`identity`, `hierarchy`, `resource`). Requests are missing for `workflow`, `demand`,
`delivery`, `knowledge`, `cost`, `execution`, `stream`, `runtime` and `attention` — the gap is
the COLLECTION's, not the API's.

It is written here on purpose: with the index, the gap is visible in the tree itself, instead
of being discovered by somebody who looked and did not find.
