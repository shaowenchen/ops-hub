#!/bin/bash
IMAGES_LIST_FILE=$1

ALL_IMAGES="$(cat $1 | sed '/#/d' | sed 's/: /,/g')"

function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

for image in ${ALL_IMAGES}; do
    IFS=', ' read -r -a imagearr <<<"$image"

    echo "Processing image: ${imagearr[0]} to ${imagearr[1]}"

    src_tags=$(skopeo list-tags docker://${imagearr[0]} | jq '.Tags[]' | sed '1!G;h;$!d')
    if ! dest_raw=$(skopeo list-tags docker://${imagearr[1]} 2>/dev/null); then
        log "Warning: Failed to fetch tags from destination ${imagearr[1]}, assuming no tags exist."
        dest_tags=""
    else
        dest_tags=$(echo "$dest_raw" | jq -r '.Tags[]')
    fi

    # Convert destination tags list to associative array for efficient lookup
    declare -A dest_tags_set
    if [ -n "$dest_tags" ]; then
        while IFS= read -r tag; do
            dest_tags_set["$tag"]=1
        done <<< "$dest_tags"
    fi

    # Counter for copied tags per image
    tag_count=0

    for tag in $src_tags; do
        if [ $tag_count -ge 5 ]; then
            log "Copied 5 tags for ${imagearr[0]}, moving to next image"
            break
        fi

        tag=$(echo $tag | sed 's/"//g')
        if [[ ${#tag} -gt 30 || ${tag} == *"--"* || ${tag} =~ ([0-9]{8}) || ${tag} =~ -[a-f0-9]{7,}- || ${tag} =~ -SNAPSHOT$ || ${tag} =~ beta[0-9]+ || ${tag} == *"windows"* || ${tag} == *"0.0.0"* || ${tag} == *"dev"* || ${tag} == sha256* || ${tag} == sha-* || ${tag} == *.sig || ${tag} == *post1 || ${tag} == *post2 || ${tag} =~ [0-9]{4}-[0-9]{2}-[0-9]{2} || ${tag} =~ .*-[a-z0-9]{12,}.* || ${tag} =~ .*-[a-z0-9]{7,}-.* ]]; then
            # echo "Skipping special tag ${imagearr[0]}:${tag}"
            continue
        fi

        preserve_tags=("latest" "master" "main" "dev" "development" "nightly" "test" "testing" "staging" "experimental" "alpha" "beta")

        is_preserve_tag=false
        for ptag in "${preserve_tags[@]}"; do
            if [[ "$tag" == "$ptag" || "$tag" == *"$ptag"* ]]; then
                is_preserve_tag=true
                break
            fi
        done

        # Check if tag exists in destination using cached data only
        if [[ ${dest_tags_set["$tag"]} -eq 1 ]]; then
            # echo "Skipping copy ${imagearr[0]}:${tag} as it already exists in ${imagearr[1]}"
            continue
        fi

        log "Copying ${imagearr[0]}:${tag} to ${imagearr[1]}:${tag}"
        output=$(docker run --rm -v ~/.docker/config.json:/auth.json quay.io/skopeo/stable:v1.13.0 copy \
            --multi-arch all docker://${imagearr[0]}:${tag} docker://${imagearr[1]}:${tag} \
            --dest-authfile /auth.json \
            --insecure-policy \
            --src-tls-verify=false \
            --dest-tls-verify=false \
            --retry-times 0 2>&1)

        status=$?

        if [[ $output == *"toomanyrequests"* ]]; then
            log "Failed to copy ${imagearr[0]}:${tag} to ${imagearr[1]}:${tag}"
            echo "Printing output start >>>>"
            echo "$output"
            echo "Printing output end   <<<<"
            break 2
        elif [ $status -ne 0 ]; then
            log "Failed to copy ${imagearr[0]}:${tag} to ${imagearr[1]}:${tag}"
            echo "$output"
            break 1
        else
            log "Successfully copied ${imagearr[0]}:${tag} to ${imagearr[1]}:${tag}"
            ((tag_count++))
        fi
    done
done
