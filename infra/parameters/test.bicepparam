// Test environment parameters.
// az deployment sub create --location eastus2 --template-file infra/main.bicep \
//   --parameters infra/parameters/test.bicepparam

using '../main.bicep'

param workloadName = 'cosmos-backup'
param environmentName = 'test'
param location = 'eastus2'
param secondaryLocation = ''         // add 'westus2' to test multi-region behavior
param owner = 'demo-team'
param costCenter = 'demo'
param cosmosPitrTier = 'Continuous30Days'
param cosmosMaxThroughput = 4000
param longTermRetentionDays = 2555
param immutabilityRetentionDays = 1
param coolAfterDays = 7
param archiveAfterDays = 30
param exportCronSchedule = '0 */6 * * *'
param ingestIntervalMs = 20000
param ingestorImageRef = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param exporterImageRef = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
