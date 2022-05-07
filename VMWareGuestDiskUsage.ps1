# vMWareGuestDiskUsage.ps1
# Trabant Technology Partners LLC
# Copyright (c) 2022 Kevin Robert Harig
# https://www.trabanttech.com
#================================================================================================================
# Purpose:      This script uses PowerShell & VMWare PowerCLI to create and send emailed reports on the disk size
#               and available capacity of virtual machine guest disks in a VMware virtualization environment.
# Author:       Kevin Robert Harig :: kevin@trabanttech.com
# Notes:        This script requires PowerShell (ver. 6+) and VMWare PowerCLI installed on the machine where this 
#               PowerShell script is to be executed. See VMWare Documentation: https://bit.ly/3pNgDlf
#               This script must be run manually the first time in order to capture, encrypt, and store necessary 
#               credentials. (Script can then be automated via Scheduled Task, etc.)
#
#               To execute this script without email: "pwsh vMWareGuestDiskUsage.ps1 -noemail"
#================================================================================================================
# Version:      1.0.0 - Initial completed script. 2022/03/07 (KRH)
#               1.0.1 - Style changes & added logic for optional SSL. 2022/03/08 (KRH)
#               1.0.2 - OS platform logic & progress bar added. 2002/03/09 (KRH)
#================================================================================================================
# License:      Attribution-NonCommercial-NoDerivatives 4.0 International (CC BY-NC-ND 4.0)
# Terms:        https://creativecommons.org/licenses/by-nc-nd/4.0/
#================================================================================================================
# This script will clear all existing PowerShell variables to ensure accurate results.
Remove-Variable * -ErrorAction SilentlyContinue
#================================================================================================================
#**** UPDATE THE FOLLOWING VARIABLES FOR YOUR ENVIRONMENT. ******************************************************
#================================================================================================================
#For the following REQUIRED variables, replace the sample values.   
    #DNS name or IP address of the target VMWare vCenter Server or ESXi Host.
    $hostAddress = "vcenter.sample.com"
    #Email sender, smtp server, smtp port number, and email recipients. Sender should match credentials
    #captured, encrypted, and stored on first run of this script.
    $emailFrom = "sender@sample.com"
    $smtpServer = "smtp.sample.com"
    $smtpPort = "587"
    #Set the value to "Yes" for SSL or "No" if SSL is not used.
    $useSSL = "Yes"
    #Multiple addresses can be entered, separated by commas ("sample01@sample.com","sample02@sample.com").
    $emailTo = @("recipient@sample.com")
#================================================================================================================
#**** EDITS BELOW THIS LINE ARE NOT REQUIRED. *******************************************************************
#================================================================================================================
$version = "1.0.2"
$ts = Get-Date -UFormat "%R %m/%d/%Y"
if (Get-Module -ListAvailable -Name VMware.PowerCLI){
    Write-Progress -Activity "Checking Prerequisites" -Status "Module exists"; Start-Sleep -Seconds 2
} 
else {
    Write-Progress -Activity "Checking Prerequisites" -Status "Installing Prerequisites"; Start-Sleep -Seconds 2
    Install-Module -Name VMware.PowerCLI -AllowClobber -Scope CurrentUser -Force;
}
Write-Progress -Activity "Checking Prerequisites" -Status "Ready" -Completed; Start-Sleep -Seconds 2
Write-Progress -Activity 'Progress' -Status ' Accessing Credentials' -PercentComplete 1 ; Start-Sleep -Seconds 2
#Find or create folder for storing credentials.
$hostCredName = $hostAddress -replace '[^\p{L}\p{Nd}]', ''
If ($IsMacOS) {
    $credsStore = "~\Library\Application Support\PowerCLI Data\SharedCredentials\"
}  
If ($IsWindows) {
    $credsStore = "$env:LOCALAPPDATA\PowerCLI Data\SharedCredentials\"
}
If(!(test-path $credsStore)) {
    New-Item -ItemType Directory -Force -Path $credsStore | Out-Null
}
#Find or request & store VMWare & email credentials.
try {
    $vmwCreds = Import-CliXml -Path "$credsStore\$hostCredName.cred"
} 
catch {
    $vmwCreds = Get-Credential -Message 'Please Enter VMWare Username and Password.' ; $vmwCreds | Export-CliXml -Path "$credsStore\$hostCredName.cred"
}
    $vmwUser = $vmwCreds.UserName ; $vmwPassword = $vmwCreds.GetNetworkCredential().Password
