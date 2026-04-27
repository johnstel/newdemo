// Creates two user-assigned managed identities:
//   ingest-id  — used by the weather-ingestor Container App
//   export-id  — used by the backup-exporter Container App Job
// RBAC assignments against Cosmos DB and Storage are made in rbac.bicep and storage-retention.bicep.

param workloadName string
param environmentName string
param location string
param tags object

resource ingestorIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${workloadName}-ingest-id-${environmentName}'
  location: location
  tags: tags
}

resource exporterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${workloadName}-export-id-${environmentName}'
  location: location
  tags: tags
}

output ingestorIdentityId string = ingestorIdentity.id
output ingestorIdentityPrincipalId string = ingestorIdentity.properties.principalId
output ingestorIdentityClientId string = ingestorIdentity.properties.clientId

output exporterIdentityId string = exporterIdentity.id
output exporterIdentityPrincipalId string = exporterIdentity.properties.principalId
output exporterIdentityClientId string = exporterIdentity.properties.clientId
