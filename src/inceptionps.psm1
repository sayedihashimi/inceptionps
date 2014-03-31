[cmdletbinding()]
param()

# Based on XmlDsl by Joel Bennett http://huddledmasses.org/a-dsl-for-xml-in-powershell-new-xdocument/

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")
$zenCodingAssembly = (Join-Path -Path ((Get-ChildItem $scriptDir).Directory.Parent.FullName) -ChildPath 'tools\ZenCoding.dll')
'path :[{0}]' -f $zenCodingAssembly | Write-Host

Add-Type -Path $zenCodingAssembly

Add-Type -AssemblyName 'System.Web'
$acceleratorsType = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
$accelerators = ($acceleratorsType::Get)
if(-not $accelerators.ContainsKey('PSParser')){
    $acceleratorsType::Add('PSParser','System.Management.Automation.PSParser, System.Management.Automation, Version=1.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35')
}
if(-not $accelerators.ContainsKey('HtmlTextWriter')){
    $acceleratorsType::Add('HtmlTextWriter','System.Web.UI.HtmlTextWriter')
}

<#
New-XDocument html {
    head {
        title {"title here"}
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
    }
}
#>
$script:currentStringWriter = $null
$script:currentHtmlWriter = $null
function New-HtmlDocument {
    [cmdletbinding()]
    param(
       [AllowNull()][AllowEmptyString()][AllowEmptyCollection()]
       [Parameter(Position=99, Mandatory = $false, ValueFromRemainingArguments=$true)]
       [PSObject[]]$args
    )
    process{
        'new-htmldocument' | Write-Verbose

        $script:currentStringWriter = $stringWriter = New-Object 'System.IO.StringWriter'
        $script:currentHtmlWriter = $htmlWriter = New-Object 'System.Web.UI.HtmlTextWriter' ($stringWriter)
        
        $htmlWriter.WriteLine('<!doctype html>')
        $htmlWriter.RenderBeginTag('html') | Out-Null
        
        while($args){
            $attrib, $value, $args = $args
            if($attrib -is [ScriptBlock]){
                $attrib = ConverFrom-HtmlDsl $attrib
                &$attrib
            }
            elseif ( $value -is [ScriptBlock] <#-and "-CONTENT".StartsWith($attrib.TrimEnd(':').ToUpper())#>){
                $value = ConverFrom-HtmlDsl $value
                &$value
            }            
        }

        # end html
        $htmlWriter.RenderEndTag() | Out-Null

        $stringWriter.ToString()

        $stringWriter.Dispose()
        $htmlWriter.Dispose()

        $script:currentStringWriter = $stringWriter = $null
        $script:currentHtmlWriter = $htmlWriter = $null
    }
}

function New-HtmlElement{
    [cmdletbinding()]
    param(       
        [Parameter(Mandatory=$true,Position=0)]
        $tag,
        
        [AllowNull()][AllowEmptyString()][AllowEmptyCollection()]
        [Parameter(Position=99, Mandatory = $false, ValueFromRemainingArguments=$true)]
        [PSObject[]] $args
    )
    process{
        'new-HtmlElement [{0}]' -f $tag | Write-Verbose

        $htmlWriter = $script:currentHtmlWriter
        $pendingWriteBeginTag = $true
        while($args){
            $attrib, $value, $args = $args

            # TODO: needs clean up
            if($args -ne $null){
                # don't write this out until all attributes have been added
                $htmlWriter.RenderBeginTag($tag)
                $pendingWriteBeginTag = $false
            }            
            elseif($attrib -is [ScriptBlock]){
                if($pendingWriteBeginTag){
                    $htmlWriter.RenderBeginTag($tag)
                    $pendingWriteBeginTag = $false;
                }
                &$attrib
            }
            elseif ($value -is [ScriptBlock] -and "-CONTENT".StartsWith($attrib.TrimEnd(':').ToUpper())) { # then it's content
                if($pendingWriteBeginTag){
                    $htmlWriter.RenderBeginTag($tag)
                    $pendingWriteBeginTag = $false;
                }
                &$value
            }
            elseif($value -match "-(?!\d)\w") { # TODO: Do we need this?
                $args = @($value)+@($args)
            }
            elseif($value -ne $null) {
                $htmlWriter.AddAttribute($attrib.TrimStart("-").TrimEnd(':'),$value)
            }
            elseif($attrib -is [string]){
                if($pendingWriteBeginTag){
                    $htmlWriter.RenderBeginTag($tag)
                    $pendingWriteBeginTag = $false;
                }
                $htmlWriter.Write($attrib)
            }
        }
        
        if($pendingWriteBeginTag){
            $htmlWriter.RenderBeginTag($tag)
        }

        $htmlWriter.RenderEndTag()
    }
}

Set-Alias nhe New-HtmlElement

function Write-HtmlText{
    [cmdletbinding()]
    param(       
        [Parameter(Mandatory=$true,Position=0)]
        $text
    )
    process{
        $script:currentHtmlWriter.Write($text)        
    }
}

Set-Alias wht Write-HtmlText

function Write-HtmlAttribute{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $name,
        [Parameter(Mandatory=$true,Position=1)]
        $value
    )
    process{
        $script:currentHtmlWriter.AddAttribute($name,$value)
    }
}
Set-Alias wha Write-HtmlAttribute

function Write-Emmet{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $expression
    )
    process{
        $parser = New-Object 'ZenCoding.HtmlParser'
        Write-HtmlText -text $parser.Parse($expression)        
    }
}

Set-Alias emmet Write-Emmet

function ConverFrom-HtmlDsl {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$script
    )
    process{
        $parserrors = $null
        $global:tokens = [PSParser]::Tokenize( $script, [ref]$parserrors)

        [string[]]$ScriptText = "$script" -split "`n"
        [string[]]$OriginalScript = "$script" -split "`n"

        $tokensToUpdate = @()
        $previousToken = $null
        $lineOffset = 0
        foreach($t in $global:tokens){            
            if($previousToken -ne $null -and ($previousToken.StartLine -ne $t.StartLine)){
                $lineOffset = 0
            }
            else{
                $lineOffset = $ScriptText[($t.StartLine -1)].Length - $OriginalScript[($t.StartLine -1)].Length
            }

            if($t.Type -eq "Command" -and !$t.Content.Contains('-') -and ($(Get-Command $t.Content -Type Cmdlet,Function,ExternalScript,Alias -EA 0) -eq $Null)){
                $ScriptText[($t.StartLine - 1)] = $ScriptText[($t.StartLine - 1)].Insert( $t.StartColumn+$lineOffset -1, "nhe " )
            }
            elseif($t.Type -eq 'String'){
                if($previousToken -ne $null) {
                    if($previousToken.Type -eq 'Command'){
                        # leave it as is
                    }
                    elseif($previousToken.Type -eq 'CommandParameter') {
                        # leave it as is
                    }
                    elseif($previousToken.Type -ne 'CommandParameter') {
                        $ScriptText[($t.StartLine - 1)] = $ScriptText[($t.StartLine - 1)].Insert( $t.StartColumn+$lineOffset -1, "wht " )
                    }
                }
            }

            $previousToken = $t
        }


        Write-Output ([ScriptBlock]::Create( ($ScriptText -join "`n") ))
    }
}





