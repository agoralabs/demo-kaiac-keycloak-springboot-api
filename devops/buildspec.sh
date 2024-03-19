#!/bin/bash

THE_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Build started on $THE_DATE"

appenvsubstr(){
    p_template=$1
    p_destination=$2
    envsubst '$TF_VAR_ENV_APP_GL_NAME' < $p_template \
    | envsubst '$TF_VAR_ENV_APP_GL_STAGE' \
    | envsubst '$TF_VAR_ENV_APP_BE_NAMESPACE' \
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

ECR_REGION=$TF_VAR_ENV_APP_GL_AWS_REGION_ECR
ECR_REGISTRY=$TF_VAR_ENV_APP_GL_DOCKER_REPOSITORY
ECR_REPO=$TF_VAR_ENV_APP_GL_NAME
ECR_TAG=${TF_VAR_ENV_APP_BE_NAMESPACE}_${TF_VAR_ENV_APP_GL_NAME}


echo "Login into ecr..."
aws ecr get-login-password --region $ECR_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

echo "Building the Docker image..."
docker build -t $ECR_REPO:$ECR_TAG .

echo "Create $ECR_REPO repository..."
aws ecr describe-repositories --repository-names $ECR_REPO --region $ECR_REGION || aws ecr create-repository --repository-name $ECR_REPO --region $ECR_REGION
aws ecr delete-repository --repository-name $ECR_REPO --force
aws ecr create-repository --repository-name $ECR_REPO --region $ECR_REGION

echo "Tag your image with the Amazon ECR registry..."
docker tag $ECR_REPO:$ECR_TAG $ECR_REGISTRY/$ECR_REPO:$ECR_TAG

echo "Push the image to ecr..."
docker push $ECR_REGISTRY/$ECR_REPO:$ECR_TAG

