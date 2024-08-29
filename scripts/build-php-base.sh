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

## iterate over and build each variant; build matrix will override to build each
## supported version
BUILD_VERSION="${PHP_VERSION:-"8.3"}"
VARIANT_LIST="${VARIANT_LIST:-"cli cli-loaders fpm fpm-loaders"}"

IMAGE_NAME="${IMAGE_NAME:-"ghcr.io/wardenenv/centos-php"}"
if [[ "${INDEV_FLAG:-1}" != "0" ]]; then
  IMAGE_NAME="${IMAGE_NAME}-indev"
fi

LABELS=()
for BUILD_VARIANT in ${VARIANT_LIST}; do
  # Configure build args specific to this image build
  export PHP_VERSION="${MAJOR_VERSION}"
  BUILD_ARGS=(IMAGE_NAME PHP_VERSION)

  # Build the image passing list of tags and build args
  printf "\e[01;31m==> building %s:%s (%s)\033[0m\n" \
    "${IMAGE_NAME}" "${BUILD_VERSION}" "${BUILD_VARIANT}"

  # Strip the term 'cli' from tag suffix as this is the default variant
  TAG_SUFFIX="$(echo "${BUILD_VARIANT}" | sed -E 's/^(cli$|cli-)//')"
  [[ ${TAG_SUFFIX} ]] && TAG_SUFFIX="-${TAG_SUFFIX}"

  IMAGE_TAGS=()

  for TAG in ${TAGS}; do
    IMAGE_TAGS+=("-t")
    IMAGE_TAGS+=("${TAG}${TAG_SUFFIX}")
  done

  # Iterate and push image tags to remote registry
  PUSH=""
  if [[ ${PUSH_FLAG} != 0 ]]; then
    PUSH="--push"
  fi

  # Build the multi-platform image
  docker buildx build \
      --platform=linux/arm64,linux/amd64 \
      -t warden-builder \
      "php/${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
  
  # Load the image to be able to run
  docker buildx build --load \
      -t warden-builder \
      "php/${BUILD_VARIANT}" \
      $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
  
  # Run the image only once, and extract the full version
  if [[ "${BUILD_VARIANT}" == "cli" ]]; then
    VERSION=$(docker run --rm warden-builder --entrypoint php -r 'echo phpversion();')
    MAJOR_VERSION=$(echo ${VERSION} | awk -F '.' '{print $1$2}')

    LABELS+=("warden:php_major_version=${MAJOR_VERSION}")
    LABELS+=("warden:php_version=${VERSION}")
  fi

  # Push the images to registries
  docker buildx build ${PUSH} \
    "${IMAGE_TAGS[@]}" \
    -t "${VERSION}${TAG_SUFFIX}" \
    $(printf -- "--label %s" "${LABELS[@]}") \
    --label "warden:variant=${BUILD_VARIANT}" \
    "php/${BUILD_VARIANT}" \
    $(printf -- "--build-arg %s " "${BUILD_ARGS[@]}")
done
