#!/bin/zsh
# Created by Kyle Ericson and OpenAI
# Version 1.9

dialog="Dialog.app/Contents/MacOS/Dialog"
exitCode=""
Salt=""
Passphrase=""
jamfsettings="$HOME/Library/Application Support/jamfbootstrapper/jamfsettings.plist"

# Delete old Jamf Creds file
if [[ -f "$HOME/.jamfcreds" ]]; then
  rm -rf "$HOME/.jamfcreds"
fi

if [[ -f "$HOME/.jamfcred" ]]; then
  rm -rf "$HOME/.jamfcred"
fi

if [[ -f "$HOME/.jamfsp" ]]; then
  rm -rf "$HOME/.jamfsp"
fi

# Check if the credentials are already saved
if [ -f "$jamfsettings" ]; then
  # Credentials are saved, so read them from the file
  apiUser=$(/usr/bin/defaults read {$jamfsettings} apiuser)
  apiURL=$(/usr/bin/defaults read {$jamfsettings} jss_url)
  jamfexid=$(/usr/bin/defaults read {$jamfsettings} jamfeaid)
  apiPass=$(security find-generic-password -w -s "jamfBootstrapper" -a "$apiUser")
else
  # Credentials are not saved, so prompt the user for them
	dialogOutput=$( $dialog --message none --title "LAPS Password Bootstrapper" --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Accounts.icns --textfield "API Username",required --textfield "API Password",required,secure  --textfield "Jamf Pro URL",required --textfield "Jamf Extension Attribute ID",required --checkbox "Save Credentials" -p)

	apiUser=$(echo $dialogOutput | grep "API Username" | awk -F " : " '{print $NF}')
	apiPass=$(echo $dialogOutput | grep "API Password" | awk -F " : " '{print $NF}')
	apiURL=$(echo $dialogOutput | grep "Jamf Pro URL" | awk -F " : " '{print $NF}')
	jamfexid=$(echo $dialogOutput | grep "Jamf Extension Attribute ID" | awk -F " : " '{print $NF}')
	checkbox=$(echo $dialogOutput | grep "Save Credentials" | awk -F " : " '{print $NF}')

  # Trim any trailing slashes from the API URL
  apiURL=$(echo "$apiURL" | sed 's|/$||')

  # If the user chose to save the credentials, write them to the file
  if [[ "$checkbox" == *true* ]]; then
    if [[ ! -d "$HOME/Library/Application Support/jamfbootstrapper" ]]; then
        mkdir "$HOME/Library/Application Support/jamfbootstrapper"
        if [[ ! -f "${jamfsettings}" ]]; then
            touch "${jamfsettings}"
        fi
    fi
    security add-generic-password -s "jamfBootstrapper" -a "$apiUser" -w "$apiPass" -T /usr/bin/security
    defaults write "${jamfsettings}" apiuser -string ${apiUser}
    defaults write "${jamfsettings}" jss_url -string ${apiURL}
    defaults write "${jamfsettings}" jamfeaid -string ${jamfexid}
  fi
fi

# Prompt the user for the computer serial number
prompt=$($dialog --title "Enter the computer serial number" --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.imac-unibody-27.icns --textfield "Serial Number" --small --message none -p)
serialNumber=$(echo $prompt | grep "Serial Number" | awk -F " : " '{print $NF}')

BASIC=$(echo -n "${apiUser}":"${apiPass}" | base64)

#  Request API token
authToken=$(/usr/bin/curl -s -H "Authorization: Basic ${BASIC}" -X POST "${apiURL}/api/v1/auth/token")

#  Extract token, use awk if OS is below macOS 12 and use plutil if 12 or above.
if [[ $(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}') -lt 12 ]]; then
   api_token=$(/usr/bin/awk -F \" 'NR==2{print $4}' <<< "${authToken}" | /usr/bin/xargs)
else
   api_token=$(/usr/bin/plutil -extract token raw -o - - <<< "${authToken}")
fi

# Bearer token validation
apiBearerTokenCheck=$(/usr/bin/curl --write-out %{http_code} --silent --output /dev/null "${apiURL}/api/v1/auth" --request GET --header "Authorization: Bearer ${api_token}")
echo "apiBearerTokenCheck: ${apiBearerTokenCheck}; "
  if [[ ${apiBearerTokenCheck} != 200 ]]; then
    $dialog --title "LAPS Authorization Error" --button1text "Exit" --mini --message "Failed to get Bearer Token.\nError: ${apiBearerTokenCheck};" --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns -p
    echo "Error: ${apiBearerTokenCheck}; exiting."
    exit 1
  fi

computerID=$(/usr/bin/curl -s -H "Authorization: Bearer $api_token" -H "Accept: application/xml" "${apiURL}/JSSResource/computers/serialnumber/${serialNumber}/subset/general" | xpath -e '//computer/general/id/text()' )

if [[ -z ${computerID} ]]; then

    echo "Error: Unable to determine computerID; exiting."
    $dialog --title "LAPS Password Error" --button1text "Exit" --mini --message "\nComputer not found in Jamf. Please check serial number and try again." --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns -p    
    exitCode="1"

else

    LAPS_PasswordRaw=$(curl -s -H "Authorization: Bearer $api_token" -H "Accept: application/xml" "${apiURL}/JSSResource/computers/serialnumber/${serialNumber}/subset/extension_attributes" | xpath -e '//extension_attribute[id='$jamfexid']' 2>&1 | awk -F'<value>|</value>' '{print $2}' | tail -n +1)
    
    LAPS_Password=$(echo ${LAPS_PasswordRaw} | sed "s/&amp;/\&/g" | sed "s/&lt;/\</g" | sed "s/&gt;/\>/g" | sed 's/ //g')

    # Display the LAPS password and prompt the user to copy it or exit
    echo "${LAPS_Password}" | tr -d '\n' | pbcopy

    $dialog --title "LAPS Password" --button1text "Copy to macOS clipboard" --mini --message "\nThe LAPS password is: ${LAPS_Password}" --icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/LockedIcon.icns -p

    exitCode="0"

fi

# Invalidate the Bearer Token
api_token=$(/usr/bin/curl "${apiURL}/api/v1/auth/invalidate-token" --silent --header "Authorization: Bearer ${api_token}" -X POST)
api_token=""

exit $exitCode