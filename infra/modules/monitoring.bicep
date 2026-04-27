// Creates the observability foundation: Log Analytics workspace and Application Insights.
// Alert rules live in alerts.bicep (deployed after Cosmos DB and Container Apps exist).
// All other modules receive logAnalyticsWorkspaceId as a parameter for diagnostic settings.

param workloadName string
param environmentName string
param location string
param tags object

var lawName = '${workloadName}-law-${environmentName}'
var appInsightsName = '${workloadName}-ai-${environmentName}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Workspace-based App Insights routes all data through Log Analytics
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
