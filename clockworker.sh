#!/bin/sh
# /etc/init.d/clockworker
#
### BEGIN INIT INFO
# Provides:          clockworker 
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable service provided by daemon.
### END INIT INFO

# Carry out specific functions when asked to by the system
case "$1" in
  start)
    echo "Starting script clockworker"
    bundle exec clockworkd start --log -c /home/pi/projects/LendingClubAutoinvest/clock.rb
    ;;
  stop)
    echo "Stopping script clockworker"
    bundle exec clockworkd stop --log 
    ;;
  *)
    echo "Usage: /etc/init.d/clockworker {start|stop}"
    exit 1
    ;;
esac

exit 0
