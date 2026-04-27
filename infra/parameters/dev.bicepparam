// Dev environment parameters.
// az deployment sub create --location eastus2 --template-file infra/main.bicep \
//   --parameters infra/parameters/dev.bicepparam

using '../main.bicep'

param workloadName = 'cosmos-backup'
param environmentName = 'dev'
param location = 'eastus2'
param secondaryLocation = ''
param owner = 'demo-team'
param costCenter = 'demo'
param cosmosPitrTier = 'Continuous7Days'
param cosmosMaxThroughput = 1000
param longTermRetentionDays = 2555
param immutabilityRetentionDays = 1
param coolAfterDays = 7
param archiveAfterDays = 30
param exportCronSchedule = '0 */6 * * *'
param ingestIntervalMs = 20000
param ingestorImageRef = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param exporterImageRef = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
