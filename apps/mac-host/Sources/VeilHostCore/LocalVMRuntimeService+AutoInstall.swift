import Foundation

extension LocalVMRuntimeService {
    static func prepareAutomaticInstallAnswerFile(for profile: VMProfile) throws {
        let answerFileURL = automaticInstallAnswerFileURL(for: profile)
        let answerFile = automaticInstallAnswerFile(
            accountName: WindowsAccountName.resolve(preferred: profile.windowsAccountName)
        )
        if FileManager.default.fileExists(atPath: answerFileURL.path),
           (try? String(contentsOf: answerFileURL, encoding: .utf8)) == answerFile {
            return
        }

        try answerFile.write(to: answerFileURL, atomically: true, encoding: .utf8)
    }

    /// Dynamic Update is off so Setup never waits on Windows Update over the VM's user-mode
    /// network before copying files; Windows Update runs after the first sign-in instead.
    /// https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-dynamicupdate
    ///
    /// The local account has no password, so Windows signs in to it without a prompt and the
    /// first-logon command installs the Veil agent unattended. The user can add a password in
    /// Windows Settings afterward.
    ///
    /// The VirtIO drivers install in the specialize pass because its RunSynchronous commands run in
    /// order as SYSTEM, before OOBE and first sign-in; FirstLogonCommands now all start at once, so
    /// the agent bootstrap there could not wait on them. Without the virtio-win media attached the
    /// command finds no volume and does nothing.
    /// https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous
    /// https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands
    /// https://learn.microsoft.com/windows-hardware/drivers/devtest/pnputil-command-syntax
    static func automaticInstallAnswerFile(accountName: String) -> String {
        let account = xmlEscaped(accountName)
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <settings pass="windowsPE">
            <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <SetupUILanguage>
                <UILanguage>ko-KR</UILanguage>
              </SetupUILanguage>
              <InputLocale>ko-KR</InputLocale>
              <SystemLocale>ko-KR</SystemLocale>
              <UILanguage>ko-KR</UILanguage>
              <UserLocale>ko-KR</UserLocale>
            </component>
            <component name="Microsoft-Windows-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <DiskConfiguration>
                <Disk wcm:action="add">
                  <DiskID>0</DiskID>
                  <WillWipeDisk>true</WillWipeDisk>
                  <CreatePartitions>
                    <CreatePartition wcm:action="add">
                      <Order>1</Order>
                      <Type>EFI</Type>
                      <Size>100</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                      <Order>2</Order>
                      <Type>MSR</Type>
                      <Size>16</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                      <Order>3</Order>
                      <Type>Primary</Type>
                      <Extend>true</Extend>
                    </CreatePartition>
                  </CreatePartitions>
                  <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                      <Order>1</Order>
                      <PartitionID>1</PartitionID>
                      <Label>System</Label>
                      <Format>FAT32</Format>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                      <Order>2</Order>
                      <PartitionID>3</PartitionID>
                      <Label>Windows</Label>
                      <Letter>C</Letter>
                      <Format>NTFS</Format>
                    </ModifyPartition>
                  </ModifyPartitions>
                </Disk>
                <WillShowUI>Never</WillShowUI>
              </DiskConfiguration>
              <ImageInstall>
                <OSImage>
                  <InstallTo>
                    <DiskID>0</DiskID>
                    <PartitionID>3</PartitionID>
                  </InstallTo>
                  <InstallFrom>
                    <MetaData wcm:action="add">
                      <Key>/IMAGE/NAME</Key>
                      <Value>Windows 11 Pro</Value>
                    </MetaData>
                  </InstallFrom>
                  <WillShowUI>Never</WillShowUI>
                </OSImage>
              </ImageInstall>
              <DynamicUpdate>
                <Enable>false</Enable>
                <WillShowUI>Never</WillShowUI>
              </DynamicUpdate>
              <UserData>
                <AcceptEula>true</AcceptEula>
                <ProductKey>
                  <WillShowUI>Never</WillShowUI>
                </ProductKey>
              </UserData>
            </component>
          </settings>
          <settings pass="specialize">
            <component name="Microsoft-Windows-Deployment" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                  <Order>1</Order>
                  <Path>cmd /c reg add HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                  <Description>Allow Windows OOBE offline setup when no inbox network driver is available</Description>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                  <Order>2</Order>
                  <Path>\(xmlEscaped(virtioDriverInstallCommand))</Path>
                  <Description>Install VirtIO drivers from the virtio-win media so Windows gets an IPv4 address</Description>
                </RunSynchronousCommand>
              </RunSynchronous>
            </component>
          </settings>
          <settings pass="oobeSystem">
            <component name="Microsoft-Windows-International-Core" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <InputLocale>ko-KR</InputLocale>
              <SystemLocale>ko-KR</SystemLocale>
              <UILanguage>ko-KR</UILanguage>
              <UserLocale>ko-KR</UserLocale>
            </component>
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
              </OOBE>
              <UserAccounts>
                <LocalAccounts>
                  <LocalAccount wcm:action="add">
                    <Name>\(account)</Name>
                    <DisplayName>\(account)</DisplayName>
                    <Group>Administrators</Group>
                    <Password>
                      <Value></Value>
                      <PlainText>true</PlainText>
                    </Password>
                  </LocalAccount>
                </LocalAccounts>
              </UserAccounts>
              <AutoLogon>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
                <Username>\(account)</Username>
                <Password>
                  <Value></Value>
                  <PlainText>true</PlainText>
                </Password>
              </AutoLogon>
              <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                  <Order>1</Order>
                  <Description>Install and start the Veil guest agent from VEIL_AUTO media</Description>
                  <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$volume = Get-Volume -FileSystemLabel 'VEIL_AUTO' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($volume -and $volume.DriveLetter) { $script = Join-Path ($volume.DriveLetter + ':\\') 'Veil Guest Agent\\scripts\\Bootstrap-VeilAgentFromMedia.ps1'; if (Test-Path $script) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script } }"</CommandLine>
                </SynchronousCommand>
              </FirstLogonCommands>
            </component>
          </settings>
        </unattend>

