.PHONY: all init plan apply destroy

all: init plan apply

init:
	terraform init

plan:
	terraform plan -out=terraform.tfplan

apply:
	terraform apply terraform.tfplan

destroy:
	terraform destroy