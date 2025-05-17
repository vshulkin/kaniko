# Kaniko image builder

Gitea/Github action for building docker images using Kaniko. Kaniko is an image builder
that runs the build steps on the host system without a container runtime. Therefore it
runs without issues in an unprivileged container.

The action script supports building containers for multiple architectures. This requires
the installation of `qemu-user-static` on the runner machine.

This project is based on [action-kaniko](https://github.com/aevea/action-kaniko) by Alex
Viscreanu.

## Usage

```yaml
steps:
  - name: Build docker image
    uses: https://code.thetadev.de/actions/kaniko@v1
    with:
      image: thetadev256/test-actions-helloworld2
      username: thetadev256
      password: ${{ secrets.DOCKER_TOKEN }}
      platforms: "linux/amd64,linux/arm64"
```

## Required Arguments

This action aims to be as flexible as possible, so it tries to define the defaults as
for what I thought of being the most used values. So, technically there is a single
required argument

| variable | description                              | required | default |
| -------- | ---------------------------------------- | -------- | ------- |
| image    | Name of the image you would like to push | true     |         |

## Optional Arguments

| variable         | description                                              | required | default       |
| ---------------- | -------------------------------------------------------- | -------- | ------------- |
| registry         | Docker registry where the image will be pushed           | false    | docker.io     |
| username         | Username used for authentication to the Docker registry  | false    | $GITHUB_ACTOR |
| password         | Password used for authentication to the Docker registry  | false    |               |
| tag              | Image tag                                                | false    | latest        |
| cache            | Enables build cache                                      | false    | false         |
| cache_ttl        | How long the cache should be considered valid            | false    |               |
| cache_registry   | Docker registry meant to be used as cache                | false    |               |
| cache_directory  | Filesystem path meant to be used as cache                | false    |               |
| build_file       | Dockerfile filename                                      | false    | Dockerfile    |
| extra_args       | Additional arguments to be passed to the kaniko executor | false    |               |
| strip_tag_prefix | Prefix to be stripped from the tag                       | false    |               |
| platforms        | Target platforms to build (separated by comma)           | false    |               |
| path             | Path to the build context. Defaults to `.`               | false    | .             |
| tag_with_latest  | Tags the built image with additional latest tag          | false    |               |
| target           | Sets the target stage to build                           | false    |               |
| debug            | Enables trace for entrypoint.sh                          | false    |               |

**Here is where it gets specific, as the optional arguments become required depending on
the registry targeted**

### [docker.io](https://hub.docker.com/)

This is the default, and implicit docker registry, in the same way as with using the
docker CLI In this case, the authentication credentials need to be passed via GitHub
Action secrets

```yaml
with:
  image: aevea/kaniko
  username: ${{ secrets.DOCKERHUB_USERNAME }}
  password: ${{ secrets.DOCKERHUB_PASSWORD }}
```

> NOTE: Dockerhub doesn't support more than one level deep of docker images, so Kaniko's
> default approach of pushing the cache to `$image/cache` doesn't work. If you want to
> use caching with Dockerhub, create a `cache` repository, and specify it in the action
> options.

```yaml
with:
  image: aevea/kaniko
  username: ${{ secrets.DOCKERHUB_USERNAME }}
  password: ${{ secrets.DOCKERHUB_PASSWORD }}
  cache: true
  cache_registry: aevea/cache
```

### [ghcr.io](https://github.com/features/packages)

GitHub's docker registry is a bit special. It doesn't allow top-level images, so this
action will prefix any image with the GitHub namespace. If you want to push your image
like `aevea/action-kaniko/kaniko`, you'll only need to pass `kaniko` to this action.

The authentication is automatically done using the `GITHUB_ACTOR` and `GITHUB_TOKEN`
provided from GitHub itself. But as `GITHUB_TOKEN` is not passed by default, it will
have to be explicitly set up.

```yaml
with:
  registry: ghcr.io
  password: ${{ secrets.GITHUB_TOKEN }}
  image: kaniko
```

> NOTE: GitHub's docker registry is structured a bit differently, but it has the same
> drawback as Dockerhub, and that's that it's not possible to "namespace" images for
> cache. In order to use registry cache, just specify the image meant to be used as
> cache, and Kaniko will push the cache layers to that image instead

```yaml
with:
  registry: ghcr.io
  password: ${{ secrets.GITHUB_TOKEN }}
  image: kaniko
  cache: true
  cache_registry: cache
```

### [registry.gitlab.com](https://docs.gitlab.com/ee/user/packages/container_registry)

GitLab's registry is quite flexible, it allows easy image namespacing, so a project's
docker registry can hold up to three levels of image repository names.

```
registry.gitlab.com/group/project:some-tag
registry.gitlab.com/group/project/image:latest
registry.gitlab.com/group/project/my/image:rc1
```

To authenticate to it, a username and personal access token must be supplied via GitHub
Action Secrets.

```yaml
with:
  registry: registry.gitlab.com
  username: ${{ secrets.GL_REGISTRY_USERNAME }}
  password: ${{ secrets.GL_REGISTRY_PASSWORD }}
  image: aevea/kaniko
```

> NOTE: As GitLab's registry does support namespacing, Kaniko can natively push cached
> layers to it, so only `cache: true` is necessary to be specified in order to use it.

```yaml
with:
  registry: registry.gitlab.com
  username: ${{ secrets.GL_REGISTRY_USERNAME }}
  password: ${{ secrets.GL_REGISTRY_PASSWORD }}
  image: aevea/kaniko
  cache: true
```

### Other registries

If you would like to publish the image to other registries, these actions might be
helpful

| Registry                                            | Action                                        |
| --------------------------------------------------- | --------------------------------------------- |
| Amazon Webservices Elastic Container Registry (ECR) | https://github.com/elgohr/ecr-login-action    |
| Google Cloud Container Registry                     | https://github.com/elgohr/gcloud-login-action |

### Other arguments details

#### tag

The `tag` argument, **unless overridden**, is automatically guessed based on the branch
name. If the branch is `master` or `main` then the tag will be `latest`, otherwise it
will keep the branch name, but replacing any forward slash (/) with a hyphen (-).

If the `v` prefix that it's usually added to the GitHub releases is not desired when
pushed to dockerhub, the `strip_tag_prefix` allows to specify which part of the tag
should be removed.

Example:

```yaml
with:
  registry: ghcr.io
  password: ${{ secrets.GITHUB_TOKEN }}
  image: kaniko
  strip_tag_prefix: pre-
```

for the tag `pre-0.1` will push `kaniko:0.1`, as the `pre-` part will be stripped from
the tag name.

#### platforms

By default, the script will build a single image for the build platform. If you want to
create images for multiple platforms (for example x86 and ARM) you can specify these
using the `platforms` option.
[Here](https://github.com/docker-library/official-images#architectures-other-than-amd64)
is a list of supported docker architectures.

**Note:** Kaniko does not do any emulation by itself. If you are running binaries for a
different architecture during the build process, you need to setup
[`qemu-user-static`](https://wiki.debian.org/QemuUserEmulation) on the build machine.

The script will build the images in the specified order. If all images built
successfully, they will be pushed to the registry and a multi-arch manifest is created.

## Outputs

### `image`

Full reference to the built image with registry and tag.

Example: `thetadev256/test-actions-helloworld2:main`

### `digest`

Full reference to the built image with registry and tag.

Example: `thetadev256/test-actions-helloworld2:main`

### `image-tag-digest`

Full reference to the built image with registry and tag.

Example: `thetadev256/test-actions-helloworld2:main`

## Dockerfile build arguments

Action-Kaniko automatically sets build arguments to allow for different dockerfile actions
depending on the OS and architecture the image is build for.

The supported arguments are:

- `TARGETPLATFORM` (example: linux/amd64)
- `TARGETOS` (example: linux)
- `TARGETARCH` (example: amd64)
- `TARGETARCH_ALT` (alternative architecture name, x86_64 for amd64, otherwise the same as TARGETARCH)
- `TARGETVARIANT` (third docker platform parameter like ARM version)
