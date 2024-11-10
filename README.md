# to create
## Setting up AWS EC2 Instance with Terraform

Follow the steps below to set up an AWS EC2 instance using Terraform.

1. Fill in your access_key and secret_key in the security credentials section.
2. Run `terraform init` to initialize the Terraform configuration.
3. Make sure you have created a key pair for EC2 on the AWS console and name it `main-key`.
4. Download the `.pem` file for the key pair and move it into the working directory.
5. Set the permissions for the `.pem` file using `chmod 400 main-key.pem` (or the name you have given to your key pair).
6. Run `terraform apply` to create the EC2 instance.
7. Go to the AWS console, navigate to the instance, and retrieve the Elastic IP address.
8. Connect to the EC2 instance using SSH: `ssh -i "main-key.pem" ec2-user@100.28.170.35`.
9. If you cannot access the instance, try changing from `https://` to `http://` in the URL.

## to destroy
1. To delete all the resources created, run `terraform destroy` and confirm with "yes".
2. Check if all resources are destroyed to avoid incurring costs.

Please note that this guide assumes you have basic knowledge of AWS and Terraform. Make sure to replace the necessary values with your own.