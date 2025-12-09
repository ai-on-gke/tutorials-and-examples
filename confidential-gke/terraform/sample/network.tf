/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


# [OPTIONAL] This file manages the additional node network resources.
# Keep the file to create the additional node network and firewall resources.
# Otherwise, remove it as well as the OPTIONAL block from gke.tf

provider "google" {
  project = var.project_id
  region  = var.location
}

resource "google_compute_network" "extra_network" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  mtu                     = 8896
}

resource "google_compute_subnetwork" "extra_subnetwork" {
  project                  = var.project_id
  name                     = var.subnetwork_name
  region                   = var.subnetwork_region
  ip_cidr_range            = "10.100.0.0/16"
  network                  = google_compute_network.extra_network.name
  private_ip_google_access = true
}

# Deny all egress firewall rule
resource "google_compute_firewall" "deny_all_egress_network" {
  name    = "deny-all-egress-network"
  project = var.project_id
  network     = google_compute_network.extra_network.name

  direction = "EGRESS"
  priority  = 65500

  deny {
    protocol = "all"
  }
  destination_ranges = ["0.0.0.0/0"]
}

# Google API firewall rule
resource "google_compute_firewall" "allow_egress_to_restricted_vip" {
  name        = "allow-egress-to-restricted-vip"
  description = "Allow HTTPS egress to Restricted VIPs"
  project     = var.project_id
  network     = google_compute_network.extra_network.name

  direction   = "EGRESS"
  priority    = 1000

  allow {
    protocol  = "tcp"
    ports     = ["443"]
  }
  destination_ranges = ["199.36.153.4/30", "34.126.0.0/18"]
  target_tags        = ["lr-network"]
}

# Google private DNS zone
resource "google_dns_managed_zone" "extra_net_googleapis_zone" {
  name        = "extra-net-googleapis-zone"
  dns_name    = "googleapis.com."
  description = "Managed private zone for extra node network"

  visibility  = "private"
  private_visibility_config {
    networks {
      network_url = google_compute_network.extra_network.id
    }
  }
}

# DNS mapping record sets
resource "google_dns_record_set" "dns_map_to_restricted" {
  name         = "*.googleapis.com."
  managed_zone = google_dns_managed_zone.extra_net_googleapis_zone.name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["restricted.googleapis.com."]
}

resource "google_dns_record_set" "dns_map_to_ip_addr" {
  name         = "restricted.googleapis.com."
  managed_zone = google_dns_managed_zone.extra_net_googleapis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
}
