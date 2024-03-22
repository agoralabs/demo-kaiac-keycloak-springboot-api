#!/bin/bash

THE_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Build started on $THE_DATE"

appenvsubstr(){
    p_template=$1
    p_destination=$2
    envsubst '$TF_VAR_ENV_APP_GL_NAME' < $p_template \
    | envsubst '$TF_VAR_ENV_APP_GL_STAGE' \
    | envsubst '$TF_VAR_ENV_APP_GL_NAMESPACE' \
    | envsubst '$TF_VAR_ENV_APP_BE_LOCAL_SOURCE_FOLDER' \
    | envsubst '$TF_VAR_ENV_APP_BE_LOCAL_PORT' \
    | envsubst '$TF_VAR_ENV_APP_BE_URL' \
    | envsubst '$TF_VAR_ENV_APP_GL_AWS_REGION' \
    | envsubst '$TF_VAR_ENV_APP_BE_DOMAIN_NAME' \
    | envsubst '$TF_VAR_ENV_APP_GL_DOCKER_REPOSITORY' \
    | envsubst '$TF_VAR_ENV_APP_KC_REALM_CERTS_URL' \
    | envsubst '$TF_VAR_ENV_APP_GL_AWS_REGION_ECR' > $p_destination
}

appenvsubstr devops/appspec.yml.template appspec.yml
appenvsubstr devops/appspec.sh.template devops/appspec.sh
appenvsubstr devops/application.yml.template src/main/resources/application.yml
chmod 777 devops/appspec.sh

appenvsubstr devops/Dockerfile.template Dockerfile
appenvsubstr devops/docker-compose.yml.template docker-compose.yml

chmod +x ./mvnw
./mvnw clean install -DskipTests

DOCKER_REGISTRY="$TF_VAR_ENV_APP_GL_DOCKER_REPOSITORY"
ECR_REGION="$TF_VAR_ENV_APP_GL_AWS_REGION_ECR"
ECR_REPOSITORY="${TF_VAR_ENV_APP_GL_NAMESPACE}"
ECR_TAG="${TF_VAR_ENV_APP_GL_NAME}_${TF_VAR_ENV_APP_GL_STAGE}"


#Se connecter au repo ECR
echo "Login into ecr..."
aws ecr get-login-password --region $ECR_REGION | docker login --username AWS --password-stdin $DOCKER_REGISTRY

#Builder l'image
echo "Building the Docker image..."
docker build -t $ECR_REPOSITORY:$ECR_TAG .

#Créer un repo
echo "Create $ECR_REPOSITORY repository..."
aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$ECR_REGION" || aws ecr create-repository --repository-name $ECR_REPOSITORY --region $ECR_REGION

aws ecr batch-delete-image --repository-name "$ECR_REPOSITORY" --image-ids imageTag="$ECR_TAG"

# Vérifie le code de sortie de la commande précédente
if [ $? -eq 0 ]; then
    echo "L'image $1 a été supprimée avec succès."

    #Tagguer l'image
    echo "Tag your image with the Amazon ECR registry..."
    docker tag $ECR_REPOSITORY:$ECR_TAG $DOCKER_REGISTRY/$ECR_REPOSITORY:$ECR_TAG

    #Push dans ECR
    echo "Push the image to ecr..."
    docker push $DOCKER_REGISTRY/$ECR_REPOSITORY:$ECR_TAG

else
    echo "Une erreur s'est produite lors de la suppression de l'image $1."
fi

# Récupère les identifiants des images non tagguées
untagged_image_ids=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --filter tagStatus=UNTAGGED --query 'imageDetails[*].imageDigest' --output json)

# Supprime les images non tagguées du référentiel
if [ -n "$untagged_image_ids" ]; then
    aws ecr batch-delete-image --repository-name "$ECR_REPOSITORY" --image-ids "$untagged_image_ids" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Les images non tagguées du référentiel $ECR_REPOSITORY ont été supprimées avec succès."
    else
        echo "Une erreur s'est produite lors de la suppression des images non tagguées du référentiel $ECR_REPOSITORY."
    fi
else
    echo "Aucune image non tagguée à supprimer dans le référentiel $ECR_REPOSITORY."
fi