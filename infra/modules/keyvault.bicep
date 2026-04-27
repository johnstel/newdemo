// Key Vault — provisioned and pre-authorized for v1; no secrets committed at deploy time.
// Both managed identities receive Key Vault Secrets User so apps can read secrets at runtime.
// Add secrets post-deploy via az keyvault secret set or the Portal.

param workloadName string
param environmentName string
param location string
param tags object
param ingestorIdentityPrincipalId string
param exporterIdentityPrincipalId string

// Key Vault names: 3–24 chars, alphanumeric + hyphens
var kvName = take('${workloadName}-kv-${environmentName}', 24)

// Built-in: Key Vault Secrets User
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: tenant().tenantId
    // RBAC authorization; access policies are ignored when this is true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource ingestorKvAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, ingestorIdentityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: ingestorIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource exporterKvAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, exporterIdentityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: exporterIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
