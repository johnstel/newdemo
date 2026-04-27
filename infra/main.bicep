// ============================================================
// main.bicep — Subscription-scope orchestrator
// Azure Cosmos DB Enterprise Backup & Recovery Demo
// ============================================================
// Deployment: az deployment sub create --location <loc> --template-file main.bicep --parameters main.bicepparam
//
// Resource groups created:
//   {workloadName}-demo-{env}-rg       Primary: Cosmos, ACR, Container Apps, monitoring, Key Vault
//   {workloadName}-retention-{env}-rg  Retention: WORM Blob Storage — excluded from teardown
//
// Two-tier backup model:
//   Tier 1 (short-term): Cosmos DB native continuous backup (PITR) — 7 or 30 days
//   Tier 2 (long-term):  Custom export → immutable Blob Storage — up to 2555 days (≈7 years)
//   NOTE: 7-year retention is NOT a native Cosmos DB capability; it is application-managed.
// ============================================================

targetScope = 'subscription'

// ── Parameters ──────────────────────────────────────────────────────────────────────────

@description('Short name prefix used in all resource names. Default: cosmos-backup.')
param workloadName string = 'cosmos-backup'

@description('Deployment environment tier.')
@allowed(['dev', 'test', 'prod'])
param environmentName string = 'dev'

@description('Primary Azure region for all resources.')
param location string = 'eastus2'

@description('Secondary region for Cosmos DB read replica. Leave empty for single-region (dev/test default).')
param secondaryLocation string = ''

@description('Owner tag value.')
param owner string = 'demo-team'

@description('Cost center tag value.')
param costCenter string = 'demo'

@description('Cosmos DB PITR continuous backup tier.')
@allowed(['Continuous7Days', 'Continuous30Days'])
param cosmosPitrTier string = 'Continuous30Days'

@description('Cosmos DB autoscale max RU/s for the weather container.')
param cosmosMaxThroughput int = 1000

@description('Long-term retention in days (lifecycle delete rule). Default 2555 ≈ 7 years.')
@minValue(1)
@maxValue(36500)
param longTermRetentionDays int = 2555

@description('WORM immutability period in days. Keep 1 for demo; increase for production.')
@minValue(1)
param immutabilityRetentionDays int = 1

@description('Days after which export blobs transition to Cool tier.')
param coolAfterDays int = 7

@description('Days after which export blobs transition to Archive tier.')
param archiveAfterDays int = 30

@description('Cron expression for the backup-exporter job. Default: every 6 hours.')
param exportCronSchedule string = '0 */6 * * *'

@description('Milliseconds between ingestor writes. Default: 20 000 (20 s).')
param ingestIntervalMs int = 20000

@description('Container image for weather-ingestor. Override after building and pushing to ACR.')
param ingestorImageRef string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container image for backup-exporter. Override after building and pushing to ACR.')
param exporterImageRef string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// ── Variables ────────────────────────────────────────────────────────────────────────────

var primaryRgName = '${workloadName}-demo-${environmentName}-rg'
var retentionRgName = '${workloadName}-retention-${environmentName}-rg'

var commonTags = {
  project: 'cosmos-backup-demo'
  environment: environmentName
  owner: owner
  costCenter: costCenter
  createdBy: 'bicep'
}

// ── Resource Groups ───────────────────────────────────────────────────────────────────────

module resourceGroupsMod 'modules/resource-groups.bicep' = {
  name: 'resource-groups'
  params: {
    primaryRgName: primaryRgName
    retentionRgName: retentionRgName
    location: location
    commonTags: commonTags
  }
}

// ── Monitoring (deployed first — all other modules consume logAnalyticsWorkspaceId) ───────

module monitoringMod 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup(primaryRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
  }
}

// ── Managed Identities ────────────────────────────────────────────────────────────────────

module identityMod 'modules/identity.bicep' = {
  name: 'identity'
  scope: resourceGroup(primaryRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
  }
}

// ── Key Vault ─────────────────────────────────────────────────────────────────────────────

module keyVaultMod 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: resourceGroup(primaryRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
    ingestorIdentityPrincipalId: identityMod.outputs.ingestorIdentityPrincipalId
    exporterIdentityPrincipalId: identityMod.outputs.exporterIdentityPrincipalId
  }
}

// ── Cosmos DB ─────────────────────────────────────────────────────────────────────────────

module cosmosMod 'modules/cosmos.bicep' = {
  name: 'cosmos'
  scope: resourceGroup(primaryRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    secondaryLocation: secondaryLocation
    tags: commonTags
    pitrTier: cosmosPitrTier
    maxThroughput: cosmosMaxThroughput
    logAnalyticsWorkspaceId: monitoringMod.outputs.logAnalyticsWorkspaceId
  }
}

// ── Export Storage (primary RG) ───────────────────────────────────────────────────────────

