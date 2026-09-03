# deployment/main.tf
#
# Alternative IaC artifact (Terraform) declaring the same blue-green
# topology as docker-compose.yml, expressed with the `kreuzwerker/docker`
# provider. Included to satisfy the assignment's "Compose OR Terraform"
# option and to show how the same rollout model maps onto a
# Terraform-managed target (e.g. a self-hosted Docker host or, with the
# aws/azurerm providers substituted in, a cloud container service).
#
# This file is illustrative/for-reference: docker-compose.yml is the
# artifact actually exercised in the CD pipeline and in the demo evidence,
# since the assignment only requires one IaC file and Compose keeps the
# whole assessment reproducible on a local Docker Engine without cloud
# credentials.

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "image_tag" {
  description = "Tag of the dam405-wine-predict-api image to deploy"
  type        = string
  default     = "latest"
}

variable "live_slot" {
  description = "Which slot ('blue' or 'green') nginx should currently route to"
  type        = string
  default     = "blue"
}

resource "docker_image" "wine_api" {
  name = "dam405-wine-predict-api:${var.image_tag}"
}

resource "docker_network" "wine_net" {
  name = "wine-net-tf"
}

resource "docker_container" "app_blue" {
  name  = "wine-api-blue"
  image = docker_image.wine_api.image_id
  networks_advanced { name = docker_network.wine_net.name }
  env = ["SLOT=blue"]
}

resource "docker_container" "app_green" {
  name  = "wine-api-green"
  image = docker_image.wine_api.image_id
  networks_advanced { name = docker_network.wine_net.name }
  env = ["SLOT=green"]
}

# In a full deployment, an nginx or load-balancer resource here would be
# templated with `var.live_slot` and re-applied to perform the blue-green
# cutover (`terraform apply -var="live_slot=green"`), mirroring
# deployment/switch_traffic.sh in the Compose-based flow.
output "live_slot" {
  value = var.live_slot
}