If ($args[0] -ne '-noemail'){
    try {
      $emailCreds = Import-CliXml -Path "$credsStore\email.cred"
    } 
    catch {
      $emailCreds = Get-Credential -Message 'Please Enter Email Username and Password.' ; $emailCreds | Export-CliXml -Path "$credsStore\email.cred"
    }
}
$connectionStatus = ' Connecting to ' + $hostAddress
Write-Progress -Activity 'Progress' -Status $connectionStatus -PercentComplete 20 ; Start-Sleep -Seconds 2
#Allow invalid SSL certificates, suppress certificate warnings & connect to VMWare target.
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -Confirm:$false -ParticipateInCEIP $false | Out-Null ;
Write-Progress -Activity 'Progress' -Status ' Gathering Information ' -PercentComplete 40 ; Start-Sleep -Seconds 2
$server = Connect-VIServer -Server $hostAddress -User $vmwUser -Password $vmwPassword
if ($null -eq $global:defaultviserver) {
    Write-Progress -Activity 'Progress' -Status ' Failed to connect to target server.' -PercentComplete 100 ; Start-Sleep -Seconds 5
    Write-Error 'Failed to connect to target server.' -ErrorAction Stop
}
$vMDiskReport = ForEach ($vm in Get-VM){
    ($vm.Extensiondata.Guest.Disk | Select-Object @{Name="Virtual Machine Name";Expression={$vm.Name}}, @{Name="Disk";Expression={$_.DiskPath}}, @{Name="Capacity (MB)";Expression={[math]::Round($_.Capacity/ 1MB)}}, @{Name="Available (MB)";Expression={[math]::Round($_.FreeSpace / 1MB)}}, @{Name="Available (%)";Expression={[math]::Round(((100* ($_.FreeSpace))/ ($_.Capacity)),0)}});
}
#CSS styling for HTML email message body.
$head = @"
<link rel="preconnect" href="https://fonts.gstatic.com">
<link href="https://fonts.googleapis.com/css?family=Montserrat" rel="stylesheet">
<style> table { border-width: 2px; border-style: solid; border-color: grey; border-collapse: collapse; align: left; margin-bottom: 10px;} th {border-width: 2px; border-style: solid; border-color: grey; padding-top: 6px; padding-bottom: 6px; padding-left: 10px; padding-right: 10px; background-color: #0e67b4; font-weight: normal; color: white;} td {border-width: 1px; border-style: solid; border-color: grey; padding-top: 4px; padding-bottom: 4px; padding-left: 10px; padding-right: 10px; background-color: none;} tr:nth-child(even) {background-color: #E8E8E8;} * {font-family: montserrat, sans-serif; font-size: 14px; color: black;} h5 {font-weight: 600; margin: 2px;}</style>
"@
$header = @"
<style type="text/css"> .headerimg { height: 120px; width: 300px; border: 0px; margin: 3px;}</style>
<a href="https://www.trabanttech.com" target="_blank"><img class="headerimg" src="https://storage.googleapis.com/www-trabant-tech-com/Blue%20Type%20Logo%20(1).png" alt="Trabant Technology Partners Website"></a>
"@
$footer = @"
<link href="https://fonts.googleapis.com/css?family=Montserrat" rel="stylesheet">
<hr style="height:2px; width:100%; border-width:0; color:lightgrey; background-color:lightgrey;"><br>
<div style="margin-left:20%; margin-right:20%;"><div><p style="font-family: 'montserrat', sans-serif; font-size: 12px; font-weight: light;" align="center"><a href="https://www.youtube.com/channel/UCdH9e2eu01kbps6onX_TTdQ" target="_blank"><img style="width: 24px; height: 24px; border: 0px; margin: 3px;" src="https://storage.googleapis.com/www-trabant-tech-com/YouTube_social_red_squircle_(2017).svg" alt="YouTube"></a><a href="https://www.instagram.com/trabanttech/" target="_blank"><img style="width: 24px; height: 24px; border: 0px; margin: 3px;" src="https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Instagram_icon.png/256px-Instagram_icon.png" alt="Instagram"></a><a href="https://www.facebook.com/TrabantTech/" target="_blank"><img style="width: 24px; height: 24px; border: 0px; margin: 3px;" src="https://upload.wikimedia.org/wikipedia/commons/thumb/d/d5/Facebook_F_icon.svg/256px-Facebook_F_icon.svg.png" alt="Facebook"></a><a href="https://www.linkedin.com/company/trabant-technology-partners/" target="_blank"><img style="width: 24px; height: 24px; border: 0px; margin: 3px;" src="https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/LinkedIn_logo_initials.png/256px-LinkedIn_logo_initials.png" alt="LinkedIn"></a><a href="mailto:info@trabanttech.com" target="_blank"><img style="width: 24px; height: 24px; border: 0px; margin: 3px;" src="https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Mail_%28iOS%29.svg/256px-Mail_%28iOS%29.svg.png" alt="Email"></a><br>Copyright 2022 by Trabant Technology Partners LLC. All Rights Reserved.</p></div></div>
"@
Write-Progress -Activity 'Progress' -Status ' Processing Data and Sending Reports' -PercentComplete 60 ; Start-Sleep -Seconds 2
#Sort virtual disks by "Available (%).
$vMDiskReportSorted = $vMDiskReport | Sort-Object "Available (%)"
#Create body of email with formatted tables & send email with reports.
$rep01 = $vMDiskReportSorted | ConvertTo-HTML -head $head -body "<h5>Virtual Machine Guest Disk Usage - Sorted by Available Disk Space %</h5>";
$rep02 = $vMDiskReport | ConvertTo-HTML -head $head -body "<h5>Virtual Machine Guest Disk Usage - Sorted by Virtual Machine</h5>";
$preContent = "<br/>This is an automated message, do not reply. <br/><br/>";
$postContent = "vMWareGuestDiskUsage.ps1 version $version executed at $ts.<br/><br/>Trabant Technology Partners<br/><a href='mailto:info@trabanttech.com'>info@trabanttech.com</a> | <a href='https://www.trabanttech.com'>www.trabanttech.com</a><br/>";
$body = $header, $preContent, $rep01, $rep02, $postContent, $footer ; $body = $body | Out-String
If ($args[0] -eq '-noemail'){
    $tmp = [System.IO.Path]::GetTempPath()
    If(!(test-path $tmp)) {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    }
    $body | Out-File -Path $tmp'VMDiskUsage.html' ; Invoke-Item -Path $tmp'VMDiskUsage.html'
}
else{
    If ($useSSL -eq 'Yes') {
        Send-MailMessage -From $emailFrom -To $emailTo -Subject 'Virtual Machine Guest Disk Usage Report' -Body $body -BodyAsHtml -SmtpServer $smtpServer -UseSSL -Port $smtpPort -Credential $emailCreds -WarningAction silentlyContinue
    }  
    If ($useSSL -eq 'No') {
        Send-MailMessage -From $emailFrom -To $emailTo -Subject 'Virtual Machine Guest Disk Usage Report' -Body $body -BodyAsHtml -SmtpServer $smtpServer -Port $smtpPort -Credential $emailCreds -WarningAction silentlyContinue
    }
} 
Write-Progress -Activity 'Progress' -Status ' Disconnecting from Target VMWare Host' -PercentComplete 80 ; Start-Sleep -Seconds 2
#Disconnect from the target VMWare vCenter Server or ESXi Host.
Disconnect-VIServer -Confirm:$false 
Write-Progress -Activity 'Progress' -Status ' Process Complete' -PercentComplete 100 ; Start-Sleep -Seconds 2 ; clear