// Alert rules that require Cosmos DB and Container Apps to exist first.
// This module is deployed last in main.bicep after all resources are in place.
//
// Three alerts:
//   1. Cosmos 429 throttling — metric alert, fires when any throttled requests occur
//   2. Ingestion gap       — log alert, fires when ingestor produces no logs for 2 minutes
//   3. Export job failure  — log alert, fires when exporter logs contain error keywords
//
// Alert queries target Container App console log tables (ContainerAppConsoleLogs_CL).
// Verify table names in your Log Analytics workspace after first Container Apps deployment.

param workloadName string
param environmentName string
param location string
param tags object
param cosmosAccountId string
param logAnalyticsWorkspaceId string

// ── 1. Cosmos DB throttling (metric alert; always global scope) ──────────────────────────
resource cosmosThrottlingAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${workloadName}-cosmos-throttle-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    severity: 2
    enabled: true
    scopes: [cosmosAccountId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Throttled429s'
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.DocumentDB/databaseAccounts'
          metricName: 'TotalRequests'
          dimensions: [
            {
              name: 'StatusCode'
              operator: 'Include'
              values: ['429']
            }
          ]
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    autoMitigate: true
  }
}

// ── 2. Ingestion gap > 2 minutes ─────────────────────────────────────────────────────────
// Assumes the ingestor container emits at least one log line per interval.
// Adjust the query if the ingestor app name or log format changes.
resource ingestionGapAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: '${workloadName}-ingest-gap-${environmentName}'
  location: location
  tags: tags
  properties: {
    severity: 2
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'ContainerAppConsoleLogs_CL | where ContainerName contains "ingestor" | where TimeGenerated >= ago(2m) | summarize Count = count()'
          timeAggregation: 'Count'
          operator: 'LessThan'
          threshold: 1
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}

// ── 3. Export job error ───────────────────────────────────────────────────────────────────
// Triggers when the exporter container logs an error keyword in the evaluation window.
resource exportJobFailureAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: '${workloadName}-export-fail-${environmentName}'
  location: location
  tags: tags
  properties: {
    severity: 2
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT10M'
    windowSize: 'PT10M'
    criteria: {
      allOf: [
        {
          query: 'ContainerAppConsoleLogs_CL | where ContainerName contains "exporter" | where Log contains "error" or Log contains "Error" or Log contains "failed" | summarize Count = count()'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}
