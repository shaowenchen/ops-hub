#!/bin/bash

# Replace DockerHub images with Aliyun registry in specified namespace
# Usage: curl -fsSL https://raw.githubusercontent.com/shaowenchen/ops-hub/refs/heads/master/update-images.sh | sh -s --  <namespace> [--dry-run]

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <namespace> [--dry-run]"
    echo "Example: $0 monitoring"
    echo "Example: $0 monitoring --dry-run"
    exit 1
fi

NAMESPACE=$1
DRY_RUN=false
[ "$2" = "--dry-run" ] && DRY_RUN=true && echo "*** DRY-RUN MODE ***"

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found"; exit 1; }
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || { echo "Namespace $NAMESPACE not found"; exit 1; }

# Convert image to aliyun format
# Only replace: dockerhub (no prefix), docker.io, quay.io, ghcr.io, gcr.io, registry.k8s.io, nvcr.io
convert_image() {
    local img="$1"
    local first_part=$(echo "$img" | cut -d'/' -f1)
    
    # Check if should replace
    local should_replace=false
    case "$first_part" in
        # Specified registries to replace
        docker.io|quay.io|ghcr.io|gcr.io|registry.k8s.io|k8s.gcr.io|nvcr.io|docker.elastic.co)
            should_replace=true
            ;;
        *)
            # No dot means dockerhub image (nginx, grafana/grafana)
            if ! echo "$first_part" | grep -q '\.'; then
                should_replace=true
            fi
            ;;
    esac
    
    [ "$should_replace" = "false" ] && return 1
    
    # Extract tag
    local tag="latest"
    local name="$img"
    if echo "$img" | grep -q ':'; then
        tag=$(echo "$img" | rev | cut -d: -f1 | rev)
        name=$(echo "$img" | rev | cut -d: -f2- | rev)
    fi
    
    # Convert . and / to -
    name=$(echo "$name" | tr './' '--')
    
    echo "registry.cn-beijing.aliyuncs.com/opshub/${name}:${tag}"
}

echo "Namespace: $NAMESPACE"
echo ""

for type in deployment daemonset statefulset; do
    echo "=== $type ==="
    resources=$(kubectl get $type -n "$NAMESPACE" -o name 2>/dev/null | cut -d/ -f2)
    [ -z "$resources" ] && echo "None" && echo "" && continue
    
    for res in $resources; do
        echo "--- $res ---"
        updates=""
        
        # Get all container images in one jq call
        all_images=$(kubectl get $type "$res" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
            ((.spec.template.spec.containers // []) + (.spec.template.spec.initContainers // []))[] | "\(.name)|\(.image)"
        ' 2>/dev/null)
        
        [ -z "$all_images" ] && echo "  No containers" && continue
        
        # Use temp file to collect updates
        tmpfile=$(mktemp)
        
        echo "$all_images" > "$tmpfile.images"
        while IFS='|' read -r cname cimg; do
            [ -z "$cname" ] || [ -z "$cimg" ] && continue
            new_img=$(convert_image "$cimg") || continue
            echo "  $cname: $cimg -> $new_img"
            updates="$updates ${cname}=${new_img}"
        done < "$tmpfile.images"
        rm -f "$tmpfile.images" "$tmpfile"
        
        if [ -n "$updates" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo "  [DRY-RUN] kubectl set image $type/$res -n $NAMESPACE$updates"
            else
                kubectl set image "$type/$res" -n "$NAMESPACE" $updates && echo "  OK" || echo "  FAILED"
            fi
        else
            echo "  No dockerhub images"
        fi
    done
    echo ""
done

echo "Done!"
