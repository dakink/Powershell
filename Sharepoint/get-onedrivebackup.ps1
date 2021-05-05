function get-onedrivebackup {
    <#
    .synopsis
    Download a users onedrive to local disk
    .description
    Download a users onedrive to local disk for backup purposes. Can be used as part of a user termination script for instance. This script will give a global admin rights to the users onedrive, recreate the folder structure,
    and download all files into their original location. Afterwards it will zip the files for easy backup using 7-zip.
    .parameter UserPrincipalName
    Userprincipalname of the User to be backed up. In form of user@domain.com
    .parameter globaladmin
    Global Admin user that will gain temporary access to the backed up user. In the form of user@domain.com
    .parameter SharePointAdminURL
    URL to the admin portal of your sharepoint instance. In the form of https://<servicename>-admin.sharepoint.com
    .parameter Destination
    Destination folder to save files to.
    #>
    
    [CmdletBinding()]
      Param (
      #The user that will be added
      [Parameter(Mandatory=$True)]
      [string]$UserPrincipalName,
      #Global Admin username
      [Parameter(Mandatory=$True)]
      [string]$globaladmin,
      #Sharepoint Admin URL
      [Parameter(Mandatory=$False)]
      [string]$SharePointAdminURL = "https://koberservice-admin.sharepoint.com",
      #AccessRights needed for this user
      [Parameter(Mandatory=$False)]
      [string]$Destination = "c:\temp"
      )

      #set domainname for use:
      $domainname = "contoso.com"

      #URL for your sharepoint admin site
      $SharePointAdminURL = "https://contoso-admin.sharepoint.com"

      #url for Onedrive
      $SharepointSiteURL = "https://contoso-my.sharepoint.com/personal"
    
        #Input check for full principle name.
        if($UserPrincipalName -notlike "*@*"){
            $UserPrincipalName = "$userprincipalname@$domainname"
        }
    
        if($GlobalAdmin -notlike "*@*"){
            $GlobalAdmin = "$globaladmin@$domainname"
        }
    
        #Make sure there is a temp directory to save the files
        if(!(test-path("$destination"))){
            $dest = New-Item $destination -type directory
        }
    
          
        #convert special chars to underscore for onedrive
        $departingUserUnderscore = $UserPrincipalName -replace "[^a-zA-Z]", "_"
                
        #set URL for departing user
        $departingOneDriveSite = "$SharepointSiteURL/$departingUserUnderscore"
        
        #connect to sharepoint admin
        Connect-SPOService -Url $SharePointAdminURL 
    
        
        # Set current admin as a Site Collection Admin on both OneDrive Site Collections
        Set-SPOUser -Site $departingOneDriveSite -LoginName $globaladmin -IsSiteCollectionAdmin $true
        
        #Connect to departing users onedrive
        Connect-PnPOnline -Url $departingOneDriveSite -UseWebLogin
    
        #Set owner user to allow file downloads
        $departingOwner = $userprincipalname.split("@")[0]
        # Relative location for Documents to grab files later on
        $departingOneDrivePath = "/personal/$departingUserUnderscore/Documents"
        #Destination for moving? This is probably no longer necessary
        $destinationOneDrivePath = "$destination\$departingOwner"
        # Get all items in the documents folder.
        $items = Get-PnPListItem -List Documents -PageSize 1000
    
        #Can't grab items larger than 250MB. Write those to file
        $largeItems = $items | Where-Object {[long]$_.fieldvalues.SMTotalFileStreamSize -ge 261095424 -and $_.FileSystemObjectType -contains "File"}
        if ($largeItems) {
            $largeexport = @()
            foreach ($item in $largeitems) {
                $largeexport += "$(Get-Date) - Size: $([math]::Round(($item.FieldValues.SMTotalFileStreamSize / 1MB),2)) MB Path: $($item.FieldValues.FileRef)"
            }
            $largeexport | Out-file C:\temp\largefiles.txt -Append
            
        }
    
        #Get items that can be downloaded
        $rightSizeItems = $items | Where-Object {[long]$_.fieldvalues.SMTotalFileStreamSize -lt 261095424 -or $_.FileSystemObjectType -contains "Folder"}
    
        #grab foldernames
        $folders = $rightSizeItems | Where-Object {$_.FileSystemObjectType -contains "Folder"}
    
        #Recreate folderstructure in temp.
        foreach ($folder in $folders) {
            $path = ('{0}{1}' -f $destinationOneDrivePath, $folder.fieldvalues.FileRef).Replace($departingOneDrivePath, '')
            #Write-Host "Creating folder in $path" -ForegroundColor Green
            #$newfolder = resolve-PnPFolder -SiteRelativePath $path
            $newfolder = new-item -Path $path -ItemType Directory
        }
    
        #Get all files
        $files = $rightSizeItems | Where-Object {$_.FileSystemObjectType -contains "File"}
        #Track possible file errors.
        $fileerrors = ""
        foreach ($file in $files) {            
            #set destinationpath
            $destpath = ("$destinationOneDrivePath$($file.fieldvalues.FileDirRef)").Replace($departingOneDrivePath, "")
            #actually download the file
            $newfile = get-pnpfile -Url "$($file.FieldValues.FileRef)" -Path $destpath -Filename "$($file.fieldvalues.FileLeafRef)" -AsFile -ErrorVariable errors -ErrorAction SilentlyContinue
            #if there is an error, log it.
            $fileerrors += $errors
        }
        #output errors
        $fileerrors | Out-File "$destinationOneDrivePath\fileerrors.txt"
    
        # Remove Global Admin from Site Collection Admin role for both users
        Set-SPOUser -Site $departingOneDriveSite -LoginName $globaladmin -IsSiteCollectionAdmin $false
    
        #zip files
        if(!(test-path "$($env:ProgramFiles)\7-Zip\7z.exe")){
            throw "7-Zip not found"
        }
        else {
            set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"
        }
        
        try{
            sz a -tzip "$destination\$departingOwner.zip" -r $destinationOneDrivePath
        }
        catch{
            write-output "Zip not created: $PSerror"
        }
    
    }