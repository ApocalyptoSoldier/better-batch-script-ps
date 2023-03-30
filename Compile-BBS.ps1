<#
 .Synopsis
	Transpile a .bbs (better-batch-script) file to .bat (batch)

 .Description
	Translation of https://github.com/konalt/better-batch-script from js to PowerShell

 .Parameter FilePath
	The .bbs file to be transpiled
	
 .Example
	.\Compile-BBS -FilePath .\example.bbs
 #>

[cmdletBinding(SupportsShouldProcess=$false)]
param(
	[Parameter(Mandatory=$True)]
	[string]$FilePath
)

function logToFile() {
	param([string]$text)
	Write-Host $text
	$text | Out-File "betterbatch.log" -Append
}

if (-not (Test-Path $FilePath))
{
	Throw "Invalid file path specified!"
}

$lines = Get-Content $FilePath
logToFile "Loaded $FilePath with $($lines.Length) lines."

$fileText = "";
$reading = "none";
$newlineChar = "`n";
$functionList = "exit /b 1101";

$lineNum = 0

foreach ($line in $lines)
{
	$lineNum += 1
	$line = $line.Trim()
	$words = $line -split '\s+' | Select -Skip 1

	if ($line.StartsWith("echo"))
	{
		if (($words.Length -eq 1) -and ($words[0] -in @('off', 'on')))
		{
			$line = "echo. $($words[0])"
		}
	}

	if 		($line.StartsWith("s0")) 	{ $line = "@echo off" 	}
	elseif 	($line.StartsWith("s1"))	{ $line = "@echo on"	}
	
	if ($line.startsWith("fn ")) {
		if ($reading -eq "function") { throw "Compiler error on line $lineNum`: Nested functions aren't supported" };
		if ($words.Length -ge 2)
		{
			if ($words[-1] -ne "{") { throw "Compiler error on line $lineNum`: Missing opening bracket in function declaration" }
			
			$reading = "function"
			$line = "//skipline"
			
			# Function without arguments
			if ($words.Length -eq 2) {
				$functionList += "`n:BBSFN_" + $words[0] + "`n";
			}
			# Function with arguments
			else {
				$functionDeclarationLine = "`n:BBSFN_" + $words[0]
				$functionVariables = ''
							
				$functionArgs = $words | Select -Skip 1 -First ($words.Length - 2)
				[int]$argNum = 0
				
				# Add each argument to the function declaration and create a line that sets the argument to it's actual variable name
				# since arguments can only be accessed by their position eg. %~1
				foreach ($functionArg in $functionArgs) {
					$argNum += 1
					$argName = $functionArg -replace ',\s*', '' # Remove the comma separator
					$functionDeclarationLine += " $argName"
					$functionVariables += "set `"$argName=%~$argNum`"$newlineChar"
				}
				
				$functionList += "$functionDeclarationLine$newlineChar"
				$functionList += $functionVariables
			}
		}
		else { throw "Compiler error on line $lineNum" }
	}
	
	if ($line -eq "}") {
		if ($reading -eq "function") {
			$functionList += "goto :eof" + $newlineChar;
			$line = "//skipline";
			$reading = "none";
		} 
		elseif ($reading -eq "loop") {
			$line = ")";
			$reading = "none";
		} 
		else { throw "Compiler error on line $lineNum`: Unmatched closing bracket" }
	}
	
	if ($line.startsWith("fnrun ")) { $line = "call :BBSFN_" + ($words -join " ") }
	
	if ($line.startsWith("loop ")) {
		if ($reading -eq "loop") { throw "Compiler error on line $lineNum`: Nested loops not yet supported" }
		if ($words.length -eq 2) {
			# Function without arguments.
			# Check if syntax is gud
			if ($words[1] -ne "{") { throw "Compiler error on line $lineNum`: Missing opening bracket in loop declaration" } 
			else {
				$reading = "loop";
				$line = "for /l %%p in (0,1," + ([int]::Parse($words[0]) - 1) + ") do (";
			}
		} 
		else { $line = "rem BBS: Not Supported Yet!"; }
	}
	
	if ($line.StartsWith("sleep ")) { $line = "timeout /t " + $words[0] + " >nul" 	}
	if ($reading -eq "loop") 		{ $line = ($line -replace '\$loop', "%%p")		}
	
	# END OF COMMAND SHIT
	if ($line.StartsWith("//")) {
		if ($line -eq '//skipline') { continue; }
		$line = ($line -replace '^//\s{0,1}', 'REM ')
	}
	elseif ($reading -eq "function") {
		$functionList += "$line$newlineChar"
		continue;
	}
	
	$fileText += "$line$newlineChar"
}

$fileText += $functionList.TrimEnd()

$outPath = $filePath -replace "\.\w+$", '.bat'
Write-Host "Writing file $outPath"

$fileText | Out-File $outPath -Encoding utf8 # specify utf8 to make sure cmd can parse it