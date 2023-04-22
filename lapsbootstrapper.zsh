#!/bin/zsh
# Created by Kyle Ericson and OpenAI
# Version 1.4

dialog="/usr/local/bin/dialog"
exitCode=""

if [[ -f "$dialog" ]]; then 
    echo "Installed"; 
else  
    echo "Not Installed"
    if [[ $(id -u) -ne 0 ]]; then
        osascript -e 'tell app "System Events" to display dialog "This must be run as admin." giving up after (100) with title "LAPS Password Error" buttons {"Exit"} default button "Exit" with icon file "System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:AlertStopIcon.icns"'
        exit 1
    fi
    dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
    /usr/bin/curl --location --silent "$dialogURL" -o "/tmp/Dialog.pkg"
    /usr/sbin/installer -pkg "/tmp/Dialog.pkg" -target /
    dialogVersion=$( /usr/local/bin/dialog --version )
    echo "swiftDialog version ${dialogVersion} installed; proceeding..."
fi

# Define the file path for the saved credentials
credsFile="$HOME/.jamfcreds"

# Check if the credentials are already saved
if [ -f "$credsFile" ]; then
  # Credentials are saved, so read them from the file
  read -r apiUser apiPass apiURL jamfexid < "$credsFile"
else
  # Credentials are not saved, so prompt the user for them
	dialogOutput=$( $dialog --message none --title "LAPS Password Bootstrapper"  --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Accounts.icns --textfield "API Username",required --textfield "API Password",required,secure  --textfield "Jamf Pro URL",required --textfield "Jamf Extension Attribute ID",required --checkbox "Save Credentials" -p)

	apiUser=$(echo $dialogOutput | grep "API Username" | awk -F " : " '{print $NF}')
	apiPass=$(echo $dialogOutput | grep "API Password" | awk -F " : " '{print $NF}')
	apiURL=$(echo $dialogOutput | grep "Jamf Pro URL" | awk -F " : " '{print $NF}')
	jamfexid=$(echo $dialogOutput | grep "Jamf Extension Attribute ID" | awk -F " : " '{print $NF}')
	checkbox=$(echo $dialogOutput | grep "Save Credentials" | awk -F " : " '{print $NF}')

  # Trim any trailing slashes from the API URL
  apiURL=$(echo "$apiURL" | sed 's|/$||')

  # If the user chose to save the credentials, write them to the file
  if [[ "$checkbox" == *true* ]]; then
    echo "$apiUser $apiPass $apiURL $jamfexid" > "$credsFile"
  fi
fi

# Prompt the user for the computer serial number
prompt=$($dialog --title "Enter the computer serial number" --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.imac-unibody-27.icns --textfield "Serial Number" --small --message none -p)
serialNumber=$(echo $prompt | grep "Serial Number" | awk -F " : " '{print $NF}')

BASIC=$(echo -n "$apiUser":"$apiPass" | base64)

#  Request API token
authToken=$(/usr/bin/curl -s -H "Authorization: Basic ${BASIC}" -X POST "${apiURL}/api/v1/auth/token")

#  Extract token, use awk if OS is below macOS 12 and use plutil if 12 or above.
if [[ $(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}') -lt 12 ]]; then
   api_token=$(/usr/bin/awk -F \" 'NR==2{print $4}' <<< "$authToken" | /usr/bin/xargs)
else
   api_token=$(/usr/bin/plutil -extract token raw -o - - <<< "$authToken")
fi
#echo $api_token

computerID=$(/usr/bin/curl -s -H "Authorization: Bearer $api_token" -H "Accept: application/xml" "$apiURL/JSSResource/computers/serialnumber/$serialNumber/subset/general" | xpath -e '//computer/general/id/text()' )

echo $computerID

if [[ -z ${computerID} ]]; then

    echo "Error: Unable to determine computerID; exiting."
    $dialog --title "LAPS Password Error" --button1text "Exit" --mini --message "\nComputer not found in Jamf. Please check serial number and try again." --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns -p
    
    exitCode="1"

else

    LAPS_Password=$(curl -s -H "Authorization: Bearer $api_token" -H "Accept: application/xml" "$apiURL/JSSResource/computers/serialnumber/$serialNumber/subset/extension_attributes" | xpath -e '//extension_attribute[id='$jamfexid']' 2>&1 | awk -F'<value>|</value>' '{print $2}' | tail -n +1)

    LAPS_Password=$(echo $LAPS_Password | sed "s/&amp;/\&/g" | sed "s/&lt;/\</g" | sed "s/&gt;/\>/g")

    # Display the LAPS password and prompt the user to copy it or exit
    echo "$LAPS_Password" | pbcopy

    $dialog --title "LAPS Password" --button1text "Copy to macOS clipboard" --mini --message "\nThe LAPS password is: $LAPS_Password" --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/LockedIcon.icns -p

    exitCode="0"

fi

# Invalidate the Bearer Token
api_token=$(/usr/bin/curl "${apiURL}/api/v1/auth/invalidate-token" --silent --header "Authorization: Bearer ${api_token}" -X POST)
api_token=""

exit $exitCode