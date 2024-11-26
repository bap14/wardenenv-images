#!/usr/bin/env bash
set -e
trap 'error "$(printf "Command \`%s\` at $BASH_SOURCE:$LINENO failed with exit code $?" "$BASH_COMMAND")"' ERR

function error {
  >&2 printf "\033[31mERROR\033[0m: %s\n" "$@"
}

## find directory above where this script is located following symlinks if neccessary
readonly BASE_DIR="$(
  cd "$(
    dirname "$(
      (readlink "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}") \
        | sed -e "s#^../#$(dirname "$(dirname "${BASH_SOURCE[0]}")")/#"
    )"
  )/.." >/dev/null \
  && pwd
)"
pushd "${BASE_DIR}" >/dev/null

## if --push is passed as first argument to script, this will login to docker hub and push images
PUSH_FLAG=${PUSH_FLAG:=0}
if [[ "${1:-}" = "--push" ]]; then
  PUSH_FLAG=1
fi

## login to docker hub as needed
if [[ $PUSH_FLAG != 0 && ${PRE_AUTH:-0} != 1 ]]; then
  if [ -t 1 ]; then
    docker login
  else
    echo "${DOCKER_PASSWORD:-}" | docker login -u "${DOCKER_USERNAME:-}" --password-stdin
  fi
fi

## iterate over and build each version/variant combination; by default building
## latest version; build matrix will override to build each supported version
VERSION_LIST="${VERSION_LIST:-"7.4"}"
VARIANT_LIST="${VARIANT_LIST:-"cli cli-loaders fpm fpm-loaders"}"
MINOR_VERSION=""
BUILT_TAGS=()

##### docker buildx create --use
IMAGE_NAME="${IMAGE_NAME:-"ghcr.io/wardenenv/centos-php"}"
if [[ "${INDEV_FLAG:-1}" != "0" ]]; then
  IMAGE_NAME="${IMAGE_NAME}-indev"
fi
for BUILD_VERSION in ${VERSION_LIST}; do
  MAJOR_VERSION="$(echo "${BUILD_VERSION}" | sed -E 's/^([0-9]+\.[0-9]+).*$/\1/')"
  echo "### PHP ${MAJOR_VERSION} Tags" >> $GITHUB_STEP_SUMMARY

  for BUILD_VARIANT in ${VARIANT_LIST}; do
    # Configure build args specific to this image build
    export PHP_VERSION="${MAJOR_VERSION}"
    BUILD_ARGS=(IMAGE_NAME PHP_VERSION)

    # Build the image passing list of tags and build args
    printf "\e[01;31m==> building %s:%s (%s)\033[0m\n" \
      "${IMAGE_NAME}" "${BUILD_VERSION}" "${BUILD_VARIANT}"

    # Build for all platforms at once
    docker buildx build \
      --platform=linux/amd64,linux/arm64 \
      --cache-from=type=registry,ref=image:buildcache-amd64 \
      --cache-to=type=registry,ref=image:buildcache-amd64 \
      --cache-from=type=registry,ref=image:buildcache-arm64 \
      --cache-to=type=registry,ref=image:buildcache-arm64 \
      --tag "${IMAGE_NAME}:build" \
      "${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
    
    # Load the built image to run it temporarily
    docker buildx build --load \
      --tag "${IMAGE_NAME}:build" \
      "${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")

    # Strip the term 'cli' from tag suffix as this is the default variant
    TAG_SUFFIX="$(echo "${BUILD_VARIANT}" | sed -E 's/^(cli$|cli-)//')"
    [[ ${TAG_SUFFIX} ]] && TAG_SUFFIX="-${TAG_SUFFIX}"

    # Fetch the precise php version from the built image and tag it
    if [[ "${BUILD_VARIANT}" == "cli" ]]; then
      MINOR_VERSION="$(docker run --rm -t --entrypoint php "${IMAGE_NAME}:build" -r 'echo phpversion();')"
    fi

    # Generate array of tags for the image being built
    IMAGE_TAGS=(
      "${IMAGE_NAME}:${MAJOR_VERSION}${TAG_SUFFIX}"
      "${IMAGE_NAME}:${MINOR_VERSION}${TAG_SUFFIX}"
    )

    # Update the tags for the image, will use build cache
    docker buildx build \
      --platform=linux/arm64,linux/amd64 \
      --cache-from=type=registry,ref=image:buildcache-amd64 \
      --cache-to=type=registry,ref=image:buildcache-amd64 \
      --cache-from=type=registry,ref=image:buildcache-arm64 \
      --cache-to=type=registry,ref=image:buildcache-arm64 \
      --tag "${IMAGE_NAME}:${MAJOR_VERSION}${TAG_SUFFIX}" \
      --tag "${IMAGE_NAME}:${MINOR_VERSION}${TAG_SUFFIX}" \
      "${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
    
    BUILT_TAGS+=("${IMAGE_TAGS[@]}")

    # Load and push tagged images to cache
    #    Separate because of https://github.com/docker/buildx/issues/59
    #  These are alrady in the cache, so this step should only take a few seconds
    docker buildx build --load \
      --platform=linux/amd64 \
      --cache-from=type=registry,ref=image:buildcache-amd64 \
      --cache-to=type=registry,ref=image:buildcache-amd64 \
      --tag "${IMAGE_NAME}:${MAJOR_VERSION}${TAG_SUFFIX}" \
      --tag "${IMAGE_NAME}:${MINOR_VERSION}${TAG_SUFFIX}" \
      "${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
    
    docker buildx build --load \
      --platform=linux/arm64 \
      --cache-from=type=registry,ref=image:buildcache-arm64 \
      --cache-to=type=registry,ref=image:buildcache-arm64 \
      --tag "${IMAGE_NAME}:${MAJOR_VERSION}${TAG_SUFFIX}" \
      --tag "${IMAGE_NAME}:${MINOR_VERSION}${TAG_SUFFIX}" \
      "${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")

    # Iterate and push image tags to remote registry
    # if [[ ${PUSH_FLAG} != 0 ]]; then
    #   docker buildx build \
    #     --push \
    #     --platform=linux/arm64,linux/amd64 \
    #     -t "${IMAGE_NAME}:${MAJOR_VERSION}${TAG_SUFFIX}" \
    #     -t "${IMAGE_NAME}:${MINOR_VERSION}${TAG_SUFFIX}" \
    #     "${BUILD_VARIANT}" \
    #     $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
    # fi
  done

  echo "$(jq -R 'split(" ")' <<< "${BUILT_TAGS[@]}")" >> $GITHUB_STEP_SUMMARY
  echo "::notice title=PHP ${MAJOR_VERSION} Tags to Push::${BUILT_TAGS}" >> $GITHUB_OUTPUT
done

echo "built_tags=$(jq -cR 'split(" ")' <<< "${BUILT_TAGS[@]}")" >> $GITHUB_OUTPUT
