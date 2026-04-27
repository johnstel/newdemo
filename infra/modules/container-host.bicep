// Container Apps managed environment, ACR, ingestor Container App,
// and exporter Container App Job.
//
// ACR: images must be built and pushed by Parker before the Container Apps will function.
//   Default imageRef values are MCR hello-world placeholders — they start but do nothing.
//   Update ingestorImageRef / exporterImageRef params after `docker push` to ACR.
//
// Managed identity pull from ACR: no static credentials; AcrPull role assigned in rbac.bicep.
//
// Container Apps managed environment sends console logs to the Log Analytics workspace.
// listKeys() retrieves the workspace shared key at deployment time (not stored in Bicep state).

param workloadName string
param environmentName string
param location string
param tags object
param logAnalyticsWorkspaceId string
param logAnalyticsWorkspaceCustomerId string
param cosmosEndpoint string
param cosmosDatabaseName string
param cosmosContainerName string
param retentionStorageBlobEndpoint string
param exportStorageBlobEndpoint string
param ingestorIdentityId string
param ingestorIdentityClientId string
param exporterIdentityId string
param exporterIdentityClientId string
param ingestorImageRef string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param exporterImageRef string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param exportCronSchedule string = '0 */6 * * *'
param ingestIntervalMs int = 20000

var caeName = '${workloadName}-cae-${environmentName}'
var ingestorAppName = '${workloadName}-ingestor-${environmentName}'
var exporterJobName = '${workloadName}-exporter-${environmentName}'
var baseNameClean = replace(toLower(workloadName), '-', '')
// ACR names: alphanumeric only, 5–50 chars. Pad short names with 'acr' suffix minimum.
// BCP334 suppressed: cosmos-backup prefix guarantees >= 18 chars; linter can't verify statically.
#disable-next-line BCP334
var acrName = take('${baseNameClean}acr${environmentName}', 50)

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: environmentName == 'prod' ? 'Standard' : 'Basic' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Container Apps managed environment — ties compute, networking, and logging together
resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caeName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspaceCustomerId
        // listKeys is evaluated at deploy time; the shared key is not persisted in Bicep outputs
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
  }
}

// ── Ingestor Container App ────────────────────────────────────────────────────────────────
// Runs continuously (minReplicas: 1). Scale is fixed at 1 for the demo — no queue-based scaling.
resource ingestorApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: ingestorAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ingestorIdentityId}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      // ACR pull via managed identity; no static credentials
      registries: [
        {
          server: acr.properties.loginServer
          identity: ingestorIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'weather-ingestor'
          image: ingestorImageRef
          env: [
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'COSMOS_DATABASE_NAME', value: cosmosDatabaseName }
            { name: 'COSMOS_CONTAINER_NAME', value: cosmosContainerName }
            // AZURE_CLIENT_ID tells DefaultAzureCredential which user-assigned identity to use
            { name: 'AZURE_CLIENT_ID', value: ingestorIdentityClientId }
            { name: 'INGEST_INTERVAL_MS', value: string(ingestIntervalMs) }
            // Bicep has already provisioned the DB/container; prevent SDK auto-create
            { name: 'COSMOS_AUTO_CREATE', value: 'false' }
          ]
          // Container Apps API accepts decimal CPU values via json() to bypass int type hint
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ── Exporter Container App Job ────────────────────────────────────────────────────────────
// Scheduled (cron). Each execution writes one export bundle to both storage accounts.
resource exporterJob 'Microsoft.App/jobs@2024-03-01' = {
  name: exporterJobName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${exporterIdentityId}': {} }
  }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 1800
      replicaRetryLimit: 1
      scheduleTriggerConfig: {
        cronExpression: exportCronSchedule
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: exporterIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'backup-exporter'
          image: exporterImageRef
          env: [
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'COSMOS_DATABASE_NAME', value: cosmosDatabaseName }
            { name: 'COSMOS_CONTAINER_NAME', value: cosmosContainerName }
            { name: 'AZURE_CLIENT_ID', value: exporterIdentityClientId }
            { name: 'RETENTION_STORAGE_URL', value: retentionStorageBlobEndpoint }
            { name: 'EXPORT_STORAGE_URL', value: exportStorageBlobEndpoint }
            { name: 'COSMOS_AUTO_CREATE', value: 'false' }
          ]
          resources: { cpu: json('0.5'), memory: '1Gi' }
        }
      ]
    }
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output containerAppsEnvironmentId string = cae.id
output containerAppsEnvironmentName string = cae.name
output ingestorAppName string = ingestorApp.name
output exporterJobName string = exporterJob.name