module storageExportsMod 'modules/storage-exports.bicep' = {
  name: 'storage-exports'
  scope: resourceGroup(primaryRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
    longTermRetentionDays: longTermRetentionDays
    coolAfterDays: coolAfterDays
    archiveAfterDays: archiveAfterDays
    logAnalyticsWorkspaceId: monitoringMod.outputs.logAnalyticsWorkspaceId
  }
}

// ── Container Apps + ACR (primary RG) ────────────────────────────────────────────────────

module containerHostMod 'modules/container-host.bicep' = {
  name: 'container-host'
  scope: resourceGroup(primaryRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
    logAnalyticsWorkspaceId: monitoringMod.outputs.logAnalyticsWorkspaceId
    logAnalyticsWorkspaceCustomerId: monitoringMod.outputs.logAnalyticsWorkspaceCustomerId
    cosmosEndpoint: cosmosMod.outputs.cosmosEndpoint
    cosmosDatabaseName: cosmosMod.outputs.cosmosDatabaseName
    cosmosContainerName: cosmosMod.outputs.cosmosContainerName
    retentionStorageBlobEndpoint: storageRetentionMod.outputs.retentionStorageBlobEndpoint
    exportStorageBlobEndpoint: storageExportsMod.outputs.exportStorageBlobEndpoint
    ingestorIdentityId: identityMod.outputs.ingestorIdentityId
    ingestorIdentityClientId: identityMod.outputs.ingestorIdentityClientId
    exporterIdentityId: identityMod.outputs.exporterIdentityId
    exporterIdentityClientId: identityMod.outputs.exporterIdentityClientId
    ingestorImageRef: ingestorImageRef
    exporterImageRef: exporterImageRef
    exportCronSchedule: exportCronSchedule
    ingestIntervalMs: ingestIntervalMs
  }
}

// ── Retention Storage (retention RG) ─────────────────────────────────────────────────────
// Deployed to the RETENTION resource group — isolated from primary RG teardown.
// Diagnostic settings cross-reference the primary RG's Log Analytics workspace (this is valid).

module storageRetentionMod 'modules/storage-retention.bicep' = {
  name: 'storage-retention'
  scope: resourceGroup(retentionRgName)
  dependsOn: [resourceGroupsMod]
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
    immutabilityRetentionDays: immutabilityRetentionDays
    longTermRetentionDays: longTermRetentionDays
    coolAfterDays: coolAfterDays
    archiveAfterDays: archiveAfterDays
    exporterIdentityPrincipalId: identityMod.outputs.exporterIdentityPrincipalId
    logAnalyticsWorkspaceId: monitoringMod.outputs.logAnalyticsWorkspaceId
  }
}

// ── RBAC (primary RG resources: Cosmos data-plane, export storage, ACR) ──────────────────

module rbacMod 'modules/rbac.bicep' = {
  name: 'rbac'
  scope: resourceGroup(primaryRgName)
  params: {
    cosmosAccountName: cosmosMod.outputs.cosmosAccountName
    exportStorageAccountName: storageExportsMod.outputs.exportStorageAccountName
    acrName: containerHostMod.outputs.acrName
    ingestorIdentityPrincipalId: identityMod.outputs.ingestorIdentityPrincipalId
    exporterIdentityPrincipalId: identityMod.outputs.exporterIdentityPrincipalId
  }
}

// ── Alert Rules (deployed last; depends on Cosmos and Container Apps existing) ─────────────

module alertsMod 'modules/alerts.bicep' = {
  name: 'alerts'
  scope: resourceGroup(primaryRgName)
  params: {
    workloadName: workloadName
    environmentName: environmentName
    location: location
    tags: commonTags
    cosmosAccountId: cosmosMod.outputs.cosmosAccountId
    logAnalyticsWorkspaceId: monitoringMod.outputs.logAnalyticsWorkspaceId
  }
}

// ── Outputs (consumed by Parker's app config and Lambert's runbooks) ─────────────────────

output cosmosAccountEndpoint string = cosmosMod.outputs.cosmosEndpoint
output cosmosDatabaseName string = cosmosMod.outputs.cosmosDatabaseName
output cosmosContainerName string = cosmosMod.outputs.cosmosContainerName

output exportStorageAccountName string = storageExportsMod.outputs.exportStorageAccountName
output retentionStorageAccountName string = storageRetentionMod.outputs.retentionStorageAccountName

output containerHostName string = containerHostMod.outputs.containerAppsEnvironmentName
output ingestorAppName string = containerHostMod.outputs.ingestorAppName
output exporterJobName string = containerHostMod.outputs.exporterJobName
output acrLoginServer string = containerHostMod.outputs.acrLoginServer

output ingestionIdentityClientId string = identityMod.outputs.ingestorIdentityClientId
output exportIdentityClientId string = identityMod.outputs.exporterIdentityClientId

output primaryResourceGroupName string = primaryRgName
output retentionResourceGroupName string = retentionRgName

output keyVaultUri string = keyVaultMod.outputs.keyVaultUri
output logAnalyticsWorkspaceId string = monitoringMod.outputs.logAnalyticsWorkspaceId
output appInsightsConnectionString string = monitoringMod.outputs.appInsightsConnectionString
