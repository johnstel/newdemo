// Azure Cosmos DB Core (SQL) API account with multi-region support and continuous backup.
//
// PITR (Point-in-Time Restore) notes:
//   - Continuous backup supports Continuous7Days and Continuous30Days tiers.
//   - Restore always creates a NEW account — there is no in-place restore.
//   - This native capability does NOT provide 7-year retention; that is handled by
//     the custom export pipeline to immutable Blob Storage (storage-retention.bicep).
//
// Multi-region: primary location + optional secondary (read replica, single-write mode).
// secondaryLocation = '' disables the second region (cost-saving default for dev).
//
// disableLocalAuth: true — all data-plane access requires Entra ID RBAC; no account keys.

param workloadName string
param environmentName string
param location string
param secondaryLocation string = ''
param tags object
param pitrTier string = 'Continuous30Days'
param databaseName string = 'demo'
param containerName string = 'weather'
param partitionKeyPath string = '/cityId'
param maxThroughput int = 1000
param logAnalyticsWorkspaceId string

var cosmosAccountName = '${workloadName}-cosmos-${environmentName}'

// Build the locations array: always include primary; add secondary only when provided.
var primaryLocationEntry = {
  locationName: location
  failoverPriority: 0
  isZoneRedundant: false
}
var additionalLocations = !empty(secondaryLocation) ? [
  {
    locationName: secondaryLocation
    failoverPriority: 1
    isZoneRedundant: false
  }
] : []

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: concat([primaryLocationEntry], additionalLocations)
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: {
        tier: pitrTier
      }
    }
    disableLocalAuth: true
    enableAutomaticFailover: !empty(secondaryLocation)
    // Public endpoints acceptable for v1 demo; private endpoints are a documented enhancement.
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: { id: databaseName }
  }
}

resource weatherContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: containerName
  parent: sqlDatabase
  properties: {
    resource: {
      id: containerName
      // /cityId partition key aligns with Parker's weather document schema
      partitionKey: {
        paths: [partitionKeyPath]
        kind: 'Hash'
        version: 2
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [{ path: '/*' }]
        excludedPaths: [{ path: '/"_etag"/?' }]
      }
    }
    options: {
      autoscaleSettings: { maxThroughput: maxThroughput }
    }
  }
}

// Send all relevant Cosmos request and metric data to Log Analytics.
resource cosmosDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'cosmos-diag'
  scope: cosmosAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'DataPlaneRequests', enabled: true }
      { category: 'QueryRuntimeStatistics', enabled: true }
      { category: 'PartitionKeyStatistics', enabled: true }
      { category: 'PartitionKeyRUConsumption', enabled: true }
      { category: 'ControlPlaneRequests', enabled: true }
    ]
    metrics: [
      { category: 'Requests', enabled: true }
    ]
  }
}

output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosDatabaseName string = sqlDatabase.name
output cosmosContainerName string = weatherContainer.name
