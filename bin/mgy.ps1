<#
.SYNOPSIS
mgy (multigravity) - Profile manager for Antigravity CLI (agy) on Windows
Manages isolated credentials, sessions, and configurations per profile.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# Resolve Home and Profiles Directory
$RealHome = if ($env:REAL_HOME) { 
    $env:REAL_HOME 
} elseif ($env:USERPROFILE) { 
    $env:USERPROFILE 
} else { 
    $env:HOME 
}

$ProfilesDir = if ($env:MULTIGRAVITY_PROFILES_DIR) { 
    $env:MULTIGRAVITY_PROFILES_DIR 
} else { 
    Join-Path $RealHome ".config\multigravity-profiles" 
}

# Windows Credential Manager P/Invoke definition for isolating Go-Keyring tokens
$WinCredSource = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinCredManager {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, uint type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite([In] ref CREDENTIAL userCredential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredDelete(string target, uint type, int flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern void CredFree([In] IntPtr buffer);

    public static string ReadCredential(string target) {
        string res = ReadSingleCredential(target);
        if (res == null && target.Contains(":")) {
            res = ReadSingleCredential(target.Replace(':', '/'));
        } else if (res == null && target.Contains("/")) {
            res = ReadSingleCredential(target.Replace('/', ':'));
        }
        return res;
    }

    private static string ReadSingleCredential(string target) {
        IntPtr credPtr;
        if (CredRead(target, 1, 0, out credPtr)) {
            try {
                CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
                if (cred.CredentialBlobSize > 0 && cred.CredentialBlob != IntPtr.Zero) {
                    byte[] bytes = new byte[cred.CredentialBlobSize];
                    Marshal.Copy(cred.CredentialBlob, bytes, 0, (int)cred.CredentialBlobSize);
                    return Encoding.UTF8.GetString(bytes);
                }
            } finally {
                CredFree(credPtr);
            }
        }
        return null;
    }

    public static bool WriteCredential(string target, string data) {
        byte[] bytes = Encoding.UTF8.GetBytes(data);
        IntPtr blobPtr = Marshal.AllocHGlobal(bytes.Length);
        try {
            Marshal.Copy(bytes, 0, blobPtr, bytes.Length);
            CREDENTIAL cred = new CREDENTIAL();
            cred.Type = 1; // CRED_TYPE_GENERIC
            cred.TargetName = target;
            cred.CredentialBlobSize = (uint)bytes.Length;
            cred.CredentialBlob = blobPtr;
            cred.Persist = 2; // CRED_PERSIST_LOCAL_MACHINE
            cred.UserName = "antigravity";
            return CredWrite(ref cred, 0);
        } finally {
            Marshal.FreeHGlobal(blobPtr);
        }
    }

    public static bool DeleteCredential(string target) {
        bool d1 = CredDelete(target, 1, 0);
        if (target.Contains(":")) {
            CredDelete(target.Replace(':', '/'), 1, 0);
        } else if (target.Contains("/")) {
            CredDelete(target.Replace('/', ':'), 1, 0);
        }
        return d1;
    }
}
"@

if (-not ([System.Management.Automation.PSTypeName]'WinCredManager').Type) {
    try {
        Add-Type -TypeDefinition $WinCredSource -ErrorAction SilentlyContinue
    } catch {}
}

function Show-Help {
    @"
Usage: mgy [command] [options]

Commands:
  new <profile>          Create a new isolated profile and authenticate
  import <profile>       Import host ~/.gemini session into a profile
  list                   List all existing profiles
  quotas, quota, quotes  Check model quota usage across all profiles
  conversations          List recent conversations and their IDs
  delete <profile>       Delete an existing profile
  help, --help, -h       Show this help message
  <profile> [agy args]   Start agy session using the specified profile

Resume & Conversation Flags (same as agy):
  mgy <profile> --conversation=<id>   Resume a specific conversation by ID
  mgy <profile> -c, --continue        Continue the most recent conversation

Examples:
  mgy new work                 # Set up a new profile with Google login
  mgy list                     # List all registered profiles
  mgy work                     # Start interactive agy session with profile
  mgy work -c                  # Continue latest chat under profile
  mgy work --conversation=<id> # Resume specific conversation by ID
  mgy conversations            # View list of recent conversation IDs
  mgy quotas                   # Inspect quotas across all profiles
"@
}

function Setup-ProfileEnvironment([string]$TargetDir) {
    $geminiDir = Join-Path $TargetDir ".gemini"
    $targetAgyDir = Join-Path $geminiDir "antigravity-cli"
    $sourceAgyDir = Join-Path $RealHome ".gemini\antigravity-cli"

    if (-not (Test-Path $geminiDir)) {
        New-Item -ItemType Directory -Path $geminiDir -Force | Out-Null
    }
    if (-not (Test-Path $sourceAgyDir)) {
        New-Item -ItemType Directory -Path $sourceAgyDir -Force | Out-Null
    }

    # Create NTFS Junction (shared conversations, history, MCP tools)
    $needsJunction = $true
    if (Test-Path $targetAgyDir) {
        try {
            $item = Get-Item -LiteralPath $targetAgyDir -Force
            if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
                $needsJunction = $false
            } else {
                $children = Get-ChildItem -LiteralPath $targetAgyDir -Force -ErrorAction SilentlyContinue
                if (-not $children -or $children.Count -eq 0) {
                    Remove-Item -LiteralPath $targetAgyDir -Force -Recurse -ErrorAction SilentlyContinue
                } else {
                    $needsJunction = $false
                }
            }
        } catch {
            $needsJunction = $false
        }
    }

    if ($needsJunction -and -not (Test-Path $targetAgyDir)) {
        try {
            New-Item -ItemType Junction -Path $targetAgyDir -Target $sourceAgyDir -ErrorAction Stop | Out-Null
        } catch {
            cmd /c mklink /J "$targetAgyDir" "$sourceAgyDir" 2>$null | Out-Null
        }
    }

    # Link host .gitconfig (git identity preservation)
    $sourceGit = Join-Path $RealHome ".gitconfig"
    $targetGit = Join-Path $TargetDir ".gitconfig"
    if ((Test-Path $sourceGit) -and -not (Test-Path $targetGit)) {
        try {
            New-Item -ItemType HardLink -Path $targetGit -Target $sourceGit -ErrorAction Stop | Out-Null
        } catch {
            Copy-Item -Path $sourceGit -Destination $targetGit -Force
        }
    }

    # Link host .ssh (keys preservation)
    $sourceSsh = Join-Path $RealHome ".ssh"
    $targetSsh = Join-Path $TargetDir ".ssh"
    if ((Test-Path $sourceSsh) -and -not (Test-Path $targetSsh)) {
        try {
            New-Item -ItemType Junction -Path $targetSsh -Target $sourceSsh -ErrorAction Stop | Out-Null
        } catch {
            cmd /c mklink /J "$targetSsh" "$sourceSsh" 2>$null | Out-Null
        }
    }
}

function Start-ProfileSession([string]$ProfileName, [string[]]$AgyArgs) {
    $targetDir = Join-Path $ProfilesDir $ProfileName
    if (-not (Test-Path $targetDir)) {
        Write-Error "Error: profile '$ProfileName' does not exist. Create it first using: mgy new $ProfileName"
        exit 1
    }

    Setup-ProfileEnvironment -TargetDir $targetDir

    $hasWinCred = ([System.Management.Automation.PSTypeName]'WinCredManager').Type -ne $null
    $tokensDir = Join-Path $targetDir ".tokens"
    $tokenFile = Join-Path $tokensDir "credential.txt"

    # Swap in profile credential before launching agy
    if ($hasWinCred) {
        if (Test-Path $tokenFile) {
            $tokenData = [System.IO.File]::ReadAllText($tokenFile, [System.Text.Encoding]::UTF8)
            [WinCredManager]::WriteCredential("gemini:antigravity", $tokenData) | Out-Null
        } else {
            [WinCredManager]::DeleteCredential("gemini:antigravity") | Out-Null
        }
    }

    $prevUserProfile = $env:USERPROFILE
    $prevHome = $env:HOME
    try {
        $env:USERPROFILE = $targetDir
        $env:HOME = $targetDir
        Write-Host "Starting agy with profile '$ProfileName'..." -ForegroundColor Cyan
        & agy @AgyArgs
    } finally {
        # Save updated credential back to profile
        if ($hasWinCred) {
            $savedCred = [WinCredManager]::ReadCredential("gemini:antigravity")
            if ($savedCred) {
                if (-not (Test-Path $tokensDir)) { New-Item -ItemType Directory -Path $tokensDir -Force | Out-Null }
                [System.IO.File]::WriteAllText($tokenFile, $savedCred, [System.Text.Encoding]::UTF8)
            }
        }
        $env:USERPROFILE = $prevUserProfile
        $env:HOME = $prevHome
    }
}

switch -Wildcard ($Command) {
    "help" { Show-Help; exit 0 }
    "-h"   { Show-Help; exit 0 }
    "--help" { Show-Help; exit 0 }
    ""     { Show-Help; exit 1 }

    "list" {
        Write-Host "Available profiles:" -ForegroundColor Cyan
        if ((Test-Path $ProfilesDir) -and (Get-ChildItem -Path $ProfilesDir -Directory -ErrorAction SilentlyContinue)) {
            Get-ChildItem -Path $ProfilesDir -Directory | ForEach-Object { Write-Host "  • $($_.Name)" }
        } else {
            Write-Host "  (no profiles found)" -ForegroundColor DarkGray
        }
    }

    "new" {
        $profileName = $RemainingArgs[0]
        if (-not $profileName) { Show-Help; exit 1 }
        $targetDir = Join-Path $ProfilesDir $profileName

        if (Test-Path $targetDir) {
            Write-Host "Profile '$profileName' already exists at: $targetDir"
            $resp = Read-Host "Re-authenticate profile '$profileName'? [y/N]"
            if ($resp -notmatch "^[yY]") {
                Write-Host "Aborted."
                exit 0
            }
        }

        $tokensDir = Join-Path $targetDir ".tokens"
        New-Item -ItemType Directory -Path $tokensDir -Force | Out-Null
        Setup-ProfileEnvironment -TargetDir $targetDir

        Write-Host "Setting up profile '$profileName'..." -ForegroundColor Cyan

        $hasWinCred = ([System.Management.Automation.PSTypeName]'WinCredManager').Type -ne $null
        $prevCred = if ($hasWinCred) { [WinCredManager]::ReadCredential("gemini:antigravity") } else { $null }
        if ($hasWinCred) {
            [WinCredManager]::DeleteCredential("gemini:antigravity") | Out-Null
        }

        $prevUserProfile = $env:USERPROFILE
        $prevHome = $env:HOME
        try {
            $env:USERPROFILE = $targetDir
            $env:HOME = $targetDir
            # agy authenticates automatically on startup when unauthenticated.
            # -p "/quota" triggers OAuth login in the browser/terminal and displays quotas once authenticated.
            & agy -p "/quota"
            if ($LASTEXITCODE -ne 0) {
                & agy
            }
        } finally {
            if ($hasWinCred) {
                $savedCred = [WinCredManager]::ReadCredential("gemini:antigravity")
                if ($savedCred) {
                    $tokenFile = Join-Path $tokensDir "credential.txt"
                    [System.IO.File]::WriteAllText($tokenFile, $savedCred, [System.Text.Encoding]::UTF8)
                    Write-Host "Profile '$profileName' is ready!" -ForegroundColor Green
                } else {
                    Write-Host "Warning: No credentials were saved for profile '$profileName'." -ForegroundColor Yellow
                    if ($prevCred) {
                        [WinCredManager]::WriteCredential("gemini:antigravity", $prevCred) | Out-Null
                    }
                }
            } else {
                Write-Host "Profile '$profileName' is ready!" -ForegroundColor Green
            }
            $env:USERPROFILE = $prevUserProfile
            $env:HOME = $prevHome
        }
    }

    "import" {
        $profileName = $RemainingArgs[0]
        if (-not $profileName) { Show-Help; exit 1 }
        $targetDir = Join-Path $ProfilesDir $profileName
        $sourceAgyDir = Join-Path $RealHome ".gemini\antigravity-cli"

        if (-not (Test-Path $sourceAgyDir)) {
            Write-Error "Error: Default antigravity configuration not found at $sourceAgyDir"
            exit 1
        }

        if (Test-Path $targetDir) {
            Write-Host "Profile '$profileName' already exists at $targetDir."
            $resp = Read-Host "Overwrite profile '$profileName' with host session? [y/N]"
            if ($resp -match "^[yY]") {
                Remove-Item -Path $targetDir -Recurse -Force
            } else {
                Write-Host "Aborted."
                exit 0
            }
        }

        $tokensDir = Join-Path $targetDir ".tokens"
        New-Item -ItemType Directory -Path $tokensDir -Force | Out-Null
        Setup-ProfileEnvironment -TargetDir $targetDir

        $hasWinCred = ([System.Management.Automation.PSTypeName]'WinCredManager').Type -ne $null
        if ($hasWinCred) {
            $hostCred = [WinCredManager]::ReadCredential("gemini:antigravity")
            if ($hostCred) {
                $tokenFile = Join-Path $tokensDir "credential.txt"
                [System.IO.File]::WriteAllText($tokenFile, $hostCred, [System.Text.Encoding]::UTF8)
            }
        }

        Write-Host "Profile '$profileName' imported from global host config!" -ForegroundColor Green
    }

    { $_ -in @("quotas", "quota", "quotes", "quote") } {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $quotaScript = Join-Path $scriptDir "mgy-quota"
        if (Test-Path $quotaScript) {
            python $quotaScript @RemainingArgs
            exit $LASTEXITCODE
        } else {
            # Fallback
            $profiles = Get-ChildItem -Path $ProfilesDir -Directory -ErrorAction SilentlyContinue
            if ($profiles) {
                foreach ($p in $profiles) {
                    Write-Host "`n=== Quota for profile: $($p.Name) ===" -ForegroundColor Cyan
                    Start-ProfileSession -ProfileName $p.Name -AgyArgs @("-p", "/quota")
                }
            } else {
                Write-Host "(no profiles found in $ProfilesDir)" -ForegroundColor DarkGray
            }
        }
    }

    { $_ -in @("delete", "rm", "remove") } {
        $profileName = $RemainingArgs[0]
        if (-not $profileName) { Show-Help; exit 1 }
        $targetDir = Join-Path $ProfilesDir $profileName
        if (-not (Test-Path $targetDir)) {
            Write-Error "Error: profile '$profileName' does not exist."
            exit 1
        }
        $resp = Read-Host "Are you sure you want to delete profile '$profileName'? [y/N]"
        if ($resp -match "^[yY]") {
            Remove-Item -Path $targetDir -Recurse -Force
            Write-Host "Profile '$profileName' deleted." -ForegroundColor Green
        } else {
            Write-Host "Aborted."
        }
    }

    { $_ -in @("conversations", "history", "chats") } {
        Write-Host "Recent conversations:" -ForegroundColor Cyan
        $db = Join-Path $RealHome ".gemini\antigravity-cli\conversation_summaries.db"
        $sqliteCmd = Get-Command "sqlite3" -ErrorAction SilentlyContinue
        if ((Test-Path $db) -and $sqliteCmd) {
            & sqlite3 -header -column $db "SELECT conversation_id AS ID, title AS Title, datetime(last_modified_time) AS Last_Active FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 10;"
        } elseif (Test-Path $db) {
            Write-Host "Found conversation database at: $db (install sqlite3 to query table directly)" -ForegroundColor Yellow
        } else {
            Write-Host "(no conversation history database found)" -ForegroundColor DarkGray
        }
    }

    "-*" {
        # Flags passed without explicit profile name (e.g. mgy -c, mgy --conversation=<id>)
        $selectedProfile = $env:MULTIGRAVITY_DEFAULT_PROFILE
        if (-not $selectedProfile -or -not (Test-Path (Join-Path $ProfilesDir $selectedProfile))) {
            $profiles = @(Get-ChildItem -Path $ProfilesDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            if ($profiles.Count -eq 1 -and $profiles[0]) {
                $selectedProfile = $profiles[0]
            } elseif ($profiles.Count -eq 0) {
                Write-Error "Error: No profiles found. Create one first using: mgy new <profile_name>"
                exit 1
            } else {
                Write-Error "Multiple profiles found. Please specify which profile to run: mgy <profile> $Command $($RemainingArgs -join ' ')"
                Write-Host "Available profiles:"
                foreach ($p in $profiles) { Write-Host "  • $p" }
                exit 1
            }
        }

        Start-ProfileSession -ProfileName $selectedProfile -AgyArgs (@($Command) + $RemainingArgs)
    }

    default {
        Start-ProfileSession -ProfileName $Command -AgyArgs $RemainingArgs
    }
}
