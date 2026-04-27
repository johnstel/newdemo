// Production environment parameters.
// az deployment sub create --location eastus2 --template-file infra/main.bicep \
//   --parameters infra/parameters/prod.bicepparam
//
// NOTE: Review immutabilityRetentionDays and lockImmutabilityPolicy for production.
// A locked immutability policy can only be extended — never shortened or deleted.

using '../main.bicep'

param workloadName = 'cosmos-backup'
param environmentName = 'prod'
param location = 'eastus2'
param secondaryLocation = 'westus2'  // multi-region for production resilience
param owner = 'demo-team'
param costCenter = 'demo'
param cosmosPitrTier = 'Continuous30Days'
param cosmosMaxThroughput = 10000
param longTermRetentionDays = 2555
param immutabilityRetentionDays = 7  // 7 days for prod demo; adjust for compliance target
param coolAfterDays = 7
param archiveAfterDays = 30
param exportCronSchedule = '0 */6 * * *'
param ingestIntervalMs = 20000
// Set to ACR image references after images are built and pushed
param ingestorImageRef = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param exporterImageRef = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
