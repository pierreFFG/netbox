#!/bin/bash

# Script pour copier les images ECR nécessaires pour NetBox phase 2
# Usage: ./copy_ecr_images.sh

set -e

# Configuration
SOURCE_REGISTRY="349139558736.dkr.ecr.ca-central-1.amazonaws.com"
DEST_REGISTRY="629068383519.dkr.ecr.ca-central-1.amazonaws.com"
SOURCE_AWS_PROFILE="ProdSitesWeb"
DEST_AWS_PROFILE="TestNetbox"
AWS_REGION="ca-central-1"
NETBOX_IMAGE_SOURCE="${NETBOX_IMAGE_SOURCE:-docker.io/netboxcommunity/netbox:v4.1.4}"
NETBOX_IMAGE_TAG="${NETBOX_IMAGE_TAG:-v4.1.4}"

# Liste des images à copier avec leurs tags
# Basée sur la configuration dans eks_addons.tf + image app NetBox
declare -A IMAGES=(
    # secrets-store-csi-driver addon
    ["kubernetes/csi-secrets-store/driver"]="v1.4.8"
    ["kubernetes/csi-secrets-store/driver-crds"]="v1.5.1"
    ["kubernetes/sig-storage/csi-node-driver-registrar"]="v2.13.0"
    ["kubernetes/sig-storage/livenessprobe"]="v2.13.1"
    ["ecr-public/aws-secrets-manager/secrets-store-csi-driver-provider-aws"]="1.0.r2-96-gfeeb3ac-2025.05.06.20.19"

    # metrics-server addon
    ["kubernetes/metrics-server"]="v0.8.1"
    ["kubernetes/metrics-server/addon-resizer"]="1.8.21"

    # external-dns addon
    ["bitnami/external-dns"]="v0.20.0"
)

echo "🔍 Vérification de l'authentification AWS..."
echo "Source (${SOURCE_AWS_PROFILE}):"
aws sts get-caller-identity --profile "${SOURCE_AWS_PROFILE}"
echo "Destination (${DEST_AWS_PROFILE}):"
aws sts get-caller-identity --profile "${DEST_AWS_PROFILE}"

echo "🔐 Authentification aux registres ECR..."
aws ecr get-login-password --region "${AWS_REGION}" --profile "${SOURCE_AWS_PROFILE}" | docker login --username AWS --password-stdin "${SOURCE_REGISTRY}"
aws ecr get-login-password --region "${AWS_REGION}" --profile "${DEST_AWS_PROFILE}" | docker login --username AWS --password-stdin "${DEST_REGISTRY}"

echo "🏗️  Création des repositories dans le registre de destination..."
echo "  📁 Création du repository: netbox-image"
aws ecr create-repository --repository-name "netbox-image" --region "${AWS_REGION}" --profile "${DEST_AWS_PROFILE}" 2>/dev/null || echo "    ⚠️  Repository netbox-image existe déjà ou erreur de création"
for REPO in "${!IMAGES[@]}"; do
    echo "  📁 Création du repository: ${REPO}"
    aws ecr create-repository --repository-name "${REPO}" --region "${AWS_REGION}" --profile "${DEST_AWS_PROFILE}" 2>/dev/null || echo "    ⚠️  Repository ${REPO} existe déjà ou erreur de création"
done

echo "📦 Copie de l'image NetBox..."
NETBOX_DEST_IMAGE="${DEST_REGISTRY}/netbox-image:${NETBOX_IMAGE_TAG}"
echo "🔄 Copie de ${NETBOX_IMAGE_SOURCE} vers ${NETBOX_DEST_IMAGE}"
if docker image inspect "${NETBOX_IMAGE_SOURCE}" >/dev/null 2>&1; then
    echo "  📦 Image source déjà présente localement."
else
    echo "  📥 Pull de l'image source..."
    docker pull "${NETBOX_IMAGE_SOURCE}"
fi
echo "  🏷️  Tag de l'image pour la destination..."
docker tag "${NETBOX_IMAGE_SOURCE}" "${NETBOX_DEST_IMAGE}"
echo "  📤 Push vers le registre de destination..."
docker push "${NETBOX_DEST_IMAGE}"
echo "  🧹 Nettoyage des images locales..."
docker rmi "${NETBOX_IMAGE_SOURCE}" "${NETBOX_DEST_IMAGE}" >/dev/null 2>&1 || true
echo "  ✅ Image netbox-image:${NETBOX_IMAGE_TAG} copiée avec succès"
echo ""

echo "📦 Copie des images..."
for REPO in "${!IMAGES[@]}"; do
    TAG="${IMAGES[$REPO]}"
    SOURCE_IMAGE="${SOURCE_REGISTRY}/${REPO}:${TAG}"
    DEST_IMAGE="${DEST_REGISTRY}/${REPO}:${TAG}"

    echo "🔄 Copie de ${SOURCE_IMAGE} vers ${DEST_IMAGE}"

    # Pull de l'image source
    echo "  📥 Pull de l'image source..."
    docker pull "${SOURCE_IMAGE}"

    # Tag de l'image pour la destination
    echo "  🏷️  Tag de l'image pour la destination..."
    docker tag "${SOURCE_IMAGE}" "${DEST_IMAGE}"

    # Push vers le registre de destination
    echo "  📤 Push vers le registre de destination..."
    docker push "${DEST_IMAGE}"

    # Nettoyage des images locales
    echo "  🧹 Nettoyage des images locales..."
    docker rmi "${SOURCE_IMAGE}" "${DEST_IMAGE}" >/dev/null 2>&1 || true

    echo "  ✅ Image ${REPO}:${TAG} copiée avec succès"
    echo ""
done

echo "🎉 Toutes les images ont été copiées avec succès !"
echo ""
echo "📋 Images copiées :"
echo "  - netbox-image:${NETBOX_IMAGE_TAG}"
for REPO in "${!IMAGES[@]}"; do
    echo "  - ${REPO}:${IMAGES[$REPO]}"
done
