-s 300 # steps 5minutes
DS:allocated:GAUGE:600:0:U
DS:reserved:GAUGE:600:0:U
DS:available:GAUGE:600:0:U
RRA:AVERAGE:0.5:1:1440   #day
RRA:AVERAGE:0.5:6:1680   #week
RRA:AVERAGE:0.5:24:1800  #month
RRA:AVERAGE:0.5:288:1825 #year
RRA:MAX:0.5:1:1440   #day
RRA:MAX:0.5:6:1680   #week
RRA:MAX:0.5:24:1800  #month
RRA:MAX:0.5:288:1825 #year
RRA:MIN:0.5:1:1440   #day
RRA:MIN:0.5:6:1680   #week
RRA:MIN:0.5:24:1800  #month
RRA:MIN:0.5:288:1825 #year

