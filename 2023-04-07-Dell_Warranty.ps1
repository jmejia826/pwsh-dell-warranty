# Get the machine serial number
$ServiceTag = (Get-CimInstance Win32_BIOS).SerialNumber

# If we do not have a serial number, abort
If (-Not $ServiceTag) { Return }

# Some global variables
$Global:AuthenticationToken = ""
$Global:ApiKey = "<APIKEY>"
$Global:ApiSecret = "<APISECRET>"
$Global:URLAuth = "https://apigtwb2c.us.dell.com/auth/oauth/v2/token"
$Global:URLWarranty = "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements"

# Function to get authentication token
function Get-AuthenticationToken {
     # Build the header
     $Headers = @{}
     $Headers["Content-Type"] = "application/x-www-form-urlencoded"

     # Build the body
     $Body = "client_id=$($Global:ApiKey)&client_secret=$($Global:ApiSecret)&grant_type=client_credentials"

     # Send the request in
     $Response = (Invoke-WebRequest -Uri $Global:URLAuth -Method 'POST' -Headers $Headers -Body $Body) | ConvertFrom-Json

     # Get the token
     if ($Response.access_token) { $Global:AuthenticationToken = $Response.access_token }
}

# Function to get the warranty and purchased date
Function Get-AssetInformation {
     # Build the header
     $Headers = @{}
     $Headers["Accept"]                 = "application/json"
     $Headers["Authorization"]          = "Bearer $Global:AuthenticationToken"

     # Build the request
     $Response = (Invoke-WebRequest -Uri "$($Global:URLWarranty )?servicetags=$ServiceTag" -Method 'GET' -Headers $Headers) | ConvertFrom-Json
     
     # Build the return data
     $Data = @{}
     $Data['shipDate'] = $Response.shipDate

     # Get the warranty expiration
     ForEach($Entitlement in $Response.entitlements) {
          # Get the latest warranty from the data
          $LatestWarranty = If ($Data['warrantyExpiration']) { Get-Date $Data['warrantyExpiration'] } else { Get-Date -Date "1/1/1900" }
          
          # Get this entitlement end date
          $ThisWarranty = Get-Date $Entitlement.endDate
          
          # Get the time difference
          $TimeSpan = New-TimeSpan -Start $LatestWarranty -End $ThisWarranty
          if ($TimeSpan.TotalSeconds -gt 0) { 
               $Data['warrantyExpiration'] = $Entitlement.endDate
               $Data['warrantyType'] = $Entitlement.serviceLevelDescription
          }
     }

     # Return the data
     Return $Data
}

# Main Function
function Main {
    # Authenticate on the API
    Get-AuthenticationToken

    # Get the warranty Info
    $WarrantyInformation = Get-AssetInformation

    # If we have data, lets update the ninja variable
    If ($WarrantyInformation.warrantyExpiration) {
        # Add the text data
        Write-Host ("[$(Get-Date)]`tSetting the warranty type as {0}" -f $($WarrantyInformation.warrantyType))
        Ninja-Property-Set WarrantyType $($WarrantyInformation.warrantyType)

        # Format the date values as yyyy-MM-dd
        $ShippingDate = Get-Date $WarrantyInformation.shipDate -Format "yyyy-MM-dd"
        $WarrantyExpiration =  Get-Date $WarrantyInformation.warrantyExpiration -Format "yyyy-MM-dd"

        # Update teh values
        Write-Host ("[$(Get-Date)]`tSetting the ship date as {0}" -f $ShippingDate)
        Write-Host ("[$(Get-Date)]`tSetting the warranty expiration date as {0}" -f $WarrantyExpiration)
    }
}

# Make the magic happen
Main
