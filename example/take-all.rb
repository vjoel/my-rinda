$LOAD_PATH.unshift "lib"

require 'rinda/rinda'
require 'rinda/take-all'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::TakeAll
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

c1 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  ts.extend Rinda::TupleSpaceProxy::TakeAll

  puts "read_all:"
  p ts.read_all [1,2,nil]

  puts "take_all:"
  p ts.take_all [1,2,nil]

  puts "write..."
  ts.write [1,2,3]
  ts.write [1,2,4]
  ts.write [1,2,5]

  puts "read_all:"
  p ts.read_all [1,2,nil]

  puts "take_all:"
  p ts.take_all [1,2,nil]

  puts "read_all:"
  p ts.read_all [1,2,nil]
end

Process.wait c1

Process.kill "TERM", server
