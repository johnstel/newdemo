// Subscription-scope module — creates the primary demo RG and the long-term retention RG.
// The retention RG carries teardownExcluded=true so teardown scripts skip it.
targetScope = 'subscription'

param primaryRgName string
param retentionRgName string
param location string
param commonTags object

resource primaryRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: primaryRgName
  location: location
  tags: commonTags
}

// Retention RG lives outside the primary demo lifecycle.
// DO NOT delete this RG during demo teardown — it holds WORM-protected long-term archive data.
resource retentionRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: retentionRgName
  location: location
  tags: union(commonTags, { teardownExcluded: 'true' })
}

output primaryRgName string = primaryRg.name
output retentionRgName string = retentionRg.name
