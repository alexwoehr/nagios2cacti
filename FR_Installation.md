# Introduction #

**Nagios2Cacti** est une passerelle entre l'outils de supervision nagios et le frontend RRDTool Cacti. Il permet d'utiliser Nagios pour réaliser toutes les opérations d'ordonnancement et laisse à Cacti le soin de générer les éventuelles graphiques liés à l'activité de monitoring.


# Récupération du code source #

vous pouvez récupérer la dernière version de travail de nagios2cacti directement dans le SVN de google :
> svn checkout http://nagios2cacti.googlecode.com/svn/trunk/ nagios2cacti-read-only

ou bien, vous pouvez télécharger la dernière archive :
[download](http://code.google.com/p/nagios2cacti/downloads/list)

# Instruction d'installation #
Pour procéder à l'installation dans les dossiers par défaut :
```
# cd
# svn checkout http://nagios2cacti.googlecode.com/svn/trunk/ nagios2cacti-read-only
# cd nagios2cacti-read-only/
# mv etc/n2rrd/ /etc
# cd /etc/n2rrd/
# cp dist-n2rrd.conf n2rrd.conf
# cd
# cp -R nagios2cacti-read-only /usr/lib/N2Cacti
# chmod +x /usr/lib/N2Cacti/*.pl
```
ensuite vous devrez personnaliser la configuration de n2rrd (voir la suite de la documentation pour le détail)

# Dépendance librairie PERL #
Package requis :
```
perl
perl-datemanip
perl-Net-Server
perl-error
```


Vous pouvez utiliser l'application de gestion de package de votre distribution (dpkg, rpm..) ou bien directement via CPAN comme ceci :
`perl -MCPAN -e 'install Error'`

# Méthode de transmission #

il y a deux méthodes de transmission possible :
**Transfert par un pipe nommé** Transfert par UDP

## Transfert par PIPE ##

Cette méthode est la plus légère, nagios écrit dans un pipe, et le serveur **perf2rrd** lit ces données les traites et les intègre dans des bases RRDtool. Si le serveur **perf2rrd** s'interrompt pour une raison (filesystem plein..) les données seront perdu, car le mécanisme de PIPE ne peut garder suffisamment de données en buffer.

## Transfert par UDP ##

Cette méthode est plus sûr. On configure Nagios pour qu'ils exécutent une commande pour transmettre les données de performance. Cette commande intègre un mécanisme de protection qui va enregistrer toutes les données dans un dossier, un fichier par indicateur. Le fichier est supprimé une fois le transfert de toutes les données à réussit. Si la transmission échoue, les données vont s'accumuler et seront correctement reprise ensuite.

## Transfer par AF\_UNIX ##

Cette méthode semblable à l'udp mais en local, elle devrait offrir performance et fiabilité.


# Configuration #
## Dossier d'installation ##
La configuration de nagios2cacti doit être placer dans /etc/n2rrd avec dans la racine de ce dossier le fichier n2rrd.conf et le dossier templates.

Par défaut, la partie logiciel doit être installer dans /usr/lib/N2Cacti


## Configuration de N2RRD ##
### Configuration du fichiers : /etc/n2rrd/n2rrd.conf ###
Listes variables importantes à configurer dans le fichier
> /etc/n2rrd/n2rrd.conf
```
* CACTI_DIR chemin d'accès a la racine de cacti
* OREON_DIR chemin d'accès a la racine d'oreon
* NAGIOS_CONF_DIR chemin d'accès au dossier de configuration de Nagios /etc/nagios/ par defaut
* ROTATION type de rotation : d pour daily, h pour hour, n pour none
* PID_FILE chemin du fichier contenant le PID quand le démon *perf2rrd.pl* ou *server_perf.pl*
* SERVICE_PERFDATA_PIPE chemin vers le pipe nommé si c'est la methode employé
* PERFDB_NAME nom de la base de données utilisé pour les PERFDB (optionnel)
* PERFDB_USER user
* PERFDB_PASSWORD password
* PERFDB_HOST nom du serveur
* TEMPLATE_SEPARATOR_FIELD : "@" par défaut, permet de spécifier le nom du template n2rrd dans le nom du service nagios exemple : charge_cpu@CPULOAD
```

### Configuration des templates ###
les templates sont placé dans le dossier
> /etc/n2rrd/templates/rra

**Exemple avec les valeurs supplémentaires warn et crit:**
```
 WSC_CPU.t
 -s 300 # steps 5minutes
 DS:cpu:GAUGE:1200:0:U
 DS:cpu_warn:GAUGE:1200:0:U
 DS:cpu_crit:GAUGE:1200:0:U
 RRA:AVERAGE:0.25:1:4320   #day
 RRA:AVERAGE:0.25:6:1680   #week
 RRA:AVERAGE:0.25:24:1800  #month
 RRA:AVERAGE:0.25:288:1825 #year
 RRA:MAX:0.25:1:4320   #day
 RRA:MAX:0.25:6:1680   #week
 RRA:MAX:0.25:24:1800  #month
 RRA:MAX:0.25:288:1825 #year
 RRA:MIN:0.25:1:4320   #day
 RRA:MIN:0.25:6:1680   #week
 RRA:MIN:0.25:24:1800  #month
 RRA:MIN:0.25:288:1825 #year
```
**Exemple avec les valeurs supplémentaires max et min:**
```
-s 300 # steps 5minutes
DS:Free_PMem:GAUGE:1200:0:U
DS:Free_PMem_min:GAUGE:1200:0:U
DS:Free_PMem_max:GAUGE:1200:0:U
DS:Free_VMem:GAUGE:1200:0:U
DS:Free_VMem_min:GAUGE:1200:0:U
DS:Free_VMem_max:GAUGE:1200:0:U
RRA:AVERAGE:0.25:1:4320   #day
RRA:AVERAGE:0.25:6:1680   #week
RRA:AVERAGE:0.25:24:1800  #month
RRA:AVERAGE:0.25:288:1825 #year
RRA:MAX:0.25:1:4320   #day
RRA:MAX:0.25:6:1680   #week
RRA:MAX:0.25:24:1800  #month
RRA:MAX:0.25:288:1825 #year
RRA:MIN:0.25:1:4320   #day
RRA:MIN:0.25:6:1680   #week
RRA:MIN:0.25:24:1800  #month
RRA:MIN:0.25:288:1825 #year
```

### Configuration des rewrite ###
il y a deux type de rewrite :
**rewrite d'indicateur**

&lt;HOSTNAME&gt;



&lt;TEMPLATENAME&gt;

_rewrite
_rewrite de service_

&lt;TEMPLATENAME&gt;

**rewrite**

la syntaxe du fichiers est la suivante :
```
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.3.1.0           1_minute
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.3.6.0                       5_minutes
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.3.11.0                      15_minutes
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.2.13.0              cores
 #
 # change file name location
 #
 rrd_file        /var/log/nagios/rra/<HOSTNAME>_<SERVICENAME>.rrd
```_

## Configuration de Cacti ##
**perf2rrd.pl** et **server\_perf.pl** doit pouvoir lire le fichier :
` $CACTI_DIR$/include/config.php `

nagios2cacti y récupère les paramètres de connexion que Cacti utilise pour accéder à sa base de données.

## Configuration pour Oreon (FACULTATIF) ##
**perf2rrd.pl** et **server\_perf.pl** doit pouvoir lire le fichier :
` $OREON_DIR$/oreon.conf.php `

nagios2cacti y récupère les paramètres de connexion qu'Oreon utilise pour accéder à sa base de données. La fonctionnalité de stockage dans une base MySQL des données de performance ne peut être actuellement utilisé qu'avec Oreon.

## Configuration de Nagios ##

### Configuration pour le PIPE ###
**/etc/nagios/nagios.cfg
```
 process_performance_data=1
 service_perfdata_file=/var/log/nagios/perfdata.pipe
 service_perfdata_file_template=[SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$
 service_perfdata_file_mode=w
```**

### Configuration pour UDP ###
**/etc/nagios/nagios.cfg
```
 process_performance_data=1
 service_perfdata_command=send_perfdata_udp
```** /etc/nagios/checkcommand.cfg
```
 define command{
    command_name            send_perfdata_udp
    command_line            /usr/lib/N2Cacti/send_perf.pl -d  "[SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$"  -p 2080 -H localhost
 }
```

### Configuration pour AF\_UNIX ###
**/etc/nagios/nagios.cfg
```
 process_performance_data=1
 service_perfdata_command=send_perfdata_afunix
```** /etc/nagios/checkcommand.cfg
```
define command{
    command_name            send_perfdata_afunix
    command_line            /usr/lib/N2Cacti/sendperf_afunix.pl -d "[SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$"  -s "/var/log/nagios/perfdata.sock"
}
```

### Configuration des noms de services ###
On utilise la notation suivante pour la configuration des noms de service dans Nagios :
SERVICENAME@TEMPLATENAME
ainsi plusieurs services peuvent avoir le même template N2RRD.
attention : il ne s'agit pas ici du template au sens Nagios du terme!!!

Les graphiques dans Cacti porteront le nom : 

&lt;HOSTNAME&gt;

 - 

&lt;SERVICENAME&gt;



Les graph template porteront le nom : Nagios - 

&lt;SERVICENAME&gt;



le TEMPLATENAME permet de récupérer la configuration dans N2RRD :
```
 templates/rra/TEMPLATENAME.t
 templates/rewrite/service/TEMPLATENAME_rewrite
```

# Démarrage du démon #

## Méthode UDP ##
```
/usr/lib/N2Cacti/server_perf.pl -u -d -c /etc/n2rrd/n2rrd.conf -p2080
-m enable mysql support
-d daemonize 
-c configuration file ( by default : /etc/n2rrd/n2rrd.conf)
-p port UDP
-v verbose (to debug)
```
## Méthode du PIPE ##
```
/usr/lib/N2Cacti/perf2rrd.pl -u -d -c /etc/n2rrd/n2rrd.conf
-m enable mysql support
-d daemonize 
-c configuration file ( by default : /etc/n2rrd/n2rrd.conf)
-v verbose (to debug)
```

## Méthode AF\_UNIX ##
```
/usr/lib/N2Cacti/server_afunix.pl -u -d -c /etc/n2rrd/n2rrd.conf -s /var/log/nagios/perfdata.sock
-m enable mysql support
-d daemonize 
-c configuration file ( by default : /etc/n2rrd/n2rrd.conf)
-p port UDP
-v verbose (to debug)
```