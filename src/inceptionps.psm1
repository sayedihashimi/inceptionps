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

        $htmlWriter.RenderBeginTag($tag)
        # we have to handle any blocks inside
        while($args){
            $attrib, $value, $args = $args
            if($attrib -is [ScriptBlock]){ # this is content
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
        [Array]$duds = $global:tokens | Where-Object { $_.Type -eq "Command" -and !$_.Content.Contains('-') -and ($(Get-Command $_.Content -Type Cmdlet,Function,ExternalScript -EA 0) -eq $Null) }
        [Array]::Reverse( $duds )
   
        [string[]]$ScriptText = "$script" -split "`n"

        foreach($token in $duds ) {           
            # insert 'nhe' before everything (unless it's a valid command)
            $ScriptText[($token.StartLine - 1)] = $ScriptText[($token.StartLine - 1)].Insert( $token.StartColumn -1, "nhe " )
        }
<#
        # update all text elements with 'wht <text'
        [Array]$textTokens = $global:tokens | Where-Object {$_.Type -eq 'String' }
        [Array]::Reverse($textTokens)
        foreach($textToken in $textTokens){
            $ScriptText[($textToken.StartLine - 1)] = $ScriptText[($textToken.StartLine - 1)].Insert( $textToken.StartColumn -1, "wht " )
        }
        #>
        Write-Output ([ScriptBlock]::Create( ($ScriptText -join "`n") ))


    }
}





