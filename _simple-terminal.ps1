param([string]$Ttyd,[string]$Port,[string]$Cred,[string]$Cwd)

# Dark background for the web terminal (xterm.js theme).
# Inner quotes are escaped as \" so they survive to ttyd's JSON parser.
$theme = 'theme={\"background\":\"#0d0d0d\",\"foreground\":\"#e6e6e6\",\"cursor\":\"#d97757\"}'

$argline = "-p $Port -W -c $Cred -w `"$Cwd`" -t $theme powershell -NoLogo"
Start-Process -FilePath $Ttyd -ArgumentList $argline -WindowStyle Minimized
