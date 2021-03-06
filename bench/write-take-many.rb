# benchmark that does a lot of write and take ops, but all tuples are small and
# the tuplespace is small.

$LOAD_PATH.unshift "lib"

profile = ARGV.delete("-p")
if profile
  require 'ruby-prof'
end

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

t0 = Process.times.to_a.inject{|s,x|s+x}

c1 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  
  n = 1000
  
  RubyProf.start if profile ## not profiling the server

  n.times do |i|
    ts.write([i])
    ts.take([nil])
  end
  
  if profile
    result = RubyProf.stop
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT)
    printer = RubyProf::MultiPrinter.new(result)
    FileUtils.makedirs "bench/results"
    printer.print(
      :path => "bench/results",
      :profile => File.basename(__FILE__, ".rb"))
  end
end

Process.wait c1

t1 = Process.times.to_a.inject{|s,x|s+x}

printf "time = %.2f\n", t1 - t0

Process.kill "TERM", server
