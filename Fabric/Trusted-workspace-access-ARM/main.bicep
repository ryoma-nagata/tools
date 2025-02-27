targetScope = 'resourceGroup'

@description('ストレージアカウントリソース名称を入力してください')
param storageAccountName string

@description('URLから取得したワークスペースインスタンスIDを入力してください')
param workspace_instance_id string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
  scope: resourceGroup()
}
module networkAcls './module/storage_nw_acl.bicep' = {
  name: 'storage_nw_acl'
  params: {
    storageAccountName: storageAccount.name
    location: storageAccount.location
    workspace_instance_id: workspace_instance_id
  }
}
