# Define input and output files
$InputFile = "fqdn_list.txt"  # Input file with FQDN:Port format (one per line)
$OutputFile = "certs_info.csv"  # Output CSV file

# Email notification details
$EmailRecipient = "your_email@example.com"
$DaysAhead = 30  # Days before expiration for warning
$FinalNoticeDays = 7  # Days before expiration for final notice

# Check if the input file exists
if (-Not (Test-Path $InputFile)) {
    Write-Host "Input file '$InputFile' not found."
    exit 1
}

# Initialize the output CSV file with headers
"Expiration (YYYYMMDD),FQDN,Port,Expiration Date (Org),Serial Number,Subject Name" | Set-Content $OutputFile

# Read the input file line by line
Get-Content $InputFile | ForEach-Object {
    $Parts = $_ -split ":"
    if ($Parts.Count -ne 2) {
        Write-Host "Skipping invalid line: $_"
        return
    }

    $FQDN = $Parts[0]
    $Port = $Parts[1]

    # Fetch the certificate using OpenSSL
    $CertOutput = openssl s_client -connect "$FQDN`:$Port" -showcerts 2>$null

    if (-Not $CertOutput) {
        Write-Host "Failed to connect to $FQDN:$Port"
        return
    }

    # Extract certificates
    $Certs = $CertOutput -match "-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----"
    if (-Not $Certs) {
        Write-Host "No valid certificates found for $FQDN:$Port"
        return
    }

    foreach ($Cert in $Certs) {
        # Extract expiration date, subject name, and serial number
        $ExpirationDate = openssl x509 -enddate -noout -in <# CertFile #> | ForEach-Object { ($_ -split "=")[1] }
        $SubjectName = openssl x509 -subject -noout -in <# CertFile #> | ForEach-Object { ($_ -replace "subject= ", "").Trim() }
        $SerialNumber = openssl x509 -serial -noout -in <# CertFile #> | ForEach-Object { ($_ -split "=")[1] }

        if ($ExpirationDate -and $SubjectName -and $SerialNumber) {
            # Convert expiration date to YYYYMMDD format
            $FormattedDate = Get-Date $ExpirationDate -Format "yyyyMMdd"
            $Today = Get-Date -Format "yyyyMMdd"
            $DaysRemaining = (New-TimeSpan -Start (Get-Date) -End (Get-Date $ExpirationDate)).Days

            # Append data to CSV file
            "$FormattedDate,$FQDN,$Port,$ExpirationDate,$SerialNumber,$SubjectName" | Add-Content $OutputFile

            # Send email notifications
            if ($DaysRemaining -le $DaysAhead -and $DaysRemaining -gt $FinalNoticeDays) {
                Send-MailMessage -To $EmailRecipient -Subject "SSL Certificate Expiring Soon - $FQDN" -Body "The SSL certificate for $FQDN on port $Port expires in 30 days on $ExpirationDate." -SmtpServer "your_smtp_server"
                Write-Host "30-day expiration email sent for $FQDN:$Port"
            } elseif ($DaysRemaining -le $FinalNoticeDays -and $DaysRemaining -gt 0) {
                Send-MailMessage -To $EmailRecipient -Subject "FINAL NOTICE: SSL Certificate Expiring Soon - $FQDN" -Body "The SSL certificate for $FQDN on port $Port expires in 7 days on $ExpirationDate." -SmtpServer "your_smtp_server"
                Write-Host "7-day final notice email sent for $FQDN:$Port"
            }
        } else {
            Write-Host "Could not parse certificate details for $FQDN:$Port"
        }
    }
}

Write-Host "Certificate information saved to $OutputFile"
