-s 300 # steps 5minutes
DS:<datasource>:GAUGE:1200:0:U
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

