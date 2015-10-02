
```
version 0.3.0               2008/05/08
*   best support nagios perfdata format :                           (TODO) (X)
    'label'=value[UOM];[warn];[crit];[min];[max]
    define datasource postfixed if allowed (_warn, _crit, _min, _max)
*   new method transmission between nagios and N2Cacti via UDP      (TODO) (X)
*   secure UDP transmission with backlog file on client side        (TODO) (X)
*   add statistics table NGS_RESULT when mysql support is enable    (TODO) (X)
*   use Error.pm to handle exception                                (TODO) (X)
BUG FIX: duplicate host was create when daemon restart              (TODO) (X)



version 0.2.1               2007/11/07
*   perf2rrd can be run in standalone without use N2Cacti to configure
Cacti. He configure it on the fly! use -u parameter to activate this feature

BUG FIX: if host or service missing will disable mysql support and not crash
the daemon


version 0.2         -       2007/10/31
*   delete N2Cacti::N2RRD module use N2Cacti::RRD (object oriented) (TODO) (X)
*   better support of error message                                 (TODO) (X)
*   support host_template natively                                  (TODO) (X)
*   add Format Text in Graph_template to get a legend directly      (TODO) (X)
*   add Parameter to select the default graph type (LINE2, AREA...) (TODO) (X)
*   support multiple instance of N2RRD template for one host        (TODO) (X)
*   support for host with hostname unique                           (TODO) (X)
*   support variable datasource from check                          (TODO) (X)
    use default.T file DEFAULT_RRA in n2rrd.conf to custom it
    format is same .t but one line for datasource and name is arbitrary
*   migration N2Cacti::Database to N2Cacti::database                (TODO) (X)
    *   grab cacti configuration database (user, passwd, ...)       (TODO) (X)
*   faire une priÃ¨re!!!
*   -c parameter use /etc/n2rrd/n2rrd.conf by default               (TODO) (X)
*   create data_input_method needed by n2cacti                      (TODO) (X)
*   add predefined color in n2rrd.conf
(TODO) (X)

File Change :
n2cacti.pl :
    *   delete N2Cacti::N2RRD module use N2Cacti::RRD               (TODO) (X)
    *   use N2Cacti::Cacti::Host instead of api_cacti script        (TODO) (X)

N2Cacti::Cacti :
    * wait to remove useless function bind for api_cacti (php)      (WAIT)

perf2rrd.pl :
    *   support individual rrd file                                 (TODO) (X)
        rrdupdate for template.t + rrdupdate for individual datasource
        (implemented in N2Cacti::RRD)

N2Cacti::RRD:
    *   add service_name, service_name is firt part of              (TODO) (X)
    service_description or service_description if MAPS file
    has been used.
    *   move datasource from array to hash                          (TODO) (X)
        see module using RRD module to be updated with that!        (TODO)

    TODO :
    *   support various rrdfile and rrdfile by datasource!          (TODO) (X)
        add a method get_pathrrd ($datasource)

N2Cacti::Graph:
    TODO :
    *   use N2Cacti::RRD module instead of parameter to constructor (TODO) (X)
    *   use N2Cacti::database instead of N2Cacti::Database          (TODO) (X)
    *   add try catch capture error                                 (TODO) (X)
    *   Specify a graph title like : host_name - service_name       (TODO) (X)
    *   support various datasource independant from template (?)    (TODO)
    *   use log_msg by parameter and remove N2Cacti::Config         (TODO) (X)
    *   get host by the couple (hostname & host_address)            (TODO) (X)
    *   fix get_random_color
    *   create individual graph                                     (TODO) (X)

N2Cacti::Data:
    TODO :
    *   use N2Cacti::RRD module instead of parameter to constructor (TODO) (X)
    *   use N2Cacti::database instead of N2Cacti::Database          (TODO) (X)
    *   add try catch capture error                                 (TODO) (X)
    *   support various datasource independant from template (?)    (TODO) (X)
        for individual datasource, create a template for each datasource
        add function create_individual_instance with support it
    *   use log_msg by parameter and remove N2Cacti::Config         (TODO) (X)
    *   get host by the couple (hostname & host_address)            (TODO) (X)

N2Cacti::Host:                                                      (TODO) (X)
    COMMENT :
    the cacti host_name     = the oreon/nagios host_adress
    the cacti description   = the oreon/nagios host_name
    the key used is : (host_name in nagios)
    limited support of host template only the necessary by nagios!


Constraint :
    the file service_map is requist
    the part service_name of service_description must to be unique for a host!
    hostname in nagios/oreon must be unique! (stockage RRD file)
N2Cacti::database:
    *   use exception and error control                             (TODO) (X)
        use raise_exception parameter to raise up some exception

Legend :
(*) in progress
(X) to be tested!
```