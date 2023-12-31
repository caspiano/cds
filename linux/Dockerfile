FROM debian:11 AS debian

RUN apt-get update \
 && apt-get install -y build-essential libevent-dev libpcre2-dev automake libtool pkg-config git curl llvm-13 clang-13 \
 && (pkg-config || true)

ARG release
ENV CC="clang-13"
ENV CFLAGS="-fPIC -pipe ${release:+-O3}"

# Build libgc
ARG gc_version

# Helper script to shallow clone a git repo and checkout a specific tag
ARG scripts_path=build_context/scripts
COPY ${scripts_path}/shallow-clone.sh /tmp/shallow-clone.sh

RUN /tmp/shallow-clone.sh ${gc_version} https://github.com/ivmai/bdwgc \
 && cd bdwgc \
 \
 && ./autogen.sh \
 && ./configure --disable-debug --disable-shared --enable-large-config \
 && make -j$(nproc)

FROM alpine:3.17

ARG llvm_version=15

# Install dependencies
RUN apk add --no-cache \
      # Statically-compiled llvm
      llvm${llvm_version}-dev llvm${llvm_version}-static \
      # Static stdlib dependencies
      zlib-static yaml-static libxml2-static pcre2-dev libevent-static \
      # Static compiler dependencies
      libffi-dev \
      # Build tools
      git gcc g++ make automake libtool autoconf bash coreutils curl

ARG release
ENV CFLAGS="-fPIC -pipe ${release:+-O3}"

# Build libgc (again, this time for musl)
ARG gc_version

# Helper script to shallow clone a git repo and checkout a specific tag
ARG scripts_path=build_context/scripts
COPY ${scripts_path}/shallow-clone.sh /tmp/shallow-clone.sh

RUN /tmp/shallow-clone.sh ${gc_version} https://github.com/ivmai/bdwgc \
 && cd bdwgc \
 \
 && ./autogen.sh \
 && ./configure --disable-debug --disable-shared --enable-large-config \
 && make -j$(nproc) CFLAGS="-DNO_GETCONTEXT ${CFLAGS}"

# This overrides default CRYSTAL_LIBRARY_PATH baked into the binary (starting with 1.2.0)
# or configured via wrapper script (before 1.2.0) because we want to link against
# the newly-built libraries, not the ones shipped with the bootstrap compiler.
ENV CRYSTAL_LIBRARY_PATH=/bdwgc/.libs/
RUN llvm-config --version

ARG previous_crystal_release
COPY ${previous_crystal_release} /tmp/crystal.tar.gz

# TODO: Update path to new install directory /tmp/crystal/bin after migration period
ENV PATH=${PATH}:/tmp/crystal/lib/crystal/bin/
RUN mkdir -p /tmp/crystal \
  && tar xz -f /tmp/crystal.tar.gz -C /tmp/crystal --strip-component=1 \
  && crystal --version \
  && shards --version

# Build crystal
ARG crystal_version
ARG crystal_sha1
ARG gnu_target

RUN /tmp/shallow-clone.sh ${crystal_sha1} https://github.com/crystal-lang/crystal \
 && cd crystal \
 \
 && make crystal stats=true static=true ${release:+release=true} \
                 CRYSTAL_CONFIG_TARGET=${gnu_target} \
 && ([ "$(ldd .build/crystal 2>&1 | wc -l)" -eq "1" ] || { echo './build/crystal is not statically linked'; ldd .build/crystal; exit 1; })

# Build shards
ARG shards_version
ARG musl_target
RUN /tmp/shallow-clone.sh ${shards_version} https://github.com/crystal-lang/shards \
 && cd shards \
 # FIXME: Remove this workaround for https://github.com/crystal-lang/crystal/issues/10861
 && touch shard.lock \
 && make SHARDS=false CRYSTAL=/crystal/bin/crystal \
         FLAGS="--stats --target ${musl_target} --static ${release:+--release}" \
 \
 && ([ "$(ldd bin/shards 2>&1 | wc -l)" -eq "1" ] || { echo 'shards is not statically linked'; ldd bin/shards; exit 1; })

COPY --from=debian /bdwgc/.libs/libgc.a /libgc-debian.a

ARG package_iteration

RUN \
 # Copy libgc.a to /lib/crystal/
 mkdir -p /output/lib/crystal/ \
 && cp /libgc-debian.a /output/lib/crystal/libgc.a \
 \
 # Install crystal
 && make -C /crystal install DESTDIR=/output PREFIX= \
 \
 # TODO: Remove legacy paths to previous install directories after migration period
 && ln -s ../../bin /output/lib/crystal/bin \
 && ln -s .. /output/lib/crystal/lib \
 \
 # Install shards
 && make -C /shards install DESTDIR=/output PREFIX= \
 \
 # Create tarball
 && mv /output /crystal-${crystal_version}-${package_iteration} \
 && mkdir /output \
 && tar -cvf /output/crystal-${crystal_version}-${package_iteration}.tar /crystal-${crystal_version}-${package_iteration}
