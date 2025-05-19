FROM gcr.io/kaniko-project/executor:v1.23.0-debug

SHELL ["/busybox/sh", "-c"]

# Download crane
RUN set -eux; \
    case "$(arch)" in \
		'x86_64') \
			url='https://github.com/google/go-containerregistry/releases/download/v0.19.1/go-containerregistry_Linux_x86_64.tar.gz'; \
			sha256='5f2b43c32a901adaaabaa78755d56cea71183954de7547cb4c4bc64b9ac6b2ff'; \
			;; \
		'aarch64') \
			url='https://github.com/google/go-containerregistry/releases/download/v0.19.1/go-containerregistry_Linux_arm64.tar.gz'; \
			sha256='9118c29cdf2197441c4a934cf517df76c021ba12a70edc14ee9dc4dc08226680'; \
			;; \
		*) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
    esac; \
    \
    cd /workspace; \
    wget -O crane.tar.gz "$url"; \
    echo "$sha256 crane.tar.gz" | sha256sum -c -; \
    tar -xzf crane.tar.gz; \
    mv crane /kaniko; \
    rm *; \
    mkdir /kaniko/build;

COPY entrypoint.sh /kaniko/entrypoint.sh

ENTRYPOINT ["/kaniko/entrypoint.sh"]

LABEL repository="https://github.com/vshulkin/kaniko" \
    maintainer="<vshulkin@gmail.com>"
