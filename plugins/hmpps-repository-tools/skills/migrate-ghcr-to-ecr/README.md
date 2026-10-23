# Migration assistant for GHCR -> ECR

## Introduction
This skill is used to assist with the migration of a repository from GHCR to ECR, which enables the repository to be made `internal` as part of the Transition to a [Curated Public Code Presence](https://justiceuk.sharepoint.com/:w:/s/DeveloperExperience/IQC4FO76SJq5Sp_bS6uMAGMqAYfFzWknQ_kEoxjDMkbjXTQ).

### Why?
Public GitHub repositories, by default, push GHCR repositories images that are public by default. This enables the Helm deployment process to pull those images without authentication, and then deploy them.

When a GitHub repository is switched to internal, it's expected that the GHCR packages will be made internal as well (although this is a manual process) and therefore authentication is required to pull the iamges for deployment. An interim solution was to set store a GitHub PAT as a secret on the Cloud Platform namespace, but this is not a sustainable means of authentication, especially since the tokens expire.

### Moving to ECR
Cloud Platform already offers ECR as a configurable module within their namespaces, to which Kubernetes automatically have access; all we need to do is authenticate when *pushing* the image. 

We have built in support to generate ECR credentials and store them in GitHub repository secrets/variables so that the build/deploy process can use them. This skill is intended to simplify the process of moving from GHCR to ECR.
