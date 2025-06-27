#!/bin/bash

if [ "x${VERSION}" = "x" ]; then
  VERSION=$(cat /etc/os-release | grep "VERSION_ID" | cut -d '"' -f 2)
fi

default_proxy="https://ghproxy.chenshaowen.com/"
proxy=${PROXY:-$default_proxy}
repo_url="$proxy""https://raw.githubusercontent.com/shaowenchen/ops-hub/master/mirror/ubuntu/"

case $VERSION in
14.04)
  repo_url=$repo_url"14.04.trusty.aliyun.sources.list"
  ;;
16.04)
  repo_url=$repo_url"16.04.xenial.aliyun.sources.list"
  ;;
18.04)
  repo_url=$repo_url"18.04.bionic.aliyun.sources.list"
  ;;
20.04)
  repo_url=$repo_url"20.04.focal.aliyun.sources.list"
  ;;
22.04)
  repo_url=$repo_url"22.04.jammy.aliyun.sources.list"
  ;;
24.04)
  repo_url=$repo_url"24.04.noble.aliyun.sources.list"
  ;;
*)
  echo "Unsupported version"
  exit 1
  ;;
esac

# Handle different sources file locations for different Ubuntu versions
if [ "$VERSION" = "24.04" ]; then
  # Ubuntu 24.04 uses /etc/apt/sources.list.d/ubuntu.sources
  sources_file="/etc/apt/sources.list.d/ubuntu.sources"

  if [ -e "$sources_file" ]; then
    mv "$sources_file" "$sources_file.backup.$(date +"%Y%m%d%H%M%S")"
    echo "File not found: $sources_file"
  fi
else
  # Older versions use /etc/apt/sources.list
  sources_file="/etc/apt/sources.list"

  if [ -e "$sources_file" ]; then
    mv "$sources_file" "$sources_file.backup.$(date +"%Y%m%d%H%M%S")"
  else
    echo "File not found: $sources_file"
  fi
fi

curl -sfL $repo_url -o "$sources_file"

apt update
