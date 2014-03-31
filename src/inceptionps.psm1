[cmdletbinding()]
param()

# Based on XmlDsl by Joel Bennett http://huddledmasses.org/a-dsl-for-xml-in-powershell-new-xdocument/

# TODO: Should this be here?
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
            elseif ( $value -is [ScriptBlock] -and "-CONTENT".StartsWith($attrib.TrimEnd(':').ToUpper())){
                $value = ConverFrom-HtmlDsl $value
                &value
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
        
        while($args){
            $attrib, $value, $args = $args

            if($args -eq $null){
                # don't write this out until all attributes have been added
                $htmlWriter.RenderBeginTag($tag)
            }

            if($attrib -is [ScriptBlock]){
                &$attrib
            }
            elseif ($value -is [ScriptBlock] -and "-CONTENT".StartsWith($attrib.TrimEnd(':').ToUpper())) { # then it's content
                &$value
            }
            elseif($value -match "-(?!\d)\w") { # TODO: Do we need this?
                $args = @($value)+@($args)
            }
            elseif($value -ne $null) {
                $htmlWriter.AddAttribute($attrib.TrimStart("-").TrimEnd(':'),$value)
            }
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

function ConverFrom-HtmlDsl {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$script
    )
    process{
        $parserrors = $null
        $global:tokens = [PSParser]::Tokenize( $script, [ref]$parserrors )
        
        # find all command tokens which don't exist
        [Array]$duds = $global:tokens | Where-Object { 
            ($_.Type -eq "Command" -and !$_.Content.Contains('-') -and ($(Get-Command $_.Content -Type Cmdlet,Function,ExternalScript -EA 0) -eq $Null) ) -or
            ($_.Type -eq 'String')}

        [Array]::Reverse( $duds )

        [string[]]$ScriptText = "$script" -split "`n"
        [string[]]$OriginalScript = "$script" -split "`n"

        $tokensToUpdate = @()
        $previousToken = $null
        $lineOffset = 0
        foreach($t in $global:tokens){            
            if($previousToken -ne $null -and ($previousToken.StartLine -ne $t.StartLine)){
                $lineOffset = 0
            }

            if($t.Type -eq "Command" -and !$t.Content.Contains('-') -and ($(Get-Command $t.Content -Type Cmdlet,Function,ExternalScript -EA 0) -eq $Null)){
                $ScriptText[($t.StartLine - 1)] = $ScriptText[($t.StartLine - 1)].Insert( $t.StartColumn+$lineOffset -1, "nhe " )
            }
            elseif($t.Type -eq 'String'){
                if($previousToken -ne $null) {

                    if($previousToken.Type -ne 'CommandParameter') {
                        $ScriptText[($t.StartLine - 1)] = $ScriptText[($t.StartLine - 1)].Insert( $t.StartColumn+$lineOffset -1, "wht " )
                    }

                    if($previousToken.Type -eq 'CommandParameter') {
                        # overwrite the previous token as well as this one with a call to wha
                        $ScriptText[($t.StartLine - 1)] = $ScriptText[($t.StartLine - 1)].Remove(($previousToken.StartColumn+$lineOffSet - 1),1).Insert(($previousToken.StartColumn+$lineOffset - 1),'{ wha ') + '}'
                    }
                }
            }

            if($previousToken -ne $null -and $previousToken.StartLine -eq $t.StartLine){
                # we need to add the number of new characters to the lineoffset variable
                $lineOffset = $ScriptText[($t.StartLine -1)].Length - $OriginalScript[($t.StartLine -1)].Length
            }
            
            $previousToken = $t
        }


        Write-Output ([ScriptBlock]::Create( ($ScriptText -join "`n") ))
    }
}





