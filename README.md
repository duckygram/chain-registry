## Platform Deployment configuration

This repository contains deployment configuration template and configurations of deployed environments of the Platform.

Configuration is split by [Systems](here must be a link to the definition of the term 'System'). Configuration of every
system consists of a [Terraform](https://terraform.io) module to deploy required cloud resources and a
[Helmfile](https://github.com/helmfile/helmfile) DSF (desired state file) describing [Helm](https://helm.sh) releases
to be deployed to some [Kubernetes](https://kubernetes.io) cluster. Together these are complete 
[IaC](https://en.wikipedia.org/wiki/Infrastructure_as_code) definition of the deployed environments of the Platform.

Please find some additional notes and descriptions in the `docs` folder.

## The layout

- `templates` - named templates of whole environment.
    - `templates/default` - environment template named `default`.
        - `templates/default/<system-name>` - configuration template for a system.
            - `templates/default/<system-name>/helmfile/helmfile.yaml` - Helmfile DSF (desired state file) of the system.
            - `templates/default/<system-name>/helmfile/values.yaml` - Helmfile env configuration for the system not 
              application-specific.
            - `templates/default/<system-name>/helmfile/apps/<service-name>.yaml.gotmpl` - default configuration for the 
              particular application (service).
        - `templates/default/helmfile-global.yaml` - Helmfile configuration which is merged into Helmfile env configuration
          of every system helmfile. Values required by several systems goes here. Every system may override any value from
          this file with its own values.yaml configuration.
        - `templates/default/<system-name>/terraform` - terraform module to deploy required cloud resources existing outside 
          k8s cluster for the system.
- `environments` - named environments to deploy. Every environment is a completely separate set of resources and applications.
    - `environments/<environment-name>` - environment named `<environment-name>`.
        - `environments/<environment-name>/environment.yaml` - configuration values global for the environment. Values from here
          are shared between all systems and may be used by both Helmfile and Terraform based parts of the configuration.
          Among other values this file contains reference to the deployment template used to deploy this environment.
          The reference could be a filesystem path (relative to the repository root dir) or a Terraform-like URL (for ex.: 
          *git::ssh://gitlab.base.our-own.cloud/platform/platform/deploy-config.git@templates/default?ref=v1.2*)
        - `environments/<environment-name>/helmfile-env.yaml` - The Helmfile DSF to manipulate the Helmfile based part of the 
          environment as a whole. It references to the helmfile.yaml DSFs of all the systems in the environment.
        - `environments/<environment-name>/<system-name>/helmfile.yaml` - Helmfile DSF of the system in this environemnt. It 
          references same-named system's helmfile.yaml from the template. and provides overrides for system configuration specific 
          for the environment.  
        - `environments/<environment-name>/<system-name>/terragrunt.hcl` - Terragrunt configuration file to deploy the system's
          terraform module. It references same-named system's terraform module from the template and provides environment-specific 
          input values for variables of the module.
- `retired` - here we move deployment templates of systems no longer in use. Please be sure you've destroyed the system in all
  to environments it was ever deployed before moving it here.  

## Skeleton

Skeleton is special "system" to hold infrastructural resources serving particular environment and needed by other systems 
to function and shared by several systems. For example, it is Postgres cluster holding databases for many application from 
different systems, a KMS key used to encrypt secrets for the environment or DNS records and wildcard SSL certificates 
required by APIs and web applications.

## Deployment template versioning

Deployment templates are versioned so that modifications to the template not necessarily affects all the dependent
environments. Every environment has a reference (`environments\<name>\environment.yaml:template`) to the template to use. The
reference could be a filesystem path
```yaml
url: templates/default
ref: ""
```
or a remote URL with particular version ref:
```yaml
url: git::ssh://git@gitlab.base.our-own.cloud/platform/platform/deploy-config.git@templates/default
ref: v1.2.3
```
In the latter case the version of the template to use is fixed and new updates to the template do not affect the
environment. Once you want to upgrade an environment and use a newer version of the template you have to update the
reference and then apply changes to the environment.

Versions are just a git tags generated from CHANGELOG.md during merging of MRs into the default branch.

If you modify any file under `templates` directory you have to update CHANGELOG.md file with new semver formatted
version. The repository will be tagged with new version tag taken from the CHANGELOG.md file during execution of the
CICD pipeline on commit to the default branch.

## DNS and SSL certificates

Every system has its own 3d-level sub-domain in `.our-own.cloud` zone. It is to be used for non-customer-facing urls the services 
should be accessible at, from outside the cluster they are deployed into. The following hostname scheme to be used:
```
`<service>.<environment>.<system>.our-own.cloud
```
The dns zones for the system's domains are managed in a separate AWS account and must be registered
[here](https://gitlab.base.our-own.cloud/base/infrastructure/network/-/blob/main/stacks/account/terragrunt.hcl?ref_type=heads#L53)
before it could be used.

The SSL certificates for the system's domains urls are a part of the environment configuration and are managed 
in the `skeleton`. To have wildcard SSL certificates for `*.<environemnt>.<system>.our-own.cloud` created, the system to 
be mentioned in default value of variable `system_list` in `templates/default/skeleton/terraform/variables.tf` file. 

Creation of DNS records for services and attaching of the SSL certificates to required load balancers happens automatically.

## Production mode

File environment.yaml contains variable `production_mode` of boolean type. The variable purpose is to serve as single handle
to switch between "cheap" and "reliable" configuration defaults of some services like MongoDB (standalone/replicaset) or 
min number of replicas, etc. It is expected the variable to be set *true* in staging and production environments.

## Network policies

All the applications deployed are encouraged to set k8s Network Policies for itself restricting outbound traffic destinations
to the application dependencies only. This measure is intended to limit the potential impact in the event of execution of 
unwanted code as a result of a successful attack such as remote application hacking or dependency injection.

[Generic application chart](https://gitlab.base.our-own.cloud/base/tools/chart-template-library/-/tree/main/charts/generic-app-template?ref_type=heads) offers this functionality since version 2.8.0. 

By default the Network Policy is switched off and pods are free to initiate any outbound traffic. 
When `app.networkPolicy.enabled` property set to `true` then only mentioned destinations will be accessible, attempt to 
access anything else will result in network timeout. 

Please find description on how to set allowed destinations [here](https://gitlab.base.our-own.cloud/base/tools/chart-template-library/-/blob/main/charts/generic-app-template/values.yaml?ref_type=heads#L300).

## environment.yaml file

`environemnt.yaml` file holds values global for all systems of an environment and shared between terrafrom and helmfile 
based parts of configuration. Here is commented example of the file content with description for all the typical values:

```yaml
# name of the project. It is being used for tagging of resources and for composing names of some resources which 
# have global scope such as AWS SecretsManager secrets or S3 buckets
project_name: "platform"

# The name of the environment of the project. Also used for for tagging and naming
environment: "staging"

# The name of the organization in the Cosmo Wundergraph control plane where the environment must deploy its Graphql subgraphs.
# The value is used to find the AWS SecretsManager secret holding url and credentials for the control plane
cosmo_organization: "development"

# Specifies if the environment must be configured for production. See the 'Production mode' section for more details
production_mode: true

# name of the k8s cluster to deploy to. It is expected that local kube context has the same name
cluster_name: "development"

# ID of the AWS account we deploy to. If not present the ID of the "development" account will be used by default for 
# terraform-based part of the configuration. The main use of the value is to protect from accidental use of aws credentials 
# bound to wrong account
account_id: "637423344222"

# name of the AWS region we deploy to. Must match the region of the k8s cluster
region: eu-central-1

# This variables are not used in the deployment configuration but modifies the behaviour of CD pipelines. See the 
# 'CD pipelines' section for more details 
ci:
  auto_apply_main: false
  branch_apply_enabled: true
  all_jobs_are_manual: false

# Template to use for the environment. It could be a local directory or a remote git URL.
#
# reference to a local directory:
#   template:
#     url: "templates/default"
#     ref: ""
#
# reference to a remote versioned template:
#   template:
#     url: "git::ssh://git@gitlab.base.our-own.cloud/platform/platform/deploy-config.git@templates/default"
#     ref: "v1.2.3"
template:
  url: "../../templates/default"
  ref: ""

```

## Conventional Commits

We adhere to the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification to maintain consistent commit messages across this project. 
This practice improves the readability of the project history and helps in automating the release process.

### Why We Use Conventional Commits

- **Improved Readability**: Standardized commit messages make it easier to understand the purpose of each change.
- **Automated Changelogs**: We have automated the generation of changelogs from commit messages, saving time and reducing errors.
- **Automated Release Tagging**: Release versions and Git tags are automatically created based on commit types and messages, following semantic versioning principles.

### Setup

To ensure all commit messages comply with the Conventional Commits standard, we have configured Git hooks using **Husky** and **commitlint**. 
The necessary configuration files are already included in the repository.

### Prerequisites:
- Ensure you have **npm** installed on your system.

### Installation:
Run the following command in the root directory of the project:

```bash
npm install
```

This command installs all required packages and activates the Git hooks for commit message validation.

### Commit Message Guidelines

Format your commit messages using the following structure:

```
<type>[optional scope]: <description>
```

### Types of Changes and Their Impact on Versioning:

- **feat**: Increases *minor version* (e.g., `1.2.0` → `1.3.0`).  
  Adds new functionality that is backward-compatible.

- **fix**: Increases *patch version* (e.g., `1.2.0` → `1.2.1`).  
  Fixes bugs without adding new features and maintains compatibility.

- **docs**: Does not change version.  
  Documentation updates do not affect the codebase functionality.

- **style**: Does not change version.  
  Changes in code formatting that do not affect logic (e.g., whitespace, missing semicolons).

- **refactor**: Does not change version.  
  Code changes that improve structure or readability without adding new features or fixing bugs.

- **test**: Does not change version.  
  Adding or updating tests without affecting the functionality.

- **chore**: Does not change version.  
  Changes related to build processes, dependencies, or auxiliary tools.

- **perf**: Increases *patch version* (e.g., `1.2.0` → `1.2.1`).  
  Performance improvements that do not add new features.

- **ci**: Does not change version.  
  Changes in CI/CD configuration files or scripts that do not affect the product itself.

### When to Increase the *Major Version*:

- **BREAKING CHANGE**: When an update introduces breaking changes that are incompatible with the previous versions, it **increases the major version** (e.g., `1.2.0` → `2.0.0`).


## CD pipelines

Gitlab pipelines for all the environments are generated by the `.gitlab/generate.py` script. The script searches for
existing environments and systems and generates downstream pipelines for every environment found with separate `preview`
and `apply` jobs for every system mentioned in the environment.

- `preview` jobs show differences that were introduced by the change, with `terraform plan` or `hemfile diff`
- `apply` jobs execute `terraform apply` and then `helmfile apply` for the system in the environment.

The script takes into account changes made in the branch the pipeline was created for and auto run `preview` jobs only
for those systems which were affected by the change. Jobs for the systems without changes will be added in manual mode.
The script understands templating and changes made to the template affect environments which are referencing the template.
`apply` jobs for non-default branches are always in manual mode if added.

The behaviour of the `generate.py` script could be controlled by several values in the `environment.yaml` file:
```yaml
...
ci:
  auto_apply_main: false         # true will result in automatic run of the `apply` jobs when a pipeline were created
                                 # for the default branch
  
  branch_apply_enabled: true     # when true the pipeline created for non-default branch will contain `apply` jobs
                                 # in manual mode. When false - then only `preview` jobs will be generated for such a pipeline
  
  all_jobs_are_manual: false     # when true all the jobs generated in a pipeline will be in manual mode regardless of 
                                 # the changes detected or auto_apply_main value
...
```

## Quick debug deployment

When debugging an application in an integrated environment (means with all the dependencies available) 
one sometimes need to perform several rounds of updating code, commiting it to the repository, waiting for automated tests 
passed and a new container image become available in the container registry and then updating the deployment config to 
use the newly build version, commiting and pushing to the repository and waiting for the deploy pipeline to succeed.

The workflow mentioned above is not fast enough for the cases when several updates to the application are required in
a row to understand the problem and develop a fix. So there is shortcut way to speedup delivering new code to the 
development environment:

1. Build a container image locally and tag it with the `quickfix-registry.base.our-own.cloud` registry host:
    ```bash
    docker build . -t quickfix-registry.base.our-own.cloud/system/my-app:debug-image-001
    ```
    When you build locally by default you will get a container image built for your local CPU architecture. In many cases
    it could appear to be the ARM. But in the cloud we run our services on the x86_64 hardware. In this case you can use [Buildx project](https://github.com/docker/buildx) to get images for proper architecture:
    ```bash
    docker buildx build . -t quickfix-registry.base.our-own.cloud/system/my-app:debug-image-001 --platform linux/amd64
    ```
2. Push the image to the `quickfix-registry` registry:
    ```bash
    docker push quickfix-registry.base.our-own.cloud/system/my-app:debug-image-001
    ```
3. Restart the application in K8s with this new image:
    ```bash
    kubectl set image -n <namespace> deployment/my-app <container-name>=quickfix-registry.base.our-own.cloud/system/my-app:debug-image-001
    ```
    this will cause the pods of the deployment <name> in the namespace <namespace> to be restarted with the new image. 
    (<container-name> in most cases matches the name of the application, so it could be "my-app" in this example. You will find the exact 
    name with `kubectl get deployment -n <namespace> my-app -o=custom-columns=CONTAINERS:.spec.template.spec.containers[*].name`)
    
    If you need to update some configuration (for example change value of an env variable) then
    you have to update you local copy of the deployment config with required configuration 
    changes and also add override to the image in the system's helmfile.yaml instead of the `kubectl set image`:
    ```yaml
    ...
    helmfiles:
      - path: ...
        values:
          - apps:
              values:
                my-app:
                  app:
                    env:
                      ENABLE_DEBUG: true
                  image:
                    registry: quickfix-registry.base.our-own.cloud
                    repository: system/my-app
                    tag: my-debug-image-001
                    pullPolicy: Always
    ```
    and then run `helmfile apply -l name=my-app`, see the [Runbook](#Runbook) section for further details.

### Some considerations:
- if you use the same image tag every time you rebuild and push your container image ensure that `imagePullPolicy` is set to "Always". 
  If it is not so a new version of the image could not be pulled from the registry on pod restart if the node already has an image 
  with this tag in the local cache. To update `imagePullPolicy` of existing deployment one can run:
  ```bash
  kubectl patch deployment -n <namespace> my-app -p '{"spec": {"template": {"spec":{"containers":[{"name":"my-app","imagePullPolicy":"Always"}]}}}}'
  ```
  After first call to `kubectl set image` or applying with `helmfile` use the following command to update the pods.
  ```bash
  kubectl rollout restart deployment/my-app -n <namespace>
  ```
- Take into account that any run of the deployment job for the same System/Environment you are working on in Gitlab can unexpectedly override the changes you've made from local.

## Runbook

You can work with the entire environment at once or separately with a particular system in the environment.

### Prerequisites

Before you begin, make sure to have the following tools installed:

- **AWS CLI**
- **Terraform**
- **Terragrunt**
- **Helm**
- **Helmfile** 

For the installation instructions of these tools, please refer to:
 - [Install deployment tools on macOS]()
 - [Setup access to project infrastructure]().

### Manage the whole environment at once

Display the Terraform plan (list of actions to perform), highlighting changes between the current configuration and 
the last applied state in the specified environment:
```bash
terragrunt run-all plan --terragrunt-working-dir environments/<name>
```

Compare the current Helmfile configuration with the last applied configuration in the specified environment:
```bash
helmfile diff -f environments/<name>/helmfile-env.yaml
```

Apply the current Terraform configuration to the specified environment:
```bash
terragrunt run-all apply --terragrunt-working-dir environments/<name>
```

Apply the current Helmfile configuration to update Kubernetes resources in the specified environment:
```bash
helmfile apply -f environments/<name>/helmfile-env.yaml
```

Re-apply the current Helmfile configuration regardless of detected changes. Can help to override changes in Kubernetes
manifests made in the cluster by hands:
```bash
helmfile sync -f environments/<name>/helmfile-env.yaml
```

### Manage specific system in an environment

Apply Terraform configuration of a specific system within an environment:
```bash
terragrunt apply --terragrunt-working-dir environments/<name>/<system>
```

Apply Helmfile configuration to a specific system within an environment:
```bash
helmfile apply -f environments/<name>/<system>/helmfile.yaml
```

### Run commands from current directory

It is also possible and may be convenient in some cases to run the commands not from the repository root directory 
as shown above, but from the environment's or system's subdirectory:
```bash
# Show diff for an environment
cd environments/<name>
terragrunt plan
helmfile diff -f helmfile-env.yaml

# Now let's see the diff for one of the systems
cd <system>
terragrunt plan
helmfile diff
```

## S2S integration

S2S clients and secrets are automatically provisioned as a part of `identity` configuration.  
`.Values.s2s` global Helm value would contain all the necessary integration parameters.  
Example service configuration:  
```
// For getting S2S tokens.
s2s {
  host = "{{ tpl .Values.s2s.url . }}"
  clientId = "{{ tpl .Values.s2s.clientId . }}"
  clientSecret = "{{ tpl .Values.s2s.clientSecret . }}"
}

// For S2S token validation.
auth {
  issuer = "{{ tpl .Values.s2s.issuer . }}"
  jwksUrl = "{{ tpl .Values.s2s.jwksUri . }}"
}
```
To register a new system in S2S, add it to `s2s_systems` list (in the default variables of `identity` system).

## Services with Traceability ID Generators

There are services that should generate globally unique IDs for traceable entities.
To be able to generate IDs offline (without any synchronous communication to validate uniqueness),
each instance of such services MUST have unique identifier.
This identifier consists of 2 parameters provided as env variables:
* `ID_GENERATOR_PREFIX` - unique prefix defined in `templates/default/helmfile-global.yaml` file
* `POD_INDEX` - unique number of pod of service deployed as `StatefulSet` (provided automatically when `generic-app-template` >= `3.1.0` is used)
