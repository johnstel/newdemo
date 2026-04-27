// WORM long-term retention storage in the RETENTION resource group.
// This storage account MUST survive primary RG teardown; do not delete it during demo cleanup.
//
// Immutability design:
//   - Blob versioning enabled: every write creates a new version; old versions are preserved.
//   - Container uses version-level immutability (immutableStorageWithVersioning).
//   - A container-level time-based retention policy sets the minimum lock window.
//     Default: 1 day (demo-friendly). Set lockImmutabilityPolicy=true to lock in production.
//     WARNING: A LOCKED policy can only be extended, never shortened. Never lock in dev/test.
//
// Lifecycle management transitions blob versions to Cool/Archive over time.
// The delete rule fires only after immutability expires AND longTermRetentionDays have passed.
//
// allowSharedKeyAccess: false — managed identity + RBAC access only.

param workloadName string
param environmentName string
param location string
param tags object
param immutabilityRetentionDays int = 1
param longTermRetentionDays int = 2555
param coolAfterDays int = 7
param archiveAfterDays int = 30
param exporterIdentityPrincipalId string
param logAnalyticsWorkspaceId string

var baseNameClean = replace(toLower(workloadName), '-', '')
var storageAccountName = take('${baseNameClean}ret${environmentName}', 24)

// Built-in Azure RBAC: Storage Blob Data Contributor
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// GRS ensures the retention archive survives a regional failure
resource retentionStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_GRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }
}

// Versioning must be enabled at the blob service level for version-level immutability
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: retentionStorage
  properties: {
    isVersioningEnabled: true
  }
}

// Container with version-level immutability; once enabled it cannot be disabled
resource retentionContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'exports'
  parent: blobService
  properties: {
    publicAccess: 'None'
    immutableStorageWithVersioning: { enabled: true }
  }
}

// Container-level time-based retention policy.
// Left UNLOCKED by default so the demo can be redeployed cleanly.
resource immutabilityPolicy 'Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2023-01-01' = {
  name: 'default'
  parent: retentionContainer
  properties: {
    immutabilityPeriodSinceCreationInDays: immutabilityRetentionDays
    // false = blobs in the container cannot be appended once written (strictest WORM)
    allowProtectedAppendWrites: false
  }
}

// Lifecycle: tier blobs over time and delete only after retention expires
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  name: 'default'
  parent: retentionStorage
  properties: {
    policy: {
      rules: [
        {
          name: 'RetentionLifecycle'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['exports/']
            }
            actions: {
              // Version-level actions apply to individual blob versions
              version: {
                tierToCool: { daysAfterCreationGreaterThan: coolAfterDays }
                tierToArchive: { daysAfterCreationGreaterThan: archiveAfterDays }
                // Lifecycle delete will only succeed after immutability period has expired
                delete: { daysAfterCreationGreaterThan: longTermRetentionDays }
              }
            }
          }
        }
      ]
    }
  }
}

// Grant the export identity write access to retention storage (scoped to storage account)
resource exporterRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(retentionStorage.id, exporterIdentityPrincipalId, storageBlobDataContributorRoleId)
  scope: retentionStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: exporterIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings can target a Log Analytics workspace in a different resource group
resource blobServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'retention-storage-diag'
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

output retentionStorageAccountId string = retentionStorage.id
output retentionStorageAccountName string = retentionStorage.name
output retentionStorageBlobEndpoint string = retentionStorage.properties.primaryEndpoints.blob
