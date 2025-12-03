This directory provides sample Terraform files to provision Confidential GKE infrastructure.

Note: These Terraform scripts use configurations that won't work in typical GKE clusters. 
This serves as a companion for Confidential GKE user guide.

# Use the samples

* Configure the `google-private` provider as mentioned in the user guide.
* Review and edit variable values in `terraform.tfvars`.
* To skip the optional additional node network, remove files or blocks marked with "[OPTIONAL]".
* Proceed with the normal Terraform commands.
```
cd sample

terraform init
terraform plan
terraform apply
```
