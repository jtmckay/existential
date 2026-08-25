# decree-webhook — static binary, no runtime.
#
# This service used to ride existential/decree:local and run `node server.js`
# against that image's baked node_modules. It is now self-contained: nothing
# here depends on the decree image, so it can run on the front-door host or
# anywhere else without dragging the npm tree along.
#
# Both bases are pinned by tag *and* digest. The tag documents the version and
# is what `./existential.sh run check-versions` reads and bumps; the digest is
# what Docker actually resolves, so a re-pushed tag cannot change this build.
# Update both together — check-versions --update does.

FROM golang:1.26.5-alpine3.23@sha256:622e56dbc11a8cfe87cafa2331e9a201877271cbff918af53d3be315f3da88cc AS builder

# Never silently fetch a different toolchain: go.mod's floor is 1.22 and this
# image ships 1.26.5, so any download would be a surprise, not a fix. Also
# makes the build work without network access to the toolchain server.
ENV GOTOOLCHAIN=local \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOFLAGS=-mod=readonly

WORKDIR /src

# Dependency layer first so it caches independently of source edits. go.sum is
# committed, so `download` is reproducible and `verify` fails the build if a
# module's contents do not match the recorded hashes.
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY main.go ./
# -trimpath strips local paths, -buildvcs=false keeps build output independent
# of any VCS state, -s -w drop the symbol and DWARF tables. Together these make
# the binary byte-identical across machines for a given input.
RUN go build -trimpath -buildvcs=false -ldflags="-s -w" -o /webhook .

# distroless has no semver tags — the Debian release is part of the repo name
# and everything else is `latest`/`nonroot`/`debug`. check-versions therefore
# tracks this one for digest drift rather than a version bump; moving to a new
# Debian release is a deliberate repo-name change.
FROM gcr.io/distroless/static-debian13:latest@sha256:9197324ba51d9cd071af8505989365c006adf9d6d2067eada25aef00abbb5278

COPY --from=builder /webhook /webhook

# Fail closed if compose forgets to set `user:`. Normal operation overrides this
# with ${EXIST_PUID}:${EXIST_PGID} so inbox files stay host-owned; 65532 is
# distroless's nonroot uid, which cannot write the bind mount — a visible
# permission error rather than a container quietly running as root.
USER 65532:65532

EXPOSE 8801

# No shell, curl or wget in distroless — the binary probes itself. start-period
# is short because startup is just a config parse and a listen.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/webhook", "-healthcheck"]

ENTRYPOINT ["/webhook"]
