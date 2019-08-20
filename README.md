[![Build Status](https://dev.azure.com/scottcollins87/batch-pipeline/_apis/build/status/scollins87.batch-pipeline?branchName=master)](https://dev.azure.com/scottcollins87/batch-pipeline/_build/latest?definitionId=5&branchName=master)

# Azure Batch demo
Code to use Azure DevOps pipeline to provision a batch account, a batch pool, & create a single job containing a number of tasks using Terraform.

## Prerequisites
* Service Principal
* Key Vault
* Storage account

## Secrets
The Azure DevOps pipeline gets all secrets from an Azure KeyVault. Although this example uses YAML to define the pipeline, a variable group will need to be created in the GUI to allow it to pull secrets from a KeyVault - At the time of writing there's no way to do this programmatically.


## The Terraform
The Terraform takes the following inputs:

| Name        | Type          | Description |
| ------------- |:-------------:|:------:|
| Subscription_ID      | string | Azure subscription ID |
| Tenant_ID      | string      |   Azure tenant ID |
| Client_ID | string      |SPN Client ID (App ID)|
| Client_Secret | string      |SPN Client Secret|
| Access_Key | string      |    Access key for the storage account used to hold TF state|


## Batch pool auto-scale configuration
I used an example from the official documentation to scale the batch pool based on the number of active tasks. This will set the minimum number of nodes in the pool to 0. The max is configurable by setting the ```cappedPoolSize``` variable. I set mine to 20 because it lit Batch Explorer up quite nicely.


I set the ```evaluation_interval``` to PT5M (5 minutes) to ensure that my nodes weren't running for longer than they needed to.

Other examples can be found [here](https://docs.microsoft.com/en-gb/azure/batch/batch-automatic-scaling).


## Pipeline definition
I started by disabling the trigger - I didn't want a new build to be triggered with every commit:

```YAML
trigger: none
```

Next i set the basic configuration of the agent I wanted to use. For ease, I chose an Ubuntu 16.04 hosted agent:

```YAML
pool:
  name: Azure Pipelines
  vmImage: 'ubuntu-16.04'
```

Then I set the variable groups I mentioned earlier. I have two groups; one for values pulled from my KeyVault, the other for non-secret values (Storage account name, subscription ID etc.):

```YAML
variables:
- group: 'Secrets'
- group: 'Subscription'
```

Once the pipeline configuration steps were complete, I needed to start defining what the pipeline actually _did_. I started by making sure that Terraform was installed on the agent. For this, I used a Marketplace task:

```YAML
steps:
- task: JamiePhillips.Terraform.TerraformTool.TerraformTool@0
  displayName: 'Use Terraform $(terraform.version)'
  inputs:
    version: '0.11.12'
```

This allows us to pin to a TF version that we know works for us, when a later version is released. For the remaining TF execution steps I decided against using Marketplace tasks because I found that using script tasks gave me greater flexibility when it came to configuring each step.

First I ran the AZ CLI to get the key for my storage account so that I could insert this into my tfvars file for storing state remotely. Then I created the .tfvars file and populated it with the secrets from my KeyVault:

```YAML
- script: |
   az login --service-principal -u $(tfsp-id) -p $(tfsp-secret) --tenant $(tenant_id)
   ACCESS_KEY=`az storage account keys list -n $(storage_acct) -o json | jq -r '.[0].value'`
   echo "##vso[task.setvariable variable=ACCESS_KEY]$ACCESS_KEY"
  displayName: 'AZ Login and Set ACCESS_KEY'
- script: |
   cat << EOT >> terraform.tfvars
   access_key = "$(ACCESS_KEY)"
   tenant_id = "$(tenant_id)"
   subscription_id = "$(subscription_id)"
   client_id = "$(client_id)"
   client_secret = "$(Client_Secret)"
   EOT
  workingDirectory: '$(System.DefaultWorkingDirectory)'
  displayName: 'Create terraform.tfvars'
```

Using ```"##vso[task.setvariable variable=ACCESS_KEY]$ACCESS_KEY"``` allowed me to persist the value of ```ACCESS_KEY``` across multiple steps. I reused this later on. Next I ran a ```terraform init``` and passed in the backend configuration, before running a ```validate``` so that I can be sure that my TF syntax is correct before running a ```plan``` and ```apply```:

```YAML
- script: |
   terraform init -backend-config=resource_group_name=$(resource_group) -backend-config=storage_account_name=$(storage_acct) -backend-config=container_name=state -backend-config=key=output.tfstate -backend-config=access_key=$(ACCESS_KEY) -no-color -input=false
  displayName: 'Terraform Init'
  workingDirectory: '$(System.DefaultWorkingDirectory)'
- script: |
   terraform validate
  workingDirectory: '$(System.DefaultWorkingDirectory)'
  displayName: 'Terraform Validate'
- script: |
   terraform plan -out=tfplan -no-color -input=false
  displayName: 'Terraform Plan'
  workingDirectory: '$(System.DefaultWorkingDirectory)'
- script: |
   terraform apply -auto-approve
  displayName: 'Terraform Apply'
  workingDirectory: '$(System.DefaultWorkingDirectory)'
```
Successful completion of those steps meant I had a new storage account, batch account & batch pool ready to go. SO next I had to test it out. I did this by using the Azure CLI to create a single job before spawning 40 tasks with a 90 second wait. First I had to grab the output of the TF run and insert them into variables to be used in subsequent steps:

```YAML
- script: |
   ACCOUNT_ID=`terraform output batch_account_id`
   ACCOUNT_NAME=`terraform output batch_account_name`
   POOL_NAME=`terraform output batch_pool_name`
   echo "##vso[task.setvariable variable=ACCOUNT_ID]$ACCOUNT_ID"
   echo "##vso[task.setvariable variable=ACCOUNT_NAME]$ACCOUNT_NAME"
   echo "##vso[task.setvariable variable=POOL_NAME]$POOL_NAME"
  displayName: 'Get TF output and set to vars'
```

Then I used these values to log into the newly created batch account, before creating the job and spawning the tasks:

```YAML
- script: |
   az batch account login -n $(ACCOUNT_NAME) -g Batch --shared-key-auth
  displayName: 'Login to the new batch account'
- script: |
   TIMESTAMP=`date +%s`
   echo "##vso[task.setvariable variable=TIMESTAMP]$TIMESTAMP"
   az batch job create --id $TIMESTAMP --pool-id $(POOL_NAME)
  displayName: 'Create a new batch job'
- script: |
   for i in {1..40}
   do
   az batch task create \
    --task-id mytask$i \
    --job-id $TIMESTAMP \
    --command-line "/bin/bash -c 'printenv | grep AZ_BATCH; sleep 90s'"
   done
  displayName: 'Create dummy tasks'
```

I assigned a variable to the timestamp, which I used for the name of my job. This allowed me to create multiple jobs without needing to delete the previous job.

Once this runs successfully, the batch pool will auto-scale to meet the demands that those 40 tasks place on it. I recommend downloading [Azure Batch Explorer](https://azure.github.io/BatchExplorer/) to keep an eye on your batch account as it processes. It's little limited, but I still think it's a better experience than trying to do this through the portal.

