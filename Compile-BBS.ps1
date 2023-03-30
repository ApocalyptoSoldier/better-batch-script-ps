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

foreach ($line in $lines)
{
	$line = $line.Trim()
	$words = $line -split ' ' | Select -Skip 1

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
		if ($reading -eq "function") { throw "Compiler Error!" };
		if ($words.Length -eq 2) {
			# Function without arguments.
			# Check if syntax is gud
			if ($words[1] -ne "{") { throw "Compiler Error!" } 
			else {
				$reading = "function";
				$functionList += "`n:BBSFN_" + $words[0] + "`n";
				$line = "//skipline";
			}
		} else { $line = "rem BBS: Not Supported Yet!"; }
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
		else { throw "Compiler Error!" }
	}
	
	if ($line.startsWith("fnrun ")) { $line = "call :BBSFN_" + ($words -join " ") }
	
	if ($line.startsWith("loop ")) {
		if ($reading -eq "loop") { throw "Compiler Error!" }
		if ($words.length -eq 2) {
			# Function without arguments.
			# Check if syntax is gud
			if ($words[1] -ne "{") { throw "Compiler Error!" } 
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
		# continue;
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