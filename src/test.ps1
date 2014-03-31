$moduleName = 'inceptionps'
function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")
$modulePath = (Join-Path -Path $scriptDir -ChildPath ("{0}.psm1" -f $moduleName))

if(Test-Path $modulePath){
    "Importing [{0}] module from [{1}]" -f $moduleName, $modulePath | Write-Verbose

    if((Get-Module $moduleName)){
        Remove-Module $moduleName
    }
    
    Import-Module $modulePath -PassThru -DisableNameChecking | Out-Null
}
else{
    'Unable to find [{0}] module at [{1}]' -f $moduleName, $modulePath | Write-Error
	return
}

<#

New-HtmlDocument {
    title 'foo'
}
#>

New-HtmlDocument {
    head {
        script -src 'http://foo.js'
    }
}

<#

New-HtmlDocument {
    head {
        title{'title text'}
    }
}

New-HtmlDocument head { title {'title value'} }

New-HtmlDocument {
    head {
        script -src 'http://foo.js'
    }
}

New-HtmlDocument {
    head {
        title {"title here"}
        script -src 'http://foo.js'
    }
}
#>
<#
New-HtmlDocument {
    head {
        title {"title here"}
        script -src 'http://foo.js'
    }
    body {
        h1 {"h1 here"}
        p {
            ul {
                li {"first item"}
                li {'second item'}
                li {'third item'}
            }
        }
        footer {'footer here'}
    }
}
#>


$foo = 'bar'


