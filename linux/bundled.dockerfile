FROM debian:11 AS debian

RUN apt-get update \
 && apt-get install -y curl build-essential git automake libtool pkg-config

ENV CFLAGS="-fPIC -pipe ${release:+-O3}"

# build libpcre2
FROM debian AS libpcre2
ARG libpcre2_version
RUN curl -L https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${libpcre2_version}/pcre2-${libpcre2_version}.tar.gz | tar -zx \
 && cd pcre2-${libpcre2_version} \
 && ./configure --disable-shared --disable-cpp --enable-jit --enable-utf --enable-unicode-properties \
 && make -j$(nproc)

# build libevent

FROM debian AS libevent

ARG scripts_path=build-context/scripts
COPY ${scripts_path}/shallow-clone.sh /tmp/shallow-clone.sh

ARG libevent_version
RUN /tmp/shallow-clone.sh ${libevent_version} https://github.com/libevent/libevent \
 && cd libevent \
 \
 && ./autogen.sh \
 && ./configure --disable-shared --disable-openssl \
 && make -j$(nproc)

FROM debian
ARG crystal_version
ARG package_iteration
ARG libpcre2_version
ARG libevent_version

RUN mkdir -p /output/lib/crystal/lib/

# Copy libraries
COPY --from=libpcre2 pcre2-${libpcre2_version}/.libs/libpcre2-8.a /output/lib/crystal/
COPY --from=libevent libevent/.libs/libevent.a libevent/.libs/libevent_pthreads.a /output/lib/crystal/

# Create tarball
RUN mv /output /crystal-${crystal_version}-${package_iteration} \
 && mkdir /output \
 && tar -cvf /output/bundled-libs.tar /crystal-${crystal_version}-${package_iteration}
