<html>
 <head>
  <title>PHP Test</title>
 </head>
 <body>
  <?php
   # Call me: hass_update.php?entity=input_boolean.motion&state=on
   if( ini_get('safe_mode') ){
     echo "[Warning] Safemode on";
     exit(1);
   }
   $hass = "http://192.168.1.2:8123"; # Hass ip or domain
   $hass_token = ".konnected.vn."; # Long-lived token from Hass
   $entity = htmlspecialchars($_GET["entity"]);
   $state = htmlspecialchars($_GET["state"]);
   $source = "synology";
   $command = "curl -s -X POST -H \"Authorization: Bearer $hass_token\" -H \"Content-Type: application/json\" -d '{\"state\":\"$state\",\"attributes\":{\"source\":\"$source\"}}' $hass/api/states/$entity";
   echo "<pre>".$command."</pre>";
   echo "<pre>".shell_exec($command)."</pre>";
  ?>
 </body>
</html>