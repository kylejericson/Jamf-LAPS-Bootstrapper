 Jamf LAPS Bootstrapper
 
I wanted to make a tool to get the LAPS password from a Mac in Jamf using the free tool macOSLAPS.

You can get this tool from here: https://github.com/joshua-d-miller/macOSLAPS

Jamf Extension attribute: https://github.com/kylejericson/JAMF/blob/master/Computer%20Extension%20Attributes/LAPS%20Password.xml

First, this tool assumes you have the following deployed:

1. Jamf Pro with macOS LAPS setup and an extension attribute with the laps password
2. The Extension attribute Id from Jamf ![](https://github.com/kylejericson/Jamf-LAPS-Bootstrapper/blob/main/id.jpg)
3. Jamf Pro user with rights to read the LAPS password via API
4. Mac enrolled with a LAPS password in its inventory


![](https://github.com/kylejericson/Jamf-LAPS-Bootstrapper/blob/main/Jamf%20LAPS%20Bootstrapper.gif)
