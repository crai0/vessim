locals {
  user = split("@", data.google_client_openid_userinfo.me.email)[0]
}

### node

resource "google_compute_instance" "node" {
  name                    = "node"
  machine_type            = var.machine_type
  tags                    = ["allow-ssh", "allow-http"]
  metadata_startup_script = "apt update && apt upgrade -y; apt install python3-pip"
  metadata                = {
    ssh-keys = "${local.user}:${tls_private_key.ssh.public_key_openssh}"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-jammy-v20221206"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
      nat_ip = google_compute_address.external.address
    }
  }

  provisioner "file" {
    source      = "../example_node/"
    destination = "api_server"
    connection {
      host = google_compute_address.external.address
      user = local.user
      private_key = local_file.ssh_private_key_pem.content
    }
  }

  provisioner "remote-exec" {
    inline = [
      "cd api_server/virtual_node",
      "sudo pip install -r requirements.txt",
      "sudo python v_node_api_server.py"
    ]

    connection {
      host = google_compute_address.external.address
      user = local.user
      private_key = local_file.ssh_private_key_pem.content
    }
  }
}

### network

resource "google_compute_network" "vpc_network" {
  name = "node-vpc"
}

resource "google_compute_address" "external" {
  name = "node-external"
}

resource "google_compute_firewall" "allow_ssh" {
  name          = "allow-ssh"
  network       = google_compute_network.vpc_network.name
  target_tags   = ["allow-ssh"]
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_http" {
  name          = "allow-http"
  network       = google_compute_network.vpc_network.name
  target_tags   = ["allow-http"]
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

### local ssh keys

provider "tls" {}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key_pem" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = ".ssh/google_compute_engine"
  file_permission = "0600"
}

### gcp

provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project
  region      = var.region
  zone        = var.zone
}

resource "google_project_service" "cloud_resource_manager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

data "google_client_openid_userinfo" "me" {}


### providers

terraform {
  required_providers {
    tls = {
      source = "hashicorp/tls"
    }
    google = {
      source = "hashicorp/google"
    }
  }
}
