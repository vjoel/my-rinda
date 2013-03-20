$LOAD_PATH.unshift "lib"

# Output before fix:
#
#   $ ruby thread-int.rb lose
#   read_all returned: []
#
# Output after fix:
#
#   $ ruby thread-int.rb
#   read_all returned: [[42]]

require 'rinda/rinda'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

c1 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  th = Thread.new do
    result = ts.take([nil])
    $stderr.puts "take returned: #{result.inspect}"
  end
  sleep 0.1
  th.raise Interrupt # causes bug
  #DRb.stop_service # avoids bug, but not correct solution
  sleep
end

sleep 0.2

c2 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  ts.write([42])
  result = ts.read_all([nil])
  $stderr.puts "read_all returned: #{result.inspect}"
end

sleep 0.2

Process.wait c2
Process.kill "TERM", c1
Process.kill "TERM", server
