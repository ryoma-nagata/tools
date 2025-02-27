param storageAccountName string
param location string
param workspace_instance_id string

var resouceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/Fabric/providers/Microsoft.Fabric/workspaces/${workspace_instance_id}'

resource networkAcls 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  kind: 'StorageV2'
  location: location
  properties: {
    networkAcls: {
      resourceAccessRules: [
        {
          tenantId: subscription().tenantId
          resourceId: resouceId
        }
      ]
    }
  }
}
