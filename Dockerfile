FROM ubuntu:24.04 AS base

RUN dpkg --add-architecture i386 \
	&& apt-get update \
	&& apt-get upgrade -y \
	&& apt-get dist-upgrade -y \
	&& apt-get install -y --no-install-recommends \
		ca-certificates

FROM base AS byond
WORKDIR /byond

RUN apt-get install -y --no-install-recommends \
	curl \
	unzip \
	make \
	libstdc++6:i386 \
    libcurl4:i386

COPY dependencies.sh .

RUN . ./dependencies.sh \
	&& curl -H "User-Agent: vstation/1.0 CI Script" "http://www.byond.com/download/build/${BYOND_MAJOR}/${BYOND_MAJOR}.${BYOND_MINOR}_byond_linux.zip" -o byond.zip \
	&& unzip byond.zip \
	&& cd byond \
	&& sed -i 's|install:|&\n\tmkdir -p $(MAN_DIR)/man6|' Makefile \
	&& make install \
	&& chmod 644 /usr/local/byond/man/man6/* \
	&& apt-get purge -y --auto-remove curl unzip make \
	&& cd .. \
	&& rm -rf byond byond.zip

FROM byond AS build

WORKDIR /vorestation

RUN apt-get install -y --no-install-recommends \
	curl \
    unzip \
    python3 \
    python3-pip \
    git \
    gcc-multilib \
    clang \
    libclang-dev

# DQ build: the icon-repack step (tools/dq_icons) runs under python3 and needs
# Pillow + numpy (+ bidict, used by the vendored tools/dmi module). The upstream
# Dockerfile predates this fork-added step, so install them here.
RUN pip3 install --break-system-packages --no-cache-dir \
    Pillow==12.2.0 \
    numpy==2.4.4 \
    bidict==0.23.1

# DQ build: install the Rust toolchain so the in-tree verdigris FFI lib builds
# inline during build.sh instead of warn-skipping. verdigris/rust-toolchain.toml
# pins the channel + i686 targets (BYOND's 32-bit ABI); rustup reads it when
# cargo runs in verdigris/. gcc-multilib links the i686 cdylib; clang/libclang
# back bindgen (byondapi-sys); git feeds bosion (verdigris build.rs).
ENV PATH="/root/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

COPY . .

# bosion (verdigris/verdigris/build.rs) captures build provenance from git, but
# the build context excludes .git — give it a throwaway repo with one commit so
# the build.rs probe succeeds.
RUN git init -q . \
    && git config user.email build@local \
    && git config user.name "docker build" \
    && git commit -q --allow-empty -m "docker build provenance"

RUN env TG_BOOTSTRAP_NODE_LINUX=1 tools/build/build.sh

FROM base AS rust
RUN apt-get install -y --no-install-recommends \
		curl && \
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
	&& ~/.cargo/bin/rustup target add i686-unknown-linux-gnu

FROM rust AS rust_g
WORKDIR /rust_g

RUN apt-get install -y --no-install-recommends \
	libssl3 \
	gcc-multilib \
	git \
	&& git init \
	&& git remote add origin https://github.com/tgstation/rust-g

COPY dependencies.sh .

RUN . ./dependencies.sh \
	&& git fetch --depth 1 origin "${RUST_G_VERSION}" \
	&& git checkout FETCH_HEAD \
	&& env PKG_CONFIG_ALLOW_CROSS=1 ~/.cargo/bin/cargo build --release --target i686-unknown-linux-gnu --features all

FROM byond
WORKDIR /vorestation

RUN apt-get install -y --no-install-recommends \
        libssl3 \
        zlib1g:i386 \
        libcurl4:i386

COPY --from=build /vorestation/ ./
COPY --from=rust_g /rust_g/target/i686-unknown-linux-gnu/release/librust_g.so ./librust_g.so

#VOLUME [ "/vorestation/config", "/vorestation/data" ]

ENTRYPOINT [ "DreamDaemon", "deepquarry.dmb", "-port", "2303", "-trusted", "-close", "-verbose" ]
EXPOSE 2303
