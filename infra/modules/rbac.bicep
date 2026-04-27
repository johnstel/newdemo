// Role assignments for Cosmos DB data-plane RBAC and storage access.
//
// Cosmos DB data-plane RBAC uses sqlRoleAssignments (not Azure ARM RBAC).
//   Built-in Data Contributor = ID 00000000-0000-0000-0000-000000000002
//   Both identities get this role so the ingestor can write and the exporter can read.
//
// Storage Blob Data Contributor is granted to the exporter on the EXPORT storage account.
// The RETENTION storage account role is granted in storage-retention.bicep (different RG).
//
// AcrPull grants both identities permission to pull images from the shared ACR.

param cosmosAccountName string
param exportStorageAccountName string
param acrName string
param ingestorIdentityPrincipalId string
param exporterIdentityPrincipalId string

// Built-in Azure RBAC role IDs
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// References to existing resources deployed in the same resource group
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

resource exportStorage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: exportStorageAccountName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// ──────────────────────────────────────────────────────────────
// Cosmos DB data-plane RBAC (sqlRoleAssignments, not ARM RBAC)
// ──────────────────────────────────────────────────────────────

// Ingestor: writes weather documents
resource ingestorCosmosRbac 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, ingestorIdentityPrincipalId, 'cosmos-data-contributor')
  parent: cosmosAccount
  properties: {
    principalId: ingestorIdentityPrincipalId
    // /sqlRoleDefinitions/000...0002 = Built-in Data Contributor (read + write)
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmosAccount.id
  }
}

// Exporter: reads documents for export bundles
resource exporterCosmosRbac 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, exporterIdentityPrincipalId, 'cosmos-data-contributor')
  parent: cosmosAccount
  properties: {
    principalId: exporterIdentityPrincipalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmosAccount.id
  }
}

// ──────────────────────────────────────────────────────────────
// Export storage RBAC (exporter writes bundles; ingestor has no storage access)
// ──────────────────────────────────────────────────────────────

resource exporterStorageRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(exportStorage.id, exporterIdentityPrincipalId, storageBlobDataContributorRoleId)
  scope: exportStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: exporterIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ──────────────────────────────────────────────────────────────
// ACR pull rights — both identities pull their respective images
// ──────────────────────────────────────────────────────────────

resource ingestorAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, ingestorIdentityPrincipalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: ingestorIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource exporterAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, exporterIdentityPrincipalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: exporterIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
