#!/busybox/sh
set -e pipefail

if [ "$INPUT_DEBUG" = "true" ]; then
    set -x
fi

OLDIFS=$IFS

REGISTRY="${INPUT_REGISTRY:-"docker.io"}"
IMAGE="$INPUT_IMAGE"
BRANCH=$(echo "$GITHUB_REF" | sed -E "s/refs\/(heads|tags)\///g" | sed -e "s/\//-/g")
TAG=${INPUT_TAG:-$({ [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; } && echo latest || echo "$BRANCH")}
TAG="${TAG:-"latest"}"
TAG="${TAG#$INPUT_STRIP_TAG_PREFIX}"
USERNAME="${INPUT_USERNAME:-$GITHUB_ACTOR}"
PASSWORD="${INPUT_PASSWORD:-$GITHUB_TOKEN}"
REPOSITORY="$IMAGE"
IMAGE="${IMAGE}:${TAG}"
CONTEXT_PATH="$INPUT_PATH"

if [ "$INPUT_TAG_WITH_LATEST" = "true" ]; then
    IMAGE_LATEST="${REPOSITORY}:latest"
fi

ensure() {
    if [ -z "${1}" ]; then
        echo >&2 "Unable to find the ${2} variable. Did you set with.${2}?"
        exit 1
    fi
}

ensure "${REGISTRY}" "registry"
ensure "${USERNAME}" "username"
ensure "${PASSWORD}" "password"
ensure "${IMAGE}" "image"
ensure "${TAG}" "tag"
ensure "${CONTEXT_PATH}" "path"

if [ "$REGISTRY" = "ghcr.io" ]; then
    IMAGE_NAMESPACE="$(echo "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"
    # Set `/` separator, unless image is pre-fixed with dash or slash
    [ -n "$REPOSITORY" ] && expr "$REPOSITORY" : "^[-/]" > /dev/null && SEPARATOR="/"
    IMAGE="$IMAGE_NAMESPACE$SEPARATOR$IMAGE"
    REPOSITORY="$IMAGE_NAMESPACE$SEPARATOR$REPOSITORY"

    if [ -n "$IMAGE_LATEST" ]; then
        IMAGE_LATEST="${IMAGE_NAMESPACE}/${IMAGE_LATEST}"
    fi

    if [ -n "$INPUT_CACHE_REGISTRY" ]; then
        INPUT_CACHE_REGISTRY="${REGISTRY}/${IMAGE_NAMESPACE}/${INPUT_CACHE_REGISTRY}"
    fi
fi

if [ "$REGISTRY" != "docker.io" ]; then
    IMAGE="${REGISTRY}/${IMAGE}"

    if [ -n "$IMAGE_LATEST" ]; then
        IMAGE_LATEST="${REGISTRY}/${IMAGE_LATEST}"
    fi
fi

CACHE="${INPUT_CACHE:+"--cache=true"}"
CACHE="$CACHE"${INPUT_CACHE_TTL:+" --cache-ttl=$INPUT_CACHE_TTL"}
CACHE="$CACHE"${INPUT_CACHE_REGISTRY:+" --cache-repo=$INPUT_CACHE_REGISTRY"}
CACHE="$CACHE"${INPUT_CACHE_DIRECTORY:+" --cache-dir=$INPUT_CACHE_DIRECTORY"}
CONTEXT="--context $GITHUB_WORKSPACE/$CONTEXT_PATH"
DOCKERFILE="--dockerfile $CONTEXT_PATH/${INPUT_BUILD_FILE:-Dockerfile}"
TARGET=${INPUT_TARGET:+"--target=$INPUT_TARGET"}

ARGS="$CACHE $CONTEXT $DOCKERFILE $TARGET $INPUT_EXTRA_ARGS"

crane auth login "$REGISTRY" -u "$USERNAME" -p "$PASSWORD"

runKaniko() {
    # https://github.com/GoogleContainerTools/kaniko/issues/1803
    # https://github.com/GoogleContainerTools/kaniko/issues/1349
    IFS=''
    kaniko_cmd="executor ${1} --reproducible --force --cleanup"
    echo "Running kaniko command: ${kaniko_cmd}"
    eval "${kaniko_cmd}"
    IFS=$OLDIFS
}

if [ -n "$INPUT_PLATFORMS" ]; then
    # Build image for all platforms, then push the manifest
    platformArray=$(echo "$INPUT_PLATFORMS" | sed 's/,/ /g' )
    echo "⚒️ Building image $IMAGE for the following platforms: $platformArray"

    for platform in $platformArray; do
        echo; echo "📦 Building image for $platform"

        platformFn=$(echo "$platform" | sed 's#/#-#g')

        DESTINATION="--no-push --tarPath /kaniko/build/${platformFn}.tar --destination $IMAGE"
        DIGEST="--image-name-tag-with-digest-file=/kaniko/build/${platformFn}_image-tag-digest"

        targetos=$(echo "$platform" | cut -d/ -f1)
        targetarch=$(echo "$platform" | cut -d/ -f2)
        targetvariant=$(echo "$platform" | cut -d/ -f3)

        case "$targetarch" in
            'amd64') targetarchAlt="x86_64" ;;
            'arm64') targetarchAlt="aarch64" ;;
            'i386') targetarchAlt="i686" ;;
            '386') targetarchAlt="i686" ;;
            'ppc64le') targetarchAlt="powerpc64le" ;;
            'arm')
                case "$targetvariant" in
                    'v5') targetarchAlt="armv5te" ;;
                    'v7') targetarchAlt="armv7" ;;
                    *) targetarchAlt="arm" ;;
                esac
                ;;
            *) targetarchAlt="$targetarch" ;;
        esac

        runKaniko "${ARGS} --custom-platform=${platform} --build-arg TARGETPLATFORM='${platform}' --build-arg TARGETOS='${targetos}' --build-arg TARGETARCH='${targetarch}' --build-arg TARGETARCH_ALT='${targetarchAlt}' --build-arg TARGETVARIANT='${targetvariant}' $DESTINATION $DIGEST"

        echo "✅ $platform image built: $(head -n 1 "/kaniko/build/${platformFn}_image-tag-digest")"
    done

    echo; echo "🚀 Pushing images"

    DIGESTS=""
    for platform in $platformArray; do
        platformFn=$(echo "$platform" | sed 's#/#-#g')
        digest=$(head -n 1 "/kaniko/build/${platformFn}_image-tag-digest")

        echo "Pushing $platform img $digest"
        crane push "/kaniko/build/${platformFn}.tar" "$digest"
        DIGESTS="$DIGESTS -m $digest"
    done

    manifest_cmd="crane index append -t $IMAGE $DIGESTS"
    echo "Building manifest: $manifest_cmd"
    IMAGE_TAG_DIGEST=$(eval "$manifest_cmd")

    if [ -n "$IMAGE_LATEST" ]; then
        crane tag "$IMAGE" latest
    fi
else
    # Build and push image for the default platform
    echo "⚒️ Building image $IMAGE"

    DESTINATION="--destination $IMAGE"
    if [ -n "$IMAGE_LATEST" ]; then
        DESTINATION="$DESTINATION --destination $IMAGE_LATEST"
    fi
    DIGEST="--image-name-tag-with-digest-file=/kaniko/build/image-tag-digest"

    runKaniko "${ARGS} $DESTINATION $DIGEST"
    IMAGE_TAG_DIGEST=$(head -n 1 /kaniko/build/image-tag-digest)
fi

DIGEST=$(echo "$IMAGE_TAG_DIGEST" | cut -f2 -d '@')

echo "🎉 Successfully deployed $IMAGE"
echo "Digest: $DIGEST"
