// Export storage in the PRIMARY resource group (not WORM).
// Holds working export bundles written by the backup-exporter job.
// Lifecycle policy transitions blobs to Cool, then Archive, then deletes after retention window.
//
// allowSharedKeyAccess: false — all access via managed identity; no storage keys in apps.

param workloadName string
param environmentName string
param location string
param tags object
param longTermRetentionDays int = 2555
param coolAfterDays int = 7
param archiveAfterDays int = 30
param logAnalyticsWorkspaceId string

// Storage account names: alphanumeric only, max 24 chars
var baseNameClean = replace(toLower(workloadName), '-', '')
var storageAccountName = take('${baseNameClean}exp${environmentName}', 24)

// Use GRS for prod; LRS is sufficient for demo dev/test (export bundles are re-creatable)
var storageSkuName = environmentName == 'prod' ? 'Standard_GRS' : 'Standard_LRS'

resource exportStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: storageSkuName }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: exportStorage
}

resource exportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'exports'
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

// Tier blob data over time; delete after longTermRetentionDays (default 2555 ≈ 7 years)
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  name: 'default'
  parent: exportStorage
  properties: {
    policy: {
      rules: [
        {
          name: 'ExportRetentionLifecycle'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['exports/']
            }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: coolAfterDays }
                tierToArchive: { daysAfterModificationGreaterThan: archiveAfterDays }
                delete: { daysAfterModificationGreaterThan: longTermRetentionDays }
              }
            }
          }
        }
      ]
    }
  }
}

resource blobServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'export-storage-diag'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'StorageRead', enabled: true }
      { category: 'StorageWrite', enabled: true }
      { category: 'StorageDelete', enabled: true }
    ]
    metrics: [
      { category: 'Transaction', enabled: true }
    ]
  }
}

output exportStorageAccountId string = exportStorage.id
output exportStorageAccountName string = exportStorage.name
output exportStorageBlobEndpoint string = exportStorage.properties.primaryEndpoints.blob
