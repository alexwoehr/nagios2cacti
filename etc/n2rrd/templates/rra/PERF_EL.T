-s 86400 # steps 5minutes
DS:execution_time:GAUGE:600:0:U
DS:latency:GAUGE:600:0:U
RRA:AVERAGE:0.5:1:10  #day
RRA:AVERAGE:0.5:2:35  #week
RRA:AVERAGE:0.5:4:75  #month
RRA:AVERAGE:0.5:8:457 #year
RRA:MAX:0.5:1:10   #day
RRA:MAX:0.5:2:35   #week
RRA:MAX:0.5:4:75  #month
RRA:MAX:0.5:8:457 #year
RRA:MIN:0.5:1:10   #day
RRA:MIN:0.5:2:35   #week
RRA:MIN:0.5:4:75  #month
RRA:MIN:0.5:8:457 #year
