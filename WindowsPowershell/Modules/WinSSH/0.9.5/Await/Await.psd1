#
# Module manifest for module 'Await'
#
# Generated by: Lee Holmes
#

@{

ModuleToProcess = 'Await.psm1'

FunctionsToExport = 'Start-AwaitSession', 'Stop-AwaitSession', 'Send-AwaitCommand',
    'Receive-AwaitResponse', 'Wait-AwaitResponse'
AliasesToExport = 'spawn', 'saas', 'spas', 'sendac', 'sdac', 'expect', 'war', 'expect?', 'rcar'

ModuleVersion = '0.8'

GUID = '5fc00d79-9947-4a3c-be93-a75c9c3aa9e1'

Author = 'Lee Holmes'

Description = 'Await - A modern implementation of EXPECT for Windows. For a demo, see: https://www.youtube.com/watch?v=tKyAVm7bXcQ'

PowerShellVersion = '3.0'

}
