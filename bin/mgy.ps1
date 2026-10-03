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
} elseif ($env:USERPROFILE -and $env:USERPROFILE -like "*\.config\multigravity-profiles*") {
    $env:USERPROFILE.Substring(0, $env:USERPROFILE.IndexOf("\.config\multigravity-profiles"))
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
  fork --conversation=<id> Fork an existing conversation across all other profiles
  delete <profile>       Delete an existing profile
  help, --help, -h       Show this help message
  <profile> [agy args]   Start agy session using the specified profile

Resume & Conversation Flags (same as agy):
  mgy <profile> --conversation=<id>   Resume a specific conversation by ID
  mgy <profile> -c, --continue        Continue the most recent conversation

Examples:
  mgy new work                 # Set up a new profile with Google login
  mgy list                     # List all registered profiles
  mgy fork --conversation=<id> # Fork conversation across all profiles
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
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($tokenFile, $savedCred, $utf8NoBom)
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

    "fork" {
        $convId = $null
        for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
            if ($RemainingArgs[$i] -match "^--conversation=(.+)$") {
                $convId = $matches[1]
                break
            } elseif ($RemainingArgs[$i] -eq "--conversation" -and ($i + 1) -lt $RemainingArgs.Count) {
                $convId = $RemainingArgs[$i + 1]
                break
            } elseif (-not $convId -and $RemainingArgs[$i] -notmatch "^-") {
                $convId = $RemainingArgs[$i]
            }
        }

        if (-not $convId) {
            Write-Error "Error: Missing conversation ID to fork. Usage: mgy fork --conversation=<id>"
            exit 1
        }

        $sourceAgyDir = Join-Path $RealHome ".gemini\antigravity-cli"
        $srcDb = Join-Path $sourceAgyDir "conversations\$convId.db"
        $srcBrain = Join-Path $sourceAgyDir "brain\$convId"

        if (-not (Test-Path $srcDb) -and -not (Test-Path $srcBrain)) {
            Write-Error "Error: Conversation '$convId' not found at $sourceAgyDir"
            exit 1
        }

        if (-not (Test-Path $ProfilesDir)) {
            Write-Error "Error: Profiles directory not found at $ProfilesDir"
            exit 1
        }

        $profiles = @(Get-ChildItem -Path $ProfilesDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($profiles.Count -eq 0) {
            Write-Error "Error: No profiles found in $ProfilesDir. Create profiles first with: mgy new <profile_name>"
            exit 1
        }

        $firstProfile = $profiles[0].Name
        $otherProfiles = if ($profiles.Count -gt 1) { $profiles[1..($profiles.Count - 1)] } else { @() }

        Write-Host "Forking conversation '$convId' across $($profiles.Count) profiles..." -ForegroundColor Cyan

        $results = @()
        # First profile retains original conversation
        $results += "mgy $firstProfile --conversation $convId"

        # Subsequent profiles each get a new forked conversation
        foreach ($p in $otherProfiles) {
            $pName = $p.Name
            $newId = [guid]::NewGuid().ToString()

            # 1. Copy SQLite database files (.db, .db-wal, .db-shm)
            $dstDb = Join-Path $sourceAgyDir "conversations\$newId.db"
            $srcWal = Join-Path $sourceAgyDir "conversations\$convId.db-wal"
            $dstWal = Join-Path $sourceAgyDir "conversations\$newId.db-wal"
            $srcShm = Join-Path $sourceAgyDir "conversations\$convId.db-shm"
            $dstShm = Join-Path $sourceAgyDir "conversations\$newId.db-shm"

            if (Test-Path $srcDb) {
                Copy-Item -Path $srcDb -Destination $dstDb -Force
                if (Test-Path $srcWal) { Copy-Item -Path $srcWal -Destination $dstWal -Force }
                if (Test-Path $srcShm) { Copy-Item -Path $srcShm -Destination $dstShm -Force }

                # Rebind trajectory identity in SQLite to prevent "trajectory not found" / duplicate-load collisions
                try {
                    $pythonCmd = Get-Command "python" -ErrorAction SilentlyContinue
                    if ($pythonCmd) {
                        $pyScript = @"
import sqlite3, uuid
c = sqlite3.connect(r'$dstDb')
new_traj = str(uuid.uuid4())
c.execute("UPDATE trajectory_meta SET cascade_id = ?, trajectory_id = ?", ('$newId', new_traj))
rows = c.execute("SELECT id, data FROM trajectory_metadata_blob").fetchall()
for b_id, b_data in rows:
    if b_data and '$convId'.encode('utf-8') in b_data:
        patched = b_data.replace('$convId'.encode('utf-8'), '$newId'.encode('utf-8'))
        c.execute("UPDATE trajectory_metadata_blob SET data = ? WHERE id = ?", (patched, b_id))
c.commit()
c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
c.close()
"@
                        & python -c $pyScript 2>$null
                    }
                } catch {}
            }

            # 2. Copy brain directory using robocopy for high-speed multi-file cloning
            $dstBrain = Join-Path $sourceAgyDir "brain\$newId"
            if (Test-Path $srcBrain) {
                if (Test-Path $dstBrain) { Remove-Item -Path $dstBrain -Recurse -Force }
                New-Item -ItemType Directory -Path $dstBrain -Force | Out-Null
                robocopy "$srcBrain" "$dstBrain" /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
            }

            # 3. Copy annotations if present
            $srcAnno = Join-Path $sourceAgyDir "annotations\$convId.pbtxt"
            $dstAnno = Join-Path $sourceAgyDir "annotations\$newId.pbtxt"
            if (Test-Path $srcAnno) {
                Copy-Item -Path $srcAnno -Destination $dstAnno -Force
            }

            # 4. Remove presence lock if exists
            $dstLock = Join-Path $sourceAgyDir "presence\$newId.lock"
            if (Test-Path $dstLock) {
                Remove-Item -Path $dstLock -Force -ErrorAction SilentlyContinue
            }

            $results += "mgy $pName --conversation $newId"
        }

        Write-Host ""
        foreach ($r in $results) {
            Write-Host $r
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
                    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                    [System.IO.File]::WriteAllText($tokenFile, $savedCred, $utf8NoBom)
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
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($tokenFile, $hostCred, $utf8NoBom)
            }
        }

        Write-Host "Profile '$profileName' imported from global host config!" -ForegroundColor Green
    }

    { $_ -in @("quotas", "quota", "quotes", "quote") } {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $quotaScript = Join-Path $scriptDir "mgy-quota"
        if (-not (Test-Path $quotaScript)) {
            $quotaScript = Join-Path $scriptDir "mgy-quota.py"
        }
        if (-not (Test-Path $quotaScript)) {
            $quotaCmd = Get-Command "mgy-quota" -ErrorAction SilentlyContinue
            if ($quotaCmd) { $quotaScript = $quotaCmd.Source }
        }
        if (-not (Test-Path $quotaScript)) {
            $quotaCmd = Get-Command "mgy-quota.py" -ErrorAction SilentlyContinue
            if ($quotaCmd) { $quotaScript = $quotaCmd.Source }
        }

        if (Test-Path $quotaScript) {
            if (-not $env:COLUMNS) {
                try {
                    $cols = $Host.UI.RawUI.WindowSize.Width
                    if ($cols -and $cols -gt 0) {
                        $env:COLUMNS = "$cols"
                    }
                } catch {}
            }
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