        """
    }

    /// Finds the virtio-win volume by label (drive letters differ between installs), adds NetKVM's
    /// Windows 11 Arm64 package with `pnputil /add-driver /install`, and appends pnputil's output
    /// to `%windir%\Temp\veil-virtio.log`. It always exits 0 so a driver problem cannot stop
    /// Windows Setup. RunSynchronous `Path` holds at most 259 characters, which is why the command
    /// is terse and installs one driver folder.
    /// https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous-runsynchronouscommand-path
    static var virtioDriverInstallCommand: String {
        "powershell -NoProfile -Command \""
            + "$d=([IO.DriveInfo]::GetDrives()|?{$_.IsReady -and $_.VolumeLabel -like '\(VirtioWinDriverMedia.volumeLabelPrefix)*'})[0];"
            + "if($d){pnputil /add-driver ($d.Name+'\(VirtioWinDriverMedia.networkDriverFolder)\\w11\\ARM64\\*.inf') /install *>>$env:windir\\Temp\\veil-virtio.log};"
            + "exit 0\""
    }

    static let runSynchronousPathMaximumLength = 259

    static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func allocatedFileSize(path: String?, bookmarkData: Data? = nil) -> Int64? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if protectedPathNeedsFilePicker(path, bookmarkData: bookmarkData) {
            return nil
        }

        let access = securityScopedAccess(role: .disk, bookmarkData: bookmarkData)
        defer {
            access?.stop()
        }
        let url = access?.url ?? URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ])

        if let totalAllocatedSize = values?.totalFileAllocatedSize {
            return Int64(totalAllocatedSize)
        }

        if let allocatedSize = values?.fileAllocatedSize {
            return Int64(allocatedSize)
        }

        return nil
    }
}
